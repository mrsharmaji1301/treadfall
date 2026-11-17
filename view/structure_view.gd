extends Node3D
## How a defence looks: a concrete emplacement with a head that turns to
## aim, a health bar, and a burnt shell once it is destroyed.

const Mat := preload("res://view/materials.gd")
const Kit := preload("res://view/mesh_kit.gd")
const Fx := preload("res://fx/fx.gd")
const Terrain := preload("res://view/terrain.gd")
const Bar := preload("res://view/health_bar.gd")

const S := 1.0 / 48.0
const ALONG_X := Vector3(0.0, 0.0, -PI * 0.5)

var source
var _head: Node3D
var _gun: Node3D
var _lamp: MeshInstance3D
var _parts: Array[MeshInstance3D] = []
var _smoke: CPUParticles3D
var _bar: MeshInstance3D
var _dead := false
var _clock := 0.0
var _gun_x := 0.0
## Parts waiting to be joined: fixed base, turning head, gun.
var _fixed: Dictionary = {}
var _turn: Dictionary = {}
var _tube: Dictionary = {}


func setup(structure) -> void:
	source = structure
	var p: Vector2 = structure.global_position
	position = Vector3(p.x * S, Terrain.height(p.x * S, p.y * S) - 0.06, p.y * S)
	var ours: bool = structure.team == Cfg.TEAM_PLAYER
	# Riveted armour plate: sand-coloured for the player, red and black for
	# the enemy. `dark` is for collars, mantlets and trim.
	var plate: Material = Mat.built("metal_plates", 2.4, Color(0.86, 0.8, 0.68), 0.25, 0.62) if ours \
		else Mat.built("metal_red_enemy", 1.1, Color(0.9, 0.85, 0.85), 0.3, 0.6)
	if plate == null:
		plate = Mat.paint(Cfg.PAINT_PLAYER if ours else Color(0.62, 0.3, 0.26))
	var dark: Material = Mat.built("metal_dark", 1.6, Color(0.75, 0.73, 0.7) if ours else Color(0.6, 0.55, 0.55), 0.5, 0.5)
	if dark == null:
		dark = Mat.steel()
	_head = Node3D.new()
	add_child(_head)
	_gun = Node3D.new()
	_head.add_child(_gun)
	match structure.kind:
		"tower":
			_build_tower(plate, dark, ours)
		"turret":
			_build_turret(plate, dark)
		"artillery":
			_build_artillery(plate, dark)
		"guard":
			_build_guard(plate, dark)
	_parts.append_array(Kit.flush(_fixed, self))
	_parts.append_array(Kit.flush(_turn, _head))
	_parts.append_array(Kit.flush(_tube, _gun))
	_gun_x = _gun.position.x
	_smoke = Fx.make(Fx.smoke_cfg(16, 0.5, 2.4))
	_smoke.position = Vector3(0.0, 0.7, 0.0)
	_smoke.emitting = false
	add_child(_smoke)
	_bar = Bar.make(self, Bar.color_for(structure.team, false), 1.1, structure.max_hp,
		3.1 if structure.kind == "tower" else 1.6)


func _bags() -> Material:
	var m: Material = Mat.built("sandbags", 2.6, Color(0.9, 0.86, 0.76))
	return m if m != null else Mat.mud_brick()


## A gun barrel along +x from the gun mount: sleeve, tube, fume extractor
## and a slotted muzzle brake.
func _barrel(plate: Material, dark: Material, length: float, bore: float, z: float = 0.0) -> void:
	Kit.add(_tube, plate, Kit.cylinder(bore * 1.55, 0.26, 12), Vector3(0.13, 0.0, z), ALONG_X)
	Kit.add(_tube, Mat.steel(), Kit.cylinder(bore, length, 12), Vector3(length * 0.5, 0.0, z), ALONG_X)
	Kit.add(_tube, plate, Kit.cylinder(bore * 1.4, 0.17, 12), Vector3(length * 0.52, 0.0, z), ALONG_X)
	Kit.add(_tube, dark, Kit.box(Vector3(0.15, bore * 2.1, bore * 3.0)), Vector3(length + 0.03, 0.0, z))
	Kit.add(_tube, Mat.steel(), Kit.box(Vector3(0.03, bore * 2.3, bore * 3.3)), Vector3(length - 0.01, 0.0, z))
	Kit.add(_tube, Mat.steel(), Kit.box(Vector3(0.03, bore * 2.3, bore * 3.3)), Vector3(length + 0.07, 0.0, z))


## An angular armoured turret body on the head: six-sided, sloped in to the
## roof, with collar, mantlet, cupola, hatch, bustle and aerials.
func _armour(plate: Material, dark: Material, k: float) -> void:
	Kit.add(_turn, dark, Kit.cylinder(0.27 * k, 0.12, 16), Vector3(0.0, 0.06, 0.0))
	var low := PackedVector2Array([Vector2(0.36, -0.17), Vector2(0.36, 0.17), Vector2(0.14, 0.33),
		Vector2(-0.36, 0.3), Vector2(-0.36, -0.3), Vector2(0.14, -0.33)])
	var top := PackedVector2Array([Vector2(0.25, -0.12), Vector2(0.25, 0.12), Vector2(0.08, 0.24),
		Vector2(-0.3, 0.22), Vector2(-0.3, -0.22), Vector2(0.08, -0.24)])
	for i in low.size():
		low[i] *= k
		top[i] *= k
	Kit.add(_turn, plate, Kit.loft(low, 0.1, top, 0.1 + 0.3 * k), Vector3.ZERO)
	var roof: float = 0.1 + 0.3 * k
	# Mantlet: the thick plate the gun comes through.
	Kit.add(_turn, dark, Kit.box(Vector3(0.12, 0.2 * k, 0.3 * k)), Vector3(0.35 * k, 0.1 + 0.14 * k, 0.0),
		Vector3(0.0, 0.0, 0.2))
	# Commander's cupola with a hatch, and a flat loader's hatch.
	Kit.add(_turn, dark, Kit.cylinder(0.085 * k, 0.07, 12), Vector3(-0.1 * k, roof + 0.03, 0.1 * k))
	Kit.add(_turn, plate, Kit.cylinder(0.065 * k, 0.02, 12), Vector3(-0.1 * k, roof + 0.075, 0.1 * k))
	Kit.add(_turn, dark, Kit.box(Vector3(0.12 * k, 0.015, 0.1 * k)), Vector3(-0.08 * k, roof + 0.008, -0.1 * k))
	# Stowage: bustle rack at the back and bins on the sides.
	Kit.add(_turn, dark, Kit.box(Vector3(0.12 * k, 0.13 * k, 0.42 * k)), Vector3(-0.4 * k, 0.1 + 0.13 * k, 0.0))
	for side in [-1.0, 1.0]:
		Kit.add(_turn, plate, Kit.box(Vector3(0.24 * k, 0.07 * k, 0.05)), Vector3(-0.12 * k, 0.1 + 0.1 * k, side * 0.325 * k),
			Vector3(side * -0.25, 0.0, 0.0))
		Kit.add(_turn, Mat.steel(), Kit.cylinder(0.02, 0.07, 6), Vector3(0.2 * k, 0.1 + 0.2 * k, side * 0.27 * k),
			Vector3(0.0, 0.0, -1.2))
	Kit.add(_turn, Mat.steel(), Kit.cylinder(0.008, 0.6, 5), Vector3(-0.27 * k, roof + 0.3, -0.16 * k))


func _build_turret(plate: Material, dark: Material) -> void:
	# Round concrete drum, weathered, with a ring of sandbags on its rim and
	# a few more heaped at the foot.
	Kit.add(_fixed, Mat.concrete(), Kit.cone(0.62, 0.57, 0.1, 20), Vector3(0.0, 0.05, 0.0))
	Kit.add(_fixed, Mat.concrete(), Kit.cone(0.53, 0.5, 0.38, 20), Vector3(0.0, 0.27, 0.0))
	Kit.add(_fixed, dark, Kit.cylinder(0.31, 0.03, 16), Vector3(0.0, 0.465, 0.0))
	Kit.bag_ring(_fixed, _bags(), 0.43, 0.46, 2, PI * 0.5, 0.9)
	Kit.bag_ring(_fixed, _bags(), 0.66, 0.02, 1, -PI * 0.5, 2.6)
	_head.position = Vector3(0.0, 0.5, 0.0)
	_armour(plate, dark, 1.0)
	_gun.position = Vector3(0.36, 0.25, 0.0)
	_barrel(plate, dark, 0.95, 0.055)


func _build_guard(plate: Material, dark: Material) -> void:
	# A sloped eight-sided armoured bunker with buttresses, and a heavy
	# twin-gun turret on top.
	Kit.add(_fixed, Mat.concrete(), Kit.cone(0.92, 0.88, 0.08, 8), Vector3(0.0, 0.04, 0.0), Vector3(0.0, PI / 8.0, 0.0))
	Kit.add(_fixed, plate, Kit.loft(Kit.ngon(0.84, 8, PI / 8.0), 0.06, Kit.ngon(0.58, 8, PI / 8.0), 0.46), Vector3.ZERO)
	for i in 4:
		var a: float = PI * 0.25 + i * PI * 0.5
		Kit.add(_fixed, dark, Kit.loft(Kit.rect(0.2, 0.15), 0.0, Kit.rect(0.1, 0.13, Vector2(-0.08, 0.0)), 0.34),
			Vector3(cos(a) * 0.72, 0.04, sin(a) * 0.72), Vector3(0.0, -a, 0.0))
		# Firing slit on each flat face.
		var f: float = i * PI * 0.5
		Kit.add(_fixed, Mat.steel(), Kit.box(Vector3(0.03, 0.05, 0.26)), Vector3(cos(f) * 0.69, 0.27, sin(f) * 0.69),
			Vector3(0.0, -f, 0.6))
	Kit.add(_fixed, dark, Kit.cylinder(0.5, 0.05, 16), Vector3(0.0, 0.47, 0.0))
	_head.position = Vector3(0.0, 0.5, 0.0)
	_armour(plate, dark, 1.28)
	Kit.add(_turn, Mat.steel(), Kit.cylinder(0.008, 0.75, 5), Vector3(-0.3, 0.86, 0.26))
	_gun.position = Vector3(0.46, 0.3, 0.0)
	for side in [-1.0, 1.0]:
		_barrel(plate, dark, 1.05, 0.045, side * 0.14)


func _build_artillery(plate: Material, dark: Material) -> void:
	# Round concrete firing pad with a steel turning ring, ready shells and
	# ammunition boxes on it.
	Kit.add(_fixed, Mat.concrete(), Kit.cone(0.8, 0.77, 0.1, 24), Vector3(0.0, 0.05, 0.0))
	Kit.add(_fixed, dark, Kit.cylinder(0.46, 0.02, 20), Vector3(0.0, 0.105, 0.0))
	var brass: Material = Mat.surface("brass", Color(0.62, 0.48, 0.22), 0.45, 0.8, 3.0)
	for i in 6:
		Kit.add(_fixed, brass, Kit.cylinder(0.032, 0.17, 8), Vector3(-0.6 + (i % 3) * 0.075, 0.185, -0.36 - (i / 3) * 0.075))
		Kit.add(_fixed, dark, Kit.cone(0.032, 0.008, 0.07, 8), Vector3(-0.6 + (i % 3) * 0.075, 0.305, -0.36 - (i / 3) * 0.075))
	var crate: Material = Mat.built("wood_crate", 2.5)
	if crate != null:
		Kit.add(_fixed, crate, Kit.box(Vector3(0.24, 0.13, 0.15)), Vector3(-0.52, 0.165, 0.42), Vector3(0.0, 0.5, 0.0))
		Kit.add(_fixed, crate, Kit.box(Vector3(0.22, 0.12, 0.14)), Vector3(-0.5, 0.29, 0.44), Vector3(0.0, 0.3, 0.0))
	Kit.bag_ring(_fixed, _bags(), 0.86, 0.0, 2, 0.0, 4.2)
	_head.position = Vector3(0.0, 0.11, 0.0)
	Kit.add(_turn, dark, Kit.cylinder(0.34, 0.05, 16), Vector3(0.0, 0.025, 0.0))
	Kit.add(_turn, Mat.steel(), Kit.cone(0.17, 0.12, 0.2, 12), Vector3(0.0, 0.15, 0.0))
	# Cradle between two trunnion cheeks.
	for side in [-1.0, 1.0]:
		Kit.add(_turn, plate, Kit.loft(Kit.rect(0.2, 0.02), 0.0, Kit.rect(0.09, 0.02, Vector2(0.03, 0.0)), 0.28),
			Vector3(0.0, 0.2, side * 0.11))
		# Gun shield: an angled plate either side of the barrel.
		Kit.add(_turn, plate, Kit.box(Vector3(0.035, 0.52, 0.3)), Vector3(0.24, 0.43, side * 0.25),
			Vector3(0.0, side * -0.22, 0.28))
		# Trails spread behind, the way a field gun is braced.
		Kit.beam(_turn, dark, Vector3(-0.1, 0.1, side * 0.1), Vector3(-0.72, 0.03, side * 0.34), 0.05)
		Kit.add(_turn, Mat.steel(), Kit.box(Vector3(0.1, 0.03, 0.16)), Vector3(-0.74, 0.02, side * 0.35))
		# Hand wheels.
		Kit.add(_turn, Mat.steel(), Kit.cylinder(0.05, 0.012, 10), Vector3(-0.02, 0.36, side * 0.15), Vector3(PI * 0.5, 0.0, 0.0))
	Kit.add(_turn, plate, Kit.box(Vector3(0.035, 0.12, 0.26)), Vector3(0.31, 0.66, 0.0), Vector3(0.0, 0.0, 0.28))
	Kit.add(_turn, dark, Kit.box(Vector3(0.12, 0.03, 0.12)), Vector3(-0.28, 0.2, 0.2))
	_gun.position = Vector3(0.05, 0.42, 0.0)
	_gun.rotation.z = deg_to_rad(38.0)
	Kit.add(_tube, dark, Kit.box(Vector3(0.24, 0.15, 0.15)), Vector3(-0.08, 0.0, 0.0))
	Kit.add(_tube, plate, Kit.box(Vector3(0.6, 0.07, 0.11)), Vector3(0.28, -0.07, 0.0))
	for up in [-1.0, 1.0]:
		Kit.add(_tube, plate, Kit.cylinder(0.028, 0.5, 8), Vector3(0.3, up * 0.085, 0.0), ALONG_X)
	Kit.add(_tube, Mat.steel(), Kit.cylinder(0.048, 1.55, 12), Vector3(0.75, 0.0, 0.0), ALONG_X)
	Kit.add(_tube, plate, Kit.cylinder(0.062, 0.5, 12), Vector3(0.3, 0.0, 0.0), ALONG_X)
	Kit.add(_tube, dark, Kit.box(Vector3(0.16, 0.1, 0.13)), Vector3(1.5, 0.0, 0.0))
	Kit.add(_tube, Mat.steel(), Kit.box(Vector3(0.03, 0.115, 0.15)), Vector3(1.46, 0.0, 0.0))
	Kit.add(_tube, Mat.steel(), Kit.box(Vector3(0.03, 0.115, 0.15)), Vector3(1.54, 0.0, 0.0))


func _build_tower(plate: Material, dark: Material, ours: bool) -> void:
	# Painted steel lattice: four legs leaning in, a ring of girders at each
	# level and crossed braces in every bay.
	var iron: Material = Mat.surface("lattice_ours", Color(0.6, 0.53, 0.4), 0.7, 0.35, 3.0) if ours \
		else Mat.surface("lattice_theirs", Color(0.27, 0.2, 0.19), 0.7, 0.45, 3.0)
	Kit.add(_fixed, Mat.concrete(), Kit.box(Vector3(0.94, 0.1, 0.94)), Vector3(0.0, 0.04, 0.0))
	var top_y := 2.0
	var corners: Array = [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for c in corners:
		Kit.beam(_fixed, iron, Vector3(c.x * 0.37, 0.05, c.y * 0.37), Vector3(c.x * 0.25, top_y, c.y * 0.25), 0.045)
		Kit.add(_fixed, dark, Kit.box(Vector3(0.12, 0.03, 0.12)), Vector3(c.x * 0.37, 0.1, c.y * 0.37))
	var levels := 5
	for level in levels:
		var y0: float = 0.1 + (top_y - 0.1) * level / levels
		var y1: float = 0.1 + (top_y - 0.1) * (level + 1) / levels
		var w0: float = lerpf(0.37, 0.25, (y0 - 0.05) / (top_y - 0.05))
		var w1: float = lerpf(0.37, 0.25, (y1 - 0.05) / (top_y - 0.05))
		for i in 4:
			var a: Vector2 = corners[i]
			var b: Vector2 = corners[(i + 1) % 4]
			Kit.beam(_fixed, iron, Vector3(a.x * w1, y1, a.y * w1), Vector3(b.x * w1, y1, b.y * w1), 0.026)
			Kit.beam(_fixed, iron, Vector3(a.x * w0, y0, a.y * w0), Vector3(b.x * w1, y1, b.y * w1), 0.02)
			Kit.beam(_fixed, iron, Vector3(b.x * w0, y0, b.y * w0), Vector3(a.x * w1, y1, a.y * w1), 0.02)
	# Ladder up one side.
	for side in [-1.0, 1.0]:
		Kit.beam(_fixed, iron, Vector3(0.43, 0.08, side * 0.07), Vector3(0.31, top_y, side * 0.07), 0.016)
	for i in 14:
		var t: float = (i + 0.5) / 14.0
		Kit.beam(_fixed, iron, Vector3(lerpf(0.43, 0.31, t), lerpf(0.08, top_y, t), -0.07),
			Vector3(lerpf(0.43, 0.31, t), lerpf(0.08, top_y, t), 0.07), 0.012)
	# Deck with a railing all round.
	Kit.add(_fixed, dark, Kit.box(Vector3(0.9, 0.04, 0.9)), Vector3(0.0, top_y + 0.02, 0.0))
	for i in 4:
		var a2: Vector2 = corners[i] * 0.43
		var b2: Vector2 = corners[(i + 1) % 4] * 0.43
		for h in [0.13, 0.24]:
			Kit.beam(_fixed, iron, Vector3(a2.x, top_y + h, a2.y), Vector3(b2.x, top_y + h, b2.y), 0.014)
		for j in 3:
			var q: Vector2 = a2.lerp(b2, j / 3.0)
			Kit.beam(_fixed, iron, Vector3(q.x, top_y + 0.03, q.y), Vector3(q.x, top_y + 0.24, q.y), 0.016)
	# Cabin: plated walls, a band of dark windows, a roof with an overhang.
	var glass: Material = Mat.surface("glass", Color(0.06, 0.09, 0.1), 0.12, 0.7, 3.0)
	Kit.add(_fixed, plate, Kit.box(Vector3(0.54, 0.4, 0.54)), Vector3(0.0, top_y + 0.24, 0.0))
	Kit.add(_fixed, glass, Kit.box(Vector3(0.55, 0.1, 0.46)), Vector3(0.0, top_y + 0.3, 0.0))
	Kit.add(_fixed, glass, Kit.box(Vector3(0.46, 0.1, 0.55)), Vector3(0.0, top_y + 0.3, 0.0))
	Kit.add(_fixed, dark, Kit.box(Vector3(0.7, 0.035, 0.7)), Vector3(0.0, top_y + 0.455, 0.0))
	# On the roof: whip aerial, a searchlight, and the turning radar dish.
	var roof: float = top_y + 0.47
	Kit.add(_fixed, Mat.steel(), Kit.cylinder(0.008, 0.7, 5), Vector3(-0.28, roof + 0.35, -0.28))
	Kit.add(_fixed, Mat.steel(), Kit.cylinder(0.012, 0.1, 6), Vector3(0.24, roof + 0.05, 0.24))
	Kit.add(_fixed, dark, Kit.cylinder(0.06, 0.09, 12), Vector3(0.24, roof + 0.13, 0.24), Vector3(0.0, -0.8, -PI * 0.5 + 0.2))
	_head.position = Vector3(0.0, roof, 0.0)
	Kit.add(_turn, Mat.steel(), Kit.cylinder(0.02, 0.2, 6), Vector3(0.0, 0.1, 0.0))
	Kit.add(_turn, plate, Kit.cone(0.03, 0.21, 0.07, 16), Vector3(0.05, 0.24, 0.0), Vector3(0.0, 0.0, -PI * 0.5 + 0.35))
	Kit.beam(_turn, Mat.steel(), Vector3(0.05, 0.24, 0.0), Vector3(0.2, 0.3, 0.0), 0.012)
	_lamp = Kit.part(self, Kit.cylinder(0.035, 0.05, 8), Mat.glow("lamp_idle", Color(0.3, 1.0, 0.4), 1.5),
		Vector3(-0.28, roof + 0.03, 0.28))


func _process(delta: float) -> void:
	if _dead or not is_instance_valid(source):
		return
	_clock += delta
	if not source.alive:
		_dead = true
		_smoke.emitting = true
		_bar.visible = false
		for part in _parts:
			part.material_override = Mat.charred()
		if _lamp != null:
			_lamp.visible = false
		# The head slumps where it was hit.
		_head.rotation.z = randf_range(-0.2, 0.2)
		_head.rotation.x = randf_range(-0.12, 0.12)
		if source.kind == "tower":
			_head.visible = false
		return
	if source.kind == "tower":
		_head.rotate_y(delta * 1.4)
		var alert: bool = source.spotting
		_lamp.material_override = Mat.glow("lamp_alert", Color(1.0, 0.15, 0.1), 3.0) if alert \
			and fmod(_clock, 0.5) < 0.3 else Mat.glow("lamp_idle", Color(0.3, 1.0, 0.4), 1.5)
	else:
		_head.rotation.y = -float(source.aim_angle)
		_gun.position.x = _gun_x - 0.12 * float(source.kick)
	_smoke.emitting = source.hp * 2 <= source.max_hp
	Bar.update(_bar, source.hp, source.max_hp,
		Bar.SHIELDED if source.shielded() else Bar.color_for(source.team, false))
