extends Node3D
## Ambient AI traffic: kinematic aircraft cruising between airports plus one
## flying the pattern at the player's airport. They carry collision shapes
## (hitting one is a mid-air) and trigger TCAS-style proximity warnings.

var planes: Array = []
var _tcas_cooldown := 0.0

const AI_TYPES := ["a320", "b737max8", "cessna172", "b757"]

func _ready() -> void:
	var count := Quality.max_ai_traffic
	for i in count:
		_spawn(i)

func _spawn(i: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Game.WORLD_SEED + 991 + i
	var ids := AirportsDB.ids()
	var from: String = ids[rng.randi() % ids.size()]
	var to: String = ids[rng.randi() % ids.size()]
	if to == from:
		to = ids[(ids.find(from) + 1) % ids.size()]
	var cfg := AircraftDB.config(AI_TYPES[i % AI_TYPES.size()])
	var body := StaticBody3D.new()
	body.add_to_group("aircraft")
	body.add_to_group("ai_traffic")
	var built := AircraftMeshBuilder.build(cfg)
	_disable_shadows(built.root)  # high-altitude casters wreck shadow precision
	body.add_child(built.root)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(cfg.wing_span * 0.8, 4.0, float(cfg.mesh.get("fuselage_length_m", 20.0)) * 0.8)
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	AircraftMeshBuilder.animate(built.parts, {"elevator": 0.0, "aileron": 0.0, "rudder": 0.0, "flap": 0.0, "slat": 0.0, "spoiler": 0.0, "gear": 0.0, "dt": 0.016})
	var alt := rng.randf_range(2200.0, 5800.0)
	planes.append({
		"body": body, "parts": built.parts, "from": AirportsDB.position_m(from),
		"to": AirportsDB.position_m(to), "alt": alt, "speed": rng.randf_range(140.0, 210.0),
		"progress": rng.randf(), "callsign": "AI-%d" % (i + 1), "spin": 0.0,
	})

func _disable_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadows(child)

func _process(dt: float) -> void:
	if Game.world == null:
		return
	var w := Game.world as WorldRoot
	var origin: Vector3 = w.origin_offset()
	_tcas_cooldown = maxf(_tcas_cooldown - dt, 0.0)
	var player := Game.player_aircraft as Aircraft

	for pl in planes:
		var total: float = (pl.to - pl.from).length()
		pl.progress += pl.speed * dt / maxf(total, 1000.0)
		if pl.progress >= 1.0:
			var tmp = pl.from
			pl.from = pl.to
			pl.to = tmp
			pl.progress = 0.0
		var abs_pos: Vector3 = (pl.from as Vector3).lerp(pl.to, pl.progress)
		abs_pos.y = pl.alt
		var dir: Vector3 = ((pl.to - pl.from) as Vector3).normalized()
		var body := pl.body as StaticBody3D
		body.global_position = abs_pos - origin
		body.rotation.y = atan2(-dir.x, -dir.z) + PI
		pl.spin += dt
		AircraftMeshBuilder.spin(pl.parts, pl.spin * 30.0, 0.0, 0.0, 0.8, false)

		# TCAS proximity warning
		if player and _tcas_cooldown <= 0.0:
			var d := body.global_position.distance_to(player.global_position)
			if d < 900.0 and absf(body.global_position.y - player.global_position.y) < 300.0:
				_tcas_cooldown = 12.0
				EventBus.toast("TRAFFIC! TRAFFIC! (%s, %.1f km)" % [pl.callsign, d / 1000.0], "warn")
				Sfx.play("warn_beep", 1.0)
