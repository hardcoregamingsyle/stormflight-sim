class_name Aircraft
extends RigidBody3D
## The complete aircraft: rigid body + aero + propulsion + gear + damage +
## fuel + autopilot. Also drives visual part animation (control surfaces,
## flaps, slats, spoilers, gear, props/rotors) built by AircraftMeshBuilder.

var cfg: AircraftConfig
var aero: Aero
var propulsion: Propulsion
var gear: GearSystem
var damage_sys: DamageSystem
var autopilot: Autopilot

var is_player: bool = false
var is_remote: bool = false      # network proxy: no local physics
var is_ai: bool = false

# --- Controls (smoothed actuals) ---
var ctl_elevator := 0.0
var ctl_aileron := 0.0
var ctl_rudder := 0.0
var ctl_throttle := 0.0
var ctl_trim := 0.0
var flap_setting := 0.0          # commanded notch 0..1
var flap_frac := 0.0             # actual surface position
var slat_frac := 0.0
var spoiler_on := false
var spoiler_frac := 0.0
var pushback_active := false

# --- State ---
var fuel_kg := 0.0
var payload_kg := 0.0
var crashed := false
var engines_on := false
var g_force := 1.0
var prev_velocity := Vector3.ZERO
var wind := Vector3.ZERO
var agl := 0.0
var world_ref: Node3D = null     # WorldRoot; provides height + wind queries
var pilot_name := ""

# --- Visual parts from AircraftMeshBuilder ---
var parts: Dictionary = {}
var _prop_angle := 0.0
var _rotor_angle := 0.0
var _wheel_angle := 0.0
var _beacon_t := 0.0
var _belly_scrape_timer := 0.0
var _stall_warn := false
var _overspeed_warn := false
var _gear_hold_t := 0.0
var last_aero_force := Vector3.ZERO  # body frame, diagnostics
var last_v_body := Vector3.ZERO
var _blob: MeshInstance3D = null
var _blob_mat: StandardMaterial3D = null

const FLAP_NOTCHES := [0.0, 0.25, 0.5, 0.75, 1.0]

func setup(config: AircraftConfig, player: bool, remote: bool = false) -> void:
	cfg = config
	is_player = player
	is_remote = remote
	aero = Aero.new(cfg)
	propulsion = Propulsion.new(cfg)
	gear = GearSystem.new(cfg)
	damage_sys = DamageSystem.new(cfg)
	autopilot = Autopilot.new()
	damage_sys.failed.connect(_on_system_failed)

	fuel_kg = cfg.fuel_capacity * 0.75
	mass = cfg.empty_mass + fuel_kg
	# All aero/gear math assumes the CG is at the node origin - never let
	# Godot infer the COM from collision shape placement.
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO
	_set_inertia()
	linear_damp = 0.0
	angular_damp = 0.04
	can_sleep = false
	continuous_cd = false
	contact_monitor = true
	max_contacts_reported = 6
	body_entered.connect(_on_body_entered)

	_build_collision()
	var built: Dictionary = AircraftMeshBuilder.build(cfg)
	add_child(built.root)
	parts = built.parts
	_make_blob_shadow()

	if is_remote:
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

	if is_player:
		var saved := SaveGame.get_condition(cfg.id)
		if not saved.is_empty():
			damage_sys.restore_from(saved.get("health", {}))
			fuel_kg = cfg.fuel_capacity * float(saved.get("fuel_frac", 0.75))
			var eng_h: Array = saved.get("engine_health", [])
			for i in mini(eng_h.size(), propulsion.health.size()):
				propulsion.health[i] = float(eng_h[i])
			# Never spawn an instantly-dead airframe: ground crew patches the
			# worst damage (proper repairs still cost SkyCoins in the hangar)
			var patched := false
			for sys in damage_sys.health.keys():
				if damage_sys.health[sys] < 0.25:
					damage_sys.health[sys] = 0.25
					patched = true
			for i in propulsion.health.size():
				if propulsion.health[i] < 0.25:
					propulsion.health[i] = 0.25
					patched = true
			if patched:
				EventBus.toast("Airframe in poor condition - visit the hangar for repairs", "warn")

func persist_condition() -> void:
	if not is_player:
		return
	SaveGame.set_condition(cfg.id, {
		"health": damage_sys.snapshot(),
		"fuel_frac": fuel_kg / maxf(cfg.fuel_capacity, 1.0),
		"engine_health": propulsion.health.duplicate(),
	})

func _set_inertia() -> void:
	var L := float(cfg.mesh.get("fuselage_length_m", 10.0))
	var b := cfg.wing_span
	var m := (cfg.empty_mass + cfg.mtow) * 0.5
	if cfg.is_helicopter():
		var r := maxf(cfg.rotor_main_radius, 3.0)
		inertia = Vector3(m * pow(0.30 * r, 2), m * pow(0.34 * r, 2), m * pow(0.26 * r, 2))
	else:
		inertia = Vector3(
			m * pow(0.22 * L, 2),                 # pitch (about +X)
			m * pow(0.26 * (L + b) * 0.5, 2),     # yaw (about +Y)
			m * pow(0.25 * b * 0.5, 2))           # roll (about +Z)

func _build_collision() -> void:
	var L := float(cfg.mesh.get("fuselage_length_m", 10.0))
	var r := float(cfg.mesh.get("fuselage_radius_m", 1.0))
	var fus := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = r * 0.95
	cap.height = L * 0.92
	fus.shape = cap
	fus.rotation.x = PI / 2.0
	# Fuselage is placed so the wing 1/4-chord (CG) sits at the origin
	fus.position.z = (0.5 - float(cfg.mesh.get("wing_z_frac", 0.45))) * L
	add_child(fus)
	if not cfg.is_helicopter():
		var wing := CollisionShape3D.new()
		var wbox := BoxShape3D.new()
		wbox.size = Vector3(cfg.wing_span * 0.92, 0.4, aero.mean_chord)
		wing.shape = wbox
		wing.position = Vector3(0, 0, 0)
		add_child(wing)

# ===================================================================== input
func _collect_player_input(dt: float) -> void:
	if Game.typing:
		return
	var invert := -1.0 if SaveGame.setting("invert_pitch", false) else 1.0
	var tgt_pitch := Input.get_axis("pitch_down", "pitch_up") * invert
	var tgt_roll := Input.get_axis("roll_left", "roll_right")
	var tgt_yaw := Input.get_axis("yaw_left", "yaw_right")

	var atk := 3.2
	var rel := 4.0
	ctl_elevator = _smooth_axis(ctl_elevator, tgt_pitch, atk, rel, dt)
	ctl_aileron = _smooth_axis(ctl_aileron, tgt_roll, atk, rel, dt)
	ctl_rudder = _smooth_axis(ctl_rudder, tgt_yaw, atk, rel, dt)

	var thr_axis := Input.get_axis("throttle_down", "throttle_up")
	ctl_throttle = clampf(ctl_throttle + thr_axis * 0.45 * dt, 0.0, 1.0)
	propulsion.throttle = ctl_throttle

	if Input.is_action_pressed("trim_up"):
		ctl_trim = clampf(ctl_trim + 0.12 * dt, -0.5, 0.5)
	if Input.is_action_pressed("trim_down"):
		ctl_trim = clampf(ctl_trim - 0.12 * dt, -0.5, 0.5)

	gear.brake_input = 1.0 if Input.is_action_pressed("brakes") else 0.0
	gear.steer_input = tgt_yaw

	if Input.is_action_just_pressed("gear_toggle"):
		if gear.jammed or damage_sys.has_failed("gear"):
			EventBus.toast("Gear jammed! Hold G for emergency gravity extension", "warn")
		else:
			gear.toggle()
	if Input.is_action_pressed("gear_toggle"):
		_gear_hold_t += dt
		if _gear_hold_t > 2.5 and not gear.is_down():
			gear.emergency_extend()
			damage_sys.clear_failure("gear")
			EventBus.toast("Emergency gear extension!", "warn")
			_gear_hold_t = -10.0
	else:
		_gear_hold_t = 0.0

	if Input.is_action_just_pressed("flaps_down"):
		_set_flap_notch(1)
	if Input.is_action_just_pressed("flaps_up"):
		_set_flap_notch(-1)
	if Input.is_action_just_pressed("spoilers_toggle") and cfg.has_spoilers:
		spoiler_on = not spoiler_on
	if Input.is_action_just_pressed("parking_brake"):
		gear.parking_brake = not gear.parking_brake
		EventBus.toast("Parking brake %s" % ("SET" if gear.parking_brake else "RELEASED"), "info")
	if Input.is_action_just_pressed("engine_toggle"):
		if engines_on:
			propulsion.stop_all()
			engines_on = false
			EventBus.toast("Engines shutting down", "info")
		else:
			propulsion.start_all()
			engines_on = propulsion.any_running()
			EventBus.toast("Engine start", "info")
	if Input.is_action_just_pressed("pushback"):
		if gear.on_ground and get_ias() < 2.0:
			pushback_active = not pushback_active
			if pushback_active:
				gear.parking_brake = false
			EventBus.toast("Pushback %s" % ("started" if pushback_active else "stopped"), "info")
	if Input.is_action_just_pressed("autopilot_toggle"):
		if damage_sys.has_failed("avionics"):
			EventBus.toast("Autopilot unavailable - avionics fault", "bad")
		elif autopilot.engaged:
			autopilot.disengage()
			EventBus.toast("Autopilot OFF", "info")
		else:
			autopilot.engage(get_heading(), global_position.y, get_ias())
			EventBus.toast("Autopilot ON (holding hdg/alt/spd)", "good")

	# Manual override kicks AP off
	if autopilot.engaged and (absf(tgt_pitch) > 0.6 or absf(tgt_roll) > 0.6):
		autopilot.disengage()
		EventBus.toast("Autopilot disconnected", "warn")

func _smooth_axis(current: float, target: float, attack: float, release: float, dt: float) -> float:
	var rate := attack if absf(target) > absf(current) else release
	return move_toward(current, target, rate * dt)

func _set_flap_notch(dir: int) -> void:
	if damage_sys.has_failed("flaps"):
		EventBus.toast("Flaps jammed!", "bad")
		return
	var idx := 0
	for i in FLAP_NOTCHES.size():
		if absf(FLAP_NOTCHES[i] - flap_setting) < 0.01:
			idx = i
	idx = clampi(idx + dir, 0, FLAP_NOTCHES.size() - 1)
	flap_setting = FLAP_NOTCHES[idx]
	EventBus.toast("Flaps %d%%" % int(flap_setting * 100), "info")

# ===================================================================== physics
func _physics_process(dt: float) -> void:
	if is_remote or crashed:
		return
	if is_player:
		_collect_player_input(dt)
		if autopilot.engaged:
			var ap := autopilot.update(dt, {
				"heading_deg": get_heading(), "bank_deg": get_bank(),
				"alt_m": global_position.y, "vs_ms": linear_velocity.y,
				"ias": get_ias(), "slip": aero.beta,
				"roll_rate": angular_velocity.dot(-global_transform.basis.z),
				"pitch_rate": angular_velocity.dot(global_transform.basis.x),
			})
			if not ap.is_empty():
				ctl_elevator = ap.elevator
				ctl_aileron = ap.aileron
				ctl_rudder = ap.rudder
				ctl_throttle = ap.throttle
				propulsion.throttle = ctl_throttle

	# Environment
	if world_ref:
		agl = global_position.y - world_ref.call("height_at", global_position)
		wind = world_ref.call("wind_at", global_position)
	else:
		agl = global_position.y
		wind = Vector3.ZERO

	var rho := Atmosphere.density(global_position.y)
	var v_air_global := linear_velocity - wind
	var tas := v_air_global.length()
	var mach := Atmosphere.mach(tas, global_position.y)

	# Actuator movement (flaps/slats/spoilers move at realistic rates)
	if not damage_sys.has_failed("flaps"):
		flap_frac = move_toward(flap_frac, flap_setting, dt / 9.0)
	var slat_target := 1.0 if (cfg.has_slats and flap_setting > 0.05) else 0.0
	slat_frac = move_toward(slat_frac, slat_target, dt / 5.0)
	spoiler_frac = move_toward(spoiler_frac, 1.0 if spoiler_on else 0.0, dt / 1.2)

	# Fuel + engines
	var burned := propulsion.update(dt, rho, mach)
	fuel_kg = maxf(fuel_kg - burned, 0.0)
	if fuel_kg <= 0.0 and propulsion.any_running():
		propulsion.stop_all()
		engines_on = false
		EventBus.toast("FUEL EXHAUSTED - engines flamed out", "bad")
	mass = cfg.empty_mass + fuel_kg + payload_kg

	# --- Aerodynamics (body frame) ---
	var basis_inv := global_transform.basis.inverse()
	var v_body := basis_inv * v_air_global
	var w_body := basis_inv * angular_velocity
	var result: Dictionary = aero.compute({
		"v_body": v_body, "omega_body": w_body, "rho": rho, "mach": mach,
		"agl": agl, "rotor_rpm": propulsion.rotor_rpm,
		"controls": {
			"elevator": ctl_elevator, "aileron": ctl_aileron, "rudder": ctl_rudder,
			"trim": ctl_trim, "throttle": ctl_throttle,
			"flap": flap_frac, "slat": slat_frac, "spoiler": spoiler_frac,
			"gear": gear.gear_frac if cfg.gear_retractable else 0.3,
		},
		"effectiveness": {
			"controls": damage_sys.control_effectiveness(),
			"structure": damage_sys.structure_effectiveness(),
		},
	})
	last_aero_force = result.force
	last_v_body = v_body
	apply_central_force(global_transform.basis * result.force)
	apply_torque(global_transform.basis * result.torque)

	# --- Thrust (per engine, so failures give asymmetric yaw) ---
	if not cfg.is_helicopter():
		var spans: Array = cfg.mesh.get("engine_span_positions", [])
		var t_y: float = -0.3 if String(cfg.mesh.get("engine_mount", "underwing")) == "underwing" else 0.0
		for i in cfg.engine_count:
			var t := propulsion.thrust_engine(i, rho, mach, tas)
			var x := 0.0
			if spans.size() > 0:
				var side := 1.0 if (i % 2) == 1 else -1.0
				x = side * float(spans[(i / 2) % spans.size()])
			var f_global := global_transform.basis * Vector3(0, 0, -t)
			apply_force(f_global, global_transform.basis * Vector3(x, t_y, 0))

	# --- Gear ---
	if cfg.is_helicopter() and not cfg.gear_retractable:
		gear.brake_input = maxf(gear.brake_input, 0.7)  # skids
		gear.steer_input = 0.0
	gear.update(self, dt)
	if gear.just_touched_down:
		var quality := damage_sys.landing_impact(gear.touchdown_fpm)
		EventBus.landed.emit(gear.touchdown_fpm, quality)
		Sfx.play("touchdown", clampf(gear.touchdown_fpm / 800.0, 0.2, 1.0))

	# Pushback tug
	if pushback_active:
		if not gear.on_ground or get_ias() > 3.0:
			pushback_active = false
		else:
			var back := global_transform.basis.z
			var want := back * 1.1
			var dv := want - linear_velocity
			apply_central_force(dv * mass * 0.8)

	# --- Damage / stress ---
	var accel := (linear_velocity - prev_velocity) / dt
	prev_velocity = linear_velocity
	if accel.length() > 245.0:  # >25 g in one tick = teleport/respawn artifact
		accel = Vector3.ZERO
	var g_body_y := (basis_inv * (accel + Vector3(0, 9.81, 0))).y
	g_force = g_body_y / 9.81
	damage_sys.update(dt, {
		"g": g_force, "ias": get_ias(), "vne": cfg.vne,
		"flap_frac": flap_frac, "gear_down": gear.is_down(),
	}, propulsion)
	if damage_sys.health["structure"] <= 0.0 and not crashed:
		crash("Structural failure")

	# Belly scrape
	if get_contact_count() > 0 and not gear.on_ground and agl < 4.0:
		_belly_scrape_timer += dt
		if linear_velocity.length() > 30.0 and _belly_scrape_timer > 0.4:
			crash("Belly impact at speed")
		elif _belly_scrape_timer > 0.2:
			damage_sys.damage("structure", 0.06 * dt)
	else:
		_belly_scrape_timer = 0.0

	_update_warnings()
	if is_player:
		SaveGame.add_stat("flight_time_s", dt)

func _update_warnings() -> void:
	var stall_now := aero.stall_margin < 0.12 and not gear.on_ground and get_ias() > cfg.stall_speed_clean * 0.4 and not cfg.is_helicopter()
	if stall_now != _stall_warn:
		_stall_warn = stall_now
		EventBus.stall_warning.emit(stall_now)
	var over_now := get_ias() > cfg.vne * 0.98
	if over_now != _overspeed_warn:
		_overspeed_warn = over_now
		EventBus.overspeed_warning.emit(over_now)
	if fuel_kg > 0.0 and fuel_kg < cfg.fuel_capacity * 0.1:
		EventBus.fuel_low.emit(fuel_kg / cfg.fuel_capacity)

func _on_body_entered(other: Node) -> void:
	if crashed or is_remote:
		return
	var speed := linear_velocity.length()
	if OS.is_debug_build():
		print("CONTACT with %s groups=%s at %s speed=%.0f agl=%.0f" % [other.name, str(other.get_groups()), str(global_position.snapped(Vector3.ONE)), speed, agl])
	if other is Aircraft:
		# Parked overlap (e.g. simultaneous multiplayer gate spawn) just
		# nudges apart; only a real closing speed is a mid-air.
		var rel_speed := speed
		if other is RigidBody3D:
			rel_speed = (linear_velocity - (other as RigidBody3D).linear_velocity).length()
		if rel_speed > 4.0:
			crash("Mid-air collision")
		return
	if other.is_in_group("building"):
		if speed > 8.0:
			crash("Collision with structure")
		return
	# Terrain / pavement contact without wheels
	if not gear.on_ground:
		var vert := absf(linear_velocity.y)
		if speed > 40.0 or vert > 12.0:
			crash("Ground impact")

func crash(reason: String) -> void:
	if crashed:
		return
	crashed = true
	propulsion.stop_all()
	engines_on = false
	autopilot.disengage()
	damage_sys.health["structure"] = 0.0
	Sfx.play("crash", 1.0)
	_spawn_crash_fx()
	EventBus.aircraft_crashed.emit(reason)

func _spawn_crash_fx() -> void:
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 60.0
	mat.initial_velocity_min = 8.0
	mat.initial_velocity_max = 24.0
	mat.gravity = Vector3(0, -4, 0)
	mat.scale_min = 1.5
	mat.scale_max = 5.0
	mat.color = Color(0.15, 0.12, 0.1, 0.85)
	p.process_material = mat
	p.amount = 48
	p.lifetime = 3.5
	p.one_shot = true
	p.explosiveness = 0.6
	p.emitting = true
	var cleanup := get_tree().create_timer(6.0)
	cleanup.timeout.connect(p.queue_free)
	var pm := SphereMesh.new()
	pm.radius = 1.0
	pm.height = 2.0
	var pmat := StandardMaterial3D.new()
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.albedo_color = Color(0.2, 0.16, 0.13, 0.5)
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.material = pmat
	p.draw_pass_1 = pm
	add_child(p)

func _on_system_failed(system_name: String, description: String) -> void:
	EventBus.system_failure.emit(system_name, description)
	if system_name == "gear":
		gear.jammed = true
	Sfx.play("warn_beep", 1.0)
	EventBus.toast("FAILURE: %s" % description, "bad")

# ===================================================================== visuals
## Soft ground blob standing in for the aircraft's directional shadow.
func _make_blob_shadow() -> void:
	_blob = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = maxf(cfg.wing_span * 0.38, 3.0)
	disc.bottom_radius = disc.top_radius
	disc.height = 0.05
	disc.radial_segments = 20
	_blob.mesh = disc
	_blob_mat = StandardMaterial3D.new()
	_blob_mat.albedo_color = Color(0, 0, 0, 0.34)
	_blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blob.material_override = _blob_mat
	_blob.top_level = true
	_blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_blob)

func _update_blob() -> void:
	if _blob == null:
		return
	var fade := clampf(1.0 - agl / 140.0, 0.0, 1.0)
	if fade <= 0.01 or crashed:
		_blob.visible = false
		return
	_blob.visible = true
	var ground_y := global_position.y - agl
	_blob.global_position = Vector3(global_position.x, ground_y + 0.25, global_position.z)
	_blob.rotation = Vector3.ZERO
	var spread := 1.0 + agl / 60.0
	_blob.scale = Vector3(spread, 1.0, spread)
	_blob_mat.albedo_color = Color(0, 0, 0, 0.34 * fade / (spread * spread))

func _process(dt: float) -> void:
	_animate_parts(dt)
	_update_blob()
	if is_player:
		_update_sound()

func _animate_parts(dt: float) -> void:
	if parts.is_empty():
		return
	var ctl_eff := 1.0 if is_remote else damage_sys.control_effectiveness()
	var elev := clampf(ctl_elevator + ctl_trim, -1, 1) * ctl_eff
	var defl := cfg.elevator_max if cfg != null else 0.4
	AircraftMeshBuilder.animate(parts, {
		"elevator": -elev * defl,
		"aileron": ctl_aileron * cfg.aileron_max * ctl_eff,
		"rudder": ctl_rudder * cfg.rudder_max * ctl_eff,
		"flap": flap_frac, "slat": slat_frac, "spoiler": spoiler_frac,
		"gear": gear.gear_frac,
		"dt": dt,
	})
	# Spinning things
	var n1 := propulsion.average_n1()
	_prop_angle += (2.0 + n1 * 55.0) * dt
	_rotor_angle += propulsion.rotor_rpm * 28.0 * dt
	_wheel_angle += linear_velocity.length() / maxf(gear.wheel_radius, 0.2) * dt * (1.0 if gear.on_ground else 0.2)
	AircraftMeshBuilder.spin(parts, _prop_angle, _rotor_angle, _wheel_angle, n1, propulsion.afterburner)
	# Beacon / strobes
	_beacon_t += dt
	AircraftMeshBuilder.lights(parts, {
		"beacon_on": engines_on and fmod(_beacon_t, 1.2) < 0.12,
		"strobe_on": not gear.on_ground and fmod(_beacon_t, 1.7) < 0.06,
		"landing_on": Quality.landing_lights and gear.is_down() and engines_on and global_position.y < 1200.0,
	})

func _update_sound() -> void:
	var n1 := propulsion.average_n1()
	Sfx.engine_state(cfg.engine_type, n1, propulsion.afterburner, propulsion.rotor_rpm)
	Sfx.wind_state(get_ias() / maxf(cfg.vne, 50.0))
	Sfx.rolling_state(gear.on_ground, linear_velocity.length())

# ===================================================================== queries
func get_ias() -> float:
	return Atmosphere.tas_to_ias((linear_velocity - wind).length(), global_position.y)

func get_ias_kts() -> float:
	return get_ias() * Atmosphere.MS_TO_KTS

func get_alt_ft() -> float:
	return global_position.y * Atmosphere.M_TO_FT

func get_vs_fpm() -> float:
	return linear_velocity.y * Atmosphere.MS_TO_FPM

func get_heading() -> float:
	var fwd := -global_transform.basis.z
	return fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)

func get_bank() -> float:
	var right := global_transform.basis.x
	return rad_to_deg(asin(clampf(-right.y, -1.0, 1.0)))

func get_pitch_deg() -> float:
	var fwd := -global_transform.basis.z
	return rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))

func get_mach() -> float:
	return Atmosphere.mach((linear_velocity - wind).length(), global_position.y)

func fuel_fraction() -> float:
	return fuel_kg / maxf(cfg.fuel_capacity, 1.0)

func abs_position() -> Vector3:
	if world_ref:
		return global_position + (world_ref.call("origin_offset") as Vector3)
	return global_position
