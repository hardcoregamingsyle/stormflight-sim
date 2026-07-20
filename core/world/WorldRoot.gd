class_name WorldRoot
extends Node3D
## The in-flight world: floating-origin management, terrain streaming,
## airport streaming, day/night cycle, weather & wind, PAPI/windsock logic,
## player spawn at a random gate, crash respawn, and multiplayer hooks.
##
## Coordinate scheme: absolute world coords are huge (hundreds of km), so all
## static content lives under `static_root` positioned at -origin_offset.
## Aircraft fly in engine coords near the origin; when the player strays
## >8 km we shift everything back. abs = engine_pos + origin_offset.

const SHIFT_DISTANCE := 8192.0
const SHIFT_GRID := 1024.0
const AIRPORT_STREAM_IN := 45000.0
const AIRPORT_STREAM_OUT := 55000.0

var static_root: Node3D
var terrain: TerrainSystem
var player: Aircraft
var camera_rig: Node3D
var origin_off := Vector3.ZERO

var airports: Dictionary = {}        # id -> airport data (built)
var current_airport_id: String = ""

# Time & weather
var hour: float = 9.5
var weather: String = "clear"
var wind_base := Vector3.ZERO
var gust_amp := 0.0
var _gust_noise := FastNoiseLite.new()
var _t := 0.0
var _sun: DirectionalLight3D
var _env: Environment
var _stream_timer := 0.0
var _papi_timer := 0.0
var _respawning := false
var rule_monitor: Node = null

func origin_offset() -> Vector3:
	return origin_off

func height_at(global_pos: Vector3) -> float:
	var abs_p := global_pos + origin_off
	return terrain.height(abs_p.x, abs_p.z)

func wind_at(global_pos: Vector3) -> Vector3:
	var alt := global_pos.y
	var scale := 1.0 + clampf(alt / 4000.0, 0.0, 1.0) * 0.8
	var gx := _gust_noise.get_noise_2d(_t * 30.0, 0.0)
	var gz := _gust_noise.get_noise_2d(0.0, _t * 30.0 + 77.0)
	# Vertical gusts (thermals/turbulence) - fade out near the ground
	var gy := _gust_noise.get_noise_2d(_t * 24.0, 191.0) * clampf(alt / 250.0, 0.0, 1.0)
	return wind_base * scale + Vector3(gx, gy * 0.6, gz) * gust_amp

func _ready() -> void:
	Game.world = self
	_setup_weather()
	_setup_environment()

	static_root = Node3D.new()
	static_root.name = "StaticWorld"
	add_child(static_root)

	terrain = TerrainSystem.new()
	static_root.add_child(terrain)

	# Center the origin on the selected airport
	current_airport_id = Game.selected_airport_id
	var apos := AirportsDB.position_m(current_airport_id)
	origin_off = Vector3(snappedf(apos.x, SHIFT_GRID), 0.0, snappedf(apos.z, SHIFT_GRID))
	static_root.position = -origin_off

	_stream_airports(apos)
	terrain.update_streaming(apos)  # near terrain + collision before spawn
	_spawn_player()

	camera_rig = load("res://core/world/CameraRig.gd").new()
	add_child(camera_rig)
	camera_rig.call("attach", player)

	var rm: Node = (load("res://core/rules/RuleMonitor.gd") as GDScript).new()
	rule_monitor = rm
	add_child(rm)

	add_child((load("res://core/world/TaxiGuide.gd") as GDScript).new())

	if Quality.max_ai_traffic > 0 and not Game.is_multiplayer():
		var traffic: Node = (load("res://core/traffic/AITraffic.gd") as GDScript).new()
		add_child(traffic)

	ATC.begin_flight(self)
	Jobs.begin_flight(self)
	Economy.begin_flight()
	Net.world_ready(self)
	EventBus.aircraft_crashed.connect(_on_crash)
	EventBus.flight_started.emit()

func _exit_tree() -> void:
	if is_instance_valid(player):
		player.persist_condition()
	ATC.end_flight()
	Jobs.end_flight()
	Economy.end_flight()
	EventBus.flight_ended.emit()
	if Game.world == self:
		Game.world = null

# ------------------------------------------------------------------ weather
func _setup_weather() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Game.WORLD_SEED + int(Time.get_unix_time_from_system() / 3600.0) if not Game.is_multiplayer() else Game.WORLD_SEED
	var roll := rng.randf()
	if roll < 0.5:
		weather = "clear"
	elif roll < 0.75:
		weather = "scattered"
	elif roll < 0.9:
		weather = "overcast"
	else:
		weather = "storm"
	var speed: float = {"clear": rng.randf_range(1.5, 6.0), "scattered": rng.randf_range(4.0, 9.0),
		"overcast": rng.randf_range(6.0, 12.0), "storm": rng.randf_range(10.0, 18.0)}[weather]
	var dir := rng.randf() * TAU
	wind_base = Vector3(sin(dir), 0, cos(dir)) * speed
	gust_amp = {"clear": 0.6, "scattered": 1.6, "overcast": 2.5, "storm": 5.5}[weather]
	_gust_noise.seed = Game.WORLD_SEED + 3
	_gust_noise.frequency = 0.7
	hour = rng.randf_range(7.5, 17.0)

func _setup_environment() -> void:
	_sun = DirectionalLight3D.new()
	_sun.light_energy = 1.3
	Quality.sun_shadow(_sun)
	add_child(_sun)
	_env = Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.18, 0.38, 0.66)
	mat.sky_horizon_color = Color(0.63, 0.71, 0.78)
	mat.ground_bottom_color = Color(0.13, 0.15, 0.16)
	mat.ground_horizon_color = Color(0.63, 0.69, 0.75)
	sky.sky_material = mat
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 1.0
	_env.fog_enabled = true
	var vis: float = {"clear": 40000.0, "scattered": 30000.0, "overcast": 16000.0, "storm": 6500.0}.get(weather, 30000.0)
	_env.fog_density = 1.0 / vis
	_env.fog_light_color = Color(0.75, 0.79, 0.84)
	_env.fog_sky_affect = 0.2
	if not Quality.is_web:
		# Soft glow lifts emissives (city windows, beacons, afterburners)
		_env.glow_enabled = true
		_env.glow_intensity = 0.45
		_env.glow_bloom = 0.03
		_env.glow_hdr_threshold = 1.15
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

func _update_sun() -> void:
	var day_frac := fposmod(hour, 24.0) / 24.0
	var sun_angle := (day_frac - 0.25) * TAU  # 6h sunrise, 18h sunset
	_sun.rotation = Vector3(-sun_angle, deg_to_rad(35.0), 0)
	var elev := sin(sun_angle)
	_sun.light_energy = clampf(elev * 1.6, 0.02, 1.4)
	_sun.light_color = Color(1.0, lerpf(0.55, 0.95, clampf(elev * 3.0, 0.0, 1.0)), lerpf(0.3, 0.9, clampf(elev * 3.0, 0.0, 1.0)))
	_env.ambient_light_energy = clampf(0.12 + elev, 0.12, 1.0)
	var sky_mat := _env.sky.sky_material as ProceduralSkyMaterial
	var night := clampf(-elev * 2.5, 0.0, 0.92)
	sky_mat.sky_top_color = Color(0.18, 0.38, 0.66).lerp(Color(0.01, 0.015, 0.04), night)
	sky_mat.sky_horizon_color = Color(0.63, 0.71, 0.78).lerp(Color(0.03, 0.04, 0.08), night)
	sky_mat.ground_horizon_color = Color(0.63, 0.69, 0.75).lerp(Color(0.02, 0.03, 0.06), night)

# ------------------------------------------------------------------ airports
func _stream_airports(player_abs: Vector3) -> void:
	for id in AirportsDB.ids():
		var apos := AirportsDB.position_m(id)
		var d := Vector2(apos.x - player_abs.x, apos.z - player_abs.z).length()
		if d < AIRPORT_STREAM_IN and not airports.has(id):
			var data := AirportBuilder.build(id)
			static_root.add_child(data.root)
			airports[id] = data
		elif d > AIRPORT_STREAM_OUT and airports.has(id) and id != current_airport_id:
			(airports[id].root as Node3D).queue_free()
			airports.erase(id)

func airport(id: String) -> Dictionary:
	return airports.get(id, {})

func nearest_airport_id(abs_pos: Vector3) -> String:
	var best := ""
	var best_d := 1e18
	for id in AirportsDB.ids():
		var d := (AirportsDB.position_m(id) - abs_pos).length()
		if d < best_d:
			best_d = d
			best = id
	return best

## Pick a random free gate at an airport (must be streamed in). A gate also
## counts as taken when any aircraft (e.g. a multiplayer proxy) is parked
## within 40 m - gate occupancy itself is not networked.
func random_gate(airport_id: String) -> Dictionary:
	if not airports.has(airport_id):
		return {}
	var gates: Array = airports[airport_id].gates
	var origin := origin_off
	var craft_positions: Array = []
	for craft in get_tree().get_nodes_in_group("aircraft"):
		craft_positions.append((craft as Node3D).global_position + origin)
	var is_clear := func(g: Dictionary) -> bool:
		for cp in craft_positions:
			if (cp as Vector3).distance_to(g.pos) < 40.0:
				return false
		return true
	var free: Array = gates.filter(func(g): return not g.occupied and is_clear.call(g))
	if free.is_empty():
		free = gates.filter(func(g): return is_clear.call(g))
	if free.is_empty():
		free = gates
	return free[randi() % free.size()]

# ------------------------------------------------------------------ player
func _spawn_player() -> void:
	var cfg := AircraftDB.config(Game.selected_aircraft_id)
	player = Aircraft.new()
	player.name = "Player"
	player.world_ref = self
	player.pilot_name = Game.player_name()
	player.add_to_group("aircraft")
	add_child(player)
	player.setup(cfg, true)
	Game.player_aircraft = player
	_place_at_gate(player, current_airport_id)
	EventBus.aircraft_spawned.emit(player)

func _place_at_gate(craft: Aircraft, airport_id: String) -> void:
	var gate := random_gate(airport_id)
	var apos := AirportsDB.position_m(airport_id)
	var gp: Vector3 = gate.get("pos", apos + Vector3(0, 0, 0))
	var heading: float = gate.get("heading", 0.0)
	gate["occupied"] = true
	var local := gp - origin_off
	craft.global_position = local + Vector3(0, craft.gear.spawn_height(), 0)
	craft.rotation = Vector3(0, -heading, 0)
	craft.linear_velocity = Vector3.ZERO
	craft.angular_velocity = Vector3.ZERO
	craft.gear.parking_brake = true
	if craft == player:
		EventBus.toast("Spawned at %s, %s" % [AirportsDB.get_airport(airport_id).name, gate.get("name", "stand")], "info")

func _on_crash(reason: String) -> void:
	if _respawning:
		return
	_respawning = true
	SaveGame.add_stat("crashes", 1)
	EventBus.toast("CRASHED: %s" % reason, "bad")
	var t := get_tree().create_timer(4.0)
	t.timeout.connect(_respawn)

func _respawn() -> void:
	_respawning = false
	if not is_instance_valid(player):
		return
	player.crashed = false
	player.damage_sys.repair_all()
	for i in player.propulsion.health.size():
		player.propulsion.health[i] = 1.0
	player.fuel_kg = player.cfg.fuel_capacity * 0.5
	player.flap_setting = 0.0
	player.flap_frac = 0.0
	player.spoiler_setting = 0.0
	player.gear.gear_frac = 1.0
	player.gear.gear_target = 1.0
	player.gear.jammed = false
	var id := nearest_airport_id(player.abs_position())
	_stream_airports(AirportsDB.position_m(id))
	_place_at_gate(player, id)
	ATC.reset_flight()
	EventBus.toast("Aircraft recovered and repaired - fly carefully out there", "info")

# ------------------------------------------------------------------ tick
func _process(dt: float) -> void:
	_t += dt
	hour += dt * float(SaveGame.setting("time_scale", 15.0)) / 3600.0
	_update_sun()
	EventBus.world_time_changed.emit(hour)

	if not is_instance_valid(player):
		return
	var abs_p := player.abs_position()

	_stream_timer += dt
	if _stream_timer > 0.5:
		_stream_timer = 0.0
		terrain.update_streaming(abs_p)
		_stream_airports(abs_p)
		_check_origin_shift()

	_papi_timer += dt
	if _papi_timer > 0.25:
		_papi_timer = 0.0
		_update_papi_and_windsock(abs_p)

func _check_origin_shift() -> void:
	var p := player.global_position
	if absf(p.x) < SHIFT_DISTANCE and absf(p.z) < SHIFT_DISTANCE:
		return
	var delta := Vector3(snappedf(p.x, SHIFT_GRID), 0.0, snappedf(p.z, SHIFT_GRID))
	origin_off += delta
	static_root.position = -origin_off
	for craft in get_tree().get_nodes_in_group("aircraft"):
		(craft as Node3D).global_position -= delta
	if camera_rig:
		camera_rig.call("origin_shift", delta)
	EventBus.origin_shifted.emit(delta)

func _update_papi_and_windsock(abs_p: Vector3) -> void:
	var near_id := nearest_airport_id(abs_p)
	if not airports.has(near_id):
		return
	var data: Dictionary = airports[near_id]
	# Windsock
	if data.windsock:
		var w := wind_at(player.global_position)
		var sock := data.windsock as Node3D
		sock.rotation.y = atan2(w.x, w.z) - data.root.rotation.y
		sock.rotation.x = lerpf(-1.1, 0.0, clampf(w.length() / 10.0, 0.0, 1.0))
	# PAPI: white/red by glidepath angle
	for rw in data.runways:
		for papi in rw.papis:
			var thr: Vector3 = _papi_abs(data, papi)
			var to_p := abs_p - thr
			var horiz := Vector2(to_p.x, to_p.z).length()
			if horiz > 15000.0 or horiz < 50.0:
				continue
			var angle := rad_to_deg(atan2(to_p.y, horiz))
			var gates := [2.5, 2.8, 3.2, 3.5]
			for i in 4:
				var mi := papi.units[i] as MeshInstance3D
				var m := mi.material_override as StandardMaterial3D
				m.emission = Color(1, 1, 1) if angle > gates[i] else Color(1, 0.1, 0.08)

func _papi_abs(data: Dictionary, papi: Dictionary) -> Vector3:
	# papi.threshold was stored airport-local; convert to absolute
	return (data.origin as Vector3) + (papi.threshold as Vector3)
