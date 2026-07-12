extends Node3D
## Player camera: chase / cockpit / orbit / tower / fly-by views.
## C cycles views, right-mouse drag looks around, scroll zooms.

enum View { CHASE, COCKPIT, ORBIT, TOWER, FLYBY }

var cam: Camera3D
var target: Aircraft
var view: int = View.CHASE
var orbit_yaw := 0.0
var orbit_pitch := 0.15
var distance := 18.0
var _dragging := false
var _flyby_pos := Vector3.ZERO
var _shake := 0.0

func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 72.0
	add_child(cam)
	Quality.apply_environment(Game.world._env if Game.world else Environment.new(), cam)
	Quality.apply_viewport(get_viewport())
	cam.current = true

func attach(aircraft: Aircraft) -> void:
	target = aircraft
	distance = maxf(float(aircraft.cfg.mesh.get("fuselage_length_m", 10.0)) * 0.9, 12.0)

func origin_shift(delta: Vector3) -> void:
	cam.global_position -= delta
	_flyby_pos -= delta

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			distance = maxf(distance * 0.88, 5.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			distance = minf(distance * 1.14, 400.0)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		orbit_yaw -= mm.relative.x * 0.008
		orbit_pitch = clampf(orbit_pitch + mm.relative.y * 0.006, -1.2, 1.4)

func _process(dt: float) -> void:
	if not is_instance_valid(target):
		return
	if Input.is_action_just_pressed("camera_cycle"):
		view = (view + 1) % 5
		orbit_yaw = 0.0
		orbit_pitch = 0.15
		cam.fov = 72.0
		if view == View.FLYBY:
			_setup_flyby()
		EventBus.toast(["Chase view", "Cockpit view", "Orbit view", "Tower view", "Fly-by view"][view], "info")

	# Stall buffet shake
	var want_shake := 0.0
	if target.aero and target.aero.stall_margin < 0.1 and not target.gear.on_ground:
		want_shake = 0.35
	_shake = lerpf(_shake, want_shake, dt * 4.0)

	match view:
		View.CHASE:
			_chase(dt)
		View.COCKPIT:
			_cockpit()
		View.ORBIT:
			_orbit()
		View.TOWER:
			_tower()
		View.FLYBY:
			cam.look_at(target.global_position)
			cam.global_position = _flyby_pos
	if _shake > 0.01:
		cam.h_offset = randf_range(-_shake, _shake) * 0.15
		cam.v_offset = randf_range(-_shake, _shake) * 0.15
	else:
		cam.h_offset = 0.0
		cam.v_offset = 0.0

func _chase(dt: float) -> void:
	var t := target.global_transform
	var back := t.basis.z
	var desired := target.global_position + back.rotated(t.basis.y, orbit_yaw) * distance + t.basis.y * distance * (0.28 + orbit_pitch * 0.5)
	# Keep camera above terrain (origin only shifts in x/z, so heights match)
	if Game.world:
		var floor_y: float = Game.world.height_at(desired) + 2.0
		desired.y = maxf(desired.y, floor_y)
	cam.global_position = cam.global_position.lerp(desired, clampf(dt * 5.0, 0.0, 1.0))
	var up := (t.basis.y * 0.7 + Vector3.UP * 0.3).normalized()
	cam.look_at(target.global_position + -t.basis.z * 8.0, up)

func _cockpit() -> void:
	var mp: Dictionary = target.cfg.mesh
	var L := float(mp.get("fuselage_length_m", 10.0))
	var R := float(mp.get("fuselage_radius_m", 1.0))
	var wz := float(mp.get("wing_z_frac", 0.45))
	var nose_z := -wz * L
	var offset := Vector3(0, R * 0.55, nose_z + float(mp.get("nose_length_frac", 0.15)) * L * 1.1)
	cam.global_transform = target.global_transform.translated_local(offset)
	if _dragging:
		cam.rotate(target.global_transform.basis.y.normalized(), orbit_yaw * 0.5)

func _orbit() -> void:
	var pos := target.global_position
	var dir := Vector3(sin(orbit_yaw) * cos(orbit_pitch), sin(orbit_pitch), cos(orbit_yaw) * cos(orbit_pitch))
	cam.global_position = pos + dir * distance
	cam.look_at(pos)

func _tower() -> void:
	if not Game.world:
		return
	var w := Game.world as WorldRoot
	var id: String = w.nearest_airport_id(target.abs_position())
	if not w.airports.has(id):
		_chase(0.016)
		return
	var a: Dictionary = AirportsDB.get_airport(id)
	var apos: Vector3 = AirportsDB.position_m(id) - w.origin_offset()
	cam.global_position = apos + Vector3(0, float(a.tower_height) + 8.0, 0)
	cam.look_at(target.global_position)
	cam.fov = clampf(3000.0 / maxf(cam.global_position.distance_to(target.global_position), 30.0), 8.0, 65.0)
	return

func _setup_flyby() -> void:
	var ahead := -target.global_transform.basis.z
	_flyby_pos = target.global_position + ahead * target.linear_velocity.length() * 4.0 + Vector3(randf_range(-30, 30), randf_range(5, 40), randf_range(-30, 30))
	cam.fov = 55.0
