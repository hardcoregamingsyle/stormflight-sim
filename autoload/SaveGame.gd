extends Node
## Persistent player profile: SkyCoins, owned aircraft, per-airframe condition,
## settings and lifetime stats. JSON in user:// (IndexedDB-backed on web).

const SAVE_PATH := "user://stormfighter_save.json"
const STARTING_COINS := 1500

var data: Dictionary = {}
var _dirty: bool = false

func _ready() -> void:
	load_game()
	var t := Timer.new()
	t.wait_time = 10.0  # web tabs can close without notice - save often
	t.autostart = true
	t.timeout.connect(_autosave)
	add_child(t)

func _defaults() -> Dictionary:
	return {
		"coins": STARTING_COINS,
		"owned": ["cessna172"],
		"condition": {},          # aircraft_id -> {health subsystems, fuel_frac}
		"settings": {
			"volume": 0.8,
			"invert_pitch": false,
			"time_scale": 15.0,
			"player_name": "Pilot",
			"assists": true,
			"quality_override": "auto",
		},
		"stats": {
			"flight_time_s": 0.0,
			"landings": 0,
			"crashes": 0,
			"jobs_done": 0,
			"total_earned": 0,
			"total_penalties": 0,
			"distance_km": 0.0,
		},
	}

func load_game() -> void:
	data = _defaults()
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_merge_into(data, parsed)

## Recursive merge so old saves gain new default keys safely.
func _merge_into(base: Dictionary, incoming: Dictionary) -> void:
	for k in incoming.keys():
		if base.has(k) and base[k] is Dictionary and incoming[k] is Dictionary:
			_merge_into(base[k], incoming[k])
		else:
			base[k] = incoming[k]

func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
	_dirty = false

func mark_dirty() -> void:
	_dirty = true

func _autosave() -> void:
	if _dirty:
		save_game()

# --- Coins ---
func coins() -> int:
	return int(data["coins"])

func add_coins(amount: int) -> void:
	data["coins"] = maxi(0, coins() + amount)
	if amount > 0:
		data["stats"]["total_earned"] = int(data["stats"]["total_earned"]) + amount
	else:
		data["stats"]["total_penalties"] = int(data["stats"]["total_penalties"]) - amount
	_dirty = true
	EventBus.sky_coins_changed.emit(coins())

func can_afford(amount: int) -> bool:
	return coins() >= amount

# --- Ownership ---
func owns(aircraft_id: String) -> bool:
	return aircraft_id in (data["owned"] as Array)

func grant_aircraft(aircraft_id: String) -> void:
	if not owns(aircraft_id):
		(data["owned"] as Array).append(aircraft_id)
		_dirty = true

# --- Condition persistence (health/fuel per owned airframe) ---
func get_condition(aircraft_id: String) -> Dictionary:
	var cond: Dictionary = data["condition"]
	if not cond.has(aircraft_id):
		return {}
	return cond[aircraft_id]

func set_condition(aircraft_id: String, condition: Dictionary) -> void:
	data["condition"][aircraft_id] = condition
	_dirty = true

# --- Settings / stats helpers ---
func setting(key: String, default_value = null):
	return data["settings"].get(key, default_value)

func set_setting(key: String, value) -> void:
	data["settings"][key] = value
	_dirty = true

func add_stat(key: String, amount) -> void:
	data["stats"][key] = data["stats"].get(key, 0) + amount
	_dirty = true

func stat(key: String):
	return data["stats"].get(key, 0)
