extends Node
## SkyCoins economy. Runs the randomized 15-30 s judgement tick that settles
## rewards/penalties from RuleMonitor, handles instant transactions, aircraft
## purchase, repairs and refueling.

const FUEL_PRICE_PER_KG := 0.02

var _tick_timer: Timer
var _rng := RandomNumberGenerator.new()
var _window := 20.0
var _active := false

func _ready() -> void:
	_rng.randomize()
	_tick_timer = Timer.new()
	_tick_timer.one_shot = true
	_tick_timer.timeout.connect(_on_tick)
	add_child(_tick_timer)

func begin_flight() -> void:
	_active = true
	_arm()

func end_flight() -> void:
	_active = false
	_tick_timer.stop()

func _arm() -> void:
	_window = _rng.randf_range(15.0, 30.0)
	_tick_timer.start(_window)

func _on_tick() -> void:
	if not _active:
		return
	var world := Game.world
	if world and world.rule_monitor:
		var result: Dictionary = world.rule_monitor.collect(_window)
		var net := 0
		for r in result.rewards:
			net += int(r.amount)
		for pn in result.penalties:
			net += int(pn.amount)
		if net != 0 or not result.rewards.is_empty() or not result.penalties.is_empty():
			SaveGame.add_coins(net)
			EventBus.rule_tick.emit(result.rewards, result.penalties, net)
			if net > 0:
				Sfx.play("cash", 0.7)
			elif net < 0:
				Sfx.play("penalty", 0.8)
	_arm()

## Immediate transaction with toast + sound.
func instant(amount: int, reason: String) -> void:
	if amount == 0:
		return
	SaveGame.add_coins(amount)
	EventBus.transaction.emit(amount, reason)
	if amount > 0:
		EventBus.toast("+%d SkyCoins - %s" % [amount, reason], "good")
		Sfx.play("cash", 0.8)
	else:
		EventBus.toast("%d SkyCoins - %s" % [amount, reason], "bad")
		Sfx.play("penalty", 0.8)

# ------------------------------------------------------------------ shop
func purchase_aircraft(id: String) -> bool:
	var price := AircraftDB.price(id)
	if SaveGame.owns(id):
		return false
	if not SaveGame.can_afford(price):
		EventBus.toast("Not enough SkyCoins (need %d)" % price, "bad")
		return false
	SaveGame.add_coins(-price)
	SaveGame.grant_aircraft(id)
	EventBus.toast("Purchased %s!" % AircraftDB.spec(id).display_name, "good")
	Sfx.play("cash", 1.0)
	return true

func repair_cost(id: String) -> int:
	var cond := SaveGame.get_condition(id)
	if cond.is_empty():
		return 0
	var missing := 0.0
	var h: Dictionary = cond.get("health", {})
	for k in h.keys():
		missing += 1.0 - float(h[k])
	for e in cond.get("engine_health", []):
		missing += 1.0 - float(e)
	var price := maxi(AircraftDB.price(id), 4000)
	return int(missing * price * 0.02)

func repair_aircraft(id: String) -> bool:
	var cost := repair_cost(id)
	if cost <= 0:
		EventBus.toast("Airframe already in perfect condition", "info")
		return false
	if not SaveGame.can_afford(cost):
		EventBus.toast("Repairs cost %d SkyCoins - insufficient funds" % cost, "bad")
		return false
	SaveGame.add_coins(-cost)
	var cond := SaveGame.get_condition(id)
	var h: Dictionary = cond.get("health", {})
	for k in h.keys():
		h[k] = 1.0
	var eh: Array = cond.get("engine_health", [])
	for i in eh.size():
		eh[i] = 1.0
	SaveGame.set_condition(id, cond)
	EventBus.toast("Aircraft fully repaired (-%d SkyCoins)" % cost, "good")
	return true

func refuel_cost(id: String, target_frac: float = 1.0) -> int:
	var cfg := AircraftDB.config(id)
	var cond := SaveGame.get_condition(id)
	var cur: float = float(cond.get("fuel_frac", 0.75))
	var need := maxf(target_frac - cur, 0.0) * cfg.fuel_capacity
	return int(ceil(need * FUEL_PRICE_PER_KG))

func refuel_aircraft(id: String, target_frac: float = 1.0) -> bool:
	var cost := refuel_cost(id, target_frac)
	if cost <= 0:
		EventBus.toast("Tanks already full", "info")
		return false
	if not SaveGame.can_afford(cost):
		EventBus.toast("Fuel costs %d SkyCoins - insufficient funds" % cost, "bad")
		return false
	SaveGame.add_coins(-cost)
	var cond := SaveGame.get_condition(id)
	if cond.is_empty():
		cond = {"health": {}, "fuel_frac": target_frac, "engine_health": []}
	cond["fuel_frac"] = target_frac
	SaveGame.set_condition(id, cond)
	# If currently flying this aircraft, top it up live
	var p := Game.player_aircraft as Aircraft
	if p and p.cfg.id == id:
		p.fuel_kg = p.cfg.fuel_capacity * target_frac
	EventBus.toast("Refueled (-%d SkyCoins)" % cost, "good")
	return true
