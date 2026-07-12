class_name Propulsion
extends RefCounted
## Per-engine thrust, spool dynamics, fuel burn, failures and restarts.
## Types: piston (prop), turboprop, turbofan, turbojet_ab (afterburning), rotor.

var cfg: AircraftConfig
var running: Array[bool] = []
var n1: Array[float] = []          # 0..1 spool state per engine
var health: Array[float] = []      # per-engine health 0..1
var afterburner: bool = false
var throttle: float = 0.0          # commanded 0..1
var rotor_rpm: float = 0.0         # helicopter rotor spool 0..1
var ab_time: float = 0.0           # continuous afterburner seconds (heat)

const JET_IDLE := 0.22
const PROP_EFF := 0.80

func _init(config: AircraftConfig) -> void:
	cfg = config
	for i in cfg.engine_count:
		running.append(false)
		n1.append(0.0)
		health.append(1.0)

func all_running() -> bool:
	for r in running:
		if not r:
			return false
	return true

func any_running() -> bool:
	for r in running:
		if r:
			return true
	return false

func start_all() -> void:
	for i in cfg.engine_count:
		if health[i] > 0.12:
			running[i] = true

func stop_all() -> void:
	for i in cfg.engine_count:
		running[i] = false
	afterburner = false

func fail_engine(i: int) -> void:
	if i >= 0 and i < running.size():
		running[i] = false

func average_n1() -> float:
	var s := 0.0
	for v in n1:
		s += v
	return s / maxf(n1.size(), 1.0)

## Advance spool state. Returns fuel burned (kg) this step.
func update(dt: float, _rho: float, _mach: float) -> float:
	var fuel_burned := 0.0
	# Afterburner engages automatically above 95% throttle on AB-capable jets
	afterburner = cfg.ab_thrust > 0.0 and throttle > 0.95 and any_running()
	ab_time = ab_time + dt if afterburner else maxf(ab_time - dt * 2.0, 0.0)

	for i in cfg.engine_count:
		var target := 0.0
		if running[i]:
			if cfg.engine_type == "piston":
				target = throttle
			else:
				target = JET_IDLE + (1.0 - JET_IDLE) * throttle
			target *= clampf(health[i] * 1.25, 0.0, 1.0)  # sick engines can't reach full power
		var rate: float = cfg.spool_rate * (1.6 if target < n1[i] else 1.0)
		n1[i] = move_toward(n1[i], target, rate * dt)
		if running[i]:
			var burn_frac: float = 0.14 + 0.86 * n1[i]
			if afterburner:
				burn_frac *= 2.9
			fuel_burned += cfg.fuel_burn_full / cfg.engine_count * burn_frac * dt

	if cfg.is_helicopter():
		var rpm_target := 1.0 if any_running() else 0.0
		rotor_rpm = move_toward(rotor_rpm, rpm_target, 0.12 * dt if rpm_target > rotor_rpm else 0.25 * dt)
	return fuel_burned

## Thrust of one engine along -Z (body forward), in newtons. Negative values
## are windmilling drag from a dead engine. Helicopter lift is produced by
## Aero's rotor model instead - this returns 0 for rotors.
func thrust_engine(i: int, rho: float, mach: float, tas: float) -> float:
	if cfg.engine_type == "rotor" or i >= n1.size():
		return 0.0
	var rho_ratio: float = rho / Atmosphere.RHO0
	if n1[i] <= 0.01:
		# Windmilling / dead engine drag
		return -350.0 * (cfg.mtow / (20000.0 * cfg.engine_count)) * clampf(tas / 80.0, 0.0, 1.5)
	var t := 0.0
	match cfg.engine_type:
		"piston":
			var power: float = cfg.max_power * n1[i] * (0.4 + 0.6 * rho_ratio)
			var prop_r: float = 0.55 * pow(cfg.max_power / 100000.0, 0.33) + 0.4
			var disc := PI * prop_r * prop_r
			var t_static := 0.85 * pow(power, 0.6667) * pow(2.0 * rho * disc, 0.3333)
			t = minf(t_static, power * PROP_EFF / maxf(tas, 8.0))
		"turboprop":
			var power2: float = cfg.max_power * n1[i] * rho_ratio
			t = minf(0.9 * pow(power2, 0.6667) * pow(2.0 * rho * 9.0, 0.3333), power2 * 0.82 / maxf(tas, 12.0))
		"turbofan":
			t = cfg.max_thrust * n1[i] * pow(rho_ratio, 0.85) * (1.0 - 0.22 * mach + 0.07 * mach * mach)
		"turbojet_ab":
			t = cfg.max_thrust * n1[i] * pow(rho_ratio, 0.8) * (1.0 - 0.12 * mach + 0.11 * mach * mach)
			if afterburner:
				t += (cfg.ab_thrust - cfg.max_thrust) * pow(rho_ratio, 0.7)
	return maxf(t, 0.0) * health[i]

func thrust(rho: float, mach: float, tas: float) -> float:
	var total := 0.0
	for i in cfg.engine_count:
		total += thrust_engine(i, rho, mach, tas)
	return total
