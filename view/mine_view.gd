extends Node3D
## A mine half buried in the sand, with a red lamp that blinks once armed.

const Terrain := preload("res://view/terrain.gd")
const Mat := preload("res://view/materials.gd")
const Kit := preload("res://view/mesh_kit.gd")

const S := 1.0 / 48.0

var source
var _lamp: MeshInstance3D
var _time := 0.0


func setup(mine) -> void:
	source = mine
	var x: float = mine.position.x * S
	var z: float = mine.position.y * S
	position = Vector3(x, Terrain.height(x, z), z)
	Kit.part(self, Kit.cylinder(0.15, 0.06, 14), Mat.steel(), Vector3(0.0, 0.015, 0.0))
	Kit.part(self, Kit.cylinder(0.06, 0.03, 10), Mat.steel(), Vector3(0.0, 0.055, 0.0))
	var bulb := SphereMesh.new()
	bulb.radius = 0.028
	bulb.height = 0.056
	_lamp = Kit.part(self, bulb, Mat.glow("mine_lamp", Color(1.0, 0.1, 0.05), 3.0),
		Vector3(0.0, 0.08, 0.0))
	_lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	if not is_instance_valid(source):
		queue_free()
		return
	_time += delta
	_lamp.visible = source.arm <= 0.0 and fmod(_time, 0.9) < 0.18
