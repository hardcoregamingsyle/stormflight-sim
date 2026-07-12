extends SceneTree
## Windowed lighting bisection: renders a red box + grey floor under the same
## environment recipe WorldRoot uses, toggling one variable per snapshot.
## Run: godot --script tools/light_test.gd

var stage := 0
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var box: MeshInstance3D

func _init() -> void:
	var vroot := Node3D.new()
	root.add_child.call_deferred(vroot)

	cam = Camera3D.new()
	cam.position = Vector3(4, 3, 6)
	vroot.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3.ZERO)
	cam.far = 45000.0
	cam.near = 0.25

	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.785, deg_to_rad(35.0), 0)
	sun.light_energy = 1.13
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 1200.0
	sun.directional_shadow_blend_splits = true
	vroot.add_child(sun)

	env = Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	sky.sky_material = mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.83
	env.fog_enabled = true
	env.fog_density = 1.0 / 40000.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vroot.add_child(we)

	box = MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.9, 0.2, 0.2)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	box.material_override = bm
	vroot.add_child(box)

	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_mi.mesh = pm
	floor_mi.position.y = -0.6
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.5, 0.5, 0.55)
	floor_mi.material_override = fm
	vroot.add_child(floor_mi)

	_run.call_deferred()

func _run() -> void:
	var dir := "C:/Users/Nitish/Desktop/stormflight-sim/docs/shots"
	await create_timer(1.0).timeout
	await _snap(dir + "/lt_a_baseline.png")
	sun.shadow_enabled = false
	await _snap(dir + "/lt_b_noshadow.png")
	sun.shadow_enabled = true
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	await _snap(dir + "/lt_c_colorambient.png")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	sun.rotation = Vector3(-PI / 2.0, 0, 0)
	await _snap(dir + "/lt_d_sunstraightdown.png")
	print("LIGHTTEST DONE")
	quit(0)

func _snap(path: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("SNAP %s" % path)
