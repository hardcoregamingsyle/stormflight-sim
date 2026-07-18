class_name FuelSystem
extends RefCounted
## Multi-tank fuel model with weight & balance and slosh dynamics.
##
## Fuel is real mass at real body-frame positions: the aircraft's centre of
## mass moves as fuel burns, refills or sloshes. Wing tanks feed their own
## side's engines (centre tank drains first, like a real airliner), so a
## failed engine slowly builds a lateral imbalance the pilot has to hold
## aileron against. Hard manoeuvring or skidding sets the fuel surging in
## any partially-filled tank, dragging the CG around with it.

class Tank:
	var tank_name: String
	var capacity: float = 0.0        # kg
	var kg: float = 0.0
	var pos := Vector3.ZERO          # body-frame centroid when settled
	var travel := Vector2.ZERO       # max slosh CG shift (lateral x, longitudinal z), m
	var slosh := Vector2.ZERO        # dimensionless free-surface state, -1..1
	var slosh_vel := Vector2.ZERO

	func fill_frac() -> float:
		return kg / maxf(capacity, 0.001)

	## Free-surface factor: nothing moves in an empty or brim-full tank;
	## slosh is worst at half fill.
	func slosh_factor() -> float:
		var f := fill_frac()
		return 4.0 * f * (1.0 - f)

	## Effective CG of this tank's fuel including the slosh displacement.
	func cg() -> Vector3:
		var k := slosh_factor()
		return pos + Vector3(slosh.x * travel.x * k, 0.0, slosh.y * travel.y * k)

const SLOSH_OMEGA := 5.0         # rad/s free-surface natural frequency (~0.8 Hz)
const SLOSH_ZETA := 0.16         # light damping - baffles only do so much
const SLOSH_GAIN := 0.8          # steady-state deflection per g of side-load

var cfg: AircraftConfig
var tanks: Array[Tank] = []

func _init(config: AircraftConfig) -> void:
	cfg = config
	var cap := cfg.fuel_capacity
	var semi := cfg.wing_span * 0.5
	var chord := cfg.wing_area / maxf(cfg.wing_span, 0.1)
	if cfg.is_helicopter():
		# Single cell under the transmission, slightly aft
		tanks.append(_mk("MAIN", cap, Vector3(0, -0.25, 0.5), Vector2(0.35, 0.6)))
	elif cap > 3000.0:
		# Airliner / heavy layout: wing cells + centre cell
		tanks.append(_mk("L", cap * 0.30, Vector3(-semi * 0.32, -0.1, chord * 0.08), Vector2(semi * 0.15, chord * 0.25)))
		tanks.append(_mk("R", cap * 0.30, Vector3(semi * 0.32, -0.1, chord * 0.08), Vector2(semi * 0.15, chord * 0.25)))
		tanks.append(_mk("CTR", cap * 0.40, Vector3(0, -0.35, chord * 0.18), Vector2(0.6, chord * 0.35)))
	else:
		# GA / fighter: one cell in each wing
		tanks.append(_mk("L", cap * 0.5, Vector3(-semi * 0.30, 0, chord * 0.10), Vector2(semi * 0.13, chord * 0.28)))
		tanks.append(_mk("R", cap * 0.5, Vector3(semi * 0.30, 0, chord * 0.10), Vector2(semi * 0.13, chord * 0.28)))

static func _mk(tname: String, capacity: float, pos: Vector3, travel: Vector2) -> Tank:
	var t := Tank.new()
	t.tank_name = tname
	t.capacity = capacity
	t.pos = pos
	t.travel = travel
	return t

# ------------------------------------------------------------------ quantity
func total() -> float:
	var s := 0.0
	for t in tanks:
		s += t.kg
	return s

## Refuel/defuel to an absolute quantity. Wings fill first (they also drain
## last), remainder goes to the centre tank - mirrors real fueling order.
func set_total(kg_total: float) -> void:
	var remaining: float = clampf(kg_total, 0.0, cfg.fuel_capacity)
	var wings: Array[Tank] = []
	var centers: Array[Tank] = []
	for t in tanks:
		(wings if t.tank_name in ["L", "R"] else centers).append(t)
	if wings.is_empty():
		wings = tanks
		centers = []
	var wing_cap := 0.0
	for t in wings:
		wing_cap += t.capacity
	var to_wings := minf(remaining, wing_cap)
	for t in wings:
		t.kg = to_wings * (t.capacity / maxf(wing_cap, 0.001))
	remaining -= to_wings
	for t in centers:
		var put := minf(remaining, t.capacity)
		t.kg = put
		remaining -= put

func tank_named(tname: String) -> Tank:
	for t in tanks:
		if t.tank_name == tname:
			return t
	return null

## Right-heavy positive, in kg. Zero for single-tank aircraft.
func imbalance_kg() -> float:
	var l := tank_named("L")
	var r := tank_named("R")
	if l == null or r == null:
		return 0.0
	return r.kg - l.kg

# ------------------------------------------------------------------ feed
## Drain fuel for this tick. per_engine_kg follows the engine indexing used
## for thrust placement: even index = left side, odd = right. Centre tank
## feeds everything first; a wing tank feeds its own side, cross-feeding
## automatically only when its side runs dry.
func consume(per_engine_kg: Array) -> void:
	var center := tank_named("CTR")
	if center == null:
		center = tank_named("MAIN")
	var single := per_engine_kg.size() <= 1
	for i in per_engine_kg.size():
		var want: float = per_engine_kg[i]
		if want <= 0.0:
			continue
		if center != null and center.kg > 0.0:
			var take := minf(want, center.kg)
			center.kg -= take
			want -= take
		if want <= 0.0:
			continue
		if single:
			# Centreline engine draws both wings down evenly
			var l := tank_named("L")
			var r := tank_named("R")
			if l != null and r != null:
				var half := want * 0.5
				var from_l := minf(half + maxf(half - r.kg, 0.0), l.kg)
				var from_r := minf(want - from_l, r.kg)
				l.kg -= from_l
				r.kg -= from_r
			continue
		var own := tank_named("L" if i % 2 == 0 else "R")
		var other := tank_named("R" if i % 2 == 0 else "L")
		if own != null and own.kg > 0.0:
			var take2 := minf(want, own.kg)
			own.kg -= take2
			want -= take2
		if want > 0.0 and other != null:
			other.kg = maxf(other.kg - want, 0.0)

# ------------------------------------------------------------------ dynamics
## Advance the free-surface (slosh) state. a_body is the proper acceleration
## the airframe feels in body frame (gravity included) - in coordinated
## flight the lateral component is near zero and the fuel stays put; slips,
## skids, braking and gusts all set it moving.
func update_slosh(dt: float, a_body: Vector3) -> void:
	var drive := Vector2(clampf(a_body.x / 9.81, -2.0, 2.0), clampf(a_body.z / 9.81, -2.0, 2.0))
	var w2 := SLOSH_OMEGA * SLOSH_OMEGA
	for t in tanks:
		if t.kg < 1.0 or t.slosh_factor() < 0.02:
			t.slosh = t.slosh.move_toward(Vector2.ZERO, dt * 2.0)
			t.slosh_vel = t.slosh_vel.move_toward(Vector2.ZERO, dt * 8.0)
			continue
		# Fuel surges opposite to the applied acceleration
		var acc := (-drive * SLOSH_GAIN - t.slosh) * w2 - t.slosh_vel * (2.0 * SLOSH_ZETA * SLOSH_OMEGA)
		t.slosh_vel += acc * dt
		t.slosh += t.slosh_vel * dt
		t.slosh = t.slosh.clamp(Vector2(-1, -1), Vector2(1, 1))

## First moment of the fuel mass about the body origin (kg*m). Divide by
## total aircraft mass to get the fuel's CG contribution.
func moment() -> Vector3:
	var m := Vector3.ZERO
	for t in tanks:
		m += t.cg() * t.kg
	return m

## Compact readout for the HUD, e.g. "L 812 · CTR 1954 · R 807".
func readout() -> String:
	var parts: PackedStringArray = []
	for t in tanks:
		parts.append("%s %d" % [t.tank_name, int(t.kg)])
	return " · ".join(parts)
