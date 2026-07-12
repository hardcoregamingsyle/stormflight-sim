extends Node
## Sound manager. Engine/wind/rolling loops with dynamic pitch+volume,
## one-shot effects, warning loops (stall horn), all volume-scaled by the
## player's master volume setting.

var _streams: Dictionary = {}
var _engine: AudioStreamPlayer
var _ab: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _rolling: AudioStreamPlayer
var _stall: AudioStreamPlayer
var _oneshots: Array[AudioStreamPlayer] = []
var _current_engine_type := ""

const LOOPS := ["engine_prop_loop", "engine_jet_loop", "engine_heli_loop", "wind_loop", "rolling_loop", "ab_rumble_loop", "stall_horn"]
const SOUNDS := ["touchdown", "screech", "crash", "click", "warn_beep", "gear_motor", "flap_motor", "cash", "penalty", "radio_blip"]

func _ready() -> void:
	for n in LOOPS + SOUNDS:
		var path := "res://assets/audio/%s.wav" % n
		if ResourceLoader.exists(path):
			var s: AudioStream = load(path)
			if s is AudioStreamWAV and n in LOOPS:
				var w := s as AudioStreamWAV
				w.loop_mode = AudioStreamWAV.LOOP_FORWARD
				w.loop_begin = 0
				# Frame count from duration - correct for any import compression
				w.loop_end = int(w.get_length() * w.mix_rate)
			_streams[n] = s
	_engine = _make_player()
	_ab = _make_player()
	_wind = _make_player()
	_rolling = _make_player()
	_stall = _make_player()
	for i in 8:
		_oneshots.append(_make_player())
	EventBus.stall_warning.connect(_on_stall)
	EventBus.flight_ended.connect(stop_all)

func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	add_child(p)
	return p

func _vol() -> float:
	return clampf(float(SaveGame.setting("volume", 0.8)), 0.0, 1.0)

func _db(linear: float) -> float:
	return linear_to_db(clampf(linear * _vol(), 0.0001, 1.0))

func play(sound: String, volume: float = 1.0) -> void:
	if not _streams.has(sound):
		return
	for p in _oneshots:
		if not p.playing:
			p.stream = _streams[sound]
			p.volume_db = _db(volume)
			p.play()
			return

func stop_all() -> void:
	for p in [_engine, _ab, _wind, _rolling, _stall]:
		p.stop()
	_current_engine_type = ""

## Called each frame by the player's Aircraft.
func engine_state(engine_type: String, n1: float, ab_on: bool, rotor_rpm: float) -> void:
	var loop_name := "engine_jet_loop"
	var level := n1
	match engine_type:
		"piston", "turboprop":
			loop_name = "engine_prop_loop"
		"rotor":
			loop_name = "engine_heli_loop"
			level = rotor_rpm
		_:
			loop_name = "engine_jet_loop"
	if _current_engine_type != loop_name:
		_current_engine_type = loop_name
		if _streams.has(loop_name):
			_engine.stream = _streams[loop_name]
			_engine.play()
	if level < 0.02:
		if _engine.playing:
			_engine.stop()
	else:
		if not _engine.playing and _streams.has(loop_name):
			_engine.play()
		_engine.pitch_scale = 0.6 + level * 0.9
		_engine.volume_db = _db(0.12 + level * 0.75)
	# Afterburner rumble layer
	if ab_on and _streams.has("ab_rumble_loop"):
		if not _ab.playing:
			_ab.stream = _streams["ab_rumble_loop"]
			_ab.play()
		_ab.volume_db = _db(0.8)
	elif _ab.playing:
		_ab.stop()

func wind_state(intensity: float) -> void:
	if not _streams.has("wind_loop"):
		return
	if intensity < 0.04:
		if _wind.playing:
			_wind.stop()
		return
	if not _wind.playing:
		_wind.stream = _streams["wind_loop"]
		_wind.play()
	_wind.pitch_scale = 0.8 + intensity * 0.9
	_wind.volume_db = _db(clampf(intensity * intensity * 0.9, 0.0, 0.9))

func rolling_state(on_ground: bool, speed: float) -> void:
	if not _streams.has("rolling_loop"):
		return
	if not on_ground or speed < 1.0:
		if _rolling.playing:
			_rolling.stop()
		return
	if not _rolling.playing:
		_rolling.stream = _streams["rolling_loop"]
		_rolling.play()
	_rolling.pitch_scale = 0.7 + clampf(speed / 80.0, 0.0, 1.0)
	_rolling.volume_db = _db(clampf(speed / 60.0, 0.05, 0.7))

func _on_stall(active: bool) -> void:
	if active and _streams.has("stall_horn"):
		_stall.stream = _streams["stall_horn"]
		_stall.volume_db = _db(0.7)
		_stall.play()
	elif not active and _stall.playing:
		_stall.stop()
