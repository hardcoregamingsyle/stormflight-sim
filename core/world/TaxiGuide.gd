extends Node3D
## Renders the ATC-assigned taxi route as a line of glowing green chevrons on
## the pavement, ending in a red hold bar (taxi out) or a green gate ring
## (taxi in). Rebuilds only when the route changes or the origin shifts.

var _last_route: Array = []
var _check_timer := 0.0
var _chevron_mat: StandardMaterial3D
var _hold_mat: StandardMaterial3D

func _ready() -> void:
	_chevron_mat = StandardMaterial3D.new()
	_chevron_mat.albedo_color = Color(0.2, 1.0, 0.35)
	_chevron_mat.emission_enabled = true
	_chevron_mat.emission = Color(0.15, 1.0, 0.3)
	_chevron_mat.emission_energy_multiplier = 2.2
	_chevron_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hold_mat = StandardMaterial3D.new()
	_hold_mat.albedo_color = Color(1.0, 0.25, 0.15)
	_hold_mat.emission_enabled = true
	_hold_mat.emission = Color(1.0, 0.2, 0.1)
	_hold_mat.emission_energy_multiplier = 2.5
	_hold_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	EventBus.origin_shifted.connect(func(_d): _rebuild())

func _process(dt: float) -> void:
	_check_timer += dt
	if _check_timer < 0.5:
		return
	_check_timer = 0.0
	var route: Array = ATC.assigned_taxi_route
	var p := Game.player_aircraft as Aircraft
	# Guide only matters on the ground
	if p == null or (not p.gear.on_ground and p.agl > 40.0):
		route = []
	if route != _last_route:
		_last_route = route.duplicate()
		_rebuild()

func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	if _last_route.size() < 2 or Game.world == null:
		return
	var w := Game.world as WorldRoot
	var origin: Vector3 = w.origin_offset()
	var going_to_gate := ATC.phase == ATC.Phase.TAXI_IN

	# Chevron transforms along the polyline, every ~14 m
	var transforms: Array = []
	for i in range(_last_route.size() - 1):
		var a := (_last_route[i] as Vector3) - origin
		var b := (_last_route[i + 1] as Vector3) - origin
		var seg := b - a
		var seg_len := seg.length()
		if seg_len < 2.0:
			continue
		var dir := seg / seg_len
		var yaw := atan2(-dir.x, -dir.z) + PI
		var n := int(seg_len / 14.0)
		for j in maxi(n, 1):
			var pos := a + dir * (7.0 + j * 14.0)
			if (pos - a).length() > seg_len:
				break
			pos.y = w.height_at(pos) + 0.45
			transforms.append(Transform3D(Basis(Vector3.UP, yaw), pos))

	if not transforms.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		# Chevron: two angled bars forming an arrowhead pointing along travel
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for side in [-1.0, 1.0]:
			var tip := Vector3(0, 0, -1.1)
			var back := Vector3(side * 1.1, 0, 0.6)
			var tip_in := Vector3(0, 0, -0.35)
			var back_in := Vector3(side * 0.65, 0, 0.75)
			st.add_vertex(tip); st.add_vertex(back); st.add_vertex(tip_in)
			st.add_vertex(tip_in); st.add_vertex(back); st.add_vertex(back_in)
			# double-sided
			st.add_vertex(tip); st.add_vertex(tip_in); st.add_vertex(back)
			st.add_vertex(tip_in); st.add_vertex(back_in); st.add_vertex(back)
		st.generate_normals()
		var chev := st.commit()
		chev.surface_set_material(0, _chevron_mat)
		mm.mesh = chev
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)

	# End marker
	var end_abs := _last_route[_last_route.size() - 1] as Vector3
	var end_pos := end_abs - origin
	end_pos.y = w.height_at(end_pos) + 0.5
	var marker := MeshInstance3D.new()
	if going_to_gate:
		var ring := TorusMesh.new()
		ring.inner_radius = 7.0
		ring.outer_radius = 8.2
		marker.mesh = ring
		marker.material_override = _chevron_mat
	else:
		var bar := BoxMesh.new()
		bar.size = Vector3(22.0, 0.5, 1.4)
		marker.mesh = bar
		marker.material_override = _hold_mat
		# Orient the hold bar across the final segment direction
		var prev := (_last_route[_last_route.size() - 2] as Vector3) - origin
		var dir2 := (end_pos - prev)
		dir2.y = 0.0
		if dir2.length() > 1.0:
			marker.rotation.y = atan2(-dir2.normalized().x, -dir2.normalized().z) + PI / 2.0
	marker.position = end_pos
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
