extends SceneTree
## Scan every generated aircraft mesh + node transform for NaN/inf values
## that would corrupt the rendering scene AABB (and thus the shadow camera).

func _init() -> void:
	for id in AircraftDB.ids():
		var cfg := AircraftDB.config(id)
		var built: Dictionary = AircraftMeshBuilder.build(cfg)
		_scan(built.root, id, built.root)
		built.root.free()
	print("NAN SCAN DONE")
	quit(0)

func _scan(node: Node, id: String, root: Node) -> void:
	if node is Node3D:
		var t := (node as Node3D).transform
		for col in [t.basis.x, t.basis.y, t.basis.z, t.origin]:
			var v := col as Vector3
			if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)):
				print("BAD TRANSFORM %s: %s -> %s" % [id, root.get_path_to(node), str(t)])
				break
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh and mesh is ArrayMesh:
			var am := mesh as ArrayMesh
			for s in am.get_surface_count():
				var arrays := am.surface_get_arrays(s)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var norms = arrays[Mesh.ARRAY_NORMAL]
				var bad_v := 0
				var bad_n := 0
				for v in verts:
					if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)):
						bad_v += 1
				if norms != null:
					for n in (norms as PackedVector3Array):
						if not (is_finite(n.x) and is_finite(n.y) and is_finite(n.z)):
							bad_n += 1
				if bad_v > 0 or bad_n > 0:
					print("BAD MESH %s node=%s surface=%d bad_verts=%d bad_normals=%d of %d" % [id, node.name, s, bad_v, bad_n, verts.size()])
		var aabb := (node as MeshInstance3D).get_aabb()
		if not (is_finite(aabb.position.x) and is_finite(aabb.size.x) and is_finite(aabb.size.y) and is_finite(aabb.size.z)):
			print("BAD AABB %s node=%s aabb=%s" % [id, node.name, str(aabb)])
	for child in node.get_children():
		_scan(child, id, root)
