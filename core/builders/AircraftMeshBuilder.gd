class_name AircraftMeshBuilder
## Parametric 3D aircraft generator. Builds a full visual model from an
## AircraftConfig's mesh parameters: lathed fuselage, airfoil wings, tails
## (conventional / T-tail / twin canted / H-tail), engines (underwing pods,
## embedded jets with afterburner nozzles, nose piston prop, helicopter
## rotors), animated control surfaces (ailerons, elevators, rudders, Fowler
## flaps, slats, spoilers), retractable gear with bogies, livery colors,
## registration text and navigation lights.
##
## Axes: +X right, +Y up, +Z back (nose = -Z). Origin = CG (wing 1/4 chord).

static var SEGS: int = 10 if OS.has_feature("web") else 20
static var _mats: Dictionary = {}

# ============================================================ material helpers
static func _mat(color: Color, rough := 0.55, metal := 0.15, emissive := false) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f_%s" % [color.to_html(), rough, metal, emissive]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emissive:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 2.0
	_mats[key] = m
	return m

static func _glass() -> StandardMaterial3D:
	if _mats.has("glass"):
		return _mats["glass"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.08, 0.1, 0.14)
	m.roughness = 0.12
	m.metallic = 0.65
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["glass"] = m
	return m

static func _mesh_node(mesh: Mesh, mat: Material, parent: Node3D, pos := Vector3.ZERO, name := "part") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.name = name
	parent.add_child(mi)
	return mi

static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

# ============================================================ lathe (fuselage)
## profile: Array of Vector2(z_along_axis, radius). Revolved around Z.
static func _lathe(profile: Array, y_squash := 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := SEGS
	for i in range(profile.size() - 1):
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		for j in n:
			var a0 := TAU * j / n
			var a1 := TAU * (j + 1) / n
			var v00 := Vector3(cos(a0) * p0.y, sin(a0) * p0.y * y_squash, p0.x)
			var v01 := Vector3(cos(a1) * p0.y, sin(a1) * p0.y * y_squash, p0.x)
			var v10 := Vector3(cos(a0) * p1.y, sin(a0) * p1.y * y_squash, p1.x)
			var v11 := Vector3(cos(a1) * p1.y, sin(a1) * p1.y * y_squash, p1.x)
			st.add_vertex(v00); st.add_vertex(v10); st.add_vertex(v01)
			st.add_vertex(v01); st.add_vertex(v10); st.add_vertex(v11)
	st.generate_normals()
	return st.commit()

## Tapered airfoil panel lofted from root to tip. Origin at root leading edge.
## dir = +1 right wing, -1 left. Returns mesh in wing-local space where
## +X = outboard*dir, +Z = aft (chordwise), +Y = up.
static func _wing_mesh(root_c: float, tip_c: float, span: float, sweep: float, dihedral: float, thick: float, dir: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Hexagonal airfoil section: (chord frac, thickness frac)
	var sec := [Vector2(0.0, 0.0), Vector2(0.28, 0.5), Vector2(0.8, 0.18), Vector2(1.0, 0.0), Vector2(0.8, -0.12), Vector2(0.28, -0.35)]
	var tip_off := Vector3(dir * span, span * tan(dihedral), span * tan(sweep))
	var pts_r: Array[Vector3] = []
	var pts_t: Array[Vector3] = []
	for s in sec:
		pts_r.append(Vector3(0, s.y * thick * root_c, s.x * root_c))
		pts_t.append(tip_off + Vector3(0, s.y * thick * tip_c * 0.8, s.x * tip_c))
	var m := sec.size()
	var flip := dir < 0.0  # mirrored wing needs reversed winding
	for i in m:
		var j := (i + 1) % m
		_tri(st, pts_r[i], pts_t[i], pts_r[j], flip)
		_tri(st, pts_r[j], pts_t[i], pts_t[j], flip)
	# End caps
	for i in range(1, m - 1):
		_tri(st, pts_r[0], pts_r[i], pts_r[i + 1], flip)
		_tri(st, pts_t[0], pts_t[i + 1], pts_t[i], flip)
	st.generate_normals()
	return st.commit()

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, flip: bool) -> void:
	if flip:
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
	else:
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)

## Point on the wing planform. sf = span fraction 0..1, cf = chord fraction 0..1.
static func _wing_point(root_c: float, tip_c: float, span: float, sweep: float, dihedral: float, dir: float, sf: float, cf: float) -> Vector3:
	var c := lerpf(root_c, tip_c, sf)
	return Vector3(dir * span * sf, span * sf * tan(dihedral), span * sf * tan(sweep) + cf * c)

# ============================================================ main entry
static func build(cfg: AircraftConfig) -> Dictionary:
	var root := Node3D.new()
	root.name = "Visual"
	var parts := {
		"elev": [], "rud": [], "flaps": [], "slats": [], "spoilers": [],
		"prop_roots": [], "fan_discs": [], "rotor_main": [], "rotor_tail": [],
		"ab_glows": [], "wheels": [], "gear_nose": null, "gear_main_l": null,
		"gear_main_r": null, "beacon": null, "strobes": [], "landing_lights": [],
		"ail_l": null, "ail_r": null,
	}
	var mp := cfg.mesh
	var L := float(mp.get("fuselage_length_m", 10.0))
	var R := float(mp.get("fuselage_radius_m", 1.0))
	var wz := float(mp.get("wing_z_frac", 0.45))
	var primary := Color(String(mp.get("livery_primary", "#e8e8ee")))
	var accent := Color(String(mp.get("livery_accent", "#3060a8")))
	var tail_col := Color(String(mp.get("livery_tail", "#3060a8")))
	var grey := Color(0.62, 0.64, 0.68)

	var nose_z := -wz * L
	var tail_z := (1.0 - wz) * L

	if cfg.is_helicopter():
		_build_heli(cfg, root, parts, primary, accent, tail_col)
		_build_lights(cfg, root, parts)
		_disable_shadow_casting(root)
		return {"root": root, "parts": parts}

	# ---------------- fuselage ----------------
	var nf := float(mp.get("nose_length_frac", 0.15))
	var tf := float(mp.get("tail_length_frac", 0.25))
	var prof: Array = []
	prof.append(Vector2(nose_z, R * 0.04))
	prof.append(Vector2(nose_z + nf * L * 0.3, R * 0.55))
	prof.append(Vector2(nose_z + nf * L, R))
	prof.append(Vector2(tail_z - tf * L, R))
	prof.append(Vector2(tail_z - tf * L * 0.4, R * 0.6))
	prof.append(Vector2(tail_z, R * 0.12))
	var is_fighter := cfg.role in ["fighter", "attack"]
	var fus := _mesh_node(_lathe(prof, 0.92 if is_fighter else 1.0), _mat(primary, 0.42, 0.25), root, Vector3.ZERO, "fuselage")
	fus.position.y = 0.0

	# Accent stripe + windows for airliners
	if cfg.role in ["airliner", "cargo"]:
		for side in [-1.0, 1.0]:
			_mesh_node(_box(Vector3(0.06, R * 0.22, L * 0.72)), _mat(accent, 0.4, 0.2), root,
				Vector3(side * R * 0.99, -R * 0.12, (nose_z + tail_z) * 0.5), "stripe")
			if cfg.role == "airliner":
				_mesh_node(_box(Vector3(0.05, R * 0.13, L * 0.62)), _mat(Color(0.1, 0.12, 0.16), 0.2, 0.5), root,
					Vector3(side * R * 0.995, R * 0.28, (nose_z + tail_z) * 0.5), "windows")

	# Cockpit
	var ck := String(mp.get("cockpit_type", "airliner"))
	if ck == "fighter_canopy":
		var can := SphereMesh.new()
		can.radius = R * 0.75
		can.height = R * 1.5
		var cmi := _mesh_node(can, _glass(), root, Vector3(0, R * 0.65, nose_z + nf * L * 1.35), "canopy")
		cmi.scale = Vector3(0.75, 0.8, 2.6)
	elif ck == "airliner":
		for side in [-1.0, 1.0]:
			var wsh := _mesh_node(_box(Vector3(R * 0.55, R * 0.28, R * 0.9)), _glass(), root,
				Vector3(side * R * 0.55, R * 0.42, nose_z + nf * L * 0.85), "windshield")
			wsh.rotation.y = side * 0.5
	else: # ga
		_mesh_node(_box(Vector3(R * 1.7, R * 0.7, R * 1.6)), _glass(), root,
			Vector3(0, R * 0.75, nose_z + L * 0.3), "cabin_glass")

	# ---------------- wings + control surfaces ----------------
	var root_c := float(mp.get("wing_root_chord_m", 2.0))
	var tip_c := float(mp.get("wing_tip_chord_m", 1.0))
	var sweep := deg_to_rad(float(mp.get("wing_sweep_deg", 0.0)))
	var dihedral := deg_to_rad(float(mp.get("wing_dihedral_deg", 0.0)))
	var semi := cfg.wing_span * 0.5 - R * 0.5
	var mount := String(mp.get("wing_mount", "low"))
	var wing_y := -R * 0.62 if mount == "low" else (R * 0.85 if mount == "high" else 0.0)
	var wing_root_z := -root_c * 0.3  # 1/4 chord near origin
	var wing_mat := _mat(grey, 0.5, 0.3)

	for dir in [-1.0, 1.0]:
		var wing := _mesh_node(_wing_mesh(root_c, tip_c, semi, sweep, dihedral, 0.085, dir), wing_mat, root,
			Vector3(dir * R * 0.5, wing_y, wing_root_z), "wing")
		# Winglet
		if cfg.role == "airliner" and rad_to_deg(sweep) >= 20.0:
			var tip := _wing_point(root_c, tip_c, semi, sweep, dihedral, dir, 1.0, 0.3)
			var wl := _mesh_node(_wing_mesh(tip_c * 0.8, tip_c * 0.35, tip_c * 1.1, deg_to_rad(38), deg_to_rad(78), 0.08, dir), _mat(tail_col, 0.45, 0.25), wing, tip, "winglet")
			wl.rotation.z = dir * -0.35
		# Aileron (outboard trailing edge)
		var ail := _hinged_surface(cfg, wing, root_c, tip_c, semi, sweep, dihedral, dir, 0.62, 0.94, 0.76, 1.0, accent.darkened(0.25))
		if dir < 0:
			parts.ail_l = ail
		else:
			parts.ail_r = ail
		# Flaps (inboard trailing edge, Fowler slide + droop)
		var flp := _hinged_surface(cfg, wing, root_c, tip_c, semi, sweep, dihedral, dir, 0.08, 0.55, 0.72, 1.0, grey.darkened(0.15))
		flp.set_meta("slide", Vector3(0, -0.04, lerpf(root_c, tip_c, 0.3) * 0.22))
		parts.flaps.append(flp)
		# Slats (leading edge)
		if cfg.has_slats:
			var slt := _hinged_surface(cfg, wing, root_c, tip_c, semi, sweep, dihedral, dir, 0.1, 0.9, 0.0, 0.13, grey.darkened(0.1))
			slt.set_meta("slide", Vector3(0, -0.05, -lerpf(root_c, tip_c, 0.5) * 0.14))
			parts.slats.append(slt)
		# Spoilers (top surface panels)
		if cfg.has_spoilers:
			var spo := _hinged_surface(cfg, wing, root_c, tip_c, semi, sweep, dihedral, dir, 0.18, 0.55, 0.45, 0.62, grey.darkened(0.25))
			spo.position.y += 0.06
			parts.spoilers.append(spo)

	# ---------------- tail ----------------
	_build_tail(cfg, root, parts, tail_z, R, tail_col, grey)

	# ---------------- engines ----------------
	_build_engines(cfg, root, parts, nose_z, tail_z, R, wing_y, wing_root_z, root_c, tip_c, semi, sweep, dihedral, primary, accent)

	# ---------------- landing gear ----------------
	_build_gear(cfg, root, parts, R)

	# ---------------- registration ----------------
	var reg := Label3D.new()
	reg.text = "SF-%s" % cfg.id.substr(0, 4).to_upper()
	reg.font_size = 120
	reg.pixel_size = 0.01 * maxf(L / 30.0, 0.5)
	reg.modulate = Color(0.12, 0.13, 0.17)
	reg.position = Vector3(0, R * 0.4, tail_z - tf * L * 1.4)
	reg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(reg)

	_build_lights(cfg, root, parts)
	_disable_shadow_casting(root)
	return {"root": root, "parts": parts}

## Aircraft meshes corrupt directional shadow-map precision (engine quirk with
## these procedural casters), so planes use a soft blob shadow instead.
static func _disable_shadow_casting(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadow_casting(child)

## Builds a control surface strip on a wing panel, parented to a hinge pivot.
## Returns the pivot Node3D (rotate .rotation.x to deflect; TE-down = negative).
static func _hinged_surface(_cfg: AircraftConfig, wing: MeshInstance3D, root_c: float, tip_c: float, semi: float, sweep: float, dihedral: float, dir: float, sf0: float, sf1: float, cf0: float, cf1: float, color: Color) -> Node3D:
	var p0 := _wing_point(root_c, tip_c, semi, sweep, dihedral, dir, sf0, cf0)
	var p1 := _wing_point(root_c, tip_c, semi, sweep, dihedral, dir, sf1, cf0)
	var mid := (p0 + p1) * 0.5
	var hinge_dir := (p1 - p0).normalized()
	var span_len := (p1 - p0).length()
	var depth := lerpf(root_c, tip_c, (sf0 + sf1) * 0.5) * (cf1 - cf0)

	var pivot := Node3D.new()
	pivot.position = mid + Vector3(0, 0.0, 0.0)
	# Basis: local X along hinge, Z chordwise-aft, Y up
	var bx := hinge_dir if dir > 0 else -hinge_dir
	var bz := Vector3(0, 0, 1)
	bz = (bz - bx * bz.dot(bx)).normalized()
	var by := bz.cross(bx).normalized()
	pivot.basis = Basis(bx, by, bz)
	wing.add_child(pivot)
	var mesh := _box(Vector3(span_len * 0.96, 0.07, depth))
	_mesh_node(mesh, _mat(color, 0.5, 0.25), pivot, Vector3(0, 0, depth * 0.5), "surf")
	pivot.set_meta("base_pos", pivot.position)
	return pivot

static func _build_tail(cfg: AircraftConfig, root: Node3D, parts: Dictionary, tail_z: float, R: float, tail_col: Color, grey: Color) -> void:
	var mp := cfg.mesh
	var tt := String(mp.get("tail_type", "conventional"))
	var ht_span := float(mp.get("htail_span_m", 6.0)) * 0.5
	var ht_c := float(mp.get("htail_chord_m", 1.5))
	var vt_h := float(mp.get("vtail_height_m", 3.0))
	var vt_c := float(mp.get("vtail_chord_m", 2.0))
	var tail_mat := _mat(tail_col, 0.45, 0.25)
	var ht_z := tail_z - ht_c * 1.15
	var is_stabilator := tt == "twin_canted"

	# --- Vertical fin(s) + rudder(s) ---
	var fin_positions: Array = []
	match tt:
		"twin_canted":
			fin_positions = [Vector3(-ht_span * 0.55, R * 0.5, ht_z - vt_c * 0.2), Vector3(ht_span * 0.55, R * 0.5, ht_z - vt_c * 0.2)]
		"h_tail":
			fin_positions = [Vector3(-ht_span, R * 0.55, ht_z), Vector3(ht_span, R * 0.55, ht_z)]
		_:
			fin_positions = [Vector3(0, R * 0.6, tail_z - vt_c * 1.05)]
	var cant := deg_to_rad(24.0) if tt == "twin_canted" else 0.0
	for i in fin_positions.size():
		var fp: Vector3 = fin_positions[i]
		var fin_root := Node3D.new()
		fin_root.position = fp
		var side := -1.0 if fp.x < 0 else 1.0
		fin_root.rotation.z = -side * cant if tt == "twin_canted" else 0.0
		root.add_child(fin_root)
		var fin := MeshInstance3D.new()
		fin.mesh = _wing_mesh(vt_c, vt_c * 0.45, vt_h, deg_to_rad(32), 0.0, 0.09, 1.0)
		fin.material_override = tail_mat
		fin.rotation.z = PI / 2.0  # rotate wing panel to vertical
		fin_root.add_child(fin)
		# Rudder: vertical hinged strip
		var rud_pivot := Node3D.new()
		rud_pivot.position = Vector3(0, vt_h * 0.42, vt_c * 0.82 + vt_h * 0.42 * tan(deg_to_rad(32)))
		fin_root.add_child(rud_pivot)
		_mesh_node(_box(Vector3(0.08, vt_h * 0.72, vt_c * 0.3)), _mat(tail_col.darkened(0.2), 0.5, 0.2), rud_pivot, Vector3(0, 0, vt_c * 0.15), "rudder")
		parts.rud.append(rud_pivot)

	# --- Horizontal tail + elevators ---
	var ht_y := R * 0.25
	if tt == "t_tail":
		ht_y = R * 0.6 + vt_h * 0.92
	elif tt == "h_tail":
		ht_y = R * 0.55
	elif tt == "twin_canted":
		ht_y = R * 0.1
	for dir in [-1.0, 1.0]:
		var stab_pivot := Node3D.new()
		stab_pivot.position = Vector3(dir * R * 0.4, ht_y, ht_z)
		root.add_child(stab_pivot)
		var stab := MeshInstance3D.new()
		stab.mesh = _wing_mesh(ht_c, ht_c * 0.5, ht_span, deg_to_rad(28), deg_to_rad(6 if tt != "h_tail" else 0), 0.07, dir)
		stab.material_override = _mat(grey, 0.5, 0.3)
		stab_pivot.add_child(stab)
		if is_stabilator:
			parts.elev.append(stab_pivot)  # all-moving stabilator
		else:
			var elev_pivot := Node3D.new()
			elev_pivot.position = Vector3(dir * ht_span * 0.45, 0.02, ht_c * 0.8 + ht_span * 0.45 * tan(deg_to_rad(28)))
			stab_pivot.add_child(elev_pivot)
			_mesh_node(_box(Vector3(ht_span * 0.85, 0.06, ht_c * 0.28)), _mat(grey.darkened(0.2), 0.5, 0.25), elev_pivot, Vector3(0, 0, ht_c * 0.14), "elevator")
			parts.elev.append(elev_pivot)

static func _build_engines(cfg: AircraftConfig, root: Node3D, parts: Dictionary, nose_z: float, tail_z: float, R: float, wing_y: float, wing_root_z: float, root_c: float, tip_c: float, semi: float, sweep: float, dihedral: float, primary: Color, accent: Color) -> void:
	var mp := cfg.mesh
	var mount := String(mp.get("engine_mount", "underwing"))
	var nac_r := float(mp.get("nacelle_radius_m", 1.0))
	var nac_l := float(mp.get("nacelle_length_m", 4.0))
	var spans: Array = mp.get("engine_span_positions", [])
	var nac_mat := _mat(primary.darkened(0.05), 0.4, 0.4)
	var dark := _mat(Color(0.12, 0.12, 0.14), 0.35, 0.7)

	match mount:
		"underwing":
			for x_pos in spans:
				for dir in [-1.0, 1.0]:
					var sf: float = clampf(float(x_pos) / maxf(semi + R * 0.5, 1.0), 0.05, 0.95)
					var wp := _wing_point(root_c, tip_c, semi, sweep, dihedral, dir, sf, 0.0)
					var pos := Vector3(dir * R * 0.5, wing_y, wing_root_z) + wp + Vector3(0, -nac_r * 1.15, -nac_l * 0.55)
					_add_nacelle(root, parts, pos, nac_r, nac_l, nac_mat, dark, accent)
		"over_fuselage": # A-10 style
			for dir in [-1.0, 1.0]:
				var pos := Vector3(dir * (R + nac_r * 0.7), R * 0.9, tail_z - nac_l * 1.6)
				_add_nacelle(root, parts, pos, nac_r, nac_l, nac_mat, dark, accent)
		"embedded": # fighters: intakes + nozzles
			var n_off := 0.6 if cfg.engine_count > 1 else 0.0
			for i in cfg.engine_count:
				var side := (1.0 if i % 2 == 1 else -1.0) * (n_off if cfg.engine_count > 1 else 0.0)
				# Intake box at mid fuselage
				_mesh_node(_box(Vector3(R * 0.55, R * 0.7, R * 2.2)), dark, root, Vector3(side + signf(side) * R * 0.8, -R * 0.15, -R * 0.5), "intake")
				# Nozzle
				var noz := _mesh_node(_lathe([Vector2(0, R * 0.42), Vector2(R * 0.9, R * 0.3)]), dark, root, Vector3(side, 0, tail_z - R * 0.3), "nozzle")
				# Afterburner glow cone
				var glow_m := StandardMaterial3D.new()
				glow_m.albedo_color = Color(1.0, 0.55, 0.15, 0.85)
				glow_m.emission_enabled = true
				glow_m.emission = Color(1.0, 0.45, 0.1)
				glow_m.emission_energy_multiplier = 6.0
				glow_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				glow_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				var glow := _mesh_node(_lathe([Vector2(0, R * 0.28), Vector2(2.2, R * 0.1)]), glow_m, noz, Vector3(0, 0, R * 0.9), "ab_glow")
				glow.visible = false
				parts.ab_glows.append(glow)
		"nose": # piston prop
			var cowl := _mesh_node(_lathe([Vector2(-0.4, R * 0.35), Vector2(0.0, R * 0.85), Vector2(1.2, R * 0.95)]), nac_mat, root, Vector3(0, 0, nose_z + 0.3), "cowl")
			var prop_root := Node3D.new()
			prop_root.position = Vector3(0, 0, -0.45)
			cowl.add_child(prop_root)
			var spinner := _lathe([Vector2(-0.35, 0.02), Vector2(0.0, 0.16), Vector2(0.15, 0.18)])
			_mesh_node(spinner, dark, prop_root, Vector3.ZERO, "spinner")
			for b in 2:
				var blade := _mesh_node(_box(Vector3(0.13, 1.9, 0.05)), dark, prop_root, Vector3.ZERO, "blade")
				blade.rotation.z = PI * b
				blade.position.y = 0.0
			parts.prop_roots.append(prop_root)
		_:
			pass

static func _add_nacelle(root: Node3D, parts: Dictionary, pos: Vector3, nac_r: float, nac_l: float, nac_mat: Material, dark: Material, accent: Color) -> void:
	var prof := [Vector2(0.0, nac_r * 0.72), Vector2(nac_l * 0.12, nac_r), Vector2(nac_l * 0.7, nac_r * 0.92), Vector2(nac_l, nac_r * 0.45)]
	var nac := _mesh_node(_lathe(prof), nac_mat, root, pos, "nacelle")
	# Pylon
	_mesh_node(_box(Vector3(0.25, nac_r * 1.2, nac_l * 0.5)), nac_mat, nac, Vector3(0, nac_r * 0.9, nac_l * 0.45), "pylon")
	# Intake lip ring accent
	_mesh_node(_lathe([Vector2(-0.02, nac_r * 0.99), Vector2(0.12, nac_r * 1.0)]), _mat(accent, 0.4, 0.5), nac, Vector3.ZERO, "lip")
	# Spinning fan disc
	var fan := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = nac_r * 0.68
	cyl.bottom_radius = nac_r * 0.68
	cyl.height = 0.1
	fan.mesh = cyl
	fan.material_override = dark
	fan.rotation.x = PI / 2.0
	fan.position = Vector3(0, 0, nac_l * 0.1)
	nac.add_child(fan)
	parts.fan_discs.append(fan)
	# Exhaust cone
	_mesh_node(_lathe([Vector2(0, nac_r * 0.32), Vector2(nac_l * 0.18, 0.03)]), dark, nac, Vector3(0, 0, nac_l * 0.97), "exhaust")

static func _build_gear(cfg: AircraftConfig, root: Node3D, parts: Dictionary, R: float) -> void:
	var leg := cfg.gear_leg_length
	var wheel_r := clampf(0.24 + 0.11 * log(maxf(cfg.mtow / 1000.0, 0.5)) / log(10.0) * 2.2, 0.2, 0.85)
	var strut_mat := _mat(Color(0.75, 0.76, 0.8), 0.35, 0.85)
	var tire_mat := _mat(Color(0.09, 0.09, 0.1), 0.9, 0.0)
	var bottom_y := -R * 0.55

	# Helicopter skids
	if cfg.is_helicopter() and not cfg.gear_retractable:
		for side in [-1.0, 1.0]:
			var rail := _mesh_node(_box(Vector3(0.09, 0.09, cfg.rotor_main_radius * 0.9)), strut_mat, root, Vector3(side * R * 1.1, bottom_y - leg, 0), "skid")
			for zz in [-0.35, 0.35]:
				var post := _mesh_node(_box(Vector3(0.07, leg, 0.07)), strut_mat, rail, Vector3(0, leg * 0.5, zz * cfg.rotor_main_radius * 0.8), "post")
				post.rotation.z = side * 0.25
		return

	var legs := [
		{"pos": Vector3(0, bottom_y, cfg.gear_nose_z), "key": "gear_nose", "stow_axis": "x", "wheels": 2 if cfg.mtow > 40000 else 1},
		{"pos": Vector3(-cfg.gear_main_x, bottom_y, cfg.gear_main_z), "key": "gear_main_l", "stow_axis": "z", "wheels": 4 if cfg.mtow > 130000 else (2 if cfg.mtow > 15000 else 1)},
		{"pos": Vector3(cfg.gear_main_x, bottom_y, cfg.gear_main_z), "key": "gear_main_r", "stow_axis": "z", "wheels": 4 if cfg.mtow > 130000 else (2 if cfg.mtow > 15000 else 1)},
	]
	for lg in legs:
		var pivot := Node3D.new()
		pivot.position = lg.pos
		pivot.set_meta("stow_axis", lg.stow_axis)
		pivot.set_meta("side", signf(lg.pos.x) if lg.stow_axis == "z" else 1.0)
		root.add_child(pivot)
		parts[lg.key] = pivot
		_mesh_node(_box(Vector3(0.14 * sqrt(wheel_r / 0.3), leg, 0.14 * sqrt(wheel_r / 0.3))), strut_mat, pivot, Vector3(0, -leg * 0.5, 0), "strut")
		var n_wheels: int = lg.wheels
		var wheel_positions: Array = []
		match n_wheels:
			1: wheel_positions = [Vector3(0, -leg, 0)]
			2: wheel_positions = [Vector3(-wheel_r * 0.55, -leg, 0), Vector3(wheel_r * 0.55, -leg, 0)]
			4: wheel_positions = [
				Vector3(-wheel_r * 0.55, -leg, -wheel_r * 1.15), Vector3(wheel_r * 0.55, -leg, -wheel_r * 1.15),
				Vector3(-wheel_r * 0.55, -leg, wheel_r * 1.15), Vector3(wheel_r * 0.55, -leg, wheel_r * 1.15)]
		if n_wheels == 4:
			_mesh_node(_box(Vector3(0.16, 0.16, wheel_r * 3.0)), strut_mat, pivot, Vector3(0, -leg, 0), "bogie")
		for wp in wheel_positions:
			var wheel := MeshInstance3D.new()
			var tor := CylinderMesh.new()
			tor.top_radius = wheel_r
			tor.bottom_radius = wheel_r
			tor.height = wheel_r * 0.42
			wheel.mesh = tor
			wheel.material_override = tire_mat
			wheel.rotation.z = PI / 2.0
			wheel.position = wp
			pivot.add_child(wheel)
			parts.wheels.append(wheel)

static func _build_heli(cfg: AircraftConfig, root: Node3D, parts: Dictionary, primary: Color, accent: Color, tail_col: Color) -> void:
	var mp := cfg.mesh
	var L := float(mp.get("fuselage_length_m", 12.0))
	var R := float(mp.get("fuselage_radius_m", 1.2))
	var rotor_r := cfg.rotor_main_radius
	var body_mat := _mat(primary, 0.45, 0.3)
	var dark := _mat(Color(0.13, 0.13, 0.15), 0.4, 0.6)

	if cfg.tandem_rotors:
		# Chinook: long box fuselage, front + rear rotors
		_mesh_node(_lathe([Vector2(-L * 0.45, R * 0.2), Vector2(-L * 0.32, R), Vector2(L * 0.35, R), Vector2(L * 0.48, R * 0.55)], 0.95), body_mat, root, Vector3.ZERO, "body")
		_mesh_node(_box(Vector3(R * 1.4, R * 0.8, R * 1.6)), _glass(), root, Vector3(0, R * 0.35, -L * 0.42), "glass")
		_mesh_node(_box(Vector3(R * 1.2, R * 1.1, R * 1.8)), body_mat, root, Vector3(0, R * 1.2, L * 0.38), "pylon")
		for cfg_pos in [Vector3(0, R * 1.15, -L * 0.3), Vector3(0, R * 1.85, L * 0.38)]:
			var mast := _mesh_node(_box(Vector3(0.2, 0.7, 0.2)), dark, root, cfg_pos, "mast")
			var hub := Node3D.new()
			hub.position = Vector3(0, 0.4, 0)
			mast.add_child(hub)
			for b in 3:
				var blade := _mesh_node(_box(Vector3(rotor_r * 0.94, 0.05, 0.34)), dark, hub, Vector3.ZERO, "blade")
				blade.rotation.y = TAU * b / 3.0
				blade.position.y = 0.05
			parts.rotor_main.append(hub)
	else:
		# Conventional: cabin + tail boom + main/tail rotor
		_mesh_node(_lathe([Vector2(-L * 0.32, R * 0.1), Vector2(-L * 0.18, R), Vector2(L * 0.08, R * 0.9), Vector2(L * 0.2, R * 0.4)], 0.95), body_mat, root, Vector3.ZERO, "cabin")
		_mesh_node(_box(Vector3(R * 1.5, R * 0.9, R * 1.1)), _glass(), root, Vector3(0, R * 0.25, -L * 0.24), "glass")
		_mesh_node(_lathe([Vector2(0, R * 0.32), Vector2(L * 0.42, R * 0.12)]), body_mat, root, Vector3(0, R * 0.25, L * 0.12), "boom")
		# Tail fin + stabilizer
		_mesh_node(_box(Vector3(0.06, R * 0.9, R * 0.5)), _mat(tail_col, 0.45, 0.3), root, Vector3(0, R * 0.7, L * 0.52), "fin")
		_mesh_node(_box(Vector3(R * 1.3, 0.05, R * 0.4)), body_mat, root, Vector3(0, R * 0.35, L * 0.42), "hstab")
		# Main rotor
		var mast := _mesh_node(_box(Vector3(0.16, 0.6, 0.16)), dark, root, Vector3(0, R * 0.95, -L * 0.05), "mast")
		var hub := Node3D.new()
		hub.position = Vector3(0, 0.35, 0)
		mast.add_child(hub)
		var n_blades := 4 if cfg.mtow > 4000 else 2
		for b in n_blades:
			var blade := _mesh_node(_box(Vector3(rotor_r * 0.96, 0.05, 0.3)), dark, hub, Vector3.ZERO, "blade")
			blade.rotation.y = TAU * b / n_blades
			blade.rotation.z = 0.02  # coning
		parts.rotor_main.append(hub)
		# Tail rotor (left side)
		var t_hub := Node3D.new()
		t_hub.position = Vector3(-R * 0.25, R * 0.55, L * 0.52)
		root.add_child(t_hub)
		for b in 2:
			var tb := _mesh_node(_box(Vector3(0.04, cfg.rotor_tail_radius * 1.9, 0.12)), dark, t_hub, Vector3.ZERO, "tblade")
			tb.rotation.x = PI * b * 0.5
		parts.rotor_tail.append(t_hub)
		# Accent stripe
		_mesh_node(_box(Vector3(R * 2.02, R * 0.18, L * 0.5)), _mat(accent, 0.4, 0.3), root, Vector3(0, 0, -L * 0.05), "stripe")

	_build_gear(cfg, root, parts, R)

static func _build_lights(cfg: AircraftConfig, root: Node3D, parts: Dictionary) -> void:
	var semi := cfg.wing_span * 0.5
	var red := _small_light(Color(1, 0.1, 0.1))
	var green := _small_light(Color(0.1, 1, 0.2))
	var white := _small_light(Color(1, 1, 1))
	var y := 0.0 if not cfg.is_helicopter() else 0.5
	root.add_child(_light_node(red, Vector3(-semi * 0.96, y, 0)))
	root.add_child(_light_node(green, Vector3(semi * 0.96, y, 0)))
	var tail_light := _light_node(white, Vector3(0, y + 0.2, float(cfg.mesh.get("fuselage_length_m", 10.0)) * 0.5))
	root.add_child(tail_light)
	# Beacon (blinks)
	var beacon := _light_node(_small_light(Color(1, 0.15, 0.1)), Vector3(0, float(cfg.mesh.get("fuselage_radius_m", 1.0)) + (2.0 if cfg.is_helicopter() else 0.3), 0))
	beacon.visible = false
	root.add_child(beacon)
	parts.beacon = beacon
	# Strobes at wingtips
	for side in [-1.0, 1.0]:
		var strobe := _light_node(_small_light(Color(1, 1, 1)), Vector3(side * semi * 0.98, y + 0.1, 0))
		strobe.visible = false
		root.add_child(strobe)
		parts.strobes.append(strobe)
	# Landing light spot (desktop only; toggled by Aircraft)
	if not OS.has_feature("web"):
		var spot := SpotLight3D.new()
		spot.light_energy = 12.0
		spot.spot_range = 220.0
		spot.spot_angle = 18.0
		spot.position = Vector3(0, -0.4, -float(cfg.mesh.get("fuselage_length_m", 10.0)) * 0.42)
		spot.rotation.x = deg_to_rad(-6.0)
		spot.visible = false
		root.add_child(spot)
		parts.landing_lights.append(spot)

static func _small_light(color: Color) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = 0.09
	s.height = 0.18
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = _mat(color, 0.3, 0.0, true)
	return mi

static func _light_node(mi: MeshInstance3D, pos: Vector3) -> MeshInstance3D:
	mi.position = pos
	return mi

# ============================================================ animation API
## deflections: elevator/aileron/rudder in radians, flap/slat/spoiler/gear 0..1
static func animate(parts: Dictionary, s: Dictionary) -> void:
	var elev_angle: float = s.elevator
	for e in parts.elev:
		(e as Node3D).rotation.x = elev_angle
	var a: float = s.aileron
	if parts.ail_l:
		(parts.ail_l as Node3D).rotation.x = -a
	if parts.ail_r:
		(parts.ail_r as Node3D).rotation.x = a
	for r in parts.rud:
		(r as Node3D).rotation.y = s.rudder
	var flap: float = s.flap
	for f in parts.flaps:
		var fp := f as Node3D
		fp.rotation.x = -flap * 0.6
		if fp.has_meta("slide") and fp.has_meta("base_pos"):
			fp.position = (fp.get_meta("base_pos") as Vector3) + (fp.get_meta("slide") as Vector3) * flap
	for sl in parts.slats:
		var sp := sl as Node3D
		sp.rotation.x = s.slat * 0.25
		if sp.has_meta("slide") and sp.has_meta("base_pos"):
			sp.position = (sp.get_meta("base_pos") as Vector3) + (sp.get_meta("slide") as Vector3) * s.slat
	for spo in parts.spoilers:
		(spo as Node3D).rotation.x = s.spoiler * 0.9
	# Gear fold
	var g: float = s.gear
	for key in ["gear_nose", "gear_main_l", "gear_main_r"]:
		var pv = parts.get(key)
		if pv == null:
			continue
		var pivot := pv as Node3D
		var stow: float = (1.0 - g) * PI / 2.0
		if String(pivot.get_meta("stow_axis", "x")) == "x":
			pivot.rotation.x = stow
		else:
			pivot.rotation.z = stow * float(pivot.get_meta("side", 1.0))
		pivot.visible = g > 0.02

static func spin(parts: Dictionary, prop_angle: float, rotor_angle: float, wheel_angle: float, n1: float, ab: bool) -> void:
	for p in parts.prop_roots:
		(p as Node3D).rotation.z = prop_angle * 6.0
	for f in parts.fan_discs:
		(f as Node3D).rotation.y = prop_angle * 4.0
	for r in parts.rotor_main:
		(r as Node3D).rotation.y = rotor_angle * 8.0
	for t in parts.rotor_tail:
		(t as Node3D).rotation.x = rotor_angle * 40.0
	for w in parts.wheels:
		(w as Node3D).rotation.x = wheel_angle
	for gl in parts.ab_glows:
		var g := gl as Node3D
		g.visible = ab
		if ab:
			g.scale = Vector3(1, 1, 0.8 + n1 * 0.7)

static func lights(parts: Dictionary, s: Dictionary) -> void:
	if parts.beacon:
		(parts.beacon as Node3D).visible = s.beacon_on
	for st in parts.strobes:
		(st as Node3D).visible = s.strobe_on
	for ll in parts.landing_lights:
		(ll as Node3D).visible = s.landing_on
