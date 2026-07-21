extends Node
## Boot node (res://scenes/Main.tscn). Swaps between the main menu and the
## in-flight world + HUD.

var menu: Node = null
var world: Node = null
var hud: Node = null

func _ready() -> void:
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	goto_menu()
	if "--smoketest" in OS.get_cmdline_user_args():
		_smoketest()
	elif "--eoscheck" in OS.get_cmdline_user_args():
		_eoscheck()
	elif "--screenshots" in OS.get_cmdline_user_args():
		_screenshots()
	elif "--lightmatrix" in OS.get_cmdline_user_args():
		_lightmatrix()

## Reports whether the EOS GDExtension actually loaded in THIS build. Run on an
## exported binary in CI to prove the plugin is really bundled (exit 0 = yes).
func _eoscheck() -> void:
	var has_peer := ClassDB.class_exists("EOSGMultiplayerPeer")
	var has_singleton := Engine.has_singleton("IEOS")
	var present := EOSBackend.plugin_present()
	print("EOSCHECK: plugin_present=%s IEOS=%s EOSGMultiplayerPeer=%s configured=%s" % [
		str(present), str(has_singleton), str(has_peer), str(EOSConfig.configured())])
	get_tree().quit(0 if present else 3)

func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SNAP %s" % path)

## Lighting bisection matrix at the airport that renders black.
func _lightmatrix() -> void:
	var dir := ProjectSettings.globalize_path("res://docs/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(1.0).timeout
	Game.start_flight("a320", "sfi", Game.Mode.SOLO)
	await get_tree().create_timer(4.0).timeout
	var w := Game.world as WorldRoot
	w.hour = 9.0
	var rig := w.camera_rig
	rig.view = 2
	rig.orbit_yaw = 2.5
	rig.orbit_pitch = 0.25
	rig.distance = 50.0
	await get_tree().create_timer(1.0).timeout
	# Isolate WITHIN the player aircraft: which part is the toxic caster?
	_set_cast(w, false)
	var p2 := Game.player_aircraft as Aircraft
	var visual := p2.get_node("Visual")
	await _snap(dir + "/m_a_all_off.png")
	for part_name in ["fuselage", "wing", "winglet", "surf", "nacelle", "canopy", "windshield", "strut", "elevator", "rudder"]:
		for node in _find_named(visual, part_name):
			_set_cast(node, true)
		await _snap(dir + "/m_part_%s.png" % part_name)
		for node in _find_named(visual, part_name):
			_set_cast(node, false)
	print("MATRIX DONE")
	get_tree().quit(0)

func _find_named(node: Node, part_name: String) -> Array:
	var out: Array = []
	if node.name.begins_with(part_name):
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_named(child, part_name))
	return out

func _set_cast(node: Node, on: bool) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_set_cast(child, on)

## Automated beauty-shot run for the landing page + visual verification.
func _screenshots() -> void:
	var dir := ProjectSettings.globalize_path("res://docs/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(1.5).timeout
	await _snap(dir + "/menu.png")

	# A320 at the gate, morning light
	Game.start_flight("a320", "sfi", Game.Mode.SOLO)
	await get_tree().create_timer(4.0).timeout
	var w := Game.world as WorldRoot
	w.hour = 9.0
	var rig := w.camera_rig
	rig.view = 2  # orbit
	rig.orbit_yaw = 2.5
	rig.orbit_pitch = 0.18
	rig.distance = 55.0
	# Run the ATC flow so the taxi guide chevrons are visible in the shot
	var p0 := Game.player_aircraft as Aircraft
	p0.propulsion.start_all()
	p0.engines_on = true
	ATC._do_clearance()
	await get_tree().create_timer(0.5).timeout
	ATC._do_taxi()
	await get_tree().create_timer(1.5).timeout
	rig.orbit_pitch = 0.55
	rig.distance = 160.0
	await get_tree().create_timer(0.5).timeout
	await _snap(dir + "/gate_a320.png")

	# Region map overlay
	hud.map_view.visible = true
	hud.map_view.queue_redraw()
	await get_tree().create_timer(0.8).timeout
	await _snap(dir + "/map.png")
	hud.map_view.visible = false

	# Airborne over the coast, gear up, golden hour
	var p := Game.player_aircraft as Aircraft
	p.propulsion.start_all()
	p.engines_on = true
	p.gear.parking_brake = false
	p.ctl_throttle = 0.8
	p.global_position = Vector3(-2500, 750, 5200)
	p.rotation = Vector3(0, 0.5, 0)
	p.linear_velocity = -p.global_transform.basis.z * 165.0
	p.gear.gear_target = 0.0
	p.gear.gear_frac = 0.0
	w.hour = 17.4
	rig.orbit_yaw = 3.8
	rig.orbit_pitch = 0.12
	rig.distance = 70.0
	await get_tree().create_timer(2.5).timeout
	await _snap(dir + "/air_a320.png")
	Game.return_to_menu()
	await get_tree().create_timer(1.0).timeout

	# F-16 with afterburner over the mountains
	Game.start_flight("f16", "vlc", Game.Mode.SOLO)
	await get_tree().create_timer(4.0).timeout
	w = Game.world as WorldRoot
	w.hour = 12.5
	p = Game.player_aircraft as Aircraft
	p.propulsion.start_all()
	p.engines_on = true
	p.ctl_throttle = 1.0
	p.gear.parking_brake = false
	p.global_position = Vector3(-4000, 1400, -3000)
	p.rotation = Vector3(0, 2.2, 0)
	p.linear_velocity = -p.global_transform.basis.z * 260.0
	p.gear.gear_target = 0.0
	p.gear.gear_frac = 0.0
	rig = w.camera_rig
	rig.view = 2
	rig.orbit_yaw = 2.9
	rig.orbit_pitch = 0.1
	rig.distance = 32.0
	await get_tree().create_timer(2.5).timeout
	await _snap(dir + "/air_f16.png")
	Game.return_to_menu()
	await get_tree().create_timer(1.0).timeout

	# Bell 206 hovering at Cove Field
	Game.start_flight("bell206", "cve", Game.Mode.SOLO)
	await get_tree().create_timer(4.0).timeout
	w = Game.world as WorldRoot
	w.hour = 15.0
	p = Game.player_aircraft as Aircraft
	p.propulsion.start_all()
	p.engines_on = true
	p.gear.parking_brake = false
	p.ctl_throttle = 0.9
	rig = w.camera_rig
	rig.view = 2
	rig.orbit_yaw = 2.2
	rig.orbit_pitch = 0.2
	rig.distance = 14.0
	await get_tree().create_timer(6.0).timeout
	await _snap(dir + "/heli_bell206.png")
	print("SCREENSHOTS DONE")
	get_tree().quit(0)

## Headless CI test: builds every aircraft + airport, flies a short hop.
func _smoketest() -> void:
	print("SMOKETEST: building all %d aircraft models..." % AircraftDB.ids().size())
	for id in AircraftDB.ids():
		var built: Dictionary = AircraftMeshBuilder.build(AircraftDB.config(id))
		AircraftMeshBuilder.animate(built.parts, {"elevator": 0.1, "aileron": 0.1, "rudder": 0.1, "flap": 0.5, "slat": 1.0, "spoiler": 0.5, "gear": 0.5, "dt": 0.016})
		AircraftMeshBuilder.spin(built.parts, 1.0, 1.0, 1.0, 0.5, true)
		AircraftMeshBuilder.lights(built.parts, {"beacon_on": true, "strobe_on": true, "landing_on": true})
		built.root.free()
		print("  aircraft OK: %s" % id)
	print("SMOKETEST: building all airports...")
	for aid in AirportsDB.ids():
		var data: Dictionary = AirportBuilder.build(aid)
		var route: Array = AirportBuilder.taxi_route(data, "gate_0", "r0_hold_e1")
		print("  airport OK: %s (%d graph nodes, taxi route %d pts)" % [aid, data.graph.nodes.size(), route.size()])
		data.root.free()
	var test_ac := "cessna172"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ac="):
			test_ac = arg.trim_prefix("--ac=")
	print("SMOKETEST: starting flight with %s..." % test_ac)
	await get_tree().create_timer(0.5).timeout
	Game.start_flight(test_ac, "sfi", Game.Mode.SOLO)
	await get_tree().create_timer(2.0).timeout
	var p := Game.player_aircraft as Aircraft
	if p == null:
		printerr("SMOKETEST FAIL: no player aircraft")
		get_tree().quit(1)
		return
	# Line up on runway 1 (spawning at the gate points at the terminal)
	var w := Game.world as WorldRoot
	var rw: Dictionary = w.airports["sfi"].runways[0]
	var dir3 := rw.dir as Vector3
	p.global_position = ((rw.e1 as Vector3) - w.origin_offset()) + dir3 * 80.0 + Vector3(0, p.gear.spawn_height() + 0.05, 0)
	p.rotation = Vector3(0, -atan2(dir3.x, -dir3.z), 0)
	p.linear_velocity = Vector3.ZERO
	p.angular_velocity = Vector3.ZERO
	# Terrain collision probe: ray straight down from 50m above the plane
	var space := p.get_world_3d().direct_space_state
	for probe_off: Vector3 in [Vector3.ZERO, Vector3(200, 0, -200), Vector3(-400, 0, 300)]:
		var from: Vector3 = p.global_position + probe_off + Vector3(0, 50, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -200, 0))
		q.exclude = [p.get_rid()]
		var hit := space.intersect_ray(q)
		print("  probe at %s: %s" % [str(from.snapped(Vector3.ONE)), ("hit y=%.1f (%s)" % [hit.position.y, hit.collider.get_groups()]) if not hit.is_empty() else "NO HIT"])
	p.propulsion.start_all()
	p.engines_on = true
	p.gear.parking_brake = false
	p.ctl_throttle = 1.0
	# Scripted pilot inputs must go through the Input layer (the aircraft
	# reads live input every frame)
	var is_heli := p.cfg.is_helicopter()
	var vr_kts := p.cfg.stall_speed_clean * Atmosphere.MS_TO_KTS * 1.18

	# --- Ground-handling regression guard: full rudder at taxi speed must NOT
	# flip or wildly over-bank the aircraft (the rudder-flip bug). ---
	if not is_heli:
		p.ctl_throttle = 0.4
		Input.action_press("yaw_right", 1.0)
		var max_ground_bank := 0.0
		for _gs in 210:
			await get_tree().physics_frame
			max_ground_bank = maxf(max_ground_bank, absf(p.get_bank()))
			if p.crashed or not p.gear.on_ground:
				break
		Input.action_release("yaw_right")
		print("SMOKETEST ground-steer: max_bank=%.1f deg ias=%.1f kts crashed=%s" % [max_ground_bank, p.get_ias_kts(), str(p.crashed)])
		if p.crashed or max_ground_bank > 35.0:
			print("SMOKETEST FAIL: rudder flipped / over-banked the aircraft on the ground (bank=%.1f)" % max_ground_bank)
			Game.return_to_menu()
			await get_tree().create_timer(0.5).timeout
			get_tree().quit(1)
			return
		# Re-line-up for the takeoff run
		p.global_position = ((rw.e1 as Vector3) - w.origin_offset()) + dir3 * 80.0 + Vector3(0, p.gear.spawn_height() + 0.05, 0)
		p.rotation = Vector3(0, -atan2(dir3.x, -dir3.z), 0)
		p.linear_velocity = Vector3.ZERO
		p.angular_velocity = Vector3.ZERO
		p.ctl_throttle = 1.0

	if not is_heli:
		Input.action_press("pitch_up", 0.25)
	var ap_engaged := false
	for step_i in 26:
		await get_tree().create_timer(1.0).timeout
		if is_heli:
			break  # collective-only hover test runs below
		if not ap_engaged:
			if p.get_ias_kts() > vr_kts and p.gear.on_ground:
				Input.action_press("pitch_up", 0.5)
			if not p.gear.on_ground and p.agl > 25.0:
				# Hand over to the autopilot for the climb-out
				Input.action_release("pitch_up")
				p.autopilot.engage(p.get_heading(), p.global_position.y, p.get_ias())
				p.autopilot.target_alt_m = p.global_position.y + 250.0
				p.autopilot.target_ias = maxf(p.cfg.stall_speed_clean * 1.4, p.get_ias())
				ap_engaged = true
				print("  -- autopilot engaged --")
		if step_i % 2 == 0:
			var rho := Atmosphere.density(p.global_position.y)
			var tas := (p.linear_velocity - p.wind).length()
			var thrust_now := p.propulsion.thrust(rho, p.get_mach(), tas)
			var n_total := 0.0
			for wh in p.gear.wheels:
				n_total += wh.normal_force
			var fwd := -p.global_transform.basis.z
			print("  t=%2ds ias=%5.1fkts thrN=%6.0f gearFwd=%8.0f gearUp=%7.0f aeroF=(%6.0f,%7.0f,%7.0f) v=%5.1f" %
				[step_i + 1, p.get_ias_kts(), thrust_now, p.gear.last_force_sum.dot(fwd), p.gear.last_force_sum.y,
				p.last_aero_force.x, p.last_aero_force.y, p.last_aero_force.z, p.linear_velocity.length()])
	if is_heli:
		for hstep in 14:
			await get_tree().create_timer(1.0).timeout
			if hstep % 2 == 0:
				print("  h t=%2ds agl=%5.1fm vs=%6.0ffpm pitch=%4.0f bank=%4.0f rpm=%.2f grd=%s crash=%s" %
					[hstep + 1, p.agl, p.get_vs_fpm(), p.get_pitch_deg(), p.get_bank(), p.propulsion.rotor_rpm, str(p.gear.on_ground), str(p.crashed)])
	print("SMOKETEST: after 12s  ias=%.1f kts  alt=%.0f ft  agl=%.0f m  pos=%s  on_ground=%s" %
		[p.get_ias_kts(), p.get_alt_ft(), p.agl, str(p.global_position.snapped(Vector3.ONE)), str(p.gear.on_ground)])
	print("SMOKETEST: ATC phase=%d  options=%d  terrain_chunks=%d" % [ATC.phase, ATC.options.size(), Game.world.terrain._chunks.size()])
	Input.action_release("pitch_up")
	var ok: bool
	if is_heli:
		ok = p.agl > 18.0 and not p.crashed
	else:
		ok = p.get_alt_ft() > 150.0 and not p.crashed and p.get_ias_kts() > 45.0
	print("SMOKETEST %s" % ("OK - climbed away" if ok else "FAIL: did not climb away"))
	Game.return_to_menu()
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if ok else 1)

func goto_menu() -> void:
	_clear_flight()
	if menu == null:
		menu = load("res://ui/MainMenu.gd").new()
		add_child(menu)

func goto_world() -> void:
	if menu:
		menu.queue_free()
		menu = null
	_clear_flight()
	world = WorldRoot.new()
	world.name = "World"
	add_child(world)
	hud = load("res://ui/HUD.gd").new()
	add_child(hud)

func _clear_flight() -> void:
	if world:
		world.queue_free()
		world = null
	if hud:
		hud.queue_free()
		hud = null
