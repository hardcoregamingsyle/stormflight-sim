extends Node
## Jobs system: cargo hauls, passenger charters, medical express runs, ferry
## flights and aerial surveys. Pay scales with distance, payload and aircraft
## class. Fragile jobs punish rough handling; medical runs have deadlines.
## Complete a job by landing at the destination, taxiing in and shutting down.

var jobs_by_airport: Dictionary = {}   # airport_id -> Array of job dicts
var active_job: Dictionary = {}
var _job_seq := 0
var _rng := RandomNumberGenerator.new()
var _refresh_timer := 0.0
var world: WorldRoot = null
var _g_abuse := 0.0

const TYPES := [
	{"type": "cargo", "title": "Cargo Haul", "roles": ["airliner", "cargo", "ga", "helicopter"], "pay_mult": 1.0, "fragile": false},
	{"type": "charter", "title": "Passenger Charter", "roles": ["airliner", "ga", "helicopter"], "pay_mult": 1.25, "fragile": true},
	{"type": "medical", "title": "Medical Express", "roles": ["ga", "helicopter", "fighter", "attack", "airliner", "cargo"], "pay_mult": 2.0, "fragile": true},
	{"type": "ferry", "title": "Ferry Flight", "roles": ["ga", "airliner", "cargo", "fighter", "attack", "helicopter"], "pay_mult": 0.9, "fragile": false},
	{"type": "heavy", "title": "Heavy Freight", "roles": ["cargo"], "pay_mult": 1.7, "fragile": false},
	{"type": "patrol", "title": "Air Patrol Circuit", "roles": ["fighter", "attack"], "pay_mult": 1.5, "fragile": false},
]

func begin_flight(w: WorldRoot) -> void:
	world = w
	if jobs_by_airport.is_empty():
		refresh_all()

func end_flight() -> void:
	world = null
	if not active_job.is_empty():
		fail_active("Flight abandoned")

func refresh_all() -> void:
	_rng.seed = Game.WORLD_SEED + int(Time.get_unix_time_from_system() / 600.0)
	jobs_by_airport.clear()
	for id in AirportsDB.ids():
		jobs_by_airport[id] = _generate_for(id)
	EventBus.jobs_refreshed.emit()

func _generate_for(airport_id: String) -> Array:
	var out: Array = []
	var others: Array = AirportsDB.ids().filter(func(x): return x != airport_id)
	var n := _rng.randi_range(4, 7)
	for i in n:
		var t: Dictionary = TYPES[_rng.randi() % TYPES.size()]
		var dest: String = others[_rng.randi() % others.size()]
		var dist := AirportsDB.distance_km(airport_id, dest)
		var payload := 0.0
		match t.type:
			"cargo": payload = _rng.randf_range(200.0, 8000.0)
			"heavy": payload = _rng.randf_range(20000.0, 90000.0)
			"charter": payload = _rng.randf_range(150.0, 5000.0)
			"medical": payload = _rng.randf_range(80.0, 400.0)
			_: payload = 0.0
		var pay := int((60.0 + dist * 3.2 + payload * 0.012) * t.pay_mult)
		var job := {
			"id": "job_%d_%s" % [_job_seq, airport_id], "type": t.type, "title": t.title,
			"from": airport_id, "to": dest, "distance_km": dist, "pay": pay,
			"payload_kg": payload, "roles": t.roles, "fragile": t.fragile,
			"time_limit_s": (60.0 + dist * 60.0 / 2.5) if t.type == "medical" else 0.0,
			"desc": _describe(t.type, airport_id, dest, payload, dist),
			"time_left": 0.0,
		}
		_job_seq += 1
		out.append(job)
	return out

func _describe(type: String, from_id: String, to_id: String, payload: float, dist: float) -> String:
	var to_name: String = AirportsDB.get_airport(to_id).name
	match type:
		"cargo": return "Deliver %d kg of freight to %s (%d km)." % [int(payload), to_name, int(dist)]
		"heavy": return "Outsized freight: %d kg to %s (%d km). Heavy metal only." % [int(payload), to_name, int(dist)]
		"charter": return "Fly %d kg of passengers+baggage to %s. Keep it smooth - they bruise easily." % [int(payload), to_name]
		"medical": return "URGENT: organ transport to %s. The clock is ticking. Fly fast, land gentle." % to_name
		"ferry": return "Reposition this aircraft to %s. Empty legs still pay." % to_name
		"patrol": return "Military patrol: fly to %s and return airspace status. Speed appreciated." % to_name
	return "Fly to %s." % to_name

func available_at(airport_id: String) -> Array:
	return jobs_by_airport.get(airport_id, [])

func can_accept(job: Dictionary) -> String:
	var p := Game.player_aircraft as Aircraft
	if p == null:
		return "Not in flight"
	if not active_job.is_empty():
		return "Finish your active job first"
	if not p.cfg.role in (job.roles as Array):
		return "Wrong aircraft type (%s needed)" % ", ".join(job.roles)
	if not p.gear.on_ground:
		return "Must be parked at %s" % AirportsDB.get_airport(job.from).name
	if world and world.nearest_airport_id(p.abs_position()) != job.from:
		return "Must be parked at %s" % AirportsDB.get_airport(job.from).name
	var capacity: float = p.cfg.mtow - p.cfg.empty_mass - p.fuel_kg
	if job.payload_kg > capacity:
		return "Payload too heavy for this aircraft (%d kg over)" % int(job.payload_kg - capacity)
	return ""

func accept(job: Dictionary) -> bool:
	var err := can_accept(job)
	if err != "":
		EventBus.toast(err, "bad")
		return false
	active_job = job.duplicate()
	active_job.time_left = active_job.time_limit_s
	_g_abuse = 0.0
	var p := Game.player_aircraft as Aircraft
	p.payload_kg = float(job.payload_kg)
	(jobs_by_airport[job.from] as Array).erase(job)
	EventBus.job_accepted.emit(active_job)
	EventBus.toast("Job accepted: %s -> %s (%d SkyCoins)" % [active_job.title, AirportsDB.get_airport(active_job.to).name, active_job.pay], "good")
	return true

func active_destination() -> String:
	return active_job.get("to", "")

func fail_active(reason: String) -> void:
	if active_job.is_empty():
		return
	var j := active_job
	active_job = {}
	var p := Game.player_aircraft as Aircraft
	if p:
		p.payload_kg = 0.0
	EventBus.job_failed.emit(j, reason)
	Economy.instant(-int(j.pay * 0.25), "Job failed: %s" % reason)

## Called by ATC when flight closes at a gate; also polled for helicopters.
func notify_parked(airport_id: String) -> void:
	if active_job.is_empty():
		return
	if airport_id == active_job.to:
		var j := active_job
		active_job = {}
		var p := Game.player_aircraft as Aircraft
		if p:
			p.payload_kg = 0.0
		var bonus := 0
		if j.fragile and _g_abuse < 1.0:
			bonus = int(j.pay * 0.2)
		SaveGame.add_stat("jobs_done", 1)
		EventBus.job_completed.emit(j, j.pay + bonus)
		Economy.instant(int(j.pay) + bonus, "Job complete: %s%s" % [j.title, " (+care bonus)" if bonus > 0 else ""])

func _process(dt: float) -> void:
	if world == null:
		return
	_refresh_timer += dt
	if _refresh_timer > 480.0:
		_refresh_timer = 0.0
		refresh_all()
	if active_job.is_empty():
		return
	var p := Game.player_aircraft as Aircraft
	if p == null:
		return
	# Deadline
	if active_job.time_limit_s > 0.0:
		active_job.time_left = maxf(active_job.time_left - dt, 0.0)
		if active_job.time_left <= 0.0:
			fail_active("Deadline missed")
			return
	# Fragile cargo abuse tracking
	if active_job.fragile:
		if absf(p.g_force) > 1.9 or p.g_force < -0.2:
			_g_abuse += dt
			if _g_abuse > 6.0:
				fail_active("Cargo destroyed by rough handling")
				return
	if p.crashed:
		fail_active("Aircraft crashed")
		return
	# Helicopter shortcut: helis complete jobs by landing + shutdown near the airport
	if p.cfg.is_helicopter() and p.gear.on_ground and not p.propulsion.any_running() and p.gear.airborne_time < 0.1:
		var near := world.nearest_airport_id(p.abs_position())
		if near == active_job.to and (AirportsDB.position_m(near) - p.abs_position()).length() < 4000.0:
			notify_parked(near)
