class_name GearSystem
extends RefCounted
## Raycast-suspension landing gear: spring/damper struts, tire grip, brakes,
## nose-wheel steering, surface detection and touchdown quality reporting.

class Wheel:
	var attach: Vector3          # body-frame strut attachment
	var is_nose: bool = false
	var is_main: bool = false
	var load_share: float = 0.4
	var k: float = 0.0           # spring rate
	var c: float = 0.0           # damping
	var contact: bool = false
	var compression: float = 0.0
	var prev_compression: float = 0.0
	var surface: String = ""     # runway | taxiway | apron | grass | ""
	var normal_force: float = 0.0

var cfg: AircraftConfig
var wheels: Array[Wheel] = []
var wheel_radius: float
var travel: float = 0.42
var gear_frac: float = 1.0       # 0 = retracted, 1 = down and locked
var gear_target: float = 1.0
var gear_transit_time: float = 6.0
var jammed: bool = false

var brake_input: float = 0.0
var parking_brake: bool = true
var steer_input: float = 0.0

var on_ground: bool = false
var ground_surface: String = ""
var last_force_sum := Vector3.ZERO  # diagnostics: net gear force this tick
var airborne_time: float = 0.0
var touchdown_fpm: float = 0.0   # set for one frame on touchdown
var just_touched_down: bool = false

const MU_LAT := 0.9
const MU_BRAKE := 0.52
const ROLL_RESIST := 0.016

func _init(config: AircraftConfig) -> void:
	cfg = config
	wheel_radius = clampf(0.24 + 0.11 * log(maxf(cfg.mtow / 1000.0, 0.5)) / log(10.0) * 2.2, 0.2, 0.85)
	if not cfg.gear_retractable:
		gear_frac = 1.0
		gear_target = 1.0
	var bottom_y := -float(cfg.mesh.get("fuselage_radius_m", 1.0)) * 0.55
	# Static load distribution follows from gear geometry (lever arms about
	# the CG). Springs sized so every wheel settles at the same 35% travel,
	# which makes the parked aircraft sit level.
	var nose_share: float = clampf(cfg.gear_main_z / (cfg.gear_main_z + absf(cfg.gear_nose_z)), 0.06, 0.35)
	var nose := Wheel.new()
	nose.attach = Vector3(0, bottom_y, cfg.gear_nose_z)
	nose.is_nose = true
	nose.load_share = nose_share
	wheels.append(nose)
	for side in [-1.0, 1.0]:
		var m := Wheel.new()
		m.attach = Vector3(side * cfg.gear_main_x, bottom_y, cfg.gear_main_z)
		m.is_main = true
		m.load_share = (1.0 - nose_share) * 0.5
		wheels.append(m)
	for wh in wheels:
		var m_share: float = cfg.mtow * wh.load_share
		wh.k = m_share * 9.81 / (0.35 * travel)
		wh.c = 2.0 * sqrt(wh.k * m_share) * 0.7

func strut_length() -> float:
	return cfg.gear_leg_length

## Height of the body origin above flat ground when parked (wheels lightly
## compressed). Accounts for strut + suspension travel + tire radius + the
## wheel attachment point below the origin.
func spawn_height() -> float:
	var attach_below: float = absf(wheels[0].attach.y) if not wheels.is_empty() else 0.5
	return attach_below + strut_length() + travel + wheel_radius - 0.12

func toggle() -> void:
	if not cfg.gear_retractable or jammed:
		return
	gear_target = 0.0 if gear_target > 0.5 else 1.0
	EventBus.gear_changed.emit(gear_target > 0.5)

func is_down() -> bool:
	return gear_frac > 0.98

func emergency_extend() -> void:
	# Gravity drop: works even when jammed, but slower
	jammed = false
	gear_target = 1.0
	gear_transit_time = 14.0

## Called from Aircraft._physics_process. body must be the RigidBody3D.
func update(body: RigidBody3D, dt: float) -> void:
	just_touched_down = false
	if cfg.gear_retractable and not jammed:
		var rate := 1.0 / gear_transit_time
		gear_frac = move_toward(gear_frac, gear_target, rate * dt)

	var was_on_ground := on_ground
	on_ground = false
	ground_surface = ""
	if gear_frac < 0.6:
		airborne_time += dt
		for wh in wheels:
			wh.contact = false
		return

	var space := body.get_world_3d().direct_space_state
	var xf := body.global_transform
	var v_before_y := body.linear_velocity.y
	var heaviest := 0.0
	last_force_sum = Vector3.ZERO

	for wh in wheels:
		wh.prev_compression = wh.compression
		var origin: Vector3 = xf * wh.attach
		var down: Vector3 = -xf.basis.y
		var rest_len: float = (strut_length() + travel) * gear_frac + wheel_radius
		var query := PhysicsRayQueryParameters3D.create(origin, origin + down * rest_len)
		query.exclude = [body.get_rid()]
		var hit := space.intersect_ray(query)
		# Water gives wheels nothing to roll on
		if not hit.is_empty() and hit.collider is Node and (hit.collider as Node).is_in_group("water"):
			hit = {}
		if hit.is_empty():
			wh.contact = false
			wh.compression = 0.0
			wh.normal_force = 0.0
			continue

		var dist: float = origin.distance_to(hit.position)
		var was_contact := wh.contact
		wh.compression = clampf(rest_len - dist, 0.0, travel * 1.5)
		# No damping on the first contact frame (prev_compression is stale) and
		# clamp the rate so a deep instant contact can't hammer the airframe.
		var comp_vel: float = 0.0
		if was_contact:
			comp_vel = clampf((wh.compression - wh.prev_compression) / dt, -6.0, 6.0)
		var n: Vector3 = hit.normal
		var f_spring: float = maxf(wh.k * wh.compression + wh.c * comp_vel, 0.0)
		wh.normal_force = f_spring
		wh.contact = true
		on_ground = true
		heaviest = maxf(heaviest, f_spring)

		var collider: Object = hit.collider
		wh.surface = "grass"
		if collider and collider is Node:
			var cn := collider as Node
			for surf in ["runway", "taxiway", "apron", "helipad"]:
				if cn.is_in_group(surf):
					wh.surface = surf
					break
		if ground_surface == "" or wh.surface == "runway":
			ground_surface = wh.surface

		var contact_pos: Vector3 = hit.position
		var r: Vector3 = contact_pos - body.global_position
		var v_contact: Vector3 = body.linear_velocity + body.angular_velocity.cross(r)

		# Local ground-plane axes, with nose-wheel steering
		var fwd: Vector3 = -xf.basis.z
		if wh.is_nose:
			# Rudder-pedal nosewheel steering: gentle so a tap can't pivot the
			# aircraft violently (that hard yaw is what used to roll it over).
			# Max deflection is modest and tightens further with speed; the
			# squared response gives fine control near centre.
			var max_steer: float = deg_to_rad(lerpf(18.0, 4.0, clampf(v_contact.length() / 20.0, 0.0, 1.0)))
			var steer: float = steer_input * absf(steer_input)
			fwd = fwd.rotated(n.normalized(), -steer * max_steer)
		var long_dir: Vector3 = (fwd - n * fwd.dot(n)).normalized()
		var lat_dir: Vector3 = long_dir.cross(n).normalized()

		var v_long: float = v_contact.dot(long_dir)
		var v_lat: float = v_contact.dot(lat_dir)

		# Impulse-limited tire forces: never apply more force in one tick than
		# needed to null the slip velocity (prevents 60 Hz spring oscillation),
		# capped by the friction circle.
		var m_eff: float = body.mass * wh.load_share
		var f_lat_needed: float = absf(v_lat) * m_eff / dt
		var f_lat: float = -signf(v_lat) * minf(f_lat_needed, MU_LAT * f_spring)
		# Rolling resistance + brakes (mains only; parking brake full)
		var resist: float = ROLL_RESIST if wh.surface != "grass" else 0.055
		var brake: float = 0.0
		if wh.is_main:
			brake = maxf(brake_input, 1.0 if parking_brake else 0.0) * MU_BRAKE
		var f_long_needed: float = absf(v_long) * m_eff / dt
		var f_long: float = -signf(v_long) * minf((resist + brake) * f_spring, f_long_needed)

		var force: Vector3 = n * f_spring + long_dir * f_long + lat_dir * f_lat
		last_force_sum += force
		body.apply_force(force, contact_pos - body.global_position)

	if on_ground and not was_on_ground and airborne_time > 1.0:
		touchdown_fpm = absf(v_before_y) * Atmosphere.MS_TO_FPM
		just_touched_down = true
	if on_ground:
		airborne_time = 0.0
	else:
		airborne_time += dt
