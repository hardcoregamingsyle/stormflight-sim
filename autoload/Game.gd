extends Node
## Session state + input registration + scene flow.

enum Mode { MENU, SOLO, HOST, CLIENT }

const WORLD_SEED := 1337

var mode: int = Mode.MENU
var selected_aircraft_id: String = "cessna172"
var selected_airport_id: String = "sfi"
var world: Node = null            # WorldRoot when flying
var player_aircraft: Node = null  # Aircraft when flying
var paused: bool = false
var typing: bool = false          # chat box focused - suppress flight inputs

func _init() -> void:
	_register_inputs()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

# ------------------------------------------------------------------ input map
func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	return ev

func _add(action: String, events: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for ev in events:
		InputMap.action_add_event(action, ev)

func _register_inputs() -> void:
	# Throttle / collective
	_add("throttle_up", [_key(KEY_W)])
	_add("throttle_down", [_key(KEY_S)])
	# Rudder / pedals
	_add("yaw_left", [_key(KEY_A)])
	_add("yaw_right", [_key(KEY_D)])
	# Pitch / roll (elevator pull = arrow down, standard yoke sense)
	_add("pitch_up", [_key(KEY_DOWN)])
	_add("pitch_down", [_key(KEY_UP)])
	_add("roll_left", [_key(KEY_LEFT)])
	_add("roll_right", [_key(KEY_RIGHT)])
	# Trim
	_add("trim_up", [_key(KEY_PERIOD)])
	_add("trim_down", [_key(KEY_COMMA)])
	# Systems
	_add("gear_toggle", [_key(KEY_G)])
	_add("flaps_down", [_key(KEY_F)])
	_add("flaps_up", [_key(KEY_V)])
	_add("spoilers_toggle", [_key(KEY_H)])
	_add("brakes", [_key(KEY_B)])
	_add("parking_brake", [_key(KEY_N)])
	_add("engine_toggle", [_key(KEY_I)])
	_add("pushback", [_key(KEY_U)])
	_add("autopilot_toggle", [_key(KEY_X)])
	# Views / panels
	_add("camera_cycle", [_key(KEY_C)])
	_add("map_toggle", [_key(KEY_M)])
	_add("jobs_toggle", [_key(KEY_J)])
	_add("atc_toggle", [_key(KEY_TAB)])
	_add("help_toggle", [_key(KEY_F1)])
	_add("pause_menu", [_key(KEY_ESCAPE)])
	_add("chat", [_key(KEY_ENTER)])
	# ATC quick replies 1..9
	for i in range(1, 10):
		_add("atc_option_%d" % i, [_key(KEY_0 + i)])

# ------------------------------------------------------------------ flow
func player_name() -> String:
	return String(SaveGame.setting("player_name", "Pilot"))

func callsign() -> String:
	var n := player_name().strip_edges()
	if n.is_empty():
		n = "Pilot"
	return "Storm %s" % n.substr(0, 12)

func start_flight(aircraft_id: String, airport_id: String, new_mode: int = Mode.SOLO) -> void:
	selected_aircraft_id = aircraft_id
	selected_airport_id = airport_id
	mode = new_mode
	get_tree().paused = false
	var main := get_tree().root.get_node("Main")
	main.call("goto_world")

func return_to_menu() -> void:
	SaveGame.save_game()
	Net.leave()
	mode = Mode.MENU
	world = null
	player_aircraft = null
	get_tree().paused = false
	var main := get_tree().root.get_node("Main")
	main.call("goto_menu")

func is_multiplayer() -> bool:
	return mode == Mode.HOST or mode == Mode.CLIENT
