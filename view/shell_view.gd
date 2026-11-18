extends Node3D
## A round in flight, made to be seen against bright sand: a glowing core in
## a colour the sand does not have, a long streak behind it, a coloured
## light on the ground under it, and a dark shadow. The player's rounds are
## cyan, enemy rounds are red. Heavy rounds and missiles are bigger and
## trail smoke.

const Mat := preload("res://view/materials.gd")
const Kit := preload("res://view/mesh_kit.gd")
const Terrain := preload("res://view/terrain.gd")
const Fx := preload("res://fx/fx.gd")
const Sfx := preload("res://fx/sfx.gd")

const S := 1.0 / 48.0
const HEIGHT := 0.42

static var _streaks: Dictionary = {}
static var _shadow: QuadMesh

var source
var _blob: MeshInstance3D
var _whoosh: AudioStreamPlayer3D


func setup(shell) -> void:
	source = shell
	var friendly: bool = shell.team == Cfg.TEAM_PLAYER
	var color := Color(0.25, 0.9, 1.0) if friendly else Color(1.0, 0.16, 0.08)
	var key := "f" if friendly else "e"
	var size: float = 1.7 if shell.heavy else 1.0
	var along := Vector3(0.0, 0.0, -PI * 0.5)

	var core := Kit.part(self, Kit.cylinder(0.034, 0.24, 8),
		Mat.glow("round_" + key, color.lerp(Color.WHITE, 0.45), 3.2), Vector3.ZERO, along)
	core.scale = Vector3(size, size, size)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Streak: two crossed cards, so it shows from above and from the side.
	for tilt in [0.0, PI * 0.5]:
		var card := MeshInstance3D.new()
		card.mesh = _streak(key, color)
		card.position = Vector3(-0.7 * size, 0.0, 0.0)
		card.rotation.x = tilt
		card.scale = Vector3(size, 1.0, size)
		card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(card)

	if Cfg.small_lights:
		var lamp := OmniLight3D.new()
		lamp.light_color = color
		lamp.light_energy = 1.6 * size
		lamp.omni_range = 2.4 * size
		add_child(lamp)

	if _shadow == null:
		var dark := StandardMaterial3D.new()
		dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dark.albedo_color = Color(0.05, 0.03, 0.02, 0.55)
		dark.albedo_texture = Fx.puff_texture()
		_shadow = QuadMesh.new()
		_shadow.orientation = PlaneMesh.FACE_Y
		_shadow.size = Vector2(0.6, 0.3)
		_shadow.material = dark
	_blob = MeshInstance3D.new()
	_blob.mesh = _shadow
	_blob.position.y = -HEIGHT + 0.03
	_blob.scale = Vector3(size, 1.0, size)
	_blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_blob)

	if shell.heavy:
		var smoke := Fx.make(Fx.smoke_cfg(18, 0.12, 0.7))
		smoke.local_coords = false
		smoke.position = Vector3(-0.2, 0.0, 0.0)
		add_child(smoke)
		smoke.emitting = true
	# Incoming fire is heard as well as seen.
	if not friendly or shell.heavy:
		_whoosh = Sfx.loop(self, "shell_whoosh", -60.0)
	_follow()


static func _streak(key: String, color: Color) -> QuadMesh:
	if _streaks.has(key):
		return _streaks[key]
	var g := Gradient.new()
	g.set_color(0, Color(color.r, color.g, color.b, 0.0))
	g.set_color(1, Color(color.r, color.g, color.b, 0.95))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.6, 1.6, 1.6, 1.0)
	mat.albedo_texture = tex
	var mesh := QuadMesh.new()
	mesh.orientation = PlaneMesh.FACE_Y
	mesh.size = Vector2(1.4, 0.11)
	mesh.material = mat
	_streaks[key] = mesh
	return mesh


func _process(_delta: float) -> void:
	if not is_instance_valid(source) or source.is_queued_for_deletion():
		queue_free()
		return
	_follow()


func _follow() -> void:
	var p: Vector2 = source.global_position
	position = Vector3(p.x * S, Terrain.height(p.x * S, p.y * S) + HEIGHT, p.y * S)
	rotation.y = -float(source.velocity.angle())
	if _whoosh != null:
		_whoosh.volume_db = -6.0 + Sfx.fall(position)
