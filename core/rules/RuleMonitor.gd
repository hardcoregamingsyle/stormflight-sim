extends Node
## Watches the player's flying and scores it. Continuous compliance is
## sampled twice a second and settled by Economy's 15-30 s tick; discrete
## events (landings, clearance busts, crashes) post immediately.
##
## Rules enforced:
##  - taxi on the yellow lines / pavement, taxi speed limits
##  - no runway entry without clearance (hold short!)
##  - no takeoff / landing without clearance
##  - gear up after takeoff, gear down before landing
##  - 250 kt below 10,000 ft, VNE, G-limits, no ignoring stall
##  - assigned altitude compliance when ATC gave one
##  - landing quality scoring (butter -> severe)
##  - passive pay for simply flying, clean-flying bonus

var _sample_timer := 0.0
var _viol: Dictionary = {}          # label -> accumulated seconds this window
var _fly_seconds := 0.0
var _was_airborne := false
var _stall_seconds := 0.0
var _last_dist_pos := Vector3.ZERO
var _airborne_since_takeoff := 0.0  # armed landing-bonus timer (anti-farming)

func _ready() -> void:
	EventBus.landed.connect(_on_landed)
	EventBus.aircraft_crashed.connect(_on_crashed)
	EventBus.took_off.connect(_on_took_off)

func _physics_process(dt: float) -> void:
	var p := Game.player_aircraft as Aircraft
	if p == null or p.crashed:
		return
	_sample_timer += dt
	if not p.gear.on_ground:
		_fly_seconds += dt
		_airborne_since_takeoff += dt
	if _sample_timer >= 0.5:
		_sample(p, _sample_timer)
		_sample_timer = 0.0

	# Takeoff detection
	if not p.gear.on_ground and _was_airborne == false and p.gear.airborne_time > 2.0 and p.get_ias() > p.cfg.stall_speed_clean * 0.8:
		_was_airborne = true
		EventBus.took_off.emit()
	elif p.gear.on_ground and p.gear.airborne_time < 0.1:
		_was_airborne = false

	# Distance stat
	if _last_dist_pos == Vector3.ZERO:
		_last_dist_pos = p.abs_position()
	elif _fly_seconds > 0:
		var d := p.abs_position().distance_to(_last_dist_pos)
		if d > 100.0:
			SaveGame.add_stat("distance_km", d / 1000.0)
			_last_dist_pos = p.abs_position()

func _add_viol(label: String, seconds: float) -> void:
	_viol[label] = _viol.get(label, 0.0) + seconds

func _sample(p: Aircraft, dt: float) -> void:
	var ias := p.get_ias()
	var on_ground := p.gear.on_ground
	var surface := p.gear.ground_surface

	if on_ground:
		var speed := p.linear_velocity.length()
		if speed > 2.0:
			if surface == "grass" and not p.cfg.is_helicopter():
				_add_viol("Off-pavement excursion", dt)
			elif surface in ["taxiway", "apron"]:
				if speed > 13.0:
					_add_viol("Taxi overspeed (max 25 kts)", dt)
				var route: Array = ATC.assigned_taxi_route
				if not route.is_empty() and _dist_to_polyline(p.abs_position(), route) > 28.0:
					_add_viol("Off assigned taxi route", dt)
			elif surface == "runway":
				if not ATC.runway_use_allowed():
					_add_viol("Runway incursion without clearance", dt * 2.0)
	else:
		# Airborne rules
		if ias > p.cfg.vne:
			_add_viol("Overspeed beyond VNE", dt)
		if ias > 132.0 and p.global_position.y < 3048.0 and not p.cfg.role in ["fighter", "attack"]:
			_add_viol("Over 250 kts below 10,000 ft", dt)
		if p.g_force > p.cfg.g_limit_pos + 0.3 or p.g_force < p.cfg.g_limit_neg - 0.3:
			_add_viol("G-limit exceeded", dt)
		if p.cfg.gear_retractable and p.gear.is_down() and agl_of(p) > 700.0 and ias > p.cfg.stall_speed_clean * 1.6:
			_add_viol("Flying around with gear down", dt)
		if ATC.assigned_altitude > 0.0 and ATC.phase == ATC.Phase.ENROUTE:
			if absf(p.global_position.y - ATC.assigned_altitude) > 180.0:
				_add_viol("Off assigned altitude", dt)
		if p.aero.stalled:
			_stall_seconds += dt
			if _stall_seconds > 4.0:
				Economy.instant(-40, "Prolonged stall - recover!")
				_stall_seconds = 0.0
		else:
			_stall_seconds = 0.0

func agl_of(p: Aircraft) -> float:
	return p.agl

func _dist_to_polyline(pos: Vector3, pts: Array) -> float:
	var best := 1e12
	for i in range(pts.size() - 1):
		var a := pts[i] as Vector3
		var b := pts[i + 1] as Vector3
		var closest := Geometry3D.get_closest_point_to_segment(pos, a, b)
		best = minf(best, Vector2(pos.x - closest.x, pos.z - closest.z).length())
	return best

## Called by Economy on each 15-30 s tick. Returns itemized results and resets.
func collect(window_s: float) -> Dictionary:
	var p := Game.player_aircraft as Aircraft
	var rewards: Array = []
	var penalties: Array = []
	if p == null:
		return {"rewards": rewards, "penalties": penalties}
	var mult := 1.0 + p.cfg.price / 60000.0

	# Passive pay for flying
	if _fly_seconds > 5.0:
		var base := int(round(_fly_seconds / 20.0 * 6.0 * mult))
		if base > 0:
			rewards.append({"label": "Flight pay", "amount": base})

	# Violations
	var had_viol := false
	for label in _viol.keys():
		var secs: float = _viol[label]
		if secs < 0.4:
			continue
		had_viol = true
		var amount := -int(round(clampf(secs * 4.0, 4.0, 90.0) * mult * 0.6))
		penalties.append({"label": label, "amount": amount})

	# Clean flying bonus
	if not had_viol and _fly_seconds > window_s * 0.5:
		rewards.append({"label": "Clean flying bonus", "amount": int(round(8.0 * mult))})
		if ATC.phase != ATC.Phase.IDLE:
			rewards.append({"label": "Following ATC procedures", "amount": int(round(5.0 * mult))})

	_viol.clear()
	_fly_seconds = 0.0
	return {"rewards": rewards, "penalties": penalties}

# ------------------------------------------------------------------ events
func _on_landed(fpm: float, quality: String) -> void:
	var p := Game.player_aircraft as Aircraft
	if p == null:
		return
	var mult := 1.0 + p.cfg.price / 60000.0
	SaveGame.add_stat("landings", 1)
	# Landing rewards only after a real flight (anti touch-and-go farming);
	# penalties always apply.
	var min_flight := 60.0 if p.cfg.is_helicopter() else 30.0
	var reward_armed := _airborne_since_takeoff >= min_flight
	_airborne_since_takeoff = 0.0
	match quality:
		"butter":
			if reward_armed:
				Economy.instant(int(120 * mult), "BUTTER landing! (%d fpm)" % int(fpm))
			else:
				EventBus.toast("Butter landing (%d fpm)" % int(fpm), "good")
		"good":
			if reward_armed:
				Economy.instant(int(50 * mult), "Smooth landing (%d fpm)" % int(fpm))
			else:
				EventBus.toast("Smooth landing (%d fpm)" % int(fpm), "info")
		"firm":
			EventBus.toast("Firm landing (%d fpm)" % int(fpm), "info")
		"hard":
			Economy.instant(int(-70 * mult), "Hard landing (%d fpm)" % int(fpm))
		"severe":
			Economy.instant(int(-180 * mult), "SEVERE landing impact (%d fpm)" % int(fpm))
	# Clearance check (helicopters may land off-airport freely)
	if not p.cfg.is_helicopter():
		if p.gear.ground_surface == "runway":
			if ATC.cleared_to_land:
				if reward_armed:
					Economy.instant(int(30 * mult), "Landed with clearance")
			else:
				Economy.instant(int(-120 * mult), "Landed WITHOUT clearance")
		else:
			# Anything that isn't the runway: grass, taxiways, aprons...
			Economy.instant(int(-150 * mult), "Landed off-runway")
	ATC.notify_landed()

func _on_took_off() -> void:
	var p := Game.player_aircraft as Aircraft
	if p == null or p.cfg.is_helicopter():
		if p != null:
			ATC.notify_airborne()
		return
	var mult := 1.0 + p.cfg.price / 60000.0
	if ATC.cleared_takeoff:
		Economy.instant(int(25 * mult), "Departure with clearance")
	else:
		Economy.instant(int(-100 * mult), "Takeoff WITHOUT clearance")
	ATC.notify_airborne()

func _on_crashed(_reason: String) -> void:
	var p := Game.player_aircraft as Aircraft
	if p == null:
		return
	# Crashing must always cost more than honest hangar repairs
	var penalty := int(-(200.0 + p.cfg.price * 0.006))
	Economy.instant(penalty, "Aircraft crashed")
	var repair := int(-(300.0 + p.cfg.price * 0.03))
	Economy.instant(repair, "Emergency recovery & repairs")
