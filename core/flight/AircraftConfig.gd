class_name AircraftConfig
extends RefCounted
## Typed view over one aircraft's spec dictionary from AircraftDB.
## SI units throughout. Godot axes: +X right, +Y up, +Z back (nose = -Z).

var id: String
var display_name: String
var role: String                 # ga | airliner | cargo | fighter | attack | helicopter
var price: int
var description: String
var cruise_speed_kts: float
var range_km: float
var ceiling_ft: float

# --- Mass / geometry ---
var empty_mass: float
var mtow: float
var fuel_capacity: float
var wing_area: float
var wing_span: float
var aspect_ratio: float
var oswald: float

# --- Aerodynamics ---
var cl_alpha: float              # per radian
var cl0: float
var alpha_stall: float           # radians, clean
var cd0: float
var flap_max_deg: float
var flap_cl_bonus: float
var flap_cd_bonus: float
var has_slats: bool
var slat_alpha_bonus: float      # radians added to stall AoA when deployed
var has_spoilers: bool
var spoiler_cd: float
var spoiler_lift_kill: float

# --- Propulsion ---
var engine_type: String          # piston | turboprop | turbofan | turbojet_ab | rotor
var engine_count: int
var max_thrust: float            # N per engine (jets)
var max_power: float             # W per engine (piston/rotor)
var ab_thrust: float             # N per engine wet (0 = no AB)
var fuel_burn_full: float        # kg/s total at full dry power
var spool_rate: float

# --- Limits ---
var vne: float                   # m/s
var stall_speed_clean: float     # m/s
var max_mach: float
var g_limit_pos: float
var g_limit_neg: float
var max_speed: float

# --- Controls ---
var aileron_max: float           # radians
var elevator_max: float
var rudder_max: float
var pitch_authority: float
var roll_authority: float
var yaw_authority: float

# --- Gear ---
var gear_retractable: bool
var gear_main_x: float
var gear_main_z: float
var gear_nose_z: float
var gear_leg_length: float

# --- Helicopter ---
var rotor_main_radius: float
var rotor_tail_radius: float
var tandem_rotors: bool

# --- Mesh parameters (consumed by AircraftMeshBuilder) ---
var mesh: Dictionary

func is_helicopter() -> bool:
	return engine_type == "rotor"

func vfe() -> float:             # max flap-extended speed
	return stall_speed_clean * 2.3

func vle() -> float:             # max gear-extended / operating speed
	if not gear_retractable:
		return vne
	return maxf(stall_speed_clean * 2.8, vne * 0.5)

static func from_dict(d: Dictionary) -> AircraftConfig:
	var c := AircraftConfig.new()
	var p: Dictionary = d["physics"]
	var u: Dictionary = d["ui"]
	c.id = d["id"]
	c.display_name = d["display_name"]
	c.role = d["role"]
	c.price = int(d.get("price", 0))
	c.description = u.get("description", "")
	c.cruise_speed_kts = u.get("cruise_speed_kts", 100.0)
	c.range_km = u.get("range_km", 800.0)
	c.ceiling_ft = u.get("ceiling_ft", 10000.0)

	c.empty_mass = p["empty_mass_kg"]
	c.mtow = p["max_takeoff_mass_kg"]
	c.fuel_capacity = p["fuel_capacity_kg"]
	c.wing_area = p["wing_area_m2"]
	c.wing_span = p["wing_span_m"]
	c.aspect_ratio = c.wing_span * c.wing_span / maxf(c.wing_area, 0.01)
	c.oswald = p["oswald"]

	c.cl_alpha = p["cl_alpha_per_rad"]
	c.cl0 = p["cl0"]
	c.alpha_stall = deg_to_rad(p["alpha_stall_deg"])
	c.cd0 = p["cd0"]
	c.flap_max_deg = p["flap_max_deg"]
	c.flap_cl_bonus = p["flap_cl_bonus"]
	c.flap_cd_bonus = p["flap_cd_bonus"]
	c.has_slats = p["has_slats"]
	c.slat_alpha_bonus = deg_to_rad(p["slat_alpha_bonus_deg"])
	c.has_spoilers = p["has_spoilers"]
	c.spoiler_cd = p["spoiler_cd"]
	c.spoiler_lift_kill = p["spoiler_lift_kill"]

	c.engine_type = p["engine_type"]
	c.engine_count = int(p["engine_count"])
	c.max_thrust = p["max_thrust_n"]
	c.max_power = p["max_power_w"]
	c.ab_thrust = p["afterburner_thrust_n"]
	c.fuel_burn_full = p["fuel_burn_full_kg_s"]
	c.spool_rate = p["spool_rate"]

	c.vne = p["vne_ms"]
	c.stall_speed_clean = p["stall_speed_clean_ms"]
	c.max_mach = p["max_mach"]
	c.g_limit_pos = p["g_limit_pos"]
	c.g_limit_neg = p["g_limit_neg"]
	c.max_speed = p["max_speed_ms"]

	c.aileron_max = deg_to_rad(p["aileron_max_deg"])
	c.elevator_max = deg_to_rad(p["elevator_max_deg"])
	c.rudder_max = deg_to_rad(p["rudder_max_deg"])
	c.pitch_authority = p["pitch_authority"]
	c.roll_authority = p["roll_authority"]
	c.yaw_authority = p["yaw_authority"]

	c.gear_retractable = p["gear_retractable"]
	c.gear_main_x = p["gear_main_x_m"]
	c.gear_main_z = p["gear_main_z_m"]
	c.gear_nose_z = p["gear_nose_z_m"]
	c.gear_leg_length = p["gear_leg_length_m"]

	c.rotor_main_radius = p["rotor_main_radius_m"]
	c.rotor_tail_radius = p["rotor_tail_radius_m"]
	c.tandem_rotors = p["tandem_rotors"]

	c.mesh = d["mesh"]
	return c
