class_name Atmosphere
## International Standard Atmosphere model (troposphere + lower stratosphere).
## All static - pure functions of altitude in meters MSL.

const RHO0 := 1.225           # kg/m^3 sea level density
const T0 := 288.15            # K sea level temperature
const P0 := 101325.0          # Pa
const LAPSE := 0.0065         # K/m tropospheric lapse rate
const TROPOPAUSE := 11000.0   # m
const T_STRAT := 216.65       # K stratosphere temperature

static func temperature(alt_m: float) -> float:
	if alt_m < TROPOPAUSE:
		return T0 - LAPSE * maxf(alt_m, 0.0)
	return T_STRAT

static func density(alt_m: float) -> float:
	var h := clampf(alt_m, 0.0, 25000.0)
	if h < TROPOPAUSE:
		var t := T0 - LAPSE * h
		return RHO0 * pow(t / T0, 4.2561)
	var rho_trop := RHO0 * pow(T_STRAT / T0, 4.2561)
	return rho_trop * exp(-(h - TROPOPAUSE) / 6341.6)

static func speed_of_sound(alt_m: float) -> float:
	return sqrt(1.4 * 287.05 * temperature(alt_m))

## Indicated airspeed from true airspeed (what the airspeed tape shows).
static func tas_to_ias(tas: float, alt_m: float) -> float:
	return tas * sqrt(density(alt_m) / RHO0)

static func ias_to_tas(ias: float, alt_m: float) -> float:
	return ias / sqrt(density(alt_m) / RHO0)

static func mach(tas: float, alt_m: float) -> float:
	return tas / speed_of_sound(alt_m)

const MS_TO_KTS := 1.943844
const M_TO_FT := 3.28084
const MS_TO_FPM := 196.8504
