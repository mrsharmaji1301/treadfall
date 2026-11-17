extends RefCounted
## Floating health bar: a small strip that always faces the camera, split
## into one segment per hit point. Colour says whose it is.

const OWN := Color(0.02, 0.4, 0.12)
const ALLY := Color(0.35, 0.95, 0.3)
const ENEMY := Color(0.95, 0.14, 0.1)
const SHIELDED := Color(0.45, 0.6, 0.75)

const SHADER := """shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled;

instance uniform float fill = 1.0;
instance uniform float segments = 4.0;
instance uniform vec3 tint : source_color = vec3(1.0, 0.0, 0.0);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv = UV;
	vec3 col = uv.x < fill ? tint * (0.75 + 0.5 * (1.0 - uv.y)) : vec3(0.07);
	float cut = fract(uv.x * segments);
	if (segments < 30.0 && (cut < 0.05 || cut > 0.95)) {
		col *= 0.25;
	}
	if (uv.x < 0.015 || uv.x > 0.985 || uv.y < 0.14 || uv.y > 0.86) {
		col = vec3(0.0);
	}
	ALBEDO = col;
	ALPHA = 0.95;
}
"""

static var _material: ShaderMaterial
static var _meshes: Dictionary = {}


## A bar `width` wide for something with `hit_points` in full.
static func make(parent: Node3D, color: Color, width: float, hit_points: int,
		height: float) -> MeshInstance3D:
	if _material == null:
		var shader := Shader.new()
		shader.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = shader
		_material.render_priority = 10
	if not _meshes.has(width):
		var quad := QuadMesh.new()
		quad.size = Vector2(width, width * 0.13 + 0.03)
		_meshes[width] = quad
	var bar := MeshInstance3D.new()
	bar.mesh = _meshes[width]
	bar.material_override = _material
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.position = Vector3(0.0, height, 0.0)
	# The bar is drawn facing the camera wherever its owner is turned, so
	# it must never be culled by the owner's own bounds.
	bar.extra_cull_margin = 2.0
	parent.add_child(bar)
	bar.set_instance_shader_parameter("tint", color)
	bar.set_instance_shader_parameter("segments", float(hit_points))
	bar.set_instance_shader_parameter("fill", 1.0)
	return bar


static func update(bar: MeshInstance3D, hp: float, max_hp: float, color: Color) -> void:
	bar.set_instance_shader_parameter("fill", clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0))
	bar.set_instance_shader_parameter("segments", max_hp)
	bar.set_instance_shader_parameter("tint", color)


## The colour for a tank or building of `team`, as the player sees it.
static func color_for(team: int, is_own: bool) -> Color:
	if is_own:
		return OWN
	return ALLY if team == Cfg.TEAM_PLAYER else ENEMY
