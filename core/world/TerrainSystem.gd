class_name TerrainSystem
extends Node3D
## Deterministic procedural terrain: an archipelago-continent with western
## mountains, northern snowfields, southeastern desert and scattered islands.
## Streams LOD-ringed chunks around the player with heightmap collision near
## the aircraft. All coordinates ABSOLUTE world meters; this node is parented
## under WorldRoot.static_root which handles the floating origin.

const CHUNK := 2048.0
const COLLISION_RINGS := 2

var continent := FastNoiseLite.new()
var mountains := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var _chunks: Dictionary = {}          # Vector2i -> Node3D
var _airport_flats: Array = []        # {x, z, elev, r0, r1}
var _grass_mat: StandardMaterial3D
var _water: MeshInstance3D

func _init() -> void:
	var s := Game.WORLD_SEED
	continent.seed = s
	continent.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	continent.frequency = 1.0 / 52000.0
	continent.fractal_octaves = 4
	mountains.seed = s + 7
	mountains.noise_type = FastNoiseLite.TYPE_SIMPLEX
	mountains.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	mountains.frequency = 1.0 / 9000.0
	mountains.fractal_octaves = 3
	detail.seed = s + 13
	detail.frequency = 1.0 / 900.0
	detail.fractal_octaves = 2

	for id in AirportsDB.ids():
		var a: Dictionary = AirportsDB.get_airport(id)
		var p := AirportsDB.position_m(id)
		var max_len := 0.0
		for rw in a.runways:
			max_len = maxf(max_len, rw.length)
		_airport_flats.append({
			"x": p.x, "z": p.z, "elev": a.elevation_m,
			"r0": max_len * 0.75 + 600.0, "r1": max_len * 0.75 + 3200.0,
		})

func _ready() -> void:
	_grass_mat = StandardMaterial3D.new()
	_grass_mat.vertex_color_use_as_albedo = true
	_grass_mat.roughness = 0.95
	_grass_mat.metallic = 0.0
	# Water plane (follows camera in world; huge)
	_water = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(Quality.far_clip * 2.6, Quality.far_clip * 2.6)
	_water.mesh = pm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.09, 0.26, 0.38, 0.92)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.08
	wm.metallic = 0.5
	if not Quality.is_web:
		var ntex := NoiseTexture2D.new()
		var wn := FastNoiseLite.new()
		wn.frequency = 0.06
		ntex.noise = wn
		ntex.as_normal_map = true
		ntex.seamless = true
		wm.normal_texture = ntex
		wm.normal_scale = 0.4
		wm.uv1_scale = Vector3(60, 60, 60)
	_water.material_override = wm
	_water.position.y = 0.0
	# A 100+ km caster wrecks directional shadow depth precision
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)
	# Water needs collision so belly-landings in the sea register
	var wb := StaticBody3D.new()
	wb.add_to_group("water")
	var wc := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(Quality.far_clip * 2.6, 2.0, Quality.far_clip * 2.6)
	wc.shape = wbox
	wc.position.y = -1.05
	wb.add_child(wc)
	_water.add_child(wb)

# ------------------------------------------------------------------ height
## Single source of truth for terrain elevation at absolute world (x, z).
func height(x: float, z: float) -> float:
	var base := continent.get_noise_2d(x, z)
	var land := smoothstep(-0.02, 0.3, base)
	var h := -38.0 + land * 105.0
	# Western mountain belt
	var mfac := clampf((-x - 55000.0) / 70000.0, 0.0, 1.0) * land
	if mfac > 0.001:
		var m := mountains.get_noise_2d(x, z)
		h += maxf(m, 0.0) * m * 1900.0 * mfac
	# Southeastern desert flattening
	var dfac := clampf((x - 90000.0) / 90000.0, 0.0, 1.0) * clampf((z * -1.0 - 60000.0) / 80000.0, 0.0, 1.0)
	h = lerpf(h, maxf(h * 0.55, 200.0 * clampf(land * 2.0, 0.0, 1.0)), dfac * 0.7)
	h += detail.get_noise_2d(x, z) * 14.0 * land
	# Airport flattening
	for f in _airport_flats:
		var d := Vector2(x - f.x, z - f.z).length()
		if d < f.r1:
			var t: float = smoothstep(f.r0, f.r1, d)
			h = lerpf(f.elev, h, t)
	return h

## Biome color for a vertex (snow north / desert SE / grass / rock / sand)
func _color(x: float, z: float, h: float, slope: float) -> Color:
	if h < 1.5:
		return Color(0.76, 0.7, 0.52)  # beach
	var snow := clampf((z - 130000.0) / 50000.0, 0.0, 1.0) + clampf((h - 1300.0) / 500.0, 0.0, 1.0)
	var desert := clampf((x - 90000.0) / 90000.0, 0.0, 1.0) * clampf((-z - 60000.0) / 80000.0, 0.0, 1.0)
	var c := Color(0.24, 0.42, 0.2)   # grass
	c = c.lerp(Color(0.68, 0.58, 0.38), clampf(desert * 1.4, 0.0, 1.0))
	if slope > 0.55:
		c = c.lerp(Color(0.42, 0.4, 0.38), clampf((slope - 0.55) * 3.0, 0.0, 1.0))
	c = c.lerp(Color(0.92, 0.93, 0.97), clampf(snow, 0.0, 1.0))
	# subtle variation
	c = c.darkened(absf(detail.get_noise_2d(x * 0.5, z * 0.5)) * 0.15)
	return c

# ------------------------------------------------------------------ streaming
## Called by WorldRoot every ~0.5 s with the player's ABSOLUTE position.
func update_streaming(abs_pos: Vector3) -> void:
	var cx := int(floor(abs_pos.x / CHUNK))
	var cz := int(floor(abs_pos.z / CHUNK))
	var rings := Quality.terrain_view_chunks
	var wanted: Dictionary = {}
	for dz in range(-rings, rings + 1):
		for dx in range(-rings, rings + 1):
			var ring := maxi(absi(dx), absi(dz))
			if ring > rings:
				continue
			var key := Vector2i(cx + dx, cz + dz)
			wanted[key] = ring
	# Remove far chunks
	for key in _chunks.keys():
		if not wanted.has(key):
			_chunks[key].queue_free()
			_chunks.erase(key)
	# Add missing, CLOSEST RINGS FIRST. Near rings (collision zone) always
	# build immediately - the aircraft must never outrun its own collision.
	var keys: Array = wanted.keys()
	keys.sort_custom(func(a, b): return wanted[a] < wanted[b])
	var added := 0
	for key in keys:
		var ring: int = wanted[key]
		if _chunks.has(key):
			var has_col: bool = _chunks[key].get_meta("has_collision", false)
			if ring <= COLLISION_RINGS and not has_col:
				_add_collision(_chunks[key], key)
			continue
		# Collision-zone chunks build synchronously (the aircraft must never
		# outrun its own collision); everything further is budgeted per call.
		if ring > COLLISION_RINGS and added >= 4:
			continue
		_build_chunk(key, ring)
		added += 1
	# Keep water centered on the player
	_water.position.x = abs_pos.x
	_water.position.z = abs_pos.z

func _build_chunk(key: Vector2i, ring: int) -> void:
	var res := Quality.terrain_chunk_verts
	if ring > 2:
		res = maxi(res / 2, 12)
	if ring > 4:
		res = maxi(res / 4, 8)
	var ox := key.x * CHUNK
	var oz := key.y * CHUNK
	var step := CHUNK / res
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights: Array = []
	for iz in res + 1:
		var row: Array = []
		for ix in res + 1:
			row.append(height(ox + ix * step, oz + iz * step))
		heights.append(row)
	for iz in res:
		for ix in res:
			var x0 := ox + ix * step
			var z0 := oz + iz * step
			var h00: float = heights[iz][ix]
			var h10: float = heights[iz][ix + 1]
			var h01: float = heights[iz + 1][ix]
			var h11: float = heights[iz + 1][ix + 1]
			var v00 := Vector3(x0, h00, z0)
			var v10 := Vector3(x0 + step, h10, z0)
			var v01 := Vector3(x0, h01, z0 + step)
			var v11 := Vector3(x0 + step, h11, z0 + step)
			var slope: float = (absf(h00 - h11) + absf(h10 - h01)) / (step * 1.4)
			var c := _color(x0, z0, (h00 + h11) * 0.5, slope)
			st.set_color(c)
			st.add_vertex(v00); st.add_vertex(v01); st.add_vertex(v10)
			st.add_vertex(v10); st.add_vertex(v01); st.add_vertex(v11)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _grass_mat
	# Only nearby chunks cast: the shadow radius is ~1.2 km, and distant
	# mountain casters just destroy shadow-map depth precision.
	if ring > 1:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.set_meta("has_collision", false)
	_chunks[key] = mi
	if ring <= COLLISION_RINGS:
		_add_collision(mi, key)

func _add_collision(chunk: Node3D, key: Vector2i) -> void:
	# Trimesh collision built from the same analytic height function the
	# visuals use - reliable across platforms (heightmap shapes misbehave
	# when scaled).
	var res := 24
	var step := CHUNK / res
	var ox := key.x * CHUNK
	var oz := key.y * CHUNK
	var heights: Array = []
	for iz in res + 1:
		var row: PackedFloat32Array = []
		for ix in res + 1:
			row.append(height(ox + ix * step, oz + iz * step))
		heights.append(row)
	var faces := PackedVector3Array()
	for iz in res:
		for ix in res:
			var x0 := ox + ix * step
			var z0 := oz + iz * step
			var v00 := Vector3(x0, heights[iz][ix], z0)
			var v10 := Vector3(x0 + step, heights[iz][ix + 1], z0)
			var v01 := Vector3(x0, heights[iz + 1][ix], z0 + step)
			var v11 := Vector3(x0 + step, heights[iz + 1][ix + 1], z0 + step)
			faces.append(v00); faces.append(v01); faces.append(v10)
			faces.append(v10); faces.append(v01); faces.append(v11)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var body := StaticBody3D.new()
	body.add_to_group("terrain")
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	chunk.add_child(body)
	chunk.set_meta("has_collision", true)
