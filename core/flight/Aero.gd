class_name Aero
extends RefCounted
## Component-buildup aerodynamics. Everything computed in BODY frame
## (+X right, +Y up, +Z back, nose = -Z), returned as {force, torque}.
##
## Fixed wing: left/right wing panels, horizontal tail, vertical tail and
## fuselage each see their own local airflow (translation + rotation), so
## roll/pitch/yaw damping, spiral tendencies and asymmetric stalls emerge
## from geometry instead of canned rates.
## Helicopter: rotor-disc model with translational lift, ground cushion,
## torque reaction, inflow damping and tail-rotor authority.

var cfg: AircraftConfig

# Derived geometry
var semi_span: float
var mean_chord: float
var wing_panel_area: float
var wing_panel_arm: float      # lateral distance to each half-wing aero center
var tail_arm: float
var htail_area: float
var vtail_area: float
var vtail_height: float
var fuselage_length: float
var rotor_mast_height: float

# Result extras (read by Aircraft after compute)
var alpha: float = 0.0
var beta: float = 0.0
var stalled: bool = false
var stall_margin: float = 1.0  # <0.15 means close to stall
var g_ratio: float = 0.0
var collect_debug: bool = false
var last_debug: Dictionary = {}  # per-surface torque breakdown (diagnostics)

const WING_INCIDENCE := 0.035  # rad, wing rigging angle vs fuselage
const TAIL_INCIDENCE := -0.03  # rad, stabilizer trim incidence
const DOWNWASH := 0.32
const CM0 := -0.045

func _init(config: AircraftConfig) -> void:
	cfg = config
	semi_span = cfg.wing_span * 0.5
	mean_chord = cfg.wing_area / maxf(cfg.wing_span, 0.1)
	wing_panel_area = cfg.wing_area * 0.5
	wing_panel_arm = semi_span * 0.42
	fuselage_length = float(cfg.mesh.get("fuselage_length_m", mean_chord * 7.0))
	tail_arm = fuselage_length * 0.42
	var ht_span := float(cfg.mesh.get("htail_span_m", cfg.wing_span * 0.35))
	var ht_chord := float(cfg.mesh.get("htail_chord_m", mean_chord * 0.6))
	htail_area = maxf(ht_span * ht_chord, cfg.wing_area * 0.12)
	var vt_h := float(cfg.mesh.get("vtail_height_m", semi_span * 0.35))
	var vt_c := float(cfg.mesh.get("vtail_chord_m", mean_chord * 0.8))
	vtail_area = maxf(vt_h * vt_c, cfg.wing_area * 0.08)
	vtail_height = vt_h * 0.5
	rotor_mast_height = cfg.rotor_main_radius * 0.28 + 0.9

## Smoothly-stalling lift coefficient.
func _cl(a: float, cl0: float, stall_a: float) -> float:
	var lin := cl0 + cfg.cl_alpha * a
	var flat := 1.05 * sin(2.0 * a)  # post-stall flat-plate behaviour
	var absa := absf(a)
	var blend := clampf((absa - stall_a) / 0.10, 0.0, 1.0)
	blend = blend * blend * (3.0 - 2.0 * blend)
	return lerpf(lin, flat, blend)

## in: state dictionary from Aircraft. out: {force: Vector3, torque: Vector3} body frame.
func compute(s: Dictionary) -> Dictionary:
	if cfg.is_helicopter():
		return _compute_heli(s)
	return _compute_fixed_wing(s)

func _compute_fixed_wing(s: Dictionary) -> Dictionary:
	var v: Vector3 = s.v_body
	var w: Vector3 = s.omega_body
	var rho: float = s.rho
	var force := Vector3.ZERO
	var torque := Vector3.ZERO

	var speed := v.length()
	if speed < 0.5:
		alpha = 0.0
		beta = 0.0
		stalled = false
		stall_margin = 1.0
		return {"force": force, "torque": torque}

	var vhat := v / speed
	alpha = atan2(-v.y, -v.z) if v.z < -0.1 else 0.0
	beta = atan2(v.x, maxf(-v.z, 0.5))

	var ctl: Dictionary = s.controls
	var eff: Dictionary = s.effectiveness
	var flap: float = ctl.flap
	var slat: float = ctl.slat
	var spoiler: float = ctl.spoiler
	var gear: float = ctl.gear
	var ctl_eff: float = eff.controls
	var lift_eff: float = eff.structure

	# Stall AoA extended by slats, slightly reduced at heavy flap
	var stall_a: float = cfg.alpha_stall + cfg.slat_alpha_bonus * slat - deg_to_rad(2.0) * flap
	var cl0_now: float = cfg.cl0 + cfg.flap_cl_bonus * flap
	var spoiler_lift_mult: float = 1.0 - cfg.spoiler_lift_kill * spoiler

	# Ground effect (McCormick): reduces induced drag, small lift gain
	var agl: float = s.agl
	var h_b: float = clampf(agl / maxf(cfg.wing_span, 1.0), 0.01, 2.0)
	var ge_ind: float = (33.0 * pow(h_b, 1.5)) / (1.0 + 33.0 * pow(h_b, 1.5))
	var ge_lift: float = 1.0 + 0.08 * exp(-4.0 * h_b)

	# ---------------- Wing halves ----------------
	last_debug = {}
	var total_cl := 0.0
	for side in [-1.0, 1.0]:
		var r := Vector3(side * wing_panel_arm, 0.0, -0.1 * mean_chord)
		var vloc := v + w.cross(r)
		var sp := vloc.length()
		if sp < 0.5:
			continue
		var q := 0.5 * rho * sp * sp
		var a_loc := atan2(-vloc.y, -vloc.z) if vloc.z < -0.1 else alpha
		a_loc += WING_INCIDENCE
		# Aileron: +input = roll right = left panel gains lift
		var ail_delta: float = -side * ctl.aileron * cfg.aileron_max * 1.0 * cfg.roll_authority * ctl_eff
		var cl := _cl(a_loc + ail_delta * 0.35, cl0_now, stall_a) * spoiler_lift_mult * lift_eff
		cl += ail_delta * 0.45 * clampf(1.0 - absf(a_loc) / (stall_a + 0.2), 0.25, 1.0)
		var cd_ind := cl * cl / (PI * cfg.aspect_ratio * cfg.oswald) * ge_ind
		var vh := vloc / sp
		var lift_dir := Vector3(1, 0, 0).cross(vh).normalized()
		var drag_dir := -vh
		var f := lift_dir * (cl * q * wing_panel_area * ge_lift) + drag_dir * (cd_ind * q * wing_panel_area)
		force += f
		torque += r.cross(f)
		total_cl += cl * 0.5
		if collect_debug:
			last_debug["wing_%s" % ("L" if side < 0 else "R")] = {"tq": r.cross(f), "cl": cl, "a": rad_to_deg(a_loc)}

	stall_margin = clampf((stall_a - absf(alpha + WING_INCIDENCE)) / stall_a, -1.0, 1.0)
	stalled = stall_margin < 0.02 and speed > cfg.stall_speed_clean * 0.5

	# ---------------- Horizontal tail ----------------
	var r_t := Vector3(0, 0, tail_arm)
	var vt := v + w.cross(r_t)
	var spt := vt.length()
	if spt > 0.5:
		var qt := 0.5 * rho * spt * spt
		var a_t := atan2(-vt.y, -vt.z) if vt.z < -0.1 else alpha
		a_t += TAIL_INCIDENCE - DOWNWASH * clampf(alpha, -0.35, 0.35)
		# Elevator: +input = pull = tail-down force. Trim adds to it.
		var elev: float = clampf(ctl.elevator + ctl.trim, -1.2, 1.2)
		a_t += -elev * cfg.elevator_max * 0.72 * cfg.pitch_authority * ctl_eff
		var cl_t := _cl(a_t, 0.0, deg_to_rad(18.0))
		var vht := vt / spt
		var lift_dir_t := Vector3(1, 0, 0).cross(vht).normalized()
		var f_t := lift_dir_t * (cl_t * qt * htail_area) - vht * (cl_t * cl_t * 0.18 * qt * htail_area)
		force += f_t
		torque += r_t.cross(f_t)
		if collect_debug:
			last_debug["htail"] = {"tq": r_t.cross(f_t), "cl": cl_t, "a": rad_to_deg(a_t)}

	# ---------------- Vertical tail ----------------
	var r_v := Vector3(0, vtail_height, tail_arm)
	var vv := v + w.cross(r_v)
	var spv := vv.length()
	if spv > 0.5:
		var qv := 0.5 * rho * spv * spv
		var a_v := atan2(vv.x, maxf(-vv.z, 0.5))
		a_v += ctl.rudder * cfg.rudder_max * 0.7 * cfg.yaw_authority * ctl_eff
		var cl_v := _cl(a_v, 0.0, deg_to_rad(22.0))
		var vhv := vv / spv
		var side_dir := Vector3(0, 1, 0).cross(vhv).normalized()
		var f_v := side_dir * (cl_v * qv * vtail_area)
		force += f_v
		torque += r_v.cross(f_v)
		if collect_debug:
			last_debug["vtail"] = {"tq": r_v.cross(f_v), "cl": cl_v, "a": rad_to_deg(a_v)}

	# ---------------- Fuselage / parasitic drag ----------------
	var q_dyn := 0.5 * rho * speed * speed
	var mach_now: float = s.mach
	var cd := cfg.cd0
	cd += cfg.flap_cd_bonus * flap * flap
	cd += cfg.spoiler_cd * spoiler
	cd += 0.021 * gear
	# Transonic wave drag rise keeps aircraft near their real Mach limits
	var m_crit: float = cfg.max_mach * 0.82
	if mach_now > m_crit:
		cd += 22.0 * pow(mach_now - m_crit, 3.0)
	force += -vhat * (cd * q_dyn * cfg.wing_area)
	# Slip side-drag (fuselage side area approximated)
	var side_area := fuselage_length * mean_chord * 0.55
	force += Vector3(-signf(beta) * sin(beta) * sin(beta) * q_dyn * side_area * 1.1, 0, 0)

	# Camber pitching moment
	torque.x += CM0 * q_dyn * cfg.wing_area * mean_chord

	# ---------------- Supplemental rotational damping ----------------
	var b := cfg.wing_span
	var damp_scale := 0.25 * rho * speed * cfg.wing_area
	torque.x += -damp_scale * mean_chord * mean_chord * 7.0 * w.x
	torque.y += -damp_scale * b * b * 0.11 * w.y
	torque.z += -damp_scale * b * b * 0.12 * w.z

	# Dihedral effect: sideslip rolls the aircraft away from the slip
	# (Cl_beta ~ -0.07, keeps the spiral mode tame like a real airframe)
	torque.z += -beta * q_dyn * cfg.wing_area * b * 0.065

	return {"force": force, "torque": torque}

# =====================================================================
func _compute_heli(s: Dictionary) -> Dictionary:
	var v: Vector3 = s.v_body
	var w: Vector3 = s.omega_body
	var rho: float = s.rho
	var ctl: Dictionary = s.controls
	var eff: Dictionary = s.effectiveness
	var force := Vector3.ZERO
	var torque := Vector3.ZERO

	var rpm: float = s.rotor_rpm       # 0..1 rotor spool
	var disc_area: float = cfg.wing_area
	var radius: float = maxf(cfg.rotor_main_radius, 1.0)
	var rho_ratio: float = rho / Atmosphere.RHO0

	alpha = 0.0
	beta = 0.0
	stalled = false
	stall_margin = 1.0

	# Max thrust budget: enough to hover at ~74% collective at MTOW, sea level
	var t_max: float = 1.35 * cfg.mtow * 9.81 * rho_ratio * rpm * rpm * eff.structure
	var collective: float = clampf(ctl.throttle, 0.0, 1.0)
	var thrust := collective * t_max

	# Translational lift + ground cushion
	var v_horiz := Vector2(v.x, v.z).length()
	thrust *= 1.0 + 0.16 * clampf(v_horiz / 26.0, 0.0, 1.0)
	var agl: float = s.agl
	thrust *= 1.0 + 0.12 * exp(-agl / maxf(0.35 * 2.0 * radius, 1.0))

	# Cyclic tilts the thrust vector; stick back (+pitch input) tilts aft
	var ctl_eff: float = eff.controls
	var tilt := 0.18
	var cyc_pitch: float = ctl.elevator * ctl_eff  # +1 = aft cyclic
	var cyc_roll: float = ctl.aileron * ctl_eff    # +1 = right cyclic
	var t_dir := Vector3(cyc_roll * tilt, 1.0, cyc_pitch * tilt).normalized()
	var r_head := Vector3(0, rotor_mast_height, 0)
	var f_rotor := t_dir * thrust
	force += f_rotor
	torque += r_head.cross(f_rotor)

	# Direct hub moments make cyclic crisp (hingeless-rotor effect)
	var hub := thrust * radius * 0.04
	torque.x += cyc_pitch * hub * cfg.pitch_authority
	torque.z += -cyc_roll * hub * cfg.roll_authority

	# Induced-inflow damping: rotor resists vertical rate (real flapping physics)
	var v_ind_hover: float = sqrt(maxf(thrust, 1000.0) / (2.0 * rho * disc_area))
	force.y += -v.y * thrust / maxf(2.0 * v_ind_hover, 4.0) * 0.6

	# Torque reaction + tail rotor / tandem yaw control
	var pedal: float = ctl.rudder * ctl_eff
	if cfg.tandem_rotors:
		torque.y += pedal * cfg.mtow * 2.4 * cfg.yaw_authority
	else:
		var q_react := thrust * radius * 0.028
		torque.y += q_react                                # main rotor reaction
		torque.y += -q_react * (1.0 + pedal * 1.8)          # tail rotor counters + pedal authority
	# Weathervane at speed
	beta = atan2(v.x, maxf(-v.z, 2.0)) if v_horiz > 4.0 else 0.0
	torque.y += -beta * 0.5 * rho * v_horiz * v_horiz * disc_area * 0.02 * radius

	# Fuselage drag (equivalent flat-plate area grows with size)
	var speed := v.length()
	if speed > 0.5:
		var f_area := 1.0 + cfg.mtow / 3800.0
		force += -v.normalized() * 0.5 * rho * speed * speed * f_area

	# Heavy rotor damping keeps it flyable; scales with rotor speed
	var inertia_like := cfg.mtow * radius * radius * 0.25
	torque += -w * inertia_like * (0.8 + 1.6 * rpm)

	g_ratio = thrust / maxf(cfg.mtow * 9.81, 1.0)
	return {"force": force, "torque": torque}
