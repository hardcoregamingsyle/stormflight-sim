class_name Autopilot
extends RefCounted
## Basic 3-axis autopilot + autothrottle: heading hold, altitude hold,
## speed hold. PID outputs feed the same control inputs a pilot uses.

var engaged: bool = false
var target_heading_deg: float = 0.0
var target_alt_m: float = 1000.0
var target_ias: float = 80.0

var _pitch_i := 0.0
var _spd_i := 0.0

func engage(current_heading: float, current_alt: float, current_ias: float) -> void:
	engaged = true
	target_heading_deg = current_heading
	target_alt_m = current_alt
	target_ias = current_ias
	_pitch_i = 0.0
	_spd_i = 0.0

func disengage() -> void:
	engaged = false

## Returns {elevator, aileron, rudder, throttle} or empty when off.
func update(dt: float, state: Dictionary) -> Dictionary:
	if not engaged:
		return {}
	var out := {}

	# --- Lateral: bank toward heading error (well-damped) ---
	var hdg_err := wrapf(target_heading_deg - state.heading_deg, -180.0, 180.0)
	var target_bank := clampf(hdg_err * 1.2, -20.0, 20.0)
	var bank_err: float = target_bank - state.bank_deg
	out["aileron"] = clampf(bank_err * 0.02 - state.roll_rate * 0.55, -0.5, 0.5)
	out["rudder"] = clampf(-state.slip * 1.2, -0.3, 0.3)

	# --- Vertical: VS command from altitude error, pitch from VS error ---
	var alt_err: float = target_alt_m - state.alt_m
	var vs_cmd := clampf(alt_err * 0.25, -8.0, 5.0)  # m/s
	var vs_err: float = vs_cmd - state.vs_ms
	_pitch_i = clampf(_pitch_i + vs_err * dt * 0.012, -0.28, 0.28)
	out["elevator"] = clampf(vs_err * 0.045 + _pitch_i - state.pitch_rate * 0.55, -0.5, 0.5)

	# --- Autothrottle ---
	var spd_err: float = target_ias - state.ias
	_spd_i = clampf(_spd_i + spd_err * dt * 0.004, -0.4, 0.4)
	out["throttle"] = clampf(0.55 + spd_err * 0.03 + _spd_i, 0.0, 1.0)
	return out
