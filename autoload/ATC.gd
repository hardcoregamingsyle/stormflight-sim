extends Node
## Automated ATC. Walks the player through a real clearance flow:
## clearance delivery -> ground taxi (routed through the airport taxi graph)
## -> tower (line up / cleared for takeoff, wind report) -> departure ->
## center (assigned cruise altitude) -> approach (into-wind runway) ->
## cleared to land -> taxi to an assigned random gate -> flight closed.
## Compliance flags feed RuleMonitor; helicopters get simplified hover ops.

enum Phase { IDLE, AT_GATE, CLEARANCE, TAXI_OUT, HOLDING_SHORT, LINEUP, TAKEOFF_CLEARED, DEPARTURE, ENROUTE, APPROACH, FINAL, TAXI_IN, EMERGENCY }

var phase: int = Phase.IDLE
var world: WorldRoot = null
var flight_airport: String = ""      # departure airport
var destination: String = ""
var dep_runway: Dictionary = {}      # {rw, end_name ("e1"/"e2"), heading}
var arr_runway: Dictionary = {}
var assigned_taxi_route: Array = []  # absolute Vector3 polyline
var assigned_altitude: float = 0.0   # meters MSL, 0 = none
var assigned_gate_pos: Vector3 = Vector3.ZERO
var cleared_takeoff := false
var cleared_to_land := false
var lineup_only := false
var options: Array = []              # [{id, label}]
var _timer := 0.0
var _chatter_timer := 20.0
var _lineup_timer := -1.0
var _rng := RandomNumberGenerator.new()

const CHATTER := [
	"Cargolift 214 heavy, descend and maintain 8,000.",
	"Skyhopper 62, traffic 2 o'clock, a 737 at 4,000.",
	"November 4 2 Charlie, squawk 4522.",
	"Stormline 88, reduce speed 210 knots.",
	"Glider traffic reported north of the field.",
	"Meridian 19, contact center on 128.4. Good day.",
]

func _ready() -> void:
	_rng.randomize()

# ------------------------------------------------------------------ lifecycle
func begin_flight(w: WorldRoot) -> void:
	world = w
	flight_airport = w.current_airport_id
	destination = ""
	phase = Phase.AT_GATE
	_clear_clearances()
	var a: Dictionary = AirportsDB.get_airport(flight_airport)
	var wind := w.wind_base
	var wind_from := fposmod(rad_to_deg(atan2(-wind.x, wind.z)), 360.0)
	_say("ATIS", "%s information Alpha: wind %03d at %d kts, weather %s, altimeter 29.92. Expect runway %s." %
		[a.name, int(wind_from), int(wind.length() * Atmosphere.MS_TO_KTS), w.weather, _pick_runway(flight_airport).id_str])
	_update_options()

func end_flight() -> void:
	phase = Phase.IDLE
	world = null
	_clear_clearances()
	options = []

func reset_flight() -> void:
	if world == null:
		return
	flight_airport = world.nearest_airport_id((Game.player_aircraft as Aircraft).abs_position())
	phase = Phase.AT_GATE
	_clear_clearances()
	_update_options()

func _clear_clearances() -> void:
	cleared_takeoff = false
	cleared_to_land = false
	lineup_only = false
	assigned_taxi_route = []
	assigned_altitude = 0.0
	dep_runway = {}
	arr_runway = {}

## True when the player may be on a runway right now.
func runway_use_allowed() -> bool:
	return cleared_takeoff or cleared_to_land or lineup_only or phase in [Phase.TAXI_IN, Phase.EMERGENCY]

# ------------------------------------------------------------------ helpers
func _say(channel: String, text: String) -> void:
	EventBus.atc_message.emit(true, channel, text)
	Sfx.play("radio_blip", 0.5)

func _reply(text: String) -> void:
	EventBus.atc_message.emit(false, "YOU", "%s, %s" % [text, Game.callsign()])

## Choose the runway end best aligned into the wind at an airport.
func _pick_runway(airport_id: String) -> Dictionary:
	var data: Dictionary = world.airport(airport_id) if world else {}
	if data.is_empty():
		return {}
	var wind := world.wind_base
	var wind_to := atan2(wind.x, -wind.z)  # direction wind blows TOWARD
	var best := {}
	var best_score := -2.0
	for rw in data.runways:
		for end in [["e1", rw.e1, rw.dir], ["e2", rw.e2, (rw.dir as Vector3) * -1.0]]:
			var dir3 := end[2] as Vector3
			var hdg := atan2(dir3.x, -dir3.z)
			# Landing/departing INTO wind: aircraft heading opposes wind_to
			var score := -cos(hdg - wind_to)
			if score > best_score:
				best_score = score
				var ids: PackedStringArray = String(rw.id).split("/")
				var id_str: String = ids[0] if end[0] == "e1" else (ids[1] if ids.size() > 1 else ids[0])
				best = {"rw": rw, "end": end[0], "threshold": end[1], "dir": dir3,
					"heading_deg": fposmod(rad_to_deg(hdg), 360.0), "id_str": id_str}
	return best

func _wind_call() -> String:
	var wind := world.wind_base
	var wind_from := fposmod(rad_to_deg(atan2(-wind.x, wind.z)), 360.0)
	return "wind %03d at %d" % [int(wind_from), int(wind.length() * Atmosphere.MS_TO_KTS)]

func _player() -> Aircraft:
	return Game.player_aircraft as Aircraft

func _is_heli() -> bool:
	var p := _player()
	return p != null and p.cfg.is_helicopter()

# ------------------------------------------------------------------ options
func _update_options() -> void:
	options = []
	var p := _player()
	if p == null or world == null:
		EventBus.atc_options_changed.emit(options)
		return
	match phase:
		Phase.AT_GATE:
			options.append({"id": "clearance", "label": "Request clearance (destination: %s)" % _dest_name()})
			if _is_heli():
				options.append({"id": "hover_dep", "label": "Request hover departure"})
		Phase.CLEARANCE:
			if _is_heli():
				options.append({"id": "hover_dep", "label": "Request hover departure"})
			else:
				options.append({"id": "taxi", "label": "Request pushback and taxi"})
		Phase.HOLDING_SHORT:
			options.append({"id": "ready", "label": "Ready for departure"})
		Phase.ENROUTE, Phase.DEPARTURE:
			options.append({"id": "approach", "label": "Request approach to %s" % _dest_name()})
		Phase.APPROACH, Phase.FINAL:
			options.append({"id": "go_around", "label": "Going around"})
		_:
			pass
	var in_flight_phase: bool = phase not in [Phase.AT_GATE, Phase.CLEARANCE, Phase.EMERGENCY]
	var has_trouble: bool = p.damage_sys != null and (not p.damage_sys.failures.is_empty() or not p.propulsion.all_running())
	if in_flight_phase and has_trouble:
		options.append({"id": "emergency", "label": "DECLARE EMERGENCY"})
	EventBus.atc_options_changed.emit(options)

func _dest_name() -> String:
	var d := destination
	if d == "":
		d = Jobs.active_destination()
	if d == "":
		# Nearest other airport
		var best_d := 1e18
		for id in AirportsDB.ids():
			if id == flight_airport:
				continue
			var dist := AirportsDB.distance_km(flight_airport, id)
			if dist < best_d:
				best_d = dist
				d = id
	return AirportsDB.get_airport(d).name if d != "" else "local"

func _dest_id() -> String:
	if destination != "":
		return destination
	var jd := Jobs.active_destination()
	if jd != "":
		return jd
	var best := ""
	var best_d := 1e18
	for id in AirportsDB.ids():
		if id == flight_airport:
			continue
		var dist := AirportsDB.distance_km(flight_airport, id)
		if dist < best_d:
			best_d = dist
			best = id
	return best

func select_option(index: int) -> void:
	if index < 0 or index >= options.size():
		return
	var id: String = options[index].id
	match id:
		"clearance":
			_do_clearance()
		"taxi":
			_do_taxi()
		"hover_dep":
			_do_hover_departure()
		"ready":
			_do_ready()
		"approach":
			_do_approach_request()
		"go_around":
			_do_go_around()
		"emergency":
			_do_emergency()
	_update_options()

# ------------------------------------------------------------------ actions
func _do_clearance() -> void:
	destination = _dest_id()
	var dist := AirportsDB.distance_km(flight_airport, destination)
	var p := _player()
	var cruise := 2400.0
	if dist > 120.0:
		cruise = 7500.0
	elif dist > 60.0:
		cruise = 4500.0
	cruise = minf(cruise, p.cfg.ceiling_ft / Atmosphere.M_TO_FT * 0.75)
	assigned_altitude = 0.0
	_reply("Requesting IFR clearance to %s" % _dest_name())
	_say("DEL", "%s, cleared to %s as filed. Climb runway heading to 3,000 ft, expect %s ft cruise one-zero minutes after departure. Contact ground for taxi." %
		[Game.callsign(), _dest_name(), _fmt_alt(cruise)])
	set_meta("cruise_alt", cruise)
	phase = Phase.CLEARANCE

func _do_taxi() -> void:
	dep_runway = _pick_runway(flight_airport)
	if dep_runway.is_empty():
		return
	var data: Dictionary = world.airport(flight_airport)
	var p := _player()
	var from := AirportBuilder.nearest_node(data, p.abs_position())
	# Route to the hold point of the chosen end
	var rw_index: int = data.runways.find(dep_runway.rw)
	var hold_node := "r%d_hold_%s" % [rw_index, dep_runway.end]
	assigned_taxi_route = AirportBuilder.taxi_route(data, from, hold_node)
	_reply("Requesting taxi")
	_say("GND", "%s, taxi to runway %s via the marked route, hold short. %s." %
		[Game.callsign(), dep_runway.id_str, _wind_call()])
	phase = Phase.TAXI_OUT
	p.gear.parking_brake = false

func _do_hover_departure() -> void:
	destination = _dest_id()
	cleared_takeoff = true
	phase = Phase.TAKEOFF_CLEARED
	_reply("Requesting hover departure")
	_say("TWR", "%s, cleared for hover departure, %s. Proceed on course, have a good flight." % [Game.callsign(), _wind_call()])

func _do_ready() -> void:
	_reply("Ready for departure, runway %s" % dep_runway.get("id_str", ""))
	if _rng.randf() < 0.45:
		lineup_only = true
		phase = Phase.LINEUP
		_lineup_timer = _rng.randf_range(6.0, 14.0)
		_say("TWR", "%s, runway %s, line up and wait." % [Game.callsign(), dep_runway.id_str])
	else:
		_grant_takeoff()

func _grant_takeoff() -> void:
	cleared_takeoff = true
	lineup_only = false
	phase = Phase.TAKEOFF_CLEARED
	_say("TWR", "%s, runway %s, %s, cleared for takeoff." % [Game.callsign(), dep_runway.id_str, _wind_call()])

func _do_approach_request() -> void:
	var dest := _dest_id()
	var p := _player()
	# If the filed destination is still out of range but another airport is
	# close by, offer THAT approach without overwriting the filed destination
	# until the player is actually landing there.
	if world.airport(dest).is_empty():
		var near := world.nearest_airport_id(p.abs_position())
		if not world.airport(near).is_empty() and (AirportsDB.position_m(near) - p.abs_position()).length() < 42000.0:
			dest = near
		else:
			_say("APP", "%s, continue toward %s, airport not yet in range. Request again when closer." % [Game.callsign(), _dest_name()])
			return
	arr_runway = _pick_runway_at(dest)
	destination = dest
	assigned_altitude = AirportsDB.get_airport(dest).elevation_m + 1100.0
	phase = Phase.APPROACH
	_reply("Requesting approach clearance")
	_say("APP", "%s, descend and maintain %s ft, expect runway %s at %s. Report established on final." %
		[Game.callsign(), _fmt_alt(assigned_altitude), arr_runway.id_str, AirportsDB.get_airport(dest).name])

func _pick_runway_at(airport_id: String) -> Dictionary:
	var save := flight_airport
	flight_airport = airport_id
	var result := _pick_runway(airport_id)
	flight_airport = save
	return result

func _do_go_around() -> void:
	cleared_to_land = false
	phase = Phase.APPROACH
	assigned_altitude = AirportsDB.get_airport(destination).elevation_m + 900.0
	_reply("Going around")
	_say("TWR", "%s, roger. Climb to %s ft, fly the pattern, expect re-clearance shortly." % [Game.callsign(), _fmt_alt(assigned_altitude)])

func _do_emergency() -> void:
	phase = Phase.EMERGENCY
	cleared_to_land = true
	cleared_takeoff = true
	assigned_altitude = 0.0
	var p := _player()
	var near := world.nearest_airport_id(p.abs_position())
	destination = near
	arr_runway = _pick_runway_at(near) if not world.airport(near).is_empty() else {}
	_reply("MAYDAY MAYDAY MAYDAY, declaring emergency")
	_say("APP", "%s, MAYDAY acknowledged. All runways available at %s, you are cleared to land any runway. Emergency services rolling." %
		[Game.callsign(), AirportsDB.get_airport(near).name])
	EventBus.toast("Emergency declared - all clearances granted", "warn")

# ------------------------------------------------------------------ notifications
func notify_airborne() -> void:
	# Advance from ANY ground phase - an unauthorized takeoff must not strand
	# the state machine on the ground while the player is flying.
	if phase in [Phase.TAKEOFF_CLEARED, Phase.AT_GATE, Phase.CLEARANCE, Phase.TAXI_OUT, Phase.HOLDING_SHORT, Phase.LINEUP]:
		cleared_takeoff = false
		assigned_taxi_route = []
		phase = Phase.DEPARTURE
		_timer = 12.0
	elif phase == Phase.EMERGENCY:
		cleared_takeoff = false
		assigned_taxi_route = []
	_update_options()

func notify_landed() -> void:
	if world == null:
		return
	var p := _player()
	if p == null:
		return
	if phase in [Phase.FINAL, Phase.APPROACH, Phase.EMERGENCY] or cleared_to_land:
		var near := world.nearest_airport_id(p.abs_position())
		flight_airport = near
		var data: Dictionary = world.airport(near)
		cleared_to_land = false
		assigned_altitude = 0.0
		if not data.is_empty():
			var gate: Dictionary = world.random_gate(near)
			assigned_gate_pos = gate.get("pos", p.abs_position())
			var from := AirportBuilder.nearest_node(data, p.abs_position())
			var gi: int = data.gates.find(gate)
			assigned_taxi_route = AirportBuilder.taxi_route(data, from, "gate_%d" % maxi(gi, 0))
			phase = Phase.TAXI_IN
			_say("GND", "%s, welcome to %s. Exit the runway when able and taxi to %s. Shut down engines at the stand to close your flight." %
				[Game.callsign(), data.name, gate.get("name", "the apron")])
		else:
			# Landed in the wilderness: keep ATC alive for the next departure
			phase = Phase.AT_GATE
	elif p.cfg.is_helicopter():
		phase = Phase.AT_GATE
	_update_options()

# ------------------------------------------------------------------ tick
func _process(dt: float) -> void:
	if world == null or phase == Phase.IDLE:
		return
	var p := _player()
	if p == null:
		return

	# Lineup -> takeoff clearance
	if phase == Phase.LINEUP and _lineup_timer > 0.0:
		_lineup_timer -= dt
		if _lineup_timer <= 0.0:
			_grant_takeoff()
			_update_options()

	# Hold-short arrival detection
	if phase == Phase.TAXI_OUT and not assigned_taxi_route.is_empty():
		var hold: Vector3 = assigned_taxi_route[assigned_taxi_route.size() - 1]
		if p.abs_position().distance_to(hold) < 45.0 and p.linear_velocity.length() < 3.0:
			phase = Phase.HOLDING_SHORT
			_say("GND", "%s, holding short runway %s. Monitor tower." % [Game.callsign(), dep_runway.id_str])
			_update_options()

	# Departure -> enroute handoff
	if phase == Phase.DEPARTURE:
		_timer -= dt
		if _timer <= 0.0 and p.agl > 400.0:
			phase = Phase.ENROUTE
			assigned_altitude = float(get_meta("cruise_alt", 3000.0))
			_say("CTR", "%s, radar contact. Climb and maintain %s ft, proceed direct %s." %
				[Game.callsign(), _fmt_alt(assigned_altitude), _dest_name()])
			_update_options()

	# Auto-offer approach when getting close
	if phase == Phase.ENROUTE and destination != "":
		var dest_pos := AirportsDB.position_m(destination)
		var d := (p.abs_position() - dest_pos).length()
		if d < 42000.0:
			_do_approach_request()
			_update_options()

	# Approach -> final (cleared to land)
	if phase == Phase.APPROACH and not arr_runway.is_empty():
		# Runway thresholds from AirportBuilder are already absolute coords
		var thr_abs := arr_runway.threshold as Vector3
		var data: Dictionary = world.airport(destination)
		if not data.is_empty():
			var to_thr := thr_abs - p.abs_position()
			var horiz := Vector2(to_thr.x, to_thr.z).length()
			var dir3 := arr_runway.dir as Vector3
			var align := to_thr.normalized().dot(dir3)
			if horiz < 14000.0 and align > 0.75 and p.agl < 1300.0:
				cleared_to_land = true
				phase = Phase.FINAL
				_say("TWR", "%s, runway %s, %s, cleared to land." % [Game.callsign(), arr_runway.id_str, _wind_call()])
				_update_options()

	# Final: stability advisory
	if phase == Phase.FINAL and p.get_vs_fpm() < -1400.0 and p.agl < 350.0:
		if _chatter_timer > 5.0:
			_say("TWR", "%s, you appear unstable. Go around if in doubt." % Game.callsign())
			_chatter_timer = 0.0

	# Taxi-in completion: at gate, stopped, engines off
	if phase == Phase.TAXI_IN and assigned_gate_pos != Vector3.ZERO:
		if p.abs_position().distance_to(assigned_gate_pos) < 30.0 and p.linear_velocity.length() < 0.5 and not p.propulsion.any_running():
			phase = Phase.AT_GATE
			flight_airport = world.nearest_airport_id(p.abs_position())
			destination = ""
			assigned_taxi_route = []
			_say("GND", "%s, flight closed. Welcome to %s!" % [Game.callsign(), AirportsDB.get_airport(flight_airport).name])
			Economy.instant(35, "Completed full ATC procedure")
			Jobs.notify_parked(flight_airport)
			_update_options()

	# Ambient chatter
	_chatter_timer += dt
	if _chatter_timer > _rng.randf_range(35.0, 75.0) and phase not in [Phase.IDLE, Phase.AT_GATE]:
		_chatter_timer = 0.0
		EventBus.atc_message.emit(true, "---", CHATTER[_rng.randi() % CHATTER.size()])

func _fmt_alt(alt_m: float) -> String:
	var ft := int(round(alt_m * Atmosphere.M_TO_FT / 100.0) * 100)
	return str(ft).insert(str(ft).length() - 3, ",") if ft >= 1000 else str(ft)
