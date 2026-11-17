extends Node3D
## The 3D desert scene: sky, sun with soft shadows, dune terrain, walls,
## rocks, trees, track marks. The game logic runs on a hidden 2D grid; this
## node shows it in 3D. 48 px in the game = 1 unit here, and game (x, y)
## maps to 3D (x, height, z).

const Sfx := preload("res://fx/sfx.gd")
const Mat := preload("res://view/materials.gd")
const Kit := preload("res://view/mesh_kit.gd")
const Terrain := preload("res://view/terrain.gd")
const TankModel := preload("res://view/tank_model.gd")
const ShellView := preload("res://view/shell_view.gd")
const CoreView := preload("res://view/core_view.gd")
const PickupView := preload("res://view/pickup_view.gd")
const MineView := preload("res://view/mine_view.gd")
const StructureView := preload("res://view/structure_view.gd")
const BarrageView := preload("res://view/barrage_view.gd")
const Fx := preload("res://fx/fx.gd")
const PortalView := preload("res://view/portal_view.gd")

const S := 1.0 / 48.0
const WALL_H := 0.7
const MAX_MARKS := 4000
## Size of one tile of ground cover, in map cells.
const TILE := 16.0
## Track prints stay fresh for MARK_HOLD seconds, then fade over MARK_FADE.
const MARK_HOLD := 5.0
const MARK_FADE := 9.0
const FROND := "res://assets/nature/palm_frond_green.png"
const FROND_DRY := "res://assets/nature/palm_frond_dry.png"
const FROND_YOUNG := "res://assets/nature/palm_frond_young.png"

var camera: Camera3D
var sun: DirectionalLight3D
var env: Environment
var _arena
var _walls: Dictionary = {}
var _rocks: Array[ArrayMesh] = []
var _shake := 0.0
var _follow = null
## The player's tank. The map camera centres on it too.
var _tank = null
var _zoom_follow := 1.0
var _zoom_arena := 1.0
var _scorch: QuadMesh
var _crater: QuadMesh
var _holes: Array = []
var _wave: QuadMesh
var _marks: MultiMesh
var _probe_time := 0.0
## THE SHIFT: how dark the scene was last set up, the sky's material, and
## the dark veil that hides what lies beyond a tank's eyes at night.
var _night_shown := -1.0
var _sky_mat: Material
var _veil: ColorRect
const VEIL := """
shader_type canvas_item;
uniform vec2 centre = vec2(640.0, 360.0);
uniform float radius = 200.0;
uniform float amount = 0.0;
void fragment() {
	vec2 p = UV * vec2(1280.0, 720.0);
	float d = length(p - centre);
	float a = smoothstep(radius * 0.7, radius * 1.3, d);
	COLOR = vec4(0.01, 0.015, 0.04, a * amount);
}
"""
var _probe_frames: int = 0
var _mark_count: int = 0
var _mark_born := PackedFloat32Array()
var _mark_cursor: int = 0
var _clock := 0.0
var _palms: Array = []
## Cut-out plants, one entry per sheet: {"xf": [], "col": colours, "cell":
## which of the 4 plants on the sheet}.
var _plants: Dictionary = {}
var _ring: QuadMesh
var _debris: Array = []
## Where every palm goes, one list per palm shape.
var _palm_xf: Array = []
## Top of each palm shape's trunk, and where date bunches hang.
var _palm_top: Array = []
var _date_xf: Array = []
## Fallen logs and stumps on the grove floor, joined per material.
var _floor_bins: Dictionary = {}
## Bush shapes, and where every bush and pebble goes (one list per shape).
var _shrubs: Array[ArrayMesh] = []
var _shrub_xf: Array = []
var _pebble_xf: Array = []
## Low-detail rocks for pebbles: there are thousands of them.
var _stones: Array[ArrayMesh] = []
## The player's ears. They sit at the followed tank, so how loud and how
## muffled a sound is depends on its distance from your tank, not the camera.
var _ears: AudioListener3D


func _ready() -> void:
	add_to_group("world_view")


func build(arena) -> void:
	_arena = arena
	Terrain.setup(arena)
	for i in 5:
		_rocks.append(Kit.rock(100 + i))
	_make_palms()
	var bush_rng := RandomNumberGenerator.new()
	bush_rng.seed = 909
	for i in 3:
		_shrubs.append(Kit.palm_crown(Vector3(0.0, 0.04, 0.0), bush_rng, 9 + i * 2,
			0.55 + 0.08 * i, 0.15 + 0.3 * i))
		_shrub_xf.append([])
	for i in 4:
		_stones.append(Kit.rock(300 + i, 8))
		_pebble_xf.append([])
	_build_light()
	_build_camera()
	_build_ground()
	_build_walls()
	_build_grass()
	_build_marks()
	arena.tile_damaged.connect(_on_tile_damaged)
	arena.tile_destroyed.connect(_on_tile_destroyed)
	apply_quality()


func ground(x: float, z: float) -> float:
	return Terrain.height(x, z)


func _build_light() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.42, 0.72)
	sky_mat.sky_horizon_color = Color(0.82, 0.76, 0.64)
	sky_mat.ground_horizon_color = Color(0.82, 0.76, 0.64)
	sky_mat.ground_bottom_color = Color(0.5, 0.42, 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	# The photographed sky, if it is there: real clouds and softer light.
	if ResourceLoader.exists("res://assets/sky/sky_day.hdr"):
		var photo = load("res://assets/sky/sky_day.hdr")
		if photo is Texture2D:
			var pano := PanoramaSkyMaterial.new()
			pano.panorama = photo
			pano.energy_multiplier = 0.8
			sky.sky_material = pano

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.tonemap_exposure = 0.8
	# Grading: a little more contrast and less colour than the raw render,
	# so it reads as sun-bleached desert and not as a toy.
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.84
	# Contact shadows where things meet the ground and each other.
	env.ssao_radius = 1.2
	env.ssao_intensity = 3.0
	env.ssao_power = 1.6
	env.ssao_light_affect = 0.25
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 1.3
	# Heat haze towards the horizon.
	env.fog_enabled = true
	env.fog_light_color = Color(0.86, 0.79, 0.66)
	env.fog_density = 0.006
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.4
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_albedo = Color(0.9, 0.82, 0.68)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_sky_mat = sky.sky_material

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -40.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 1.8
	sun.light_angular_distance = 0.6  # soft shadow edges
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_enabled = true
	add_child(sun)


## THE SHIFT: turns the light from day to night by `n` (0 day, 1 night).
## Moonlight is cold and dim, the fog closes in dark blue, the gates and
## tank lamps glow. Only redone when the darkness has changed.
func _night_look(n: float) -> void:
	_veil_follow(n)
	if absf(n - _night_shown) < 0.004:
		return
	_night_shown = n
	sun.light_energy = lerpf(1.8, 0.32, n)
	sun.light_color = Color(1.0, 0.93, 0.8).lerp(Color(0.55, 0.66, 1.0), n)
	env.ambient_light_energy = lerpf(0.42, 0.2, n)
	env.tonemap_exposure = lerpf(0.8, 1.0, n)
	env.adjustment_saturation = lerpf(0.84, 0.6, n)
	env.fog_light_color = Color(0.86, 0.79, 0.66).lerp(Color(0.08, 0.1, 0.17), n)
	env.volumetric_fog_albedo = Color(0.9, 0.82, 0.68).lerp(Color(0.2, 0.25, 0.4), n)
	env.glow_hdr_threshold = lerpf(1.3, 0.8, n)
	if _sky_mat is PanoramaSkyMaterial:
		_sky_mat.energy_multiplier = lerpf(0.8, 0.07, n)
	elif _sky_mat is ProceduralSkyMaterial:
		_sky_mat.energy_multiplier = lerpf(1.0, 0.08, n)
	PortalView.shine(n)
	TankModel.night_lamps(n)


## The dark veil follows the player's tank: open round it, black beyond
## what its crew can see at night.
func _veil_follow(n: float) -> void:
	if _veil == null:
		var layer := CanvasLayer.new()
		layer.layer = 0
		add_child(layer)
		_veil = ColorRect.new()
		_veil.size = Vector2(1280, 720)
		_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = VEIL
		mat.shader = sh
		_veil.material = mat
		layer.add_child(_veil)
	var who = _tank if _tank != null and is_instance_valid(_tank) and _tank.alive else null
	_veil.visible = n > 0.01 and who != null
	if not _veil.visible:
		return
	var at: Vector3 = spot(who.global_position)
	var edge: Vector3 = at + camera.global_transform.basis.x * Cfg.NIGHT_VISION * S
	var c: Vector2 = camera.unproject_position(at)
	var r: float = c.distance_to(camera.unproject_position(edge))
	_veil.material.set_shader_parameter("centre", c)
	_veil.material.set_shader_parameter("radius", r)
	_veil.material.set_shader_parameter("amount", 0.84 * n)


## Graphics options from the settings page (Cfg.gfx).
func apply_quality() -> void:
	var g: Dictionary = Cfg.gfx
	var sh: int = int(g["shadows"])
	sun.shadow_enabled = sh > 0
	RenderingServer.directional_shadow_atlas_set_size([1024, 1024, 2048, 4096, 8192][sh], true)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if sh <= 1 \
		else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = sh >= 3
	env.ssao_enabled = bool(g["ssao"])
	env.glow_enabled = bool(g["glow"])
	env.volumetric_fog_enabled = bool(g["fog"])
	env.sdfgi_enabled = bool(g["gi"])


## First battle after the automatic graphics pick: measure the frame rate
## for a few seconds and step one level down while it is too low.
func _probe(delta: float) -> void:
	_probe_time += delta
	if _probe_time < 2.5:
		return
	_probe_frames += 1
	if _probe_time < 6.0:
		return
	var fps: float = _probe_frames / (_probe_time - 2.5)
	_probe_time = 0.0
	_probe_frames = 0
	if fps >= 40.0:
		Cfg.gfx_probe = false
	elif Cfg.quality > 0 and Cfg.quality < 4:
		Cfg.set_preset(Cfg.quality - 1)
		Cfg.apply_graphics()
	elif int(Cfg.gfx["scale"]) > 50 or int(Cfg.gfx["shadows"]) > 0:
		# Already on LOW: thin the picture out further, then stop.
		Cfg.quality = 4
		Cfg.gfx["scale"] = 50
		Cfg.gfx["shadows"] = 0
		Cfg.apply_graphics()
	else:
		Cfg.gfx_probe = false
	Cfg.save_settings()


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 35.0
	camera.near = 0.5
	camera.far = 300.0
	add_child(camera)
	camera.current = true
	_frame_arena()


func _frame_arena() -> void:
	var target := Vector3(Cfg.cols * 0.5, 0.0, Cfg.rows * 0.6)
	var elevation := deg_to_rad(62.0)
	var dist: float = maxf(Cfg.cols * 1.14, Cfg.rows * 1.8) * _zoom_arena
	camera.position = target + Vector3(0.0, sin(elevation), cos(elevation)) * dist
	camera.look_at(target, Vector3.UP)
	sun.directional_shadow_max_distance = minf(dist * 1.7, 130.0)
	env.fog_density = 0.0005
	env.fog_aerial_perspective = 0.0
	env.volumetric_fog_density = 0.0


## Close-up camera that follows a 2D game node. Pass null for the full arena.
func set_tank(node) -> void:
	_tank = node


func set_follow(node) -> void:
	_follow = node
	if node == null:
		_frame_arena()


func _build_ground() -> void:
	Kit.part(self, Terrain.build_mesh(), Mat.sand(), Vector3.ZERO)
	var water_mesh := Terrain.build_water_mesh()
	if water_mesh != null:
		var water := Kit.part(self, water_mesh, Mat.water(), Vector3.ZERO)
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Boulders scattered over the dunes. Fixed seed, same every run.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1990
	var w := float(Cfg.cols)
	var h := float(Cfg.rows)
	for i in 170:
		var x: float = rng.randf_range(-30.0, w + 30.0)
		var z: float = rng.randf_range(-26.0, h + 18.0)
		if x > -2.5 and x < w + 2.5 and z > -2.5 and z < h + 2.5:
			continue
		var size: float = rng.randf_range(0.5, 2.6)
		_add_rock(Vector3(x, 0.0, z), Vector3(size, size * rng.randf_range(0.5, 0.9), size),
			rng, Mat.rock())


func _add_rock(at: Vector3, size: Vector3, rng: RandomNumberGenerator,
		material: Material) -> MeshInstance3D:
	var rock := Kit.part(self, _rocks[rng.randi() % _rocks.size()], material,
		Vector3(at.x, ground(at.x, at.z) + size.y * 0.25, at.z),
		Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))
	rock.scale = size
	return rock


func _build_walls() -> void:
	# Mud-brick wall blocks: the sides lean in a little, the top course is
	# uneven with a stone missing here and there, and a few bricks stand
	# proud. Four shapes, turned at random, so a run of wall is not a row
	# of identical cubes.
	var bricks: Array = []
	var wrng := RandomNumberGenerator.new()
	wrng.seed = 9917
	for v in 4:
		var bits: Array = []
		Kit.put(bits, Kit.loft(Kit.rect(0.5, 0.5), -0.3, Kit.rect(0.47, 0.47), WALL_H - 0.08), Vector3.ZERO)
		for i in 3:
			for j in 3:
				if wrng.randf() < 0.14:
					continue
				var h: float = wrng.randf_range(0.07, 0.17)
				Kit.put(bits, Kit.box(Vector3(0.3, h, 0.3)),
					Vector3((i - 1) * 0.31, WALL_H - 0.08 + h * 0.5, (j - 1) * 0.31),
					Vector3(0.0, wrng.randf_range(-0.06, 0.06), 0.0))
		for i in 5:
			var face: float = wrng.randi_range(0, 3) * PI * 0.5
			var across: float = wrng.randf_range(-0.34, 0.34)
			var up: float = wrng.randf_range(-0.1, WALL_H - 0.25)
			Kit.put(bits, Kit.box(Vector3(0.2, 0.09, 0.06)),
				Vector3(across, up, 0.485).rotated(Vector3.UP, face), Vector3(0.0, face, 0.0))
		bricks.append(Kit.merge(bits))
	# Concrete block with a base course and a capping slab.
	var parts: Array = []
	Kit.put(parts, Kit.box(Vector3(0.92, 1.1, 0.92)), Vector3(0.0, 0.3, 0.0))
	Kit.put(parts, Kit.box(Vector3(1.0, 0.12, 1.0)), Vector3(0.0, 0.84, 0.0))
	Kit.put(parts, Kit.box(Vector3(1.0, 0.5, 1.0)), Vector3(0.0, -0.05, 0.0))
	var block := Kit.merge(parts)
	var wire: Dictionary = {}
	var wire_mat: Material = Mat.cutout("res://assets/build/barbed_wire.png")
	var wire_card := QuadMesh.new()
	wire_card.size = Vector2(1.0, 0.2)
	for y in Cfg.rows:
		for x in Cfg.cols:
			var cell := Vector2i(x, y)
			var t: int = _arena.tile_at(cell)
			var at := Vector3(x + 0.5, ground(x + 0.5, y + 0.5), y + 0.5)
			if _arena.decor.has(cell):
				if _arena.decor[cell] == "T":
					_build_tree(at)
				elif _arena.decor[cell] == "M":
					_build_ridge(at)
			elif t == _arena.PLATING:
				# Walls are sunk a little so they never float over a dip.
				var pick: int = (x * 7 + y * 13 + (x * y) % 5) % 4
				_walls[cell] = Kit.part(self, bricks[pick], Mat.mud_brick(), at,
					Vector3(0.0, ((x * 3 + y * 5) % 4) * PI * 0.5, 0.0))
			elif t == _arena.ALLOY:
				_walls[cell] = Kit.part(self, block, Mat.concrete(), at)
				# Coils of barbed wire along the top, following the wall's run.
				var run_x: bool = _arena.tile_at(cell + Vector2i(1, 0)) == _arena.ALLOY \
					or _arena.tile_at(cell + Vector2i(-1, 0)) == _arena.ALLOY
				var run_z: bool = _arena.tile_at(cell + Vector2i(0, 1)) == _arena.ALLOY \
					or _arena.tile_at(cell + Vector2i(0, -1)) == _arena.ALLOY
				for turn in 2:
					if (turn == 0 and (run_x or not run_z)) or (turn == 1 and run_z):
						for lean in [-0.5, 0.5]:
							Kit.add(wire, wire_mat, wire_card, at + Vector3(0.0, 0.99, 0.0),
								Vector3(lean, turn * PI * 0.5, 0.0))
	if ResourceLoader.exists("res://assets/build/barbed_wire.png"):
		for m in Kit.flush(wire, self):
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Palm shapes shared by every palm on the map. The first six are green
## (tall, leaning, short, bushy, lush, thin), the last three are dry.
func _make_palms() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	# trunk height, lean, trunk radius, fronds, frond length, dryness
	var specs: Array = [
		[2.3, 0.35, 0.13, 15, 1.45, 0.1],
		[1.8, 0.7, 0.12, 14, 1.35, 0.25],
		[1.3, 0.15, 0.14, 13, 1.25, 0.0],
		[2.6, 0.9, 0.12, 15, 1.4, 0.3],
		[0.8, 0.1, 0.15, 12, 1.2, 0.15],
		[2.0, 0.5, 0.115, 13, 1.3, 0.2],
		[2.2, 0.6, 0.12, 11, 1.3, 0.8],
		[1.5, 0.3, 0.13, 10, 1.2, 0.95],
		[2.7, 1.0, 0.11, 9, 1.25, 0.7],
	]
	for spec in specs:
		var a: float = rng.randf() * TAU
		var lean: Vector2 = Vector2(cos(a), sin(a)) * float(spec[1])
		var top := Vector3(lean.x, float(spec[0]) - 0.04, lean.y)
		_palms.append([Kit.palm_trunk(float(spec[0]), lean, float(spec[2])),
			Kit.palm_crown(top, rng, int(spec[3]), float(spec[4]), float(spec[5]),
				2 + int(float(spec[5]) * 4.0))])
		_palm_xf.append([])
		_palm_top.append(top)


## Palms for one map cell. They are kept small against the tanks and stand
## close, so a grove reads as a wall of jungle. Deep inside a grove one palm
## per cell is enough; the edges get a looser fringe.
func _build_tree(at: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(at.x * 31.0 + at.z * 17.0)
	var cell := Vector2i(int(at.x), int(at.z))
	var inner := true
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _arena.decor.get(cell + step, "") != "T":
			inner = false
	var far: bool = Terrain.far_bank(at.x, at.z) > 0.5
	var count: int = 1 if inner and rng.randf() < 0.6 else rng.randi_range(1, 2)
	for i in count:
		var spread: float = 0.12 if i == 0 else 0.36
		var x: float = at.x + rng.randf_range(-spread, spread)
		var z: float = at.z + rng.randf_range(-spread, spread)
		var kind: int = rng.randi() % 6
		if rng.randf() < (0.7 if far else 0.08):
			kind = 6 + rng.randi() % 3
		var size: float = rng.randf_range(0.46, 0.78) * (0.8 if i > 0 else 1.0)
		var turn := Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(size, size * rng.randf_range(0.9, 1.15), size))
		_palm_xf[kind].append(Transform3D(turn, Vector3(x, ground(x, z) - 0.06, z)))
		# Some green palms carry a bunch of dates under the crown.
		if kind < 6 and rng.randf() < 0.3 and ResourceLoader.exists("res://assets/nature/palm_dates.png"):
			var palm := Transform3D(turn, Vector3(x, ground(x, z) - 0.06, z))
			var hang: Vector3 = palm * (_palm_top[kind] + Vector3(0.0, -0.75, 0.0))
			_date_xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.34, 0.42, 0.34)), hang))
	# Undergrowth at the foot of the palms.
	for i in rng.randi_range(0, 2):
		var size: float = rng.randf_range(0.4, 0.7)
		_add_tuft(at.x + rng.randf_range(-0.48, 0.48), at.z + rng.randf_range(-0.48, 0.48),
			size, size, Color(0.9, 0.85, 0.75) if far else Color(0.8, 0.85, 0.7), rng,
			"plants_shrubs" if far else ("plants_ferns" if rng.randf() < 0.6 else "plants_shrubs_green"))
	# The grove floor: fallen leaves, moss in the shade, now and then a
	# fallen trunk or a stump.
	for i in rng.randi_range(1, 3):
		_add_flat("leaf_litter", at.x + rng.randf_range(-0.5, 0.5), at.z + rng.randf_range(-0.5, 0.5),
			rng.randf_range(0.35, 0.6), rng, Color(0.85, 0.8, 0.72))
	if not far and rng.randf() < 0.35:
		_add_flat("moss_patches", at.x + rng.randf_range(-0.45, 0.45), at.z + rng.randf_range(-0.45, 0.45),
			rng.randf_range(0.3, 0.5), rng, Color(0.75, 0.8, 0.7))
	if rng.randf() < 0.07:
		var lx: float = at.x + rng.randf_range(-0.2, 0.2)
		var lz: float = at.z + rng.randf_range(-0.2, 0.2)
		if rng.randf() < 0.55:
			var long: float = rng.randf_range(0.7, 1.2)
			Kit.add(_floor_bins, Mat.bark(), Kit.cylinder(rng.randf_range(0.07, 0.1), long, 9),
				Vector3(lx, ground(lx, lz) + 0.06, lz), Vector3(0.0, rng.randf() * TAU, PI * 0.5 + rng.randf_range(-0.05, 0.05)))
		else:
			var wide: float = rng.randf_range(0.11, 0.15)
			Kit.add(_floor_bins, Mat.bark(), Kit.cylinder(wide, 0.2, 10), Vector3(lx, ground(lx, lz) + 0.06, lz))
			var cut := QuadMesh.new()
			cut.size = Vector2(wide * 2.15, wide * 2.15)
			cut.orientation = PlaneMesh.FACE_Y
			Kit.add(_floor_bins, Mat.cutout("res://assets/nature/tree_stump.png"), cut,
				Vector3(lx, ground(lx, lz) + 0.165, lz), Vector3(0.0, rng.randf() * TAU, 0.0))
	if rng.randf() < (0.25 if inner else 0.5):
		_add_shrub(at.x + rng.randf_range(-0.45, 0.45), at.z + rng.randf_range(-0.45, 0.45),
			rng.randf_range(0.5, 0.9), rng)


func _add_tuft(x: float, z: float, width: float, tall: float, color: Color,
		rng: RandomNumberGenerator, sheet: String = "plants_grass_dry", lift: float = -0.02) -> void:
	if not _plants.has(sheet):
		_plants[sheet] = {"xf": [], "col": PackedColorArray(), "cell": PackedColorArray()}
	var set: Dictionary = _plants[sheet]
	var turn := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(width, tall, width))
	set["xf"].append(Transform3D(turn, Vector3(x, ground(x, z) + lift, z)))
	var shade: float = rng.randf_range(0.8, 1.0)
	set["col"].append(Color(color.r * shade, color.g * shade, color.b * shade))
	set["cell"].append(Color(float(rng.randi() % 4), 0.0, 0.0, 0.0))


## A flat patch lying on the ground, from a sheet of 4: leaves, moss.
func _add_flat(sheet: String, x: float, z: float, wide: float, rng: RandomNumberGenerator, color: Color) -> void:
	if not ResourceLoader.exists("res://assets/nature/%s.png" % sheet):
		return
	if not _plants.has(sheet):
		_plants[sheet] = {"xf": [], "col": PackedColorArray(), "cell": PackedColorArray()}
	var set: Dictionary = _plants[sheet]
	set["xf"].append(Terrain.ground_xf(x, z, rng.randf() * TAU, 0.025).scaled_local(Vector3(wide, 1.0, wide)))
	set["col"].append(color)
	set["cell"].append(Color(float(rng.randi() % 4), 0.0, 0.0, 0.0))


## A low bush: a crown of short fronds sitting on the sand.
func _add_shrub(x: float, z: float, size: float, rng: RandomNumberGenerator) -> void:
	var kind: int = rng.randi() % _shrubs.size()
	var turn := Basis(Vector3.UP, rng.randf() * TAU).scaled(
		Vector3(size, size * rng.randf_range(0.8, 1.2), size))
	_shrub_xf[kind].append(Transform3D(turn, Vector3(x, ground(x, z) - 0.03, z)))


## A stone lying on the ground or on the river bed.
func _add_pebble(x: float, z: float, size: float, rng: RandomNumberGenerator) -> void:
	var kind: int = rng.randi() % _stones.size()
	var turn := Basis.from_euler(Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU,
		rng.randf_range(-0.4, 0.4))).scaled(Vector3(size, size * rng.randf_range(0.45, 0.8), size))
	_pebble_xf[kind].append(Transform3D(turn, Vector3(x, ground(x, z) + size * 0.1, z)))


## Many copies of one mesh, split into map tiles so that only the tiles in
## view are drawn.
func _scatter(mesh: Mesh, material: Material, xfs: Array, colors: PackedColorArray,
		shadows: bool, cells: PackedColorArray = PackedColorArray()) -> void:
	var tiles: Dictionary = {}
	for i in xfs.size():
		var o: Vector3 = xfs[i].origin
		var key := Vector2i(int(floor(o.x / TILE)), int(floor(o.z / TILE)))
		if not tiles.has(key):
			tiles[key] = []
		tiles[key].append(i)
	for key in tiles:
		var ids: Array = tiles[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = not colors.is_empty()
		mm.use_custom_data = not cells.is_empty()
		mm.mesh = mesh
		mm.instance_count = ids.size()
		for n in ids.size():
			mm.set_instance_transform(n, xfs[ids[n]])
			if mm.use_colors:
				mm.set_instance_color(n, colors[ids[n]])
			if mm.use_custom_data:
				mm.set_instance_custom_data(n, cells[ids[n]])
		var holder := MultiMeshInstance3D.new()
		holder.multimesh = mm
		holder.material_override = material
		if not shadows:
			holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(holder)


## Ground cover. Greenery follows the water: lush grass and bushes on the
## banks, reeds in the shallows, stones on the river bed. Away from water
## the desert has patches of dry grass and scrub with bare sand between.
func _build_grass() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var patch := FastNoiseLite.new()
	patch.seed = 5
	patch.frequency = 0.09
	for y in Cfg.rows:
		for x in Cfg.cols:
			var cell := Vector2i(x, y)
			if _arena.tile_at(cell) != _arena.EMPTY or _arena.deep.has(cell):
				continue
			var wet: bool = _arena.water.has(cell)
			var near := false
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if _arena.water.has(cell + Vector2i(dx, dy)):
						near = true
			var scrub: float = patch.get_noise_2d(x, y)
			if _arena.roads.has(cell):
				# Roads are bare, with the odd stone kicked up.
				if rng.randf() < 0.15:
					_add_pebble(x + rng.randf(), y + rng.randf(), rng.randf_range(0.04, 0.09), rng)
				continue
			var far: bool = Terrain.far_bank(x + 0.5, y + 0.5) > 0.5
			var grass: int = 0
			var bushes: int = 0
			var stones: int = 0
			if wet:
				grass = rng.randi_range(0, 3)
				stones = rng.randi_range(0, 3)
			elif near:
				grass = rng.randi_range(3, 7)
				bushes = 1 if rng.randf() < 0.3 else 0
				stones = rng.randi_range(0, 2)
			elif scrub > 0.18:
				grass = rng.randi_range(1, 4)
				bushes = 1 if rng.randf() < 0.14 else 0
				stones = 1 if rng.randf() < 0.3 else 0
			else:
				grass = 1 if rng.randf() < 0.14 else 0
				stones = 1 if rng.randf() < 0.12 else 0
			if far and not wet:
				# Harsher country: less green, more stone.
				grass = grass / 2
				stones += rng.randi_range(0, 2)
			# Fewer plants on weaker computers (FOLIAGE in the settings).
			var thin: float = [0.4, 0.7, 1.0][int(Cfg.gfx["foliage"])]
			if thin < 1.0:
				grass = int(grass * thin + rng.randf())
				stones = int(stones * thin + rng.randf())
			for i in grass:
				var px: float = x + rng.randf()
				var pz: float = y + rng.randf()
				var depth: float = Terrain.water_depth(px, pz)
				if depth > 0.13:
					continue
				if depth > 0.0:
					var reed: float = rng.randf_range(0.55, 0.9)
					_add_tuft(px, pz, reed, reed, Color(0.85, 0.9, 0.8), rng, "plants_reeds", -depth)
				elif near and not far:
					var roll: float = rng.randf()
					var size: float = rng.randf_range(0.26, 0.45)
					if roll < 0.12:
						_add_tuft(px, pz, size * 1.5, size * 1.5, Color(0.9, 0.9, 0.85), rng, "plants_grass_tall")
					elif roll < 0.17:
						_add_tuft(px, pz, size, size, Color(0.95, 0.95, 0.95), rng, "plants_flowers")
					else:
						_add_tuft(px, pz, size, size, Color(0.82, 0.88, 0.7), rng, "plants_grass_green")
				else:
					var roll: float = rng.randf()
					var size: float = rng.randf_range(0.32, 0.55)
					if roll < 0.06:
						_add_tuft(px, pz, size, size, Color(0.9, 0.85, 0.78), rng, "plants_tumbleweed")
					elif roll < 0.13:
						# Cacti, sunk a little so the cut foot is under the sand.
						# Sizes vary a lot: knee-high stubs to ones taller than a tank.
						var tall: float = rng.randf_range(0.25, 0.6) * (1.6 if rng.randf() < 0.2 else 1.0)
						_add_tuft(px, pz, tall * rng.randf_range(0.8, 1.0), tall,
							Color(0.86, 0.9, 0.8), rng, "plants_cactus", -0.1 * tall)
					elif roll < 0.22:
						_add_tuft(px, pz, size * 1.3, size * 1.3, Color(0.85, 0.8, 0.72), rng, "plants_shrubs")
					else:
						_add_tuft(px, pz, size, size, Color(0.92, 0.86, 0.72), rng, "plants_grass_dry")
			# Lily pads on still, shallow water.
			if wet and rng.randf() < 0.12:
				var px: float = x + rng.randf()
				var pz: float = y + rng.randf()
				var depth: float = Terrain.water_depth(px, pz)
				if depth > 0.1 and depth < 0.45:
					if not _plants.has("lily_pads"):
						_plants["lily_pads"] = {"xf": [], "col": PackedColorArray(), "cell": PackedColorArray()}
					var pads: Dictionary = _plants["lily_pads"]
					var wide: float = rng.randf_range(0.22, 0.4)
					pads["xf"].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(
						Vector3(wide, 1.0, wide)), Vector3(px, Terrain.WATER_LEVEL + 0.012, pz)))
					pads["col"].append(Color(0.8, 0.85, 0.75))
					pads["cell"].append(Color(float(rng.randi() % 4), 0.0, 0.0, 0.0))
			for i in bushes:
				var px: float = x + rng.randf()
				var pz: float = y + rng.randf()
				if Terrain.water_depth(px, pz) <= 0.0:
					_add_shrub(px, pz, rng.randf_range(0.45, 0.85) if near
						else rng.randf_range(0.35, 0.6), rng)
			for i in stones:
				_add_pebble(x + rng.randf(), y + rng.randf(),
					rng.randf_range(0.05, 0.16) * (1.6 if rng.randf() < 0.08 else 1.0), rng)
	for i in _palms.size():
		_scatter(_palms[i][0], Mat.bark(), _palm_xf[i], PackedColorArray(), true)
		_scatter(_palms[i][1], Mat.foliage(FROND if i < 6 else FROND_DRY), _palm_xf[i],
			PackedColorArray(), true)
	for sheet in _plants:
		var set: Dictionary = _plants[sheet]
		_scatter(Kit.pad() if sheet in ["lily_pads", "leaf_litter", "moss_patches"] else Kit.tuft(), Mat.plants(sheet), set["xf"],
			set["col"], false, set["cell"])
	if not _date_xf.is_empty():
		_scatter(Kit.tuft(), Mat.foliage("res://assets/nature/palm_dates.png"), _date_xf, PackedColorArray(), false)
	for m in Kit.flush(_floor_bins, self):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for i in _shrubs.size():
		_scatter(_shrubs[i], Mat.foliage(FROND_YOUNG), _shrub_xf[i], PackedColorArray(), true)
	for i in _stones.size():
		_scatter(_stones[i], Mat.rock(), _pebble_xf[i], PackedColorArray(), false)


## Rock ridge: overlapping crags that merge with neighbouring cells.
func _build_ridge(at: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(at.x * 13.0 + at.z * 29.0)
	for i in 3:
		var p := at + Vector3(rng.randf_range(-0.28, 0.28), 0.0, rng.randf_range(-0.28, 0.28))
		_add_rock(Vector3(p.x, 0.0, p.z), Vector3(rng.randf_range(0.9, 1.3),
			rng.randf_range(1.1, 2.0), rng.randf_range(0.9, 1.3)), rng, Mat.rock())


func _on_tile_damaged(cell: Vector2i) -> void:
	if _walls.has(cell):
		var m: MeshInstance3D = _walls[cell]
		m.scale = Vector3(1.0, 0.6, 1.0)
		m.position.y -= WALL_H * 0.2


func _on_tile_destroyed(cell: Vector2i) -> void:
	if _walls.has(cell):
		_walls[cell].queue_free()
		_walls.erase(cell)
	# A heap of broken brick where the wall stood.
	var rng := RandomNumberGenerator.new()
	rng.seed = cell.x * 97 + cell.y * 13
	for i in 5:
		var p := Vector3(cell.x + rng.randf_range(0.15, 0.85), 0.0, cell.y + rng.randf_range(0.15, 0.85))
		var size: float = rng.randf_range(0.18, 0.42)
		_add_rock(p, Vector3(size, size * 0.6, size), rng, Mat.rubble())


func _build_marks() -> void:
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	quad.size = Vector2(0.38, 0.15)
	quad.material = Mat.track_mark()
	_mark_born.resize(MAX_MARKS)
	_marks = MultiMesh.new()
	_marks.transform_format = MultiMesh.TRANSFORM_3D
	_marks.use_colors = true
	_marks.mesh = quad
	_marks.instance_count = MAX_MARKS
	_marks.visible_instance_count = 0
	var holder := MultiMeshInstance3D.new()
	holder.multimesh = _marks
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(holder)


## Presses one track print into the sand. Oldest prints are reused.
func add_mark(x: float, z: float, heading: float) -> void:
	var i: int = _mark_count % MAX_MARKS
	_marks.set_instance_transform(i, Terrain.ground_xf(x, z, heading, 0.012))
	_marks.set_instance_color(i, Color(1.0, 1.0, 1.0, 1.0))
	_mark_born[i] = _clock
	_mark_count += 1
	_marks.visible_instance_count = mini(_mark_count, MAX_MARKS)


## The wind fills the ruts in: each print fades by its own age, so a trail
## disappears from its far end towards the tank. A slice is updated per frame.
func _fade_marks() -> void:
	var live: int = mini(_mark_count, MAX_MARKS)
	for n in mini(live, 500):
		_mark_cursor = (_mark_cursor + 1) % live
		var age: float = _clock - _mark_born[_mark_cursor]
		var alpha: float = 1.0 - smoothstep(MARK_HOLD, MARK_HOLD + MARK_FADE, age)
		_marks.set_instance_color(_mark_cursor, Color(1.0, 1.0, 1.0, alpha))


## Takes over a part that has come off a tank: it flies, tumbles, lands,
## settles at `rest` (a rotation) and lies there until `life` runs out.
func add_debris(node: Node3D, xf: Transform3D, velocity: Vector3, life: float,
		rest: Vector3, lift: float) -> void:
	add_child(node)
	node.global_transform = xf
	var axis := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	if axis.length() < 0.1:
		axis = Vector3.RIGHT
	_debris.append({"node": node, "vel": velocity, "axis": axis.normalized(),
		"spin": randf_range(4.0, 11.0), "life": life, "rest": rest, "lift": lift, "down": false})


func _move_debris(delta: float) -> void:
	for i in range(_debris.size() - 1, -1, -1):
		var d: Dictionary = _debris[i]
		var n: Node3D = d["node"]
		d["life"] = float(d["life"]) - delta
		if float(d["life"]) <= 0.0:
			n.queue_free()
			_debris.remove_at(i)
			continue
		if d["down"]:
			if float(d["life"]) < 3.0:
				n.position.y -= delta * 0.1  # the sand swallows it
			continue
		var v: Vector3 = d["vel"]
		v.y -= 9.8 * delta
		d["vel"] = v
		n.position += v * delta
		n.rotate(d["axis"], float(d["spin"]) * delta)
		var floor_y: float = ground(n.position.x, n.position.z) + float(d["lift"])
		if v.y < 0.0 and n.position.y <= floor_y:
			var size: Vector3 = n.scale
			n.rotation = d["rest"]
			n.scale = size
			n.position.y = floor_y
			d["down"] = true
			if Terrain.water_depth(n.position.x, n.position.z) > 0.03:
				Fx.splash(self, Vector3(n.position.x, Terrain.WATER_LEVEL, n.position.z), 0.5)
				add_ripple(n.position.x, n.position.z, 0.6)
			else:
				Fx.dust(self, Vector2(n.position.x, n.position.z) / S, 4)


func water_depth(x: float, z: float) -> float:
	return Terrain.water_depth(x, z)


## A ring spreading over the water and fading out.
func add_ripple(x: float, z: float, size: float) -> void:
	if _ring == null:
		_ring = QuadMesh.new()
		_ring.orientation = PlaneMesh.FACE_Y
	var mat: StandardMaterial3D = Mat.ripple()
	var ring := MeshInstance3D.new()
	ring.mesh = _ring
	ring.material_override = mat
	ring.position = Vector3(x, Terrain.WATER_LEVEL + 0.015, z)
	ring.rotation.y = randf() * TAU
	ring.scale = Vector3(size * 0.5, 1.0, size * 0.5)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(size * 2.6, 1.0, size * 2.6), 1.9) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 1.9)
	tw.chain().tween_callback(ring.queue_free)


## A blast ring racing out over the ground.
func add_shockwave(x: float, z: float, size: float) -> void:
	if not ResourceLoader.exists("res://assets/fx/fx_shockwave.png"):
		return
	if _wave == null:
		_wave = QuadMesh.new()
		_wave.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = load("res://assets/fx/fx_shockwave.png")
	mat.albedo_color = Color(1.0, 0.92, 0.8, 0.7)
	var ring := MeshInstance3D.new()
	ring.mesh = _wave
	ring.material_override = mat
	ring.position = Vector3(x, maxf(ground(x, z), Terrain.WATER_LEVEL) + 0.08, z)
	ring.scale = Vector3(size * 0.4, 1.0, size * 0.4)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(size * 3.2, 1.0, size * 3.2), 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_callback(ring.queue_free)


## Burn mark left on the sand by an explosion.
func add_scorch(x: float, z: float, size: float) -> void:
	if Terrain.water_depth(x, z) > 0.03:
		add_ripple(x, z, size * 1.6)
		Fx.splash(self, Vector3(x, Terrain.WATER_LEVEL, z), 2.0)
		return
	if _scorch == null:
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.1, 0.08, 0.06, 0.6)
		mat.albedo_texture = Fx.puff_texture()
		if ResourceLoader.exists("res://assets/fx/fx_scorch.png"):
			mat.albedo_color = Color(0.8, 0.78, 0.75, 0.9)
			mat.albedo_texture = load("res://assets/fx/fx_scorch.png")
		mat.roughness = 1.0
		_scorch = QuadMesh.new()
		_scorch.orientation = PlaneMesh.FACE_Y
		_scorch.material = mat
	if size > 1.0 and ResourceLoader.exists("res://assets/fx/fx_crater.png"):
		# A big blast also digs a shallow crater under the burn.
		if _crater == null:
			var cm := StandardMaterial3D.new()
			cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			cm.albedo_color = Color(0.82, 0.76, 0.68, 0.85)
			cm.albedo_texture = load("res://assets/fx/fx_crater.png")
			cm.roughness = 1.0
			_crater = QuadMesh.new()
			_crater.orientation = PlaneMesh.FACE_Y
			_crater.material = cm
		var hole := MeshInstance3D.new()
		hole.mesh = _crater
		hole.transform = Terrain.ground_xf(x, z, randf() * TAU, 0.015).scaled_local(
			Vector3(size * 0.9, 1.0, size * 0.9))
		hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(hole)
		_holes.append(hole)
		if _holes.size() > 40:
			_holes.pop_front().queue_free()
	var mark := MeshInstance3D.new()
	mark.mesh = _scorch
	mark.transform = Terrain.ground_xf(x, z, randf() * TAU, 0.02).scaled_local(
		Vector3(size, 1.0, size))
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mark)


func add_tank(tank) -> void:
	var m = TankModel.new()
	m.setup(tank)
	add_child(m)


func add_shell(shell) -> void:
	var m = ShellView.new()
	m.setup(shell)
	add_child(m)


func add_mine(mine) -> void:
	var m = MineView.new()
	m.setup(mine)
	add_child(m)


## A 2D game position as a point in the 3D world, just above the ground.
func spot(pos: Vector2) -> Vector3:
	return Vector3(pos.x * S, ground(pos.x * S, pos.y * S) + 0.4, pos.y * S)


func add_pickup(pickup) -> void:
	var m = PickupView.new()
	m.setup(pickup)
	add_child(m)


func add_structure(structure) -> void:
	var m = StructureView.new()
	m.setup(structure)
	add_child(m)


func add_barrage(barrage) -> void:
	var m = BarrageView.new()
	m.setup(barrage)
	add_child(m)


func add_core(core) -> void:
	var m = CoreView.new()
	m.setup(core)
	add_child(m)


## Mouse position on the ground, in 2D game coordinates.
func mouse_ground() -> Vector2:
	var mp: Vector2 = Cfg.aim_pos
	var origin: Vector3 = camera.project_ray_origin(mp)
	var dir: Vector3 = camera.project_ray_normal(mp)
	if absf(dir.y) < 0.0001:
		return Vector2.ZERO
	# Aim is taken at the height of a tank's body on the ground under the
	# pointer, so pointing at a tank on screen aims at that tank, on a dune
	# or in the water, from either camera.
	var hit: Vector3 = origin + dir * ((0.3 - origin.y) / dir.y)
	for i in 4:
		var h: float = maxf(ground(hit.x, hit.z), Terrain.WATER_LEVEL) + 0.3
		hit = origin + dir * ((h - origin.y) / dir.y)
	return Vector2(hit.x, hit.z) / S


## True if a 2D game position is inside what the camera shows right now.
func on_screen(pos: Vector2) -> bool:
	return camera.is_position_in_frustum(spot(pos))


## The patch of ground the camera shows, as four 2D game positions
## (screen corners: top left, top right, bottom right, bottom left).
func view_patch() -> PackedVector2Array:
	var size: Vector2 = get_viewport().get_visible_rect().size
	var out := PackedVector2Array()
	for corner in [Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]:
		var origin: Vector3 = camera.project_ray_origin(corner)
		var dir: Vector3 = camera.project_ray_normal(corner)
		var reach: float = 70.0
		if dir.y < -0.02:
			reach = minf((0.3 - origin.y) / dir.y, 70.0)
		var hit: Vector3 = origin + dir * reach
		out.append(Vector2(hit.x, hit.z) / S)
	return out


## Mouse wheel (or Page Up / Page Down) zooms the current camera.
func _unhandled_input(event: InputEvent) -> void:
	var step := 0.0
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			step = -0.1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step = 0.1
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_PAGEUP:
			step = -0.1
		elif event.keycode == KEY_PAGEDOWN:
			step = 0.1
	if step == 0.0:
		return
	if _follow != null:
		_zoom_follow = clampf(_zoom_follow + step, 0.3, 3.0)
	else:
		_zoom_arena = clampf(_zoom_arena + step, 0.45, 2.4)
		_frame_arena()


func _listen_at(point: Vector3) -> void:
	if _ears == null:
		_ears = AudioListener3D.new()
		add_child(_ears)
	_ears.global_transform = Transform3D(camera.global_transform.basis, point + Vector3(0.0, 1.5, 0.0))
	Sfx.ears = point
	# Haze belongs to the horizon. Seen from high up it would lie over the
	# whole map like fog, so it thins as the camera pulls away.
	var away: float = camera.global_position.distance_to(point)
	var n: float = GameState.night
	env.fog_density = minf(0.006, 0.05 / away) * (1.0 + 3.0 * n)
	env.fog_aerial_perspective = clampf(4.0 / away, 0.0, 0.4)
	env.volumetric_fog_density = (minf(0.008, 0.07 / away) if away < 28.0 else 0.0) * (1.0 + 2.5 * n)
	if not _ears.is_current():
		_ears.make_current()


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _process(delta: float) -> void:
	_clock += delta
	if Cfg.gfx_probe and (not Cfg.has_meta("aim_test") or OS.get_cmdline_user_args().has("probe")):
		_probe(delta)
	# Tell the palm leaves where the player's tank is, so they open over it.
	var hero := Vector3(0.0, -999.0, 0.0)
	var who = _follow if _follow != null and is_instance_valid(_follow) else _tank
	if who != null and is_instance_valid(who):
		var hp2: Vector2 = who.global_position
		hero = Vector3(hp2.x * S, ground(hp2.x * S, hp2.y * S) + 0.35, hp2.y * S)
	RenderingServer.global_shader_parameter_set("hero_pos", hero)
	RenderingServer.global_shader_parameter_set("eye_pos", camera.global_position)
	if not _debris.is_empty():
		_move_debris(delta)
	if _mark_count > 0:
		_fade_marks()
	_night_look(GameState.night)
	if _follow != null and is_instance_valid(_follow):
		var fp: Vector2 = _follow.global_position
		var look := Vector3(fp.x * S, ground(fp.x * S, fp.y * S) + 0.3, fp.y * S)
		# Low enough that the dunes and the sky line show behind the tank.
		camera.position = look + Vector3(0.0, 3.4, 8.5) * _zoom_follow
		camera.look_at(look, Vector3.UP)
		sun.directional_shadow_max_distance = clampf(30.0 * _zoom_follow, 14.0, 90.0)
		_listen_at(look)
	elif _tank != null and is_instance_valid(_tank):
		# Map view: high above, centred on the tank and moving with it. The
		# aim point sits a little below the tank on screen, so the tank
		# stays clear of the bar at the bottom.
		var tp: Vector2 = _tank.global_position
		var at := Vector3(tp.x * S, ground(tp.x * S, tp.y * S) + 0.3, tp.y * S)
		var dist: float = 30.0 * _zoom_arena
		var aim := at + Vector3(0.0, 0.0, dist * 0.06)
		var tilt := deg_to_rad(66.0)
		camera.position = aim + Vector3(0.0, sin(tilt), cos(tilt)) * dist
		camera.look_at(aim, Vector3.UP)
		sun.directional_shadow_max_distance = minf(dist * 1.7, 80.0)
		_listen_at(at)
	elif _ears != null and _ears.is_current():
		_ears.clear_current()
	if _shake > 0.2:
		camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.012
		camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.012
		_shake = maxf(_shake - 30.0 * delta, 0.0)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
