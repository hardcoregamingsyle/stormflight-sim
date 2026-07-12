class_name DamageSystem
extends RefCounted
## Subsystem health, wear, stress damage and probabilistic failures.
## Health degrades slowly in normal flight; abusing the airframe (over-G,
## overspeed, hard landings, afterburner abuse) degrades it fast. The lower a
## system's health, the higher its chance of failing outright.

signal failed(system_name: String, description: String)

const SYSTEMS := ["structure", "flaps", "gear", "hydraulics", "avionics"]

const BASE_WEAR := 0.000012      # /s (~4.3% per hour of normal flight)
const FAIL_CHECK_INTERVAL := 1.0

var cfg: AircraftConfig
var health: Dictionary = {}      # system -> 0..1 (engines tracked in Propulsion)
var failures: Dictionary = {}    # system -> true once failed
var _fail_timer := 0.0
var rng := RandomNumberGenerator.new()

const FAILURE_DESCRIPTIONS := {
	"engine": "Engine %d flameout",
	"flaps": "Flap actuator jammed",
	"gear": "Landing gear hydraulics stuck",
	"hydraulics": "Hydraulic pressure loss - controls degraded",
	"avionics": "Avionics fault - autopilot offline",
}

func _init(config: AircraftConfig) -> void:
	cfg = config
	for s in SYSTEMS:
		health[s] = 1.0
	rng.randomize()

func restore_from(saved: Dictionary) -> void:
	for s in SYSTEMS:
		if saved.has(s):
			health[s] = clampf(float(saved[s]), 0.0, 1.0)

func snapshot() -> Dictionary:
	var d := {}
	for s in SYSTEMS:
		d[s] = health[s]
	return d

func overall() -> float:
	var lowest := 1.0
	for s in SYSTEMS:
		lowest = minf(lowest, health[s])
	return lowest

func damage(system: String, amount: float) -> void:
	if not health.has(system):
		return
	var before: float = health[system]
	health[system] = clampf(before - amount, 0.0, 1.0)
	if absf(before - health[system]) > 0.005:
		EventBus.health_changed.emit(system, health[system])

func repair_all() -> void:
	for s in SYSTEMS:
		health[s] = 1.0
	failures.clear()

## Per-physics-tick wear + stress accumulation.
## stress: {g: current load factor, ias, vne, flap_frac, gear_down, ab_time, engines_n1}
func update(dt: float, stress: Dictionary, propulsion: Propulsion) -> void:
	# Slow ambient wear on everything while powered
	if propulsion.any_running():
		for s in SYSTEMS:
			damage(s, BASE_WEAR * dt)
		for i in propulsion.health.size():
			propulsion.health[i] = clampf(propulsion.health[i] - BASE_WEAR * 1.4 * dt, 0.0, 1.0)

	var g: float = stress.g
	var ias: float = stress.ias
	# Over-G structural damage (quadratic beyond limit)
	if g > cfg.g_limit_pos or g < cfg.g_limit_neg:
		var excess: float = maxf(g - cfg.g_limit_pos, cfg.g_limit_neg - g)
		damage("structure", excess * excess * 0.006 * dt)
		damage("hydraulics", excess * excess * 0.002 * dt)
	# Overspeed
	if ias > cfg.vne:
		var over: float = ias / cfg.vne - 1.0
		damage("structure", over * 0.05 * dt)
		damage("avionics", over * 0.01 * dt)
	# Flap overspeed
	if stress.flap_frac > 0.05 and ias > cfg.vfe():
		damage("flaps", (ias / cfg.vfe() - 1.0) * 0.08 * dt * stress.flap_frac)
	# Gear overspeed
	if stress.gear_down and cfg.gear_retractable and ias > cfg.vle():
		damage("gear", (ias / cfg.vle() - 1.0) * 0.06 * dt)
	# Afterburner heat abuse
	if propulsion.ab_time > 90.0:
		for i in propulsion.health.size():
			propulsion.health[i] = clampf(propulsion.health[i] - 0.0004 * dt, 0.0, 1.0)

	# ---- Probabilistic failures ----
	_fail_timer += dt
	if _fail_timer >= FAIL_CHECK_INTERVAL:
		_fail_timer = 0.0
		_roll_failures(propulsion)

func _roll_failures(propulsion: Propulsion) -> void:
	# Engines
	for i in propulsion.health.size():
		if propulsion.running[i]:
			var h: float = propulsion.health[i]
			var p := 0.0016 * pow(1.0 - h, 2.0)
			if h < 0.05:
				p = 0.05
			if rng.randf() < p:
				propulsion.fail_engine(i)
				failed.emit("engine", FAILURE_DESCRIPTIONS["engine"] % (i + 1))
	# Other systems
	for s in ["flaps", "gear", "hydraulics", "avionics"]:
		if failures.has(s):
			continue
		var h: float = health[s]
		var p := 0.0012 * pow(1.0 - h, 2.0)
		if h < 0.04:
			p = 0.04
		if rng.randf() < p:
			failures[s] = true
			failed.emit(s, FAILURE_DESCRIPTIONS[s])

func has_failed(system: String) -> bool:
	return failures.get(system, false)

func clear_failure(system: String) -> void:
	failures.erase(system)

## Landing impact. Returns severity string for UI/economy.
func landing_impact(fpm: float) -> String:
	if fpm < 200.0:
		return "butter"
	if fpm < 450.0:
		return "good"
	if fpm < 700.0:
		damage("gear", 0.05)
		return "firm"
	if fpm < 1000.0:
		damage("gear", 0.22)
		damage("structure", 0.10)
		return "hard"
	damage("gear", 0.6)
	damage("structure", 0.4)
	return "severe"

func control_effectiveness() -> float:
	var h: float = health["hydraulics"]
	if has_failed("hydraulics"):
		return 0.45
	return clampf(0.5 + 0.5 * h, 0.5, 1.0)

func structure_effectiveness() -> float:
	return clampf(0.55 + 0.45 * health["structure"], 0.55, 1.0)
