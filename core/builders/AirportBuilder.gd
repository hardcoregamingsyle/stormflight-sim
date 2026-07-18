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

static var _bmats: Dictionary = {}

## Shared, cached building material (dozens of buildings reuse a handful).
static func _bmat(color: Color, rough := 0.7, metal := 0.0, emis := 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f_%.2f" % [color.to_html(), rough, metal, emis]
	if _bmats.has(key):
		return _bmats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emis > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emis
	_bmats[key] = m
	return m

static func _building(parent: Node3D, size: Vector3, pos: Vector3, rot_y: float, color: Color, rough := 0.7, metal := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos + Vector3(0, size.y * 0.5, 0)
	body.rotation.y = rot_y
	body.add_to_group("building")
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _bmat(color, rough, metal)
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

## Decorative mesh child of a building body (local coords, no collision).
static func _deco(parent: Node, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## Terminal segment: concrete shell, blue glass curtain wall facing the
## apron (local +Z), white roof fascia and rooftop plant.
static func _terminal_segment(parent: Node3D, size: Vector3, pos: Vector3, rot_y: float) -> void:
	var body := _building(parent, size, pos, rot_y, Color(0.85, 0.86, 0.88))
	var glass := _bmat(Color(0.3, 0.42, 0.55), 0.1, 0.85)
	_deco(body, Vector3(size.x * 0.94, size.y * 0.6, 0.5), Vector3(0, -size.y * 0.1, size.z * 0.5 + 0.1), glass)
	# Landside glass strip too (thinner)
	_deco(body, Vector3(size.x * 0.9, size.y * 0.35, 0.4), Vector3(0, -size.y * 0.05, -size.z * 0.5 - 0.05), glass)
	var white := _bmat(Color(0.94, 0.95, 0.97), 0.5)
	_deco(body, Vector3(size.x + 1.6, 1.3, size.z + 1.6), Vector3(0, size.y * 0.5 + 0.65, 0), white)
	var plant := _bmat(Color(0.6, 0.62, 0.65), 0.8)
	_deco(body, Vector3(4.0, 1.8, 3.0), Vector3(-size.x * 0.24, size.y * 0.5 + 2.2, size.z * 0.12), plant)
	_deco(body, Vector3(3.0, 1.4, 2.6), Vector3(size.x * 0.28, size.y * 0.5 + 2.0, -size.z * 0.1), plant)
	# Entrance canopy over the apron-side doors
	_deco(body, Vector3(size.x * 0.5, 0.35, 5.0), Vector3(0, -size.y * 0.5 + 4.6, size.z * 0.5 + 2.6), white)

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
		# Yellow centerlines (taxiway + connectors) - wide and glowing so they
		# read clearly from the cockpit
		var yellows: Array = []
		var tl := (t2 - t1).length()
		for i in int(tl / 12.0):
			yellows.append(Transform3D(Basis(Vector3.UP, -h), t1 + dir * (i * 12.0) + Vector3(0, 0.16, 0)))
		for pair in [[e1, t1], [e2, t2], [center, tc]]:
			for i in int(t_off / 12.0):
				var p2: Vector3 = (pair[0] as Vector3) + perp * (i * 12.0)
				yellows.append(Transform3D(Basis(Vector3.UP, -h + PI / 2.0), p2 + Vector3(0, 0.16, 0)))
		_multimesh(root, Vector3(0.85, 0.03, 8.0), yellows, Color(1.0, 0.82, 0.1), true)

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
		# Lead-in line: yellow dashes from the stand out to the apron edge so
		# every gate visibly connects to the taxiway system
		var lead: Array = []
		for li in 5:
			lead.append(Transform3D(Basis(Vector3.UP, -main_h + PI / 2.0),
				gpos - main_perp * (10.0 + li * 13.0) + Vector3(0, 0.16, 0)))
		_multimesh(root, Vector3(0.7, 0.03, 7.0), lead, Color(1.0, 0.82, 0.1), true)
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
		_terminal_segment(root, Vector3(40.0, 6.0, 14.0), apron_c + main_perp * 105.0, -main_h + PI / 2.0)
	else:
		var term_len := apron_len * 0.8
		var n_seg := maxi(int(ceil(term_len / 150.0)), 1)
		var seg_len := term_len / n_seg
		for seg in n_seg:
			var along := (float(seg) - (n_seg - 1) * 0.5) * seg_len
			var h_var := 14.0 + (3.0 if seg % 2 == 0 else 0.0)
			_terminal_segment(root, Vector3(seg_len - 8.0, h_var, 30.0),
				apron_c + main_perp * 105.0 + main_dir * along, -main_h + PI / 2.0)
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
	# Cab roof, antenna mast + red obstruction beacon
	var roof := MeshInstance3D.new()
	var roofm := CylinderMesh.new()
	roofm.top_radius = 5.0
	roofm.bottom_radius = 5.5
	roofm.height = 0.7
	roof.mesh = roofm
	roof.position.y = tower_h + 5.3
	roof.material_override = _bmat(Color(0.9, 0.91, 0.93), 0.5)
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tower.add_child(roof)
	var ant := MeshInstance3D.new()
	var antm := CylinderMesh.new()
	antm.top_radius = 0.06
	antm.bottom_radius = 0.14
	antm.height = 7.0
	ant.mesh = antm
	ant.position.y = tower_h + 5.6 + 3.5
	ant.material_override = _bmat(Color(0.7, 0.71, 0.75), 0.4, 0.8)
	ant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tower.add_child(ant)
	var beacon := MeshInstance3D.new()
	var beam := SphereMesh.new()
	beam.radius = 0.45
	beam.height = 0.9
	beacon.mesh = beam
	beacon.position.y = tower_h + 5.6 + 7.2
	beacon.material_override = _bmat(Color(1.0, 0.12, 0.1), 0.4, 0.0, 3.0)
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tower.add_child(beacon)
	var tcs := CollisionShape3D.new()
	var tbs := CylinderShape3D.new()
	tbs.radius = 4.5
	tbs.height = tower_h + 5.0
	tcs.shape = tbs
	tcs.position.y = (tower_h + 5.0) * 0.5
	tower.add_child(tcs)
	root.add_child(tower)

	# Hangars: steel shells with gabled roofs and big sliding doors
	for hg in int(a.hangars):
		var hpos := apron_c + main_dir * (-apron_len * 0.5 - 50.0 - hg * 40.0) + main_perp * 20.0
		var hangar := _building(root, Vector3(30.0, 8.0, 24.0), hpos, -main_h, Color(0.6, 0.62, 0.66))
		var roof_mesh := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(30.5, 5.0, 24.5)
		roof_mesh.mesh = prism
		roof_mesh.position = Vector3(0, 6.5, 0)  # sits on the 8 m shell (local)
		roof_mesh.material_override = _bmat(Color(0.45, 0.47, 0.52), 0.6, 0.3)
		roof_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hangar.add_child(roof_mesh)
		# Sliding door on the apron-facing gable end (local -Z faces the apron)
		_deco(hangar, Vector3(26.0, 6.6, 0.4), Vector3(0, -0.7, -12.2), _bmat(Color(0.35, 0.37, 0.42), 0.55, 0.4))
		_deco(hangar, Vector3(26.0, 0.5, 0.5), Vector3(0, 2.9, -12.3), _bmat(Color(0.95, 0.55, 0.1), 0.5))

	# Fuel farm: white storage tanks behind the hangar line
	for ft in 3:
		var fpos := apron_c + main_dir * (-apron_len * 0.5 - 60.0) + main_perp * (95.0 + ft * 17.0)
		var tank := StaticBody3D.new()
		tank.add_to_group("building")
		tank.position = fpos + Vector3(0, 4.0, 0)
		var tmesh := MeshInstance3D.new()
		# NB: named fuel_cyl, not tcyl - the tower's tcyl is still live in this
		# scope and GDScript 2 treats shadowing an outer local as a parse error
		var fuel_cyl := CylinderMesh.new()
		fuel_cyl.top_radius = 6.0
		fuel_cyl.bottom_radius = 6.0
		fuel_cyl.height = 8.0
		tmesh.mesh = fuel_cyl
		tmesh.material_override = _bmat(Color(0.92, 0.93, 0.95), 0.35, 0.4)
		tmesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tank.add_child(tmesh)
		_deco(tank, Vector3(1.2, 0.8, 13.0), Vector3(0, 4.2, 0), _bmat(Color(0.6, 0.62, 0.66), 0.5, 0.5))
		var tank_cs := CollisionShape3D.new()
		var tank_shape := CylinderShape3D.new()
		tank_shape.radius = 6.0
		tank_shape.height = 8.0
		tank_cs.shape = tank_shape
		tank.add_child(tank_cs)
		root.add_child(tank)

	# Cargo containers scattered along the hangar apron
	var cont_cols := [Color(0.8, 0.35, 0.1), Color(0.15, 0.35, 0.6), Color(0.2, 0.5, 0.25), Color(0.6, 0.15, 0.15)]
	for ci in 8:
		var cpos := apron_c + main_dir * (-apron_len * 0.5 - 20.0 - float(ci % 4) * 8.0) \
			+ main_perp * (52.0 + float(floori(ci / 4.0)) * 5.0)
		_building(root, Vector3(6.0, 2.6, 2.4), cpos, -main_h + (0.3 if ci % 3 == 0 else 0.0), cont_cols[ci % cont_cols.size()], 0.6, 0.3)

	# Apron floodlight masts along the terminal edge
	var flood_head := _bmat(Color(1.0, 0.97, 0.88), 0.4, 0.0, 2.2)
	var pole_mat := _bmat(Color(0.5, 0.52, 0.56), 0.5, 0.6)
	for fl in 5:
		var fl_along := (float(fl) - 2.0) * (apron_len * 0.22)
		var fl_pos := apron_c + main_perp * 88.0 + main_dir * fl_along
		var mast := Node3D.new()
		mast.position = fl_pos
		root.add_child(mast)
		var pole := MeshInstance3D.new()
		var pole_m := CylinderMesh.new()
		pole_m.top_radius = 0.16
		pole_m.bottom_radius = 0.25
		pole_m.height = 14.0
		pole.mesh = pole_m
		pole.position.y = 7.0
		pole.material_override = pole_mat
		pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mast.add_child(pole)
		var head := MeshInstance3D.new()
		var head_m := BoxMesh.new()
		head_m.size = Vector3(2.4, 0.5, 0.8)
		head.mesh = head_m
		head.position = Vector3(0, 14.0, 0)
		head.material_override = flood_head
		head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mast.add_child(head)

	# City skyline + tree belt round out the view from the pattern
	_build_city(root, a, main_h, main_dir, main_perp)
	_scatter_trees(root, a, main_dir, main_perp)

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
## Procedural downtown on the terminal side of the field: low-rise blocks
## with a handful of glass towers, obstruction lights on the tall ones.
## Deterministic per airport. Skipped at small fields.
static func _build_city(root: Node3D, a: Dictionary, main_h: float, main_dir: Vector3, main_perp: Vector3) -> void:
	if a.size == "small":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(a.icao)) + 17
	var palette := [Color(0.74, 0.72, 0.69), Color(0.62, 0.63, 0.66), Color(0.57, 0.51, 0.47),
		Color(0.68, 0.7, 0.73), Color(0.5, 0.54, 0.6)]
	var n_rows := 5 if a.size == "mega" else 4
	var n_cols := 9 if a.size == "mega" else 7
	var glass_col := Color(0.34, 0.44, 0.55)
	var window_mat := _bmat(Color(0.95, 0.9, 0.7), 0.4, 0.0, 0.7)
	for gz in n_rows:
		for gx in n_cols:
			if rng.randf() < 0.16:
				continue
			var along := (float(gx) - (n_cols - 1) * 0.5) * 150.0 + rng.randf_range(-22.0, 22.0)
			var out := 1150.0 + gz * 150.0 + rng.randf_range(-22.0, 22.0)
			var pos := main_perp * out + main_dir * along
			# Mostly low-rise, with a downtown core near the middle rows
			var core := 1.0 - clampf(absf(along) / (n_cols * 80.0) + float(gz) / (n_rows * 2.0), 0.0, 1.0)
			var hgt := rng.randf_range(9.0, 24.0) + pow(rng.randf(), 3.0) * 130.0 * (0.3 + core)
			var w := rng.randf_range(16.0, 34.0)
			var d := rng.randf_range(16.0, 34.0)
			var is_tower := hgt > 60.0
			if is_tower:
				w = clampf(w, 16.0, 26.0)
				d = clampf(d, 16.0, 26.0)
			var col: Color = glass_col if is_tower else palette[rng.randi() % palette.size()]
			var b := _building(root, Vector3(w, hgt, d), pos, -main_h + rng.randf_range(-0.06, 0.06),
				col, 0.12 if is_tower else 0.75, 0.85 if is_tower else 0.0)
			if is_tower:
				# Roof plant + lit window bands + red obstruction light
				_deco(b, Vector3(w * 0.5, 2.0, d * 0.5), Vector3(0, hgt * 0.5 + 1.0, 0), _bmat(Color(0.8, 0.81, 0.84), 0.6))
				for side in [-1.0, 1.0]:
					_deco(b, Vector3(w * 0.7, hgt * 0.8, 0.3), Vector3(0, 0, side * (d * 0.5 + 0.05)), window_mat)
				if hgt > 90.0:
					_deco(b, Vector3(0.8, 0.8, 0.8), Vector3(0, hgt * 0.5 + 2.4, 0), _bmat(Color(1.0, 0.12, 0.1), 0.4, 0.0, 3.0))

## Conifer belt around the field - everywhere except the terminal/city side
## and the runway strips. One MultiMesh, per-instance color variation.
static func _scatter_trees(root: Node3D, a: Dictionary, _main_dir: Vector3, main_perp: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(a.icao)) + 31
	var max_len := 0.0
	for rw in a.runways:
		max_len = maxf(max_len, float(rw.length))
	var safe_r := max_len * 0.75 + 400.0
	var count := 60 if Quality.is_web else 170
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var attempts := 0
	while xforms.size() < count and attempts < count * 12:
		attempts += 1
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf()) * safe_r
		var p := Vector3(cos(ang) * r, 0, sin(ang) * r)
		if p.dot(main_perp) > 40.0:
			continue  # terminal / apron / city side stays clear
		var too_close := false
		for rw in a.runways:
			var h := deg_to_rad(float(rw.heading))
			var dir := Vector3(sin(h), 0, -cos(h))
			var perp := Vector3(-cos(h), 0, -sin(h))
			var center := Vector3(float(rw.offset[0]), 0, float(rw.offset[1]))
			var rel := p - center
			if absf(rel.dot(dir)) < float(rw.length) * 0.55 + 250.0 \
					and absf(rel.dot(perp)) < float(rw.width) + 160.0:
				too_close = true
				break
		if too_close:
			continue
		var s := rng.randf_range(0.7, 1.6)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.3), s))
		xforms.append(Transform3D(basis, p + Vector3(0, 2.4 * s, 0)))
		colors.append(Color(0.12, 0.3, 0.13).lerp(Color(0.25, 0.42, 0.16), rng.randf()))
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 2.0
	cone.height = 6.0
	cone.radial_segments = 7
	var tree_mat := StandardMaterial3D.new()
	tree_mat.vertex_color_use_as_albedo = true
	tree_mat.roughness = 0.95
	cone.material = tree_mat
	mm.mesh = cone
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)

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
