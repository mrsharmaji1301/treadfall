extends Node3D
## How a power-up looks in the world: a coin with the item's icon turning
## slowly above the sand, a pulsing circle on the ground showing where to
## drive, and a soft coloured light. It blinks when it is about to expire.

const Terrain := preload("res://view/terrain.gd")
const Mat := preload("res://view/materials.gd")

const S := 1.0 / 48.0

var source
var _coin: Node3D
var _ring: MeshInstance3D
var _time := 0.0


func setup(pickup) -> void:
	source = pickup
	var color: Color = pickup.COLORS.get(pickup.kind, Color.WHITE)
	var x: float = pickup.position.x * S
	var z: float = pickup.position.y * S
	position = Vector3(x, maxf(Terrain.height(x, z), Terrain.WATER_LEVEL), z)

	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
	ring_mat.albedo_texture = Mat.ring_texture()
	var ring_mesh := QuadMesh.new()
	ring_mesh.orientation = PlaneMesh.FACE_Y
	ring_mesh.size = Vector2.ONE * (float(pickup.RADIUS) * S * 2.4)
	_ring = MeshInstance3D.new()
	_ring.mesh = ring_mesh
	_ring.material_override = ring_mat
	_ring.position.y = 0.06
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	_coin = Node3D.new()
	add_child(_coin)
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = color.darkened(0.35)
	rim_mat.metallic = 0.8
	rim_mat.roughness = 0.35
	rim_mat.emission_enabled = true
	rim_mat.emission = color
	rim_mat.emission_energy_multiplier = 0.5
	var disc := CylinderMesh.new()
	disc.top_radius = 0.34
	disc.bottom_radius = 0.34
	disc.height = 0.05
	disc.radial_segments = 28
	var rim := MeshInstance3D.new()
	rim.mesh = disc
	rim.material_override = rim_mat
	rim.rotation.x = PI * 0.5
	_coin.add_child(rim)
	var icon = null
	for ext in ["svg", "png"]:
		var path := "res://assets/ui/icons/%s.%s" % [pickup.kind, ext]
		if icon == null and ResourceLoader.exists(path):
			icon = load(path)
	if icon is Texture2D:
		var face_mat := StandardMaterial3D.new()
		face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		face_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		face_mat.albedo_texture = icon
		var face_mesh := QuadMesh.new()
		face_mesh.size = Vector2(0.56, 0.56)
		for side in [1.0, -1.0]:
			var face := MeshInstance3D.new()
			face.mesh = face_mesh
			face.material_override = face_mat
			face.position.z = 0.03 * side
			face.rotation.y = 0.0 if side > 0.0 else PI
			face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_coin.add_child(face)

	var glow := OmniLight3D.new()
	glow.light_color = color
	glow.light_energy = 0.9
	glow.omni_range = 2.6
	glow.position.y = 0.9
	add_child(glow)


func _process(delta: float) -> void:
	if not is_instance_valid(source):
		queue_free()
		return
	_time += delta
	_coin.position.y = 0.95 + 0.08 * sin(_time * 2.4)
	_coin.rotation.y = _time * 1.8
	var pulse: float = 1.0 + 0.07 * sin(_time * 4.0)
	_ring.scale = Vector3(pulse, 1.0, pulse)
	_ring.rotation.y = _time * 0.5
	# Blink for the last few seconds.
	visible = source.life > 5.0 or fmod(_time, 0.3) < 0.2
