extends Control
## A small 3D stage with the player's chosen tank turning slowly on it.
## Used behind the main menu and on the Customize page. It has its own
## little world, so it needs no map. Call refresh() after a choice changes.

const TankModel := preload("res://view/tank_model.gd")
const Tank := preload("res://entities/tank.gd")

## Turns per second of the turntable.
var spin := 0.07
var _vp: SubViewport
var _pivot: Node3D
var _model
var _stand
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	# Drawn at the real screen resolution, not at the 1280 x 720 layout
	# size, so the tank is sharp on a Full HD or bigger screen. The browser
	# draws it at layout size with plain edges, which costs far less.
	var web: bool = OS.has_feature("web")
	_vp.msaa_3d = Viewport.MSAA_DISABLED if web else Viewport.MSAA_4X
	var sharp: float = 1.0 if web else clampf(float(DisplayServer.window_get_size().y) / 720.0, 1.0, 3.0)
	_vp.size = Vector2i(size * sharp)
	add_child(_vp)
	var picture := TextureRect.new()
	picture.texture = _vp.get_texture()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.size = size
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.72, 0.68)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -40.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 8.0
	if web:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, 140.0, 0.0)
	fill.light_color = Color(0.85, 0.88, 1.0)
	fill.light_energy = 0.45
	_vp.add_child(fill)
	# The turntable: a dark steel disc.
	var disc := CylinderMesh.new()
	disc.top_radius = 0.95
	disc.bottom_radius = 1.0
	disc.height = 0.05
	disc.radial_segments = 48
	var plate := StandardMaterial3D.new()
	plate.albedo_color = Color(0.13, 0.125, 0.115)
	plate.roughness = 0.6
	plate.metallic = 0.5
	var table := MeshInstance3D.new()
	table.mesh = disc
	table.material_override = plate
	table.position.y = -0.025
	_vp.add_child(table)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(2.3, 1.35, 2.6)
	_vp.add_child(cam)
	cam.look_at(Vector3(0.0, 0.26, 0.0), Vector3.UP)
	cam.current = true
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	refresh()


## Builds the tank again from the player's choices in Cfg.
func refresh() -> void:
	_clear()
	_stand = Tank.new()
	_stand.display = true
	Cfg.fit_player(_stand, 4)
	_model = TankModel.new()
	_model.setup(_stand)
	_model.show_only()
	_pivot.add_child(_model)


func _clear() -> void:
	if is_instance_valid(_model):
		_model.queue_free()
	if is_instance_valid(_stand):
		_stand.free()
	_model = null
	_stand = null


func _exit_tree() -> void:
	_clear()


func _process(delta: float) -> void:
	_time += delta
	_pivot.rotation.y += delta * spin * TAU
	if is_instance_valid(_model):
		# The turret looks about a little, so the tank feels alive.
		_model.aim_show(0.5 * sin(_time * 0.6))
