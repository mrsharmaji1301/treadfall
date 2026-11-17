extends Node3D
## An artillery shell on its way: a red ring on the ground that closes in
## as the shell falls, and the shell itself arcing over from the gun.

const Terrain := preload("res://view/terrain.gd")
const Mat := preload("res://view/materials.gd")
const Kit := preload("res://view/mesh_kit.gd")
const Sfx := preload("res://fx/sfx.gd")

const S := 1.0 / 48.0

var source
var _ring: MeshInstance3D
var _shell: MeshInstance3D
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _whistled := false


func setup(barrage) -> void:
	source = barrage
	var x: float = barrage.position.x * S
	var z: float = barrage.position.y * S
	_to = Vector3(x, maxf(Terrain.height(x, z), Terrain.WATER_LEVEL), z)
	var ox: float = barrage.origin.x * S
	var oz: float = barrage.origin.y * S
	_from = Vector3(ox, Terrain.height(ox, oz) + 0.9, oz)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.15, 0.08, 0.9)
	mat.albedo_texture = Mat.ring_texture()
	mat.no_depth_test = true
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	quad.size = Vector2.ONE * (float(barrage.BLAST) * S * 2.3)
	_ring = MeshInstance3D.new()
	_ring.mesh = quad
	_ring.material_override = mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position = _to
	_ring.position = Vector3(0.0, 0.08, 0.0)
	add_child(_ring)
	_shell = Kit.part(self, Kit.cylinder(0.05, 0.3, 8), Mat.glow("barrage", Color(1.0, 0.5, 0.2), 2.5),
		Vector3.ZERO)
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_move(0.0)


func _arc(t: float) -> Vector3:
	var p: Vector3 = _from.lerp(_to, t)
	p.y += sin(t * PI) * (6.0 + _from.distance_to(_to) * 0.25)
	return p


func _move(t: float) -> void:
	var p: Vector3 = _arc(t)
	var ahead: Vector3 = _arc(minf(t + 0.02, 1.0)) - p
	_shell.position = p - _to
	if ahead.length() > 0.001 and absf(ahead.normalized().y) < 0.99:
		# The cylinder's long axis is Y: stand it along the flight path.
		_shell.basis = Basis.looking_at(ahead.normalized(), Vector3.UP) \
			* Basis(Vector3.RIGHT, PI * 0.5)


func _process(_delta: float) -> void:
	if not is_instance_valid(source):
		queue_free()
		return
	var t: float = clampf(source.time / source.FLIGHT, 0.0, 1.0)
	_move(t)
	# The ring tightens and flashes faster as the shell comes down.
	var k: float = lerpf(1.25, 0.8, t)
	_ring.scale = Vector3(k, 1.0, k)
	_ring.transparency = 0.25 + 0.25 * sin(source.time * lerpf(8.0, 30.0, t))
	if t > 0.45 and not _whistled:
		_whistled = true
		Sfx.at(get_parent(), "artillery_incoming", _to + Vector3(0.0, 1.0, 0.0), -4.0)
