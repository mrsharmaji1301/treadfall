extends Node3D
## The command post the player defends: bunker, mast and a turning radar.

const Mat := preload("res://view/materials.gd")
const Kit := preload("res://view/mesh_kit.gd")
const Fx := preload("res://fx/fx.gd")
const Terrain := preload("res://view/terrain.gd")
const Bar := preload("res://view/health_bar.gd")

const S := 1.0 / 48.0

var source
var _radar: Node3D
var _parts: Array[MeshInstance3D] = []
var _smoke: CPUParticles3D
var _dead := false
var _bar: MeshInstance3D


func setup(core) -> void:
	source = core
	var p: Vector2 = core.global_position
	position = Vector3(p.x * S, Terrain.height(p.x * S, p.y * S) - 0.05, p.y * S)
	var ours: bool = core.team == Cfg.TEAM_PLAYER
	_bar = Bar.make(self, Bar.color_for(core.team, false), 1.4, 40, 2.1)
	var bins: Dictionary = {}
	var spin: Dictionary = {}
	_radar = Node3D.new()
	add_child(_radar)
	if ours:
		_build_ours(bins, spin)
	else:
		_build_theirs(bins, spin)
	_parts.append_array(Kit.flush(bins, self))
	_parts.append_array(Kit.flush(spin, _radar))

	_smoke = Fx.make(Fx.smoke_cfg(16, 0.5, 2.4))
	_smoke.position = Vector3(0.0, 0.6, 0.0)
	_smoke.emitting = false
	add_child(_smoke)


## The player's Command Centre: a stepped concrete bunker behind sandbags,
## with an upper storey, a corner watch post, a door with a ramp, aerials,
## a turning radar dish and a flag.
func _build_ours(bins: Dictionary, spin: Dictionary) -> void:
	var conc: Material = Mat.concrete()
	var plate: Material = Mat.built("metal_plates", 2.4, Color(0.86, 0.8, 0.68), 0.25, 0.62)
	if plate == null:
		plate = Mat.paint(Cfg.PAINT_PLAYER)
	var dark: Material = Mat.built("metal_dark", 1.6, Color(0.75, 0.73, 0.7), 0.5, 0.5)
	if dark == null:
		dark = Mat.steel()
	var bags: Material = Mat.built("sandbags", 2.6, Color(0.9, 0.86, 0.76))
	if bags == null:
		bags = Mat.mud_brick()
	var glass: Material = Mat.surface("glass", Color(0.06, 0.09, 0.1), 0.12, 0.7, 3.0)
	# Ground floor, walls leaning in, with a parapet round the roof.
	Kit.add(bins, conc, Kit.loft(Kit.rect(0.5, 0.46), 0.0, Kit.rect(0.46, 0.42), 0.4), Vector3.ZERO)
	for i in 4:
		var a: float = i * PI * 0.5
		var half: float = 0.46 if i % 2 == 0 else 0.42
		var out: float = 0.4 if i % 2 == 0 else 0.44
		Kit.add(bins, conc, Kit.box(Vector3(0.05, 0.07, half * 2.0)),
			Vector3(cos(a) * (out + 0.035), 0.435, sin(a) * (out + 0.035)), Vector3(0.0, -a, 0.0))
	# Upper storey set back, with a window band and a roof slab.
	Kit.add(bins, plate, Kit.loft(Kit.rect(0.27, 0.24, Vector2(-0.1, -0.1)), 0.4,
		Kit.rect(0.25, 0.22, Vector2(-0.1, -0.1)), 0.66), Vector3.ZERO)
	Kit.add(bins, glass, Kit.box(Vector3(0.53, 0.07, 0.3)), Vector3(-0.1, 0.56, -0.1))
	Kit.add(bins, glass, Kit.box(Vector3(0.36, 0.07, 0.47)), Vector3(-0.1, 0.56, -0.1))
	Kit.add(bins, conc, Kit.box(Vector3(0.6, 0.04, 0.54)), Vector3(-0.1, 0.68, -0.1))
	# Corner watch post, taller than the rest, with firing slits.
	Kit.add(bins, conc, Kit.box(Vector3(0.24, 0.52, 0.24)), Vector3(0.3, 0.64, 0.26))
	Kit.add(bins, glass, Kit.box(Vector3(0.25, 0.05, 0.16)), Vector3(0.3, 0.78, 0.26))
	Kit.add(bins, glass, Kit.box(Vector3(0.16, 0.05, 0.25)), Vector3(0.3, 0.78, 0.26))
	Kit.add(bins, dark, Kit.box(Vector3(0.3, 0.035, 0.3)), Vector3(0.3, 0.915, 0.26))
	# Steel door on the near side, with a ramp up to it.
	Kit.add(bins, dark, Kit.box(Vector3(0.22, 0.26, 0.03)), Vector3(-0.12, 0.15, 0.475), Vector3(-0.09, 0.0, 0.0))
	Kit.add(bins, conc, Kit.box(Vector3(0.28, 0.03, 0.03)), Vector3(-0.12, 0.3, 0.485))
	Kit.add(bins, conc, Kit.loft(Kit.rect(0.16, 0.14), 0.0, Kit.rect(0.16, 0.01, Vector2(0.0, -0.13)), 0.05),
		Vector3(-0.12, 0.0, 0.62))
	# Sandbags round the foot, open at the door.
	Kit.bag_row(bins, bags, Vector3(0.08, 0.0, 0.56), Vector3(0.58, 0.0, 0.56), 2)
	Kit.bag_row(bins, bags, Vector3(-0.58, 0.0, 0.56), Vector3(-0.32, 0.0, 0.56), 2)
	Kit.bag_row(bins, bags, Vector3(0.6, 0.0, 0.52), Vector3(0.6, 0.0, -0.52), 2)
	Kit.bag_row(bins, bags, Vector3(-0.6, 0.0, 0.52), Vector3(-0.6, 0.0, -0.52), 2)
	Kit.bag_row(bins, bags, Vector3(-0.58, 0.0, -0.56), Vector3(0.58, 0.0, -0.56), 1)
	Kit.bag_row(bins, bags, Vector3(0.1, 0.4, 0.36), Vector3(0.1, 0.4, -0.3), 1)
	# Stores: crates and fuel drums against the wall.
	var crate: Material = Mat.built("wood_crate", 2.5)
	if crate != null:
		Kit.add(bins, crate, Kit.box(Vector3(0.16, 0.12, 0.14)), Vector3(0.3, 0.46, -0.24), Vector3(0.0, 0.3, 0.0))
		Kit.add(bins, crate, Kit.box(Vector3(0.14, 0.1, 0.12)), Vector3(0.28, 0.45, -0.05), Vector3(0.0, -0.2, 0.0))
	var drum: Material = Mat.built("metal_olive", 2.0, Color(0.8, 0.8, 0.75), 0.3, 0.6)
	if drum != null:
		for i in 3:
			Kit.add(bins, drum, Kit.cylinder(0.045, 0.13, 10), Vector3(0.36 - i * 0.1, 0.465, 0.02 + (i % 2) * 0.09))
	# Aerials, and a flag on a pole.
	for spot in [Vector3(-0.3, 0.7, -0.3), Vector3(0.08, 0.7, -0.28), Vector3(0.38, 0.93, 0.34)]:
		Kit.add(bins, Mat.steel(), Kit.cylinder(0.007, 0.6, 5), spot + Vector3(0.0, 0.3, 0.0))
	Kit.add(bins, Mat.steel(), Kit.cylinder(0.012, 0.8, 6), Vector3(-0.4, 0.8, 0.36))
	Kit.add(bins, Mat.surface("flag_ours", Color(0.2, 0.42, 0.2), 0.9, 0.0, 4.0), Kit.box(Vector3(0.24, 0.14, 0.008)),
		Vector3(-0.27, 1.12, 0.36))
	# Turning radar dish on the upper roof.
	_radar.position = Vector3(-0.14, 0.7, -0.12)
	Kit.add(spin, Mat.steel(), Kit.cylinder(0.02, 0.16, 6), Vector3(0.0, 0.08, 0.0))
	Kit.add(spin, plate, Kit.cone(0.025, 0.17, 0.06, 16), Vector3(0.04, 0.2, 0.0), Vector3(0.0, 0.0, -PI * 0.5 + 0.4))
	Kit.beam(spin, Mat.steel(), Vector3(0.04, 0.2, 0.0), Vector3(0.16, 0.26, 0.0), 0.01)


## The enemy's Command Centre: a dark stepped fortress with spiked corners,
## red-lit slits and a lattice mast.
func _build_theirs(bins: Dictionary, spin: Dictionary) -> void:
	var black: Material = Mat.built("metal_dark", 1.4, Color(0.55, 0.52, 0.52), 0.5, 0.5)
	if black == null:
		black = Mat.steel()
	var red: Material = Mat.built("metal_red_enemy", 1.1, Color(0.85, 0.8, 0.8), 0.3, 0.6)
	if red == null:
		red = Mat.paint(Color(0.62, 0.3, 0.26))
	var ember: Material = Mat.glow("enemy_slit", Color(1.0, 0.12, 0.06), 2.5)
	Kit.add(bins, black, Kit.loft(Kit.rect(0.56, 0.56), 0.0, Kit.rect(0.44, 0.44), 0.36), Vector3.ZERO)
	Kit.add(bins, red, Kit.loft(Kit.rect(0.38, 0.38), 0.36, Kit.rect(0.26, 0.26), 0.7), Vector3.ZERO)
	Kit.add(bins, black, Kit.loft(Kit.ngon(0.24, 8), 0.7, Kit.ngon(0.14, 8), 0.92), Vector3.ZERO)
	for i in 4:
		var a: float = PI * 0.25 + i * PI * 0.5
		var c := Vector3(cos(a), 0.0, sin(a))
		# Corner bastions with spikes.
		Kit.add(bins, black, Kit.loft(Kit.rect(0.12, 0.12), 0.0, Kit.rect(0.09, 0.09), 0.5), c * 0.7)
		Kit.add(bins, black, Kit.cone(0.07, 0.0, 0.26, 6), c * 0.7 + Vector3(0.0, 0.63, 0.0))
		Kit.add(bins, black, Kit.cone(0.045, 0.0, 0.2, 6), c * 0.45 + Vector3(0.0, 0.8, 0.0))
		# Lit slits on every face, and a buttress under each.
		var f: float = i * PI * 0.5
		var n := Vector3(cos(f), 0.0, sin(f))
		Kit.add(bins, ember, Kit.box(Vector3(0.02, 0.035, 0.3)), n * 0.485 + Vector3(0.0, 0.22, 0.0), Vector3(0.0, -f, 0.0))
		Kit.add(bins, ember, Kit.box(Vector3(0.02, 0.03, 0.16)), n * 0.305 + Vector3(0.0, 0.55, 0.0), Vector3(0.0, -f, 0.0))
		Kit.add(bins, black, Kit.loft(Kit.rect(0.1, 0.07), 0.0, Kit.rect(0.03, 0.06, Vector2(-0.06, 0.0)), 0.26),
			n * 0.6, Vector3(0.0, -f, 0.0))
		# Lattice mast.
		Kit.beam(bins, black, c * 0.1 + Vector3(0.0, 0.92, 0.0), c * 0.02 + Vector3(0.0, 1.55, 0.0), 0.018)
		for level in 3:
			var y: float = 1.05 + level * 0.15
			var w: float = lerpf(0.1, 0.02, (y - 0.92) / 0.63)
			var c2 := Vector3(cos(a + PI * 0.5), 0.0, sin(a + PI * 0.5))
			Kit.beam(bins, black, c * w + Vector3(0.0, y, 0.0), c2 * w + Vector3(0.0, y, 0.0), 0.01)
	Kit.add(bins, ember, Kit.cylinder(0.025, 0.05, 8), Vector3(0.0, 1.58, 0.0))
	# Turning aerial bar on the mast.
	_radar.position = Vector3(0.0, 1.3, 0.0)
	Kit.add(spin, black, Kit.box(Vector3(0.36, 0.05, 0.02)), Vector3.ZERO)


func _process(delta: float) -> void:
	if _dead or not is_instance_valid(source):
		return
	if source.alive:
		_radar.rotate_y(delta * 1.5)
		_smoke.emitting = source.hp * 2 <= source.max_hp
		Bar.update(_bar, source.hp, 40.0, Bar.SHIELDED if source.shielded()
			else Bar.color_for(source.team, false))
		_bar.set_instance_shader_parameter("fill", float(source.hp) / float(source.max_hp))
	else:
		_dead = true
		_bar.visible = false
		_smoke.emitting = true
		for part in _parts:
			part.material_override = Mat.charred()
