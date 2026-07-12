extends Node
## Platform quality tiers. Desktop = high fidelity, Web = reduced fidelity.
## Flight physics are IDENTICAL on every tier - only rendering differs.

var is_web: bool = false
var tier: String = "desktop"

# Rendering knobs consumed by World / Terrain / builders.
var terrain_view_chunks: int = 7          # ring radius of visible terrain chunks
var terrain_chunk_verts: int = 48         # vertices per chunk edge
var far_clip: float = 45000.0
var shadows_enabled: bool = true
var ssao_enabled: bool = true
var glow_enabled: bool = true
var fog_volumetric: bool = false
var scaling_3d: float = 1.0
var max_ai_traffic: int = 4
var landing_lights: bool = true
var high_detail_meshes: bool = true

func _ready() -> void:
	is_web = OS.has_feature("web")
	if is_web:
		tier = "web"
		terrain_view_chunks = 4
		terrain_chunk_verts = 24
		far_clip = 22000.0
		ssao_enabled = false
		glow_enabled = false
		scaling_3d = 1.0
		max_ai_traffic = 2
		landing_lights = false
		high_detail_meshes = false
	else:
		tier = "desktop"

## Apply tier settings to an Environment + Camera. Called by World on load.
func apply_environment(env: Environment, cam: Camera3D) -> void:
	cam.far = far_clip
	cam.near = 0.25
	if ssao_enabled and not is_web:
		env.ssao_enabled = true
		env.ssao_intensity = 1.5
	if glow_enabled and not is_web:
		env.glow_enabled = true
		env.glow_intensity = 0.4
		env.glow_bloom = 0.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if not is_web:
		env.adjustment_enabled = false

func apply_viewport(vp: Viewport) -> void:
	vp.scaling_3d_scale = scaling_3d
	if not is_web:
		vp.msaa_3d = Viewport.MSAA_4X
	else:
		vp.msaa_3d = Viewport.MSAA_DISABLED

func sun_shadow(sun: DirectionalLight3D) -> void:
	sun.shadow_enabled = shadows_enabled
	if is_web:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 400.0
	else:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = 1200.0
		sun.directional_shadow_blend_splits = true
