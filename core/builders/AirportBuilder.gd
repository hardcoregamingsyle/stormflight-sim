class_name AirportBuilder
## Generates a complete airport from an AirportsDB entry: runways with full
## markings (centerline, thresholds, numbers, touchdown zones), edge/threshold
## lights, PAPI, parallel taxiways with yellow centerlines and hold-short
## bars, apron with numbered gates (+jetways at big fields), terminal, tower,
## hangars, windsock - plus the taxi routing graph used by ATC and the rule
## monitor. All geometry in airport-local space; root placed at absolute
## world position under WorldRoot.static_root.

const ASPHALT := Color(0.16, 0.16, 0.17)
const CONCRETE := Color(0.44, 0.44, 0.46)
const TAXI_GREY := Color(0.24, 0.24, 0.25)

static func _flat_mat(c: Color, emis := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if emis:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.6
	return m

static func _slab(parent: Node3D, size: Vector3, pos: Vector3, rot_y: float, color: Color, group: String) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = rot_y
	if group != "":
		body.add_to_group(group)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _flat_mat(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # flat pavement
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	parent.add_child(body)

static func _building(parent: Node3D, size: Vector3, pos: Vector3, rot_y: float, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos + Vector3(0, size.y * 0.5, 0)
	body.rotation.y = rot_y
	body.add_to_group("building")
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	mi.material_override = m
	# Building casters break directional shadow precision across the airport
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	parent.add_child(body)
	return body

## Scatter many small boxes as a MultiMesh (markings, lights).
static func _multimesh(parent: Node3D, box_size: Vector3, transforms: Array, color: Color, emissive: bool) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = box_size
	bm.material = _flat_mat(color, emissive)
	mm.mesh = bm
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)

# =====================================================================
static func build(airport_id: String) -> Dictionary:
	var a: Dictionary = AirportsDB.get_airport(airport_id)
	var origin := AirportsDB.position_m(airport_id)
	var root := Node3D.new()
	root.name = "Airport_%s" % airport_id
	root.position = origin

	var data := {
		"id": airport_id, "icao": a.icao, "name": a.name, "root": root,
		"origin": origin, "runways": [], "gates": [], "graph": {"nodes": {}, "edges": []},
		"windsock": null, "size": a.size,
	}
	var graph: Dictionary = data.graph

	var first_rw: Dictionary = a.runways[0]
	var main_h := deg_to_rad(float(first_rw.heading))
	var main_dir := Vector3(sin(main_h), 0, -cos(main_h))
	var main_perp := Vector3(-cos(main_h), 0, -sin(main_h))  # left of runway

	# ---------------- runways ----------------
	var rw_idx := 0
	for rw in a.runways:
		var h := deg_to_rad(float(rw.heading))
		var dir := Vector3(sin(h), 0, -cos(h))
		var perp := Vector3(-cos(h), 0, -sin(h))
		var length := float(rw.length)
		var width := float(rw.width)
		var center := Vector3(float(rw.offset[0]), 0, float(rw.offset[1]))
		var e1 := center - dir * length * 0.5   # threshold 1
		var e2 := center + dir * length * 0.5

		_slab(root, Vector3(width, 0.2, length), center + Vector3(0, 0.0, 0), -h, ASPHALT, "runway")

		# Centerline dashes
		var dashes: Array = []
		var n_dash := int(length / 60.0)
		for i in n_dash:
			var p := e1 + dir * (45.0 + i * 60.0)
			if p.distance_to(e1) > length - 60.0:
				break
			var t := Transform3D(Basis(Vector3.UP, -h), p + Vector3(0, 0.13, 0))
			dashes.append(t)
		_multimesh(root, Vector3(0.9, 0.02, 24.0), dashes, Color(0.92, 0.92, 0.92), false)

		# Threshold bars + touchdown zone marks
		var bars: Array = []
		for endinfo in [[e1, dir], [e2, -dir]]:
			var ep: Vector3 = endinfo[0]
			var ed: Vector3 = endinfo[1]
			for i in 8:
				var off := (float(i) - 3.5) * (width / 9.0)
				bars.append(Transform3D(Basis(Vector3.UP, -h), ep + ed * 12.0 + perp * off + Vector3(0, 0.13, 0)))
			for tz in [300.0, 450.0]:
				if tz < length * 0.4:
					for s in [-1.0, 1.0]:
						bars.append(Transform3D(Basis(Vector3.UP, -h), ep + ed * tz + perp * s * width * 0.22 + Vector3(0, 0.13, 0)))
		_multimesh(root, Vector3(1.6, 0.02, 22.0), bars, Color(0.92, 0.92, 0.92), false)

		# Runway numbers
		var ids: PackedStringArray = String(rw.id).split("/")
		for endinfo in [[e1, dir, ids[0]], [e2, -dir, ids[1] if ids.size() > 1 else ids[0]]]:
			var lbl := Label3D.new()
			lbl.text = String(endinfo[2])
			lbl.font_size = 380
			lbl.pixel_size = 0.05
			lbl.modulate = Color(0.95, 0.95, 0.95)
			lbl.position = (endinfo[0] as Vector3) + (endinfo[1] as Vector3) * 70.0 + Vector3(0, 0.14, 0)
			lbl.rotation.x = -PI / 2.0
			lbl.rotation.y = atan2((endinfo[1] as Vector3).x, (endinfo[1] as Vector3).z) + PI
			root.add_child(lbl)

		# Edge lights (white) + threshold (green) + end (red)
		var lights: Array = []
		var step := 120.0 if Quality.is_web else 60.0
		var nl := int(length / step)
		for i in nl + 1:
			for s in [-1.0, 1.0]:
				lights.append(Transform3D(Basis(), e1 + dir * (i * step) + perp * s * (width * 0.5 + 1.5) + Vector3(0, 0.4, 0)))
		_multimesh(root, Vector3(0.35, 0.35, 0.35), lights, Color(1.0, 0.95, 0.7), true)
		var thr_g: Array = []
		var thr_r: Array = []
		for i in 10:
			var off := (float(i) - 4.5) * (width / 10.0)
			thr_g.append(Transform3D(Basis(), e1 + perp * off + Vector3(0, 0.35, 0)))
			thr_g.append(Transform3D(Basis(), e2 + perp * off + Vector3(0, 0.35, 0)))
			thr_r.append(Transform3D(Basis(), e1 - dir * 6.0 + perp * off + Vector3(0, 0.35, 0)))
			thr_r.append(Transform3D(Basis(), e2 + dir * 6.0 + perp * off + Vector3(0, 0.35, 0)))
		_multimesh(root, Vector3(0.35, 0.3, 0.35), thr_g, Color(0.2, 1.0, 0.3), true)
		_multimesh(root, Vector3(0.35, 0.3, 0.35), thr_r, Color(1.0, 0.2, 0.15), true)

		# PAPI (4 spheres, left of touchdown point, both ends)
		var papis: Array = []
		for endinfo in [[e1, dir], [e2, -dir]]:
			var papi_units: Array = []
			var base: Vector3 = (endinfo[0] as Vector3) + (endinfo[1] as Vector3) * 300.0 + perp * (width * 0.5 + 14.0)
			for i in 4:
				var s := SphereMesh.new()
				s.radius = 0.55
				s.height = 1.1
				var mi := MeshInstance3D.new()
				mi.mesh = s
				var pm := StandardMaterial3D.new()
				pm.emission_enabled = true
				pm.emission = Color(1, 1, 1)
				pm.emission_energy_multiplier = 3.0
				pm.albedo_color = Color(0.9, 0.9, 0.9)
				mi.material_override = pm
				mi.position = base + perp * (i * 3.0) + Vector3(0, 0.8, 0)
				root.add_child(mi)
				papi_units.append(mi)
			papis.append({"units": papi_units, "threshold": endinfo[0], "dir": endinfo[1]})

		# Approach lights for big runways
		if length >= 2400.0:
			var app: Array = []
			for endinfo in [[e1, dir], [e2, -dir]]:
				for i in range(1, 10):
					var p: Vector3 = (endinfo[0] as Vector3) - (endinfo[1] as Vector3) * (i * 30.0)
					for s2 in [-2.0, -1.0, 0.0, 1.0, 2.0]:
						app.append(Transform3D(Basis(), p + perp * s2 * 2.4 + Vector3(0, 0.6, 0)))
			_multimesh(root, Vector3(0.3, 0.3, 0.3), app, Color(1.0, 0.98, 0.9), true)

		data.runways.append({
			"id": rw.id, "heading_deg": float(rw.heading), "length": length, "width": width,
			"e1": origin + e1, "e2": origin + e2, "center": origin + center,
			"dir": dir, "perp": perp, "papis": papis,
		})

		# ---------------- taxiway system for this runway ----------------
		var t_off := width * 0.5 + 110.0
		var t1 := e1 + perp * t_off
		var t2 := e2 + perp * t_off
		var tc := center + perp * t_off
		# Parallel taxiway
		_slab(root, Vector3(23.0, 0.18, length), tc, -h, TAXI_GREY, "taxiway")
		# Connectors at ends + center
		for pair in [[e1, t1, "e1"], [e2, t2, "e2"], [center, tc, "c"]]:
			var rp: Vector3 = pair[0]
			var tp: Vector3 = pair[1]
			var mid: Vector3 = (rp + tp) * 0.5
			_slab(root, Vector3(20.0, 0.18, t_off), mid, -h + PI / 2.0, TAXI_GREY, "taxiway")
			# Hold-short double bar 60 m from centerline
			var hold: Vector3 = rp + perp * 60.0
			var hbars: Array = []
			hbars.append(Transform3D(Basis(Vector3.UP, -h), hold + Vector3(0, 0.14, 0)))
			hbars.append(Transform3D(Basis(Vector3.UP, -h), hold + perp * 2.0 + Vector3(0, 0.14, 0)))
			_multimesh(root, Vector3(20.0, 0.02, 0.5), hbars, Color(0.95, 0.85, 0.1), false)
		# Yellow centerlines (taxiway + connectors)
		var yellows: Array = []
		var tl := (t2 - t1).length()
		for i in int(tl / 14.0):
			yellows.append(Transform3D(Basis(Vector3.UP, -h), t1 + dir * (i * 14.0) + Vector3(0, 0.15, 0)))
		for pair in [[e1, t1], [e2, t2], [center, tc]]:
			for i in int(t_off / 14.0):
				var p2: Vector3 = (pair[0] as Vector3) + perp * (i * 14.0)
				yellows.append(Transform3D(Basis(Vector3.UP, -h + PI / 2.0), p2 + Vector3(0, 0.15, 0)))
		_multimesh(root, Vector3(0.35, 0.02, 9.0), yellows, Color(0.95, 0.8, 0.1), false)

		# Graph nodes (absolute positions)
		var pre := "r%d_" % rw_idx
		graph.nodes[pre + "rwy_e1"] = origin + e1
		graph.nodes[pre + "rwy_e2"] = origin + e2
		graph.nodes[pre + "hold_e1"] = origin + e1 + perp * 60.0
		graph.nodes[pre + "hold_e2"] = origin + e2 + perp * 60.0
		graph.nodes[pre + "hold_c"] = origin + center + perp * 60.0
		graph.nodes[pre + "taxi_e1"] = origin + t1
		graph.nodes[pre + "taxi_e2"] = origin + t2
		graph.nodes[pre + "taxi_c"] = origin + tc
		for pair in [[pre + "taxi_e1", pre + "taxi_c"], [pre + "taxi_c", pre + "taxi_e2"],
			[pre + "taxi_e1", pre + "hold_e1"], [pre + "hold_e1", pre + "rwy_e1"],
			[pre + "taxi_e2", pre + "hold_e2"], [pre + "hold_e2", pre + "rwy_e2"],
			[pre + "taxi_c", pre + "hold_c"], [pre + "hold_c", pre + "rwy_e1"], [pre + "hold_c", pre + "rwy_e2"]]:
			graph.edges.append(pair)
		rw_idx += 1

	# ---------------- apron + gates + terminal ----------------
	var apron_off := float(first_rw.width) * 0.5 + 110.0 + 130.0
	var n_gates := int(a.gates)
	var gate_spacing: float = {"mega": 90.0, "international": 72.0, "regional": 52.0, "small": 34.0}.get(a.size, 50.0)
	var apron_len := n_gates * gate_spacing + 60.0
	var apron_c := main_perp * apron_off
	_slab(root, Vector3(apron_len, 0.16, 170.0), apron_c, -main_h + PI / 2.0, CONCRETE, "apron")
	graph.nodes["apron"] = origin + apron_c + main_perp * -40.0
	# Link apron to every runway's central taxiway
	for i in a.runways.size():
		graph.edges.append(["apron", "r%d_taxi_c" % i])

	var jetways: bool = a.size in ["mega", "international"]
	for g in n_gates:
		var along := (float(g) - (n_gates - 1) * 0.5) * gate_spacing
		var gpos := apron_c + main_dir * along + main_perp * 28.0
		# Stand marking
		var stand: Array = [Transform3D(Basis(Vector3.UP, -main_h), gpos + Vector3(0, 0.12, 0))]
		_multimesh(root, Vector3(16.0, 0.02, 16.0), stand, Color(0.55, 0.56, 0.6), false)
		var lbl := Label3D.new()
		lbl.text = "G%d" % (g + 1)
		lbl.font_size = 200
		lbl.pixel_size = 0.03
		lbl.modulate = Color(1, 0.85, 0.2)
		lbl.position = gpos + Vector3(0, 8.0, 0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		root.add_child(lbl)
		if jetways:
			# Beside the nose, angled - never in the parking envelope
			_building(root, Vector3(2.6, 4.0, 16.0), gpos + main_perp * 24.0 + main_dir * 14.0, -main_h + 0.5, Color(0.7, 0.72, 0.76))
		# Gate faces the terminal (nose toward +perp)
		var gate_heading := atan2(main_perp.x, -main_perp.z)
		data.gates.append({
			"pos": origin + gpos, "heading": gate_heading, "occupied": false, "name": "Gate %d" % (g + 1),
		})
		graph.nodes["gate_%d" % g] = origin + gpos
		graph.edges.append(["gate_%d" % g, "apron"])

	# Terminal - far enough back that even an An-225 nose-in fits. Long
	# terminals are SEGMENTED: one giant box wrecks shadow-map precision.
	if a.size == "small":
		_building(root, Vector3(40.0, 6.0, 14.0), apron_c + main_perp * 105.0, -main_h + PI / 2.0, Color(0.82, 0.83, 0.86))
	else:
		var term_len := apron_len * 0.8
		var n_seg := maxi(int(ceil(term_len / 150.0)), 1)
		var seg_len := term_len / n_seg
		for seg in n_seg:
			var along := (float(seg) - (n_seg - 1) * 0.5) * seg_len
			var h_var := 14.0 + (3.0 if seg % 2 == 0 else 0.0)
			_building(root, Vector3(seg_len - 8.0, h_var, 30.0),
				apron_c + main_perp * 105.0 + main_dir * along, -main_h + PI / 2.0, Color(0.82, 0.83, 0.86))
	# Tower
	var tower_h := float(a.tower_height)
	var tower_pos := apron_c + main_perp * 120.0 + main_dir * (apron_len * 0.5 + 30.0)
	var tower := StaticBody3D.new()
	tower.add_to_group("building")
	tower.position = tower_pos
	var tcyl := CylinderMesh.new()
	tcyl.top_radius = 3.0
	tcyl.bottom_radius = 4.5
	tcyl.height = tower_h
	var tmi := MeshInstance3D.new()
	tmi.mesh = tcyl
	tmi.position.y = tower_h * 0.5
	tmi.material_override = _flat_mat(Color(0.75, 0.76, 0.8))
	tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tower.add_child(tmi)
	var cab := MeshInstance3D.new()
	var cabm := CylinderMesh.new()
	cabm.top_radius = 4.6
	cabm.bottom_radius = 5.4
	cabm.height = 5.0
	cab.mesh = cabm
	cab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cab.position.y = tower_h + 2.5
	var cabmat := StandardMaterial3D.new()
	cabmat.albedo_color = Color(0.15, 0.22, 0.3)
	cabmat.metallic = 0.6
	cabmat.roughness = 0.2
	cab.material_override = cabmat
	tower.add_child(cab)
	var tcs := CollisionShape3D.new()
	var tbs := CylinderShape3D.new()
	tbs.radius = 4.5
	tbs.height = tower_h + 5.0
	tcs.shape = tbs
	tcs.position.y = (tower_h + 5.0) * 0.5
	tower.add_child(tcs)
	root.add_child(tower)

	# Hangars
	for hg in int(a.hangars):
		_building(root, Vector3(30.0, 10.0, 24.0),
			apron_c + main_dir * (-apron_len * 0.5 - 50.0 - hg * 40.0) + main_perp * 20.0,
			-main_h, Color(0.55, 0.35, 0.3))

	# Windsock (orange cone on pole near runway 1 threshold)
	var sock_root := Node3D.new()
	sock_root.position = main_perp * (float(first_rw.width) * 0.5 + 40.0) - main_dir * (float(first_rw.length) * 0.42)
	root.add_child(sock_root)
	var pole := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.08
	pc.bottom_radius = 0.12
	pc.height = 8.0
	pole.mesh = pc
	pole.position.y = 4.0
	pole.material_override = _flat_mat(Color(0.8, 0.8, 0.85))
	sock_root.add_child(pole)
	var sock := Node3D.new()
	sock.position.y = 8.0
	sock_root.add_child(sock)
	var conem := CylinderMesh.new()
	conem.top_radius = 0.12
	conem.bottom_radius = 0.4
	conem.height = 2.4
	var cone := MeshInstance3D.new()
	cone.mesh = conem
	cone.rotation.x = PI / 2.0
	cone.position.z = 1.2
	cone.material_override = _flat_mat(Color(1.0, 0.45, 0.1))
	sock.add_child(cone)
	data.windsock = sock

	return data

# =====================================================================
## BFS shortest path through the taxi graph. Returns Array of absolute Vector3.
static func taxi_route(data: Dictionary, from_node: String, to_node: String) -> Array:
	var graph: Dictionary = data.graph
	if not graph.nodes.has(from_node) or not graph.nodes.has(to_node):
		return []
	var adj: Dictionary = {}
	for e in graph.edges:
		if not adj.has(e[0]):
			adj[e[0]] = []
		if not adj.has(e[1]):
			adj[e[1]] = []
		adj[e[0]].append(e[1])
		adj[e[1]].append(e[0])
	var queue: Array = [from_node]
	var came: Dictionary = {from_node: ""}
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == to_node:
			break
		for nb in adj.get(cur, []):
			if not came.has(nb):
				came[nb] = cur
				queue.append(nb)
	if not came.has(to_node):
		return []
	var path: Array = []
	var cur2 := to_node
	while cur2 != "":
		path.push_front(graph.nodes[cur2])
		cur2 = came[cur2]
	return path

## Nearest graph node name to an absolute position.
static func nearest_node(data: Dictionary, abs_pos: Vector3) -> String:
	var best := ""
	var best_d := 1e18
	for nname in data.graph.nodes.keys():
		var d: float = (data.graph.nodes[nname] as Vector3).distance_to(abs_pos)
		if d < best_d:
			best_d = d
			best = nname
	return best
