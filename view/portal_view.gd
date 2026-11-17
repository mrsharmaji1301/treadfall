extends Node3D
## How a portal gate looks: a steel ring standing on a concrete plinth,
## facing the camera. By day it is cold and shut, a faint shimmer in it.
## At night it opens: a swirling disc of light, glowing runes, a glow on
## the sand around it. A tank going through flashes at both gates.

const Terrain := preload("res://view/terrain.gd")
const Mat := preload("res://view/materials.gd")
const Kit := preload("res://view/mesh_kit.gd")
const S := 1.0 / 48.0

const SWIRL := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float open = 0.0;
uniform vec4 tint : source_color = vec4(0.55, 0.3, 1.0, 1.0);
uniform vec4 tint2 : source_color = vec4(0.2, 0.85, 1.0, 1.0);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float sw = sin(a * 3.0 + r * 9.0 - TIME * 4.0) * 0.5 + 0.5;
	float sw2 = sin(a * 5.0 - r * 14.0 + TIME * 2.5) * 0.5 + 0.5;
	float disc = smoothstep(1.0, 0.82, r);
	float core = smoothstep(0.55, 0.0, r);
	vec3 c = mix(tint.rgb, tint2.rgb, sw2) * (0.35 + sw * 0.9) + vec3(core * 0.9);
	ALBEDO = c * disc * open * 1.5;
}
"""

static var _swirl: ShaderMaterial
static var _rune: StandardMaterial3D
static var _glow: StandardMaterial3D

var source
var _light: OmniLight3D
var _ring: Node3D


func setup(portal) -> void:
	source = portal
	var x: float = portal.position.x * S
	var z: float = portal.position.y * S
	position = Vector3(x, Terrain.height(x, z), z)
	if _swirl == null:
		_swirl = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SWIRL
		_swirl.shader = sh
		_rune = StandardMaterial3D.new()
		_rune.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_rune.albedo_color = Color(0.2, 0.15, 0.3)
		_glow = StandardMaterial3D.new()
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_glow.albedo_texture = Mat.ring_texture()
		_glow.albedo_color = Color(0.5, 0.3, 1.0, 0.0)
	# Plinth and two feet holding the ring.
	var bins := {}
	Kit.add(bins, Mat.concrete(), Kit.box(Vector3(1.5, 0.14, 0.62)), Vector3(0.0, 0.05, 0.0))
	Kit.add(bins, Mat.concrete(), Kit.box(Vector3(1.2, 0.08, 0.5)), Vector3(0.0, 0.15, 0.0))
	for side in [-1.0, 1.0]:
		Kit.add(bins, Mat.steel(), Kit.box(Vector3(0.16, 0.42, 0.22)), Vector3(0.6 * side, 0.36, 0.0))
		Kit.add(bins, Mat.steel(), Kit.box(Vector3(0.24, 0.08, 0.3)), Vector3(0.6 * side, 0.2, 0.0))
	Kit.flush(bins, self)
	# The ring leans back a little towards the camera.
	_ring = Node3D.new()
	_ring.position = Vector3(0.0, 0.86, 0.0)
	_ring.rotation.x = -0.28
	add_child(_ring)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.56
	torus.outer_radius = 0.7
	torus.rings = 40
	torus.ring_segments = 10
	var hoop := MeshInstance3D.new()
	hoop.mesh = torus
	hoop.material_override = Mat.steel()
	hoop.rotation.x = PI * 0.5
	_ring.add_child(hoop)
	# Runes round the ring: little plates that light up at night.
	for i in 10:
		var a: float = TAU * i / 10.0
		var plate := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.09, 0.09, 0.16)
		plate.mesh = b
		plate.material_override = _rune
		plate.position = Vector3(cos(a) * 0.63, sin(a) * 0.63, 0.0)
		plate.rotation.z = a
		_ring.add_child(plate)
	var disc := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.16, 1.16)
	disc.mesh = q
	disc.material_override = _swirl
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.add_child(disc)
	var pad := MeshInstance3D.new()
	var flat := QuadMesh.new()
	flat.orientation = PlaneMesh.FACE_Y
	flat.size = Vector2(2.6, 2.6)
	pad.mesh = flat
	pad.material_override = _glow
	pad.position.y = 0.07
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pad)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.55, 0.4, 1.0)
	_light.omni_range = 4.0
	_light.position = Vector3(0.0, 0.9, 0.5)
	_light.light_energy = 0.0
	add_child(_light)
	portal.used.connect(_on_used)


## All gates share their materials, so one call per frame sets them all.
static func shine(open: float) -> void:
	if _swirl == null:
		return
	_swirl.set_shader_parameter("open", maxf(open, 0.07))
	_rune.albedo_color = Color(0.2, 0.15, 0.3).lerp(Color(1.6, 1.1, 3.0), open)
	_glow.albedo_color = Color(0.5, 0.3, 1.0, 0.75 * open)


func _process(_delta: float) -> void:
	if not is_instance_valid(source):
		queue_free()
		return
	_light.light_energy = 2.4 * GameState.night
	_light.visible = GameState.night > 0.02


func _on_used(_tank, from: Vector2, to: Vector2) -> void:
	var view = get_parent()
	for at in [from, to]:
		var p: Vector3 = view.spot(at) + Vector3(0.0, 0.6, 0.0)
		var flash = load("res://fx/fx.gd").sprite(view, "fx_shockwave", p, 0.6, true)
		if flash == null:
			continue
		flash.material_override.albedo_color = Color(0.7, 0.5, 1.0, 1.0)
		var tw: Tween = flash.create_tween()
		tw.set_parallel(true)
		tw.tween_property(flash, "scale", Vector3.ONE * 3.2, 0.5)
		tw.tween_property(flash.material_override, "albedo_color:a", 0.0, 0.5)
		tw.chain().tween_callback(flash.queue_free)
