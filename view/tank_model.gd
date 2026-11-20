extends Node3D
## A battle tank built from separate moving parts: hull, two rolling tracks,
## road wheels and sprockets that spin, a turret that turns and a gun that
## recoils. It mirrors a 2D game tank (`source`) every frame. Forward is +X.
## Small fixed details are merged into a few meshes and shared by all tanks,
## so a detailed tank stays cheap to draw.

const Mat := preload("res://view/materials.gd")
const Kit := preload("res://view/mesh_kit.gd")
const Fx := preload("res://fx/fx.gd")
const Terrain := preload("res://view/terrain.gd")
const Sfx := preload("res://fx/sfx.gd")
const Bar := preload("res://view/health_bar.gd")
const Designs := preload("res://view/tank_designs.gd")

const S := 1.0 / 48.0
const WHEEL_RADIUS := 0.075
const ALONG_X := Vector3(0.0, 0.0, -PI * 0.5)
const ALONG_Z := Vector3(PI * 0.5, 0.0, 0.0)
## A wreck burns for BURN_TIME, smokes on, and is gone after WRECK_TIME.
const WRECK_TIME := 60.0
const BURN_TIME := 32.0
const MARK_SPACING := 0.25
const LINK_LEN := 0.11
const WHEEL_Y := 0.07
## Suspension travel of a road wheel, down and up.
const WHEEL_DROP := 0.03
const WHEEL_RISE := 0.05
## Hull springs: stiffness and damping. Lower stiffness = softer, lazier rock.
## How far under the surface a tank's tracks go in deep water (model units)
## and how far the gun lifts (radians) to keep the muzzle out.
const SINK := 0.56
const GUN_LIFT := 0.3
const SPRING := 85.0
const DAMP := 8.5

## Lamps on every tank: white head lamps on ours, red ones on the enemy's.
## Shared materials, so night_lamps() brightens all of them at once.
static var _lamp_ours: StandardMaterial3D
static var _lamp_foe: StandardMaterial3D
## Parts every design shares, and the finished part sets per design.
static var _base: Dictionary = {}
static var _geos: Dictionary = {}
## This tank's own part set.
var _geo: Dictionary = {}
var _gun_x := 0.27
var _beam: SpotLight3D

var source
var _turret: Node3D
var _dome: MeshInstance3D
var _gun: Node3D
var _flash: MeshInstance3D
var _wheels: Array[MeshInstance3D] = []
var _track_mat: StandardMaterial3D
var _dust: Array[CPUParticles3D] = []
var _smoke: CPUParticles3D
var _flame: CPUParticles3D
var _last := Vector3.ZERO
var _time := 0.0
var _wreck := -1.0
var _bar: MeshInstance3D
var _mark_run := 0.0
var _ripple_run := 0.0
var _wading := false
var _wake: Array[CPUParticles3D] = []
var _spray: CPUParticles3D
var _glow: OmniLight3D
## Parts that get shot off as the tank takes damage: skirts, antennas, basket.
var _loose: Array[Node3D] = []
var _loose_total: int = 0
var _paint_parts: Array[MeshInstance3D] = []
var _dark_parts: Array[MeshInstance3D] = []
var _hp_shown: int = 0
var _stage: int = 0
## Sprung mass: hull and turret ride on the running gear and rock on springs.
var _body: Node3D
## Road wheels per side, front to back order along x: [wheel, x, z].
var _road: Array = []
## Lower track stretches per side: 8 each, in the same order as _road.
var _links: Array = []
var _pitch := 0.0
var _pitch_v := 0.0
var _roll := 0.0
var _roll_v := 0.0
var _heave := 0.0
var _heave_v := 0.0
var _speed := 0.0
var _climb := 0.0
var _last_y := 0.0
var _last_recoil := 0.0
## Engine at idle, engine under load, track clatter, and fire once wrecked.
var _snd_idle: AudioStreamPlayer3D
var _snd_move: AudioStreamPlayer3D
var _snd_tracks: AudioStreamPlayer3D
var _snd_fire: AudioStreamPlayer3D
var _snd_broken: AudioStreamPlayer3D
## Your own tank sits right at your ears, so it is turned down to stay
## under the battle.
var _own := 0.0


## Builds the shared part meshes once. Shapes follow the reference picture:
## sloped glacis with grilles, front mudguards, five skirt plates a side,
## seven road wheels, faceted turret with rear basket, gun station, round
## sight, three antennas, and a long gun with fume extractor and a
## three-ring muzzle brake.
static func _build_geo() -> void:
	var hp: Array = []  # hull, painted
	var hd: Array = []  # hull, darker paint
	var hs: Array = []  # hull, bare steel
	Kit.put(hp, Kit.prism(PackedVector2Array([
		Vector2(-0.46, 0.12), Vector2(0.40, 0.12), Vector2(0.49, 0.2),
		Vector2(0.49, 0.24), Vector2(-0.48, 0.24), Vector2(-0.49, 0.18)]), 0.42), Vector3.ZERO)
	Kit.put(hp, Kit.loft(
		PackedVector2Array([Vector2(-0.49, -0.33), Vector2(0.40, -0.33), Vector2(0.5, -0.25),
			Vector2(0.5, 0.25), Vector2(0.40, 0.33), Vector2(-0.49, 0.33)]), 0.24,
		PackedVector2Array([Vector2(-0.46, -0.28), Vector2(0.2, -0.28), Vector2(0.27, -0.2),
			Vector2(0.27, 0.2), Vector2(0.2, 0.28), Vector2(-0.46, 0.28)]), 0.34), Vector3.ZERO)
	# Raised engine deck at the rear with louvred grilles.
	Kit.put(hp, Kit.box(Vector3(0.3, 0.03, 0.5)), Vector3(-0.3, 0.35, 0.0))
	for x in [-0.42, -0.385, -0.35, -0.315, -0.28, -0.245, -0.21]:
		Kit.put(hs, Kit.box(Vector3(0.016, 0.012, 0.2)), Vector3(x, 0.37, 0.13))
		Kit.put(hs, Kit.box(Vector3(0.016, 0.012, 0.2)), Vector3(x, 0.37, -0.13))
	# Glacis: grille panel, driver hatch, tow bar.
	Kit.put(hs, Kit.box(Vector3(0.13, 0.01, 0.16)), Vector3(0.38, 0.297, -0.08), Vector3(0, 0, -0.41))
	Kit.put(hd, Kit.box(Vector3(0.09, 0.02, 0.1)), Vector3(0.22, 0.345, 0.1))
	Kit.put(hs, Kit.cylinder(0.008, 0.34, 6), Vector3(0.5, 0.2, 0.0), ALONG_Z)
	for side in [-1.0, 1.0]:
		# Front mudguards curving down over the tracks.
		Kit.put(hd, Kit.box(Vector3(0.13, 0.025, 0.15)), Vector3(0.45, 0.225, 0.262 * side),
			Vector3(0, 0, -0.55))
		Kit.put(hd, Kit.box(Vector3(0.03, 0.09, 0.15)), Vector3(0.505, 0.16, 0.262 * side))
		Kit.put(hs, Kit.cylinder(0.022, 0.03, 8), Vector3(0.47, 0.275, 0.2 * side), ALONG_X)
		Kit.put(hd, Kit.box(Vector3(0.05, 0.05, 0.06)), Vector3(0.45, 0.275, 0.2 * side))
		Kit.put(hs, Kit.box(Vector3(0.035, 0.04, 0.025)), Vector3(0.5, 0.165, 0.12 * side))
		Kit.put(hs, Kit.cylinder(0.02, 0.08, 8), Vector3(-0.5, 0.2, 0.1 * side), ALONG_X)
		Kit.put(hd, Kit.box(Vector3(0.2, 0.05, 0.05)), Vector3(-0.05, 0.335, 0.3 * side))
		Kit.put(hd, Kit.box(Vector3(0.06, 0.1, 0.16)), Vector3(-0.51, 0.27, 0.19 * side))

	var tracks: Array = []
	var belt := Kit.prism(PackedVector2Array([
		Vector2(-0.40, 0.06), Vector2(0.34, 0.06), Vector2(0.48, 0.11),
		Vector2(0.45, 0.21), Vector2(-0.46, 0.21), Vector2(-0.51, 0.11)]), 0.13)
	Kit.put(tracks, belt, Vector3(0.0, 0.0, 0.265))
	Kit.put(tracks, belt, Vector3(0.0, 0.0, -0.265))

	# Road wheel: tyre, dished hub, bolt ring. Bolts make the spin visible.
	var wheel: Array = []
	var tyre: Array = []
	Kit.put(tyre, Kit.cylinder(WHEEL_RADIUS, 0.035, 18), Vector3.ZERO)
	Kit.put(wheel, Kit.cylinder(WHEEL_RADIUS - 0.024, 0.04, 16), Vector3.ZERO)
	Kit.put(wheel, Kit.cylinder(0.042, 0.047, 12), Vector3.ZERO)
	Kit.put(wheel, Kit.cylinder(0.016, 0.06, 8), Vector3.ZERO)
	for i in 6:
		var a: float = TAU * i / 6.0
		Kit.put(wheel, Kit.cylinder(0.006, 0.052, 5), Vector3(cos(a) * 0.03, 0.0, sin(a) * 0.03))
	# Browser: the tyre is part of the wheel itself, one draw call less per
	# wheel (draw calls are what the browser renderer pays most for).
	if OS.has_feature("web"):
		wheel.append_array(tyre)

	# Side skirt plate with two bolts, and a whip antenna standing on its base.
	var skirt: Array = []
	Kit.put(skirt, Kit.box(Vector3(0.168, 0.12, 0.018)), Vector3.ZERO)
	Kit.put(skirt, Kit.box(Vector3(0.012, 0.012, 0.024)), Vector3(-0.06, 0.04, 0.0))
	Kit.put(skirt, Kit.box(Vector3(0.012, 0.012, 0.024)), Vector3(0.06, 0.04, 0.0))
	var antenna: Array = []
	Kit.put(antenna, Kit.cylinder(0.005, 1.0, 5), Vector3(0.0, 0.5, 0.0))
	var scrap: Array = []
	# Torn armour plate: a ragged outline with a bent-up corner.
	Kit.put(scrap, Kit.prism(PackedVector2Array([Vector2(-0.07, -0.04), Vector2(0.03, -0.055),
		Vector2(0.08, -0.01), Vector2(0.05, 0.05), Vector2(-0.04, 0.04)]), 0.012), Vector3.ZERO)
	Kit.put(scrap, Kit.prism(PackedVector2Array([Vector2(0.0, -0.03), Vector2(0.06, -0.02),
		Vector2(0.04, 0.03)]), 0.012), Vector3(0.05, 0.0, 0.02), Vector3(0.0, 0.7, 0.0))

	# One stretch of the lower track run. Each stretch hangs between two
	# wheels and follows them, so the track flexes over the ground.
	var link: Array = []
	Kit.put(link, Kit.box(Vector3(LINK_LEN, 0.022, 0.13)), Vector3.ZERO)

	_base = {
		"link": Kit.merge(link),
		"hull_paint": Kit.merge(hp), "hull_dark": Kit.merge(hd), "hull_steel": Kit.merge(hs),
		"tracks": Kit.merge(tracks), "wheel": Kit.merge(wheel), "tyre": Kit.merge(tyre),
		"skirt": Kit.merge(skirt), "antenna": Kit.merge(antenna), "scrap": Kit.merge(scrap),
	}


static func _pts(list: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in list:
		out.append(Vector2(p[0], p[1]))
	return out


## The parts that differ from one tank design to the next: turret, gun and
## a few hull fittings. Design numbers follow Cfg.TANKS. The shapes are
## our own, each in the manner of one country's modern tanks:
##   0 all-round desert tank     1 American: wide slab turret, long bustle
##   2 Russian: low round turret with armour bricks, fuel drums
##   3 German: arrow-head turret, very long gun
##   4 Israeli: engine in front, turret set back, long low wedge
##   5 Indian: tall square turret, thick gun sleeve
##   6 Korean: sharp angled turret, long gun, slat racks
static func _model_geo(m: int) -> Dictionary:
	if _geos.has(m):
		return _geos[m]
	if _base.is_empty():
		_build_geo()
	if m >= 1:
		# The detailed designs have their own builder.
		_geos[m] = Designs.build(m, _base)
		return _geos[m]
	var tp: Array = []
	var td: Array = []
	var ts: Array = []
	var gp: Array = []
	var gs: Array = []
	var bd: Array = []
	var bs: Array = []
	var he: Array = []  # hull extras, darker paint
	# Turret outline at the ring and at the roof, roof height, half width
	# at the sides, where the turret sits, where the gun pivots, barrel
	# length, where the fume extractor sits, muzzle brake or not, basket.
	var low: PackedVector2Array
	var top: PackedVector2Array
	var h := 0.15
	var half := 0.2
	var tx := -0.04
	var gx := 0.27
	var barrel := 0.6
	var fume := 0.38
	var brake := true
	var basket := true
	var bx := 0.0
	low = _pts([[-0.26, -0.2], [0.12, -0.22], [0.33, -0.11], [0.33, 0.11], [0.12, 0.22], [-0.26, 0.2]])
	top = _pts([[-0.22, -0.16], [0.05, -0.17], [0.14, -0.08], [0.14, 0.08], [0.05, 0.17], [-0.22, 0.16]])
	Kit.put(tp, Kit.loft(low, 0.0, top, h), Vector3.ZERO)
	# Rear stowage basket: a box of kit behind rails. Its own part, so it
	# can be shot off.
	if basket:
		Kit.put(bd, Kit.box(Vector3(0.13, 0.08, 0.3)), Vector3(-0.33 + bx, 0.07, 0.0))
		for y in [0.03, 0.075, 0.12]:
			Kit.put(bs, Kit.box(Vector3(0.15, 0.008, 0.33)), Vector3(-0.335 + bx, y, 0.0))
		for z in [-0.165, -0.055, 0.055, 0.165]:
			Kit.put(bs, Kit.box(Vector3(0.008, 0.1, 0.008)), Vector3(-0.405 + bx, 0.075, z))
	# Roof: hatches, round sight on a pedestal, remote gun station.
	var dy: float = h - 0.15
	Kit.put(td, Kit.cylinder(0.055, 0.03, 12), Vector3(-0.08, 0.165 + dy, 0.085))
	Kit.put(td, Kit.cylinder(0.045, 0.016, 12), Vector3(-0.08, 0.158 + dy, -0.085))
	Kit.put(td, Kit.box(Vector3(0.06, 0.03, 0.07)), Vector3(0.04, 0.165 + dy, 0.1))
	Kit.put(tp, Kit.cylinder(0.045, 0.022, 14), Vector3(0.04, 0.225 + dy, 0.1), ALONG_X)
	Kit.put(td, Kit.box(Vector3(0.05, 0.035, 0.05)), Vector3(0.02, 0.167 + dy, -0.07))
	Kit.put(tp, Kit.box(Vector3(0.05, 0.045, 0.07)), Vector3(0.02, 0.205 + dy, -0.07))
	Kit.put(ts, Kit.cylinder(0.008, 0.13, 6), Vector3(0.1, 0.215 + dy, -0.07), ALONG_X)
	Kit.put(ts, Kit.box(Vector3(0.04, 0.03, 0.02)), Vector3(0.02, 0.2 + dy, -0.115))
	for side in [-1.0, 1.0]:
		if m != 2:
			Kit.put(td, Kit.box(Vector3(0.1, 0.06, 0.03)), Vector3(-0.06, 0.07, (half + 0.015) * side))
		Kit.put(ts, Kit.cylinder(0.012, 0.03, 6), Vector3(-0.2, 0.16 + dy, 0.14 * side))
		# Smoke launchers.
		for j in 3:
			Kit.put(ts, Kit.cylinder(0.013, 0.05, 6),
				Vector3(0.16 - j * 0.035, 0.09, (half + j * 0.006) * side),
				Vector3(0.0, 0.0, -PI * 0.5 + 0.5))

	# Gun: boxy mantlet, sleeve, long barrel, fume extractor, and on the
	# first design a three-ring muzzle brake.
	Kit.put(gp, Kit.box(Vector3(0.11, 0.11, 0.17)), Vector3(0.0, 0.0, 0.0))
	Kit.put(gp, Kit.cylinder(0.042, 0.13, 12), Vector3(0.1, 0.0, 0.0), ALONG_X)
	Kit.put(gp, Kit.cylinder(0.024, barrel, 12), Vector3(0.12 + barrel * 0.5, 0.0, 0.0), ALONG_X)
	Kit.put(gp, Kit.cylinder(0.037, 0.15, 12), Vector3(fume, 0.0, 0.0), ALONG_X)
	var tip: float = 0.12 + barrel
	if brake:
		Kit.put(gs, Kit.cylinder(0.028, 0.13, 12), Vector3(tip + 0.035, 0.0, 0.0), ALONG_X)
		for x in [-0.005, 0.035, 0.075]:
			Kit.put(gs, Kit.cylinder(0.038, 0.022, 12), Vector3(tip + x, 0.0, 0.0), ALONG_X)
	else:
		# Smooth muzzle with a thin reference collar.
		Kit.put(gs, Kit.cylinder(0.029, 0.03, 12), Vector3(tip - 0.02, 0.0, 0.0), ALONG_X)

	var out: Dictionary = _base.duplicate()
	out.merge({
		"turret_paint": Kit.merge(tp), "turret_dark": Kit.merge(td),
		"turret_steel": Kit.merge(ts), "gun_paint": Kit.merge(gp), "gun_steel": Kit.merge(gs),
		"basket": basket, "hull_extra": Kit.merge(he) if not he.is_empty() else null,
		"hull_extra_paint": null, "hull_extra_steel": null, "wheels": 7,
		"h": h, "tx": tx, "gx": gx, "muzzle": tip + 0.18,
	})
	if basket:
		out["basket_dark"] = Kit.merge(bd)
		out["basket_steel"] = Kit.merge(bs)
	_geos[m] = out
	return out


func setup(tank) -> void:
	source = tank
	_geo = _model_geo(int(tank.model))
	_gun_x = float(_geo["gx"])
	var paint: StandardMaterial3D = Mat.paint(tank.color, 0, tank.skin, tank.wear)
	var dark: StandardMaterial3D = Mat.paint(tank.color.darkened(0.25), 0, tank.skin, tank.wear)
	_track_mat = Mat.track()

	_body = Node3D.new()
	add_child(_body)
	_bar = Bar.make(self, Bar.color_for(tank.team, tank.is_player), 0.95 * tank.size_scale,
		tank.max_hp, 1.05 * tank.size_scale)
	_own = -11.0 if tank.is_player else 0.0
	_snd_idle = Sfx.loop(self, "engine_idle", -12.0 + _own)
	_snd_move = Sfx.loop(self, "engine_move", -60.0)
	_snd_tracks = Sfx.loop(self, "tracks", -60.0)
	_snd_broken = Sfx.loop(self, "engine_broken", -60.0)
	_paint_parts.append(Kit.part(_body, _geo["hull_paint"], paint, Vector3.ZERO))
	_dark_parts.append(Kit.part(_body, _geo["hull_dark"], dark, Vector3.ZERO))
	Kit.part(_body, _geo["hull_steel"], Mat.steel(), Vector3.ZERO)
	if _geo["hull_extra"] != null:
		_dark_parts.append(Kit.part(_body, _geo["hull_extra"], dark, Vector3.ZERO))
	if _geo["hull_extra_paint"] != null:
		_paint_parts.append(Kit.part(_body, _geo["hull_extra_paint"], paint, Vector3.ZERO))
	if _geo["hull_extra_steel"] != null:
		Kit.part(_body, _geo["hull_extra_steel"], Mat.steel(), Vector3.ZERO)
	Kit.part(self, _geo["tracks"], _track_mat, Vector3.ZERO)
	_add_lamps(tank)
	for side in [-1.0, 1.0]:
		for x in [-0.39, -0.215, -0.04, 0.135, 0.31]:
			var plate := Kit.part(_body, _geo["skirt"], paint, Vector3(x, 0.185, 0.337 * side))
			_paint_parts.append(plate)
			_loose.append(plate)
		var row: Array = []
		var stretch: Array = []
		# Five, six or seven road wheels a side, bigger when there are fewer.
		var count: int = int(_geo["wheels"])
		var big: float = {5: 0.96, 6: 0.88}.get(count, 0.8)
		for i in count:
			var wx: float = -0.37 + i * 0.648 / (count - 1)
			_add_wheel(Vector3(wx, WHEEL_Y, 0.333 * side), big, dark)
			row.append([_wheels[-1], wx, 0.3 * side])
		# The lower track run between the wheels; the browser version keeps
		# only the track belt above it, which saves a draw call per stretch.
		for i in (0 if OS.has_feature("web") else count + 1):
			stretch.append(Kit.part(self, _geo["link"], _track_mat, Vector3(0.0, 0.0, 0.265 * side)))
		_road.append(row)
		_links.append(stretch)
		_add_wheel(Vector3(0.41, 0.12, 0.333 * side), 0.7, dark)
		_add_wheel(Vector3(-0.455, 0.12, 0.333 * side), 0.7, dark)
		_dust.append(_emitter(Fx.dust_cfg(10, 0.32), Vector3(-0.52, 0.06, 0.27 * side)))
		_wake.append(_emitter(Fx.wake_cfg(12), Vector3(-0.45, 0.2, 0.27 * side)))
	var drops: Dictionary = Fx.droplet_cfg(18, 2.4)
	drops["one_shot"] = false
	drops["explosive"] = 0.0
	_spray = _emitter(drops, Vector3(0.4, 0.2, 0.0))

	_turret = Node3D.new()
	_turret.position = Vector3(float(_geo["tx"]), 0.34, 0.0)
	_body.add_child(_turret)
	_paint_parts.append(Kit.part(_turret, _geo["turret_paint"], paint, Vector3.ZERO))
	_dark_parts.append(Kit.part(_turret, _geo["turret_dark"], dark, Vector3.ZERO))
	Kit.part(_turret, _geo["turret_steel"], Mat.steel(), Vector3.ZERO)
	if _geo["basket"]:
		var basket := Node3D.new()
		_turret.add_child(basket)
		_dark_parts.append(Kit.part(basket, _geo["basket_dark"], dark, Vector3.ZERO))
		Kit.part(basket, _geo["basket_steel"], Mat.steel(), Vector3.ZERO)
		_loose.append(basket)
	var roof: float = float(_geo["h"]) - 0.005
	for spot in [Vector3(-0.2, roof, 0.14), Vector3(-0.2, roof, -0.14), Vector3(-0.02, roof, -0.15)]:
		var whip := Kit.part(_turret, _geo["antenna"], Mat.steel(), spot)
		whip.scale.y = 0.4 if spot.x > -0.1 else 0.55
		_loose.append(whip)
	_loose.shuffle()
	_loose_total = _loose.size()
	_hp_shown = tank.hp

	_gun = Node3D.new()
	_gun.position = Vector3(_gun_x, 0.075, 0.0)
	_turret.add_child(_gun)
	_paint_parts.append(Kit.part(_gun, _geo["gun_paint"], paint, Vector3.ZERO))
	Kit.part(_gun, _geo["gun_steel"], Mat.steel(), Vector3.ZERO)
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.08
	flash_mesh.height = 0.16
	flash_mesh.radial_segments = 8
	flash_mesh.rings = 4
	_flash = Kit.part(_gun, flash_mesh, Mat.glow("flash", Color(1.0, 0.85, 0.5), 1.6),
		Vector3(float(_geo["muzzle"]), 0.0, 0.0))
	_flash.scale = Vector3(2.2, 0.8, 0.8)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false

	_smoke = _emitter(Fx.smoke_cfg(10, 0.3, 1.8), Vector3(-0.25, 0.4, 0.0))
	_flame = _emitter(Fx.flame_cfg(10, 0.28), Vector3(-0.1, 0.42, 0.0))
	_sync(0.0, true)


## Makes this a model on show in a menu: it stands level at the origin,
## silent, with no health bar, and no longer follows its tank.
func show_only() -> void:
	set_process(false)
	transform = Transform3D.IDENTITY
	_bar.visible = false
	for snd in [_snd_idle, _snd_move, _snd_tracks, _snd_broken]:
		if snd != null:
			snd.autoplay = false
			snd.queue_free()
	for p in _dust + _wake + [_spray, _smoke, _flame]:
		p.emitting = false


## Turns the turret of a model on show.
func aim_show(angle: float) -> void:
	_turret.rotation.y = angle


static func _lamp_mats() -> void:
	if _lamp_ours != null:
		return
	_lamp_ours = StandardMaterial3D.new()
	_lamp_ours.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp_ours.albedo_color = Color(0.5, 0.5, 0.45)
	_lamp_foe = _lamp_ours.duplicate()
	_lamp_foe.albedo_color = Color(0.4, 0.12, 0.1)


## THE SHIFT: lamps are dull by day and bright at night.
static func night_lamps(n: float) -> void:
	_lamp_mats()
	_lamp_ours.albedo_color = Color(0.5, 0.5, 0.45).lerp(Color(3.0, 2.9, 2.5), n)
	_lamp_foe.albedo_color = Color(0.4, 0.12, 0.1).lerp(Color(3.2, 0.35, 0.2), n)


## Two head lamps on the hull front; on our own tanks a real beam of light
## at night (only on the player's tank on the lowest graphics).
func _add_lamps(tank) -> void:
	_lamp_mats()
	var ours: bool = tank.team == Cfg.TEAM_PLAYER
	var lens := BoxMesh.new()
	lens.size = Vector3(0.02, 0.035, 0.05)
	for side in [-1.0, 1.0]:
		var lamp := MeshInstance3D.new()
		lamp.mesh = lens
		lamp.material_override = _lamp_ours if ours else _lamp_foe
		lamp.position = Vector3(0.5, 0.235, 0.2 * side)
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body.add_child(lamp)
	if ours and (tank.is_player or (int(Cfg.gfx["shadows"]) >= 2 and Cfg.small_lights)) and not tank.display:
		_beam = SpotLight3D.new()
		_beam.light_color = Color(1.0, 0.95, 0.85)
		_beam.spot_range = 9.0
		_beam.spot_angle = 34.0
		_beam.spot_attenuation = 0.8
		_beam.position = Vector3(0.52, 0.3, 0.0)
		# A spot light shines down its -Z: turn it to face forward (+X), a
		# little down at the ground.
		_beam.rotation = Vector3(0.0, -PI * 0.5, 0.0)
		_beam.rotate_object_local(Vector3.RIGHT, -0.22)
		_beam.visible = false
		_body.add_child(_beam)


func _add_wheel(pos: Vector3, size: float, material: Material) -> void:
	var w := Kit.part(self, _geo["wheel"], material, pos, ALONG_Z)
	w.scale = Vector3(size, 1.0, size)
	# The rubber tyre round the painted wheel disc (in the browser it is
	# already part of the wheel).
	if not OS.has_feature("web"):
		Kit.part(w, _geo["tyre"], Mat.surface("rubber", Color(0.06, 0.06, 0.065), 0.95, 0.0, 3.0), Vector3.ZERO)
	w.set_meta("radius", WHEEL_RADIUS * size)
	_wheels.append(w)


func _emitter(cfg: Dictionary, pos: Vector3) -> CPUParticles3D:
	var p := Fx.make(cfg)
	p.position = pos
	p.local_coords = false
	p.emitting = false
	add_child(p)
	return p


func _process(delta: float) -> void:
	if _wreck >= 0.0:
		_wreck += delta
		var burning: bool = _wreck < BURN_TIME
		if _snd_fire != null:
			_snd_fire.volume_db = move_toward(_snd_fire.volume_db,
				(-6.0 + Sfx.fall(global_position)) if burning else -60.0, delta * 40.0)
		_flame.emitting = burning
		_smoke.emitting = _wreck < WRECK_TIME - 5.0
		# Firelight flickering on the sand around the wreck.
		var light: float = 0.0
		if burning:
			light = 1.2 + 0.5 * sin(_wreck * 23.0) * sin(_wreck * 7.3)
		_glow.light_energy = move_toward(_glow.light_energy, light, delta * 5.0)
		if _wreck > WRECK_TIME - 3.0:
			position.y -= delta * 0.25
		if _wreck > WRECK_TIME:
			queue_free()
		return
	if not is_instance_valid(source) or not source.alive:
		_become_wreck()
		return
	_sync(delta, false)


## The tank was destroyed: leave a burnt-out hull that smokes for a while.
func _become_wreck() -> void:
	_wreck = 0.0
	if _beam != null:
		_beam.queue_free()
		_beam = null
	_bar.visible = false
	visible = true
	_flash.visible = false
	for d in _dust:
		d.emitting = false
	for w in _wake:
		w.emitting = false
	_spray.emitting = false
	for snd in [_snd_idle, _snd_move, _snd_tracks, _snd_broken]:
		if snd != null:
			snd.stop()
	_snd_fire = Sfx.loop(self, "fire_loop", -6.0)
	# A bigger fire and a taller smoke column than a damaged tank has.
	_flame.queue_free()
	_smoke.queue_free()
	_flame = _emitter(Fx.flame_cfg(18, 0.42), Vector3(-0.1, 0.4, 0.0))
	_smoke = _emitter(Fx.smoke_cfg(18, 0.5, 3.2), Vector3(-0.15, 0.6, 0.0))
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.55, 0.2)
	_glow.light_energy = 1.4
	_glow.omni_range = 4.0
	_glow.position = Vector3(0.0, 0.7, 0.0)
	_glow.visible = Cfg.small_lights
	add_child(_glow)
	_burn(self)
	_break_up()


## Tears the dead tank apart: plates, antennas and wheels fly off, the gun
## droops, the hull slumps, and the turret is either blown clean off or left
## hanging askew. Everything lands and stays as wreckage.
func _break_up() -> void:
	var view = get_parent()
	for part in _loose:
		if randf() < 0.7:
			_throw(part, 1.3, WRECK_TIME)
		else:
			part.rotation += Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.4, 0.4))
	_loose.clear()
	_wheels.shuffle()
	for i in randi_range(2, 5):
		_throw(_wheels.pop_back(), 1.0, WRECK_TIME, true)
	_gun.rotation.z = randf_range(-0.42, -0.2)
	_gun.position.x = _gun_x - 0.07
	rotate_object_local(Vector3.RIGHT, randf_range(-0.12, 0.12))
	rotate_object_local(Vector3.BACK, randf_range(-0.07, 0.07))
	position.y -= 0.025
	if randf() < 0.55 and view != null:
		# Ammunition goes up: the whole turret is thrown off and lands nearby.
		var k: float = _turret.global_transform.basis.get_scale().x
		var xf: Transform3D = _turret.global_transform
		_turret.get_parent().remove_child(_turret)
		var flip: bool = randf() < 0.5
		var rest := Vector3(PI + randf_range(-0.15, 0.15) if flip else randf_range(0.15, 0.3),
			randf() * TAU, randf_range(-0.2, 0.2))
		var away := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
		view.add_debris(_turret, xf, away * randf_range(1.2, 2.4) + Vector3.UP * randf_range(4.5, 6.5),
			WRECK_TIME, rest, (0.17 if flip else 0.03) * k)
	else:
		_turret.rotation = Vector3(randf_range(0.1, 0.22), _turret.rotation.y + randf_range(-0.9, 0.9),
			randf_range(-0.16, 0.16))
		_turret.position += Vector3(randf_range(-0.07, 0.07), 0.02, randf_range(-0.08, 0.08))
	if view == null:
		return
	# Torn plate and scrap scattered around the hull.
	for i in 6:
		var chunk := MeshInstance3D.new()
		chunk.mesh = _geo["scrap"]
		chunk.material_override = Mat.charred()
		var size: float = randf_range(0.5, 1.2)
		var xf := Transform3D(Basis.IDENTITY.scaled(Vector3(size, size, size)),
			global_position + Vector3(0.0, 0.35, 0.0))
		var out := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
		view.add_debris(chunk, xf, out * randf_range(1.0, 4.0) + Vector3.UP * randf_range(2.5, 6.0),
			WRECK_TIME, Vector3(PI * 0.5 + randf_range(-0.15, 0.15), randf() * TAU, 0.0), 0.015)


## Sends one part flying off the tank. It lands and lies there for `life`.
func _throw(part: Node3D, power: float, life: float, upright: bool = false) -> void:
	var view = get_parent()
	if view == null or part == null:
		return
	var xf: Transform3D = part.global_transform
	part.get_parent().remove_child(part)
	var out: Vector3 = xf.origin - global_position
	out.y = 0.0
	if out.length() < 0.02:
		out = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	var velocity: Vector3 = out.normalized() * randf_range(0.8, 2.4) * power \
		+ Vector3(randf_range(-0.5, 0.5), randf_range(2.0, 4.2) * power, randf_range(-0.5, 0.5))
	# Plates and wheels come to rest lying flat, antennas on their side.
	var rest := Vector3(PI * 0.5, randf() * TAU, 0.0)
	if upright or part.get_child_count() > 0:
		rest = Vector3(randf_range(-0.1, 0.1), randf() * TAU, randf_range(-0.1, 0.1))
	view.add_debris(part, xf, velocity, life, rest, 0.02)


## Shows the damage taken so far: the paint gets scorched and chipped in
## three stages, loose parts are shot off, and what is left gets bent.
func _show_damage() -> void:
	_hp_shown = source.hp
	var lost: float = 1.0 - float(source.hp) / float(maxi(source.max_hp, 1))
	var stage: int = clampi(ceili(lost * 3.0), 0, 3)
	if stage != _stage:
		_stage = stage
		var tint: Color = source.color
		for part in _paint_parts:
			if is_instance_valid(part):
				part.material_override = Mat.paint(tint, stage, source.skin, source.wear)
		for part in _dark_parts:
			if is_instance_valid(part):
				part.material_override = Mat.paint(tint.darkened(0.25), stage, source.skin, source.wear)
	var keep: int = roundi(_loose_total * (1.0 - lost * 0.85))
	while _loose.size() > keep:
		_throw(_loose.pop_back(), 1.0, 25.0)
	for part in _loose:
		if randf() < 0.45:
			part.rotation += Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.25, 0.25))


func _burn(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child != _flash:
			child.material_override = Mat.charred()
		_burn(child)


func _sync(delta: float, first: bool) -> void:
	_time += delta
	Bar.update(_bar, source.hp, source.max_hp, Bar.color_for(source.team, source.is_player))
	var p: Vector2 = source.global_position
	var pos := Vector3(p.x * S, 0.0, p.y * S)
	var hull: float = source.hull_angle
	# Sit on the sand and tilt with the slope.
	var k: float = source.size_scale
	var xf: Transform3D = Terrain.vehicle_xf(pos.x, pos.z, hull, 0.42 * k, 0.27 * k)
	# Deep water: the tank does not follow the bed all the way down. It stops
	# with the turret roof just under the surface, levels out, and lifts the
	# gun so the muzzle stays in the air.
	var floor_y: float = Terrain.WATER_LEVEL - SINK * k
	var under: float = clampf((floor_y - xf.origin.y) / (0.12 * k), 0.0, 1.0)
	if under > 0.0:
		xf.origin.y = maxf(xf.origin.y, floor_y)
		var flat := Basis(Vector3(cos(hull), 0.0, sin(hull)), Vector3.UP, Vector3(-sin(hull), 0.0, cos(hull)))
		xf.basis = xf.basis.slerp(flat, under)
	transform = xf.scaled_local(Vector3(k, k, k))
	_gun.rotation.z = lerpf(_gun.rotation.z, GUN_LIFT * under, 1.0 if first else minf(delta * 5.0, 1.0))
	_turret.rotation.y = -(float(source.turret_angle) - hull)

	var recoil: float = source.recoil
	_gun.position.x = _gun_x - 0.12 * recoil
	_flash.visible = recoil > 0.8
	_ride(delta, first, k)

	# Roll the tracks and spin the wheels by the distance actually driven.
	var forward := Vector3(cos(hull), 0.0, sin(hull))
	var driven: float = 0.0 if first else (pos - _last).dot(forward) / k
	_last = pos
	if delta > 0.0:
		_spring(delta, driven * k / delta, recoil, float(source.turret_angle) - hull)
	# Press track prints into the sand behind both tracks.
	var view = get_parent()
	var depth: float = Terrain.water_depth(pos.x, pos.z)
	var wading: bool = depth > 0.04
	if wading and not _wading and not first and view != null:
		Fx.splash(view, Vector3(pos.x, Terrain.WATER_LEVEL, pos.z), 1.0)
		view.add_ripple(pos.x, pos.z, 1.2 * k)
	_wading = wading
	_mark_run += absf(driven) * k
	_ripple_run += absf(driven) * k
	if view != null and wading:
		# No ruts under water: rings spread out from the hull instead.
		if _ripple_run >= 0.5:
			_ripple_run = 0.0
			view.add_ripple(pos.x, pos.z, 0.9 * k)
	elif view != null and _mark_run >= MARK_SPACING:
		_mark_run = 0.0
		var side := Vector3(-sin(hull), 0.0, cos(hull)) * 0.265 * k
		view.add_mark(pos.x + side.x, pos.z + side.z, hull)
		view.add_mark(pos.x - side.x, pos.z - side.z, hull)
	_track_mat.uv1_offset.x -= driven * _track_mat.uv1_scale.x
	for wheel in _wheels:
		var radius: float = wheel.get_meta("radius")
		wheel.rotate_object_local(Vector3.UP, driven / radius)

	var moving: bool = absf(driven) > 0.002
	var surface: float = (Terrain.WATER_LEVEL - position.y) / k + 0.03
	for d in _dust:
		d.emitting = moving and not wading
	for w in _wake:
		w.emitting = moving and wading
		w.position.y = surface
	_spray.emitting = moving and wading
	_spray.position.y = surface
	if source.hp != _hp_shown:
		_show_damage()
	_smoke.emitting = source.max_hp > 1 and source.hp * 2 <= source.max_hp
	# Badly hit: the engine deck is on fire.
	_flame.emitting = source.max_hp > 1 and source.hp * 3 <= source.max_hp
	if _beam != null:
		_beam.visible = GameState.night > 0.05
		_beam.light_energy = 4.0 * GameState.night
	# A shimmering energy dome while the spawn shield is up.
	var shielded: bool = source.shield_time > 0.0
	if shielded and _dome == null and ResourceLoader.exists("res://assets/fx/fx_shield.png"):
		var ball := SphereMesh.new()
		ball.radius = 0.62
		ball.height = 1.24
		ball.radial_segments = 20
		ball.rings = 10
		var skin := StandardMaterial3D.new()
		skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		skin.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		skin.cull_mode = BaseMaterial3D.CULL_DISABLED
		skin.albedo_texture = load("res://assets/fx/fx_shield.png")
		skin.uv1_scale = Vector3(2.0, 1.0, 1.0)
		_dome = MeshInstance3D.new()
		_dome.mesh = ball
		_dome.material_override = skin
		_dome.position = Vector3(0.0, 0.25, 0.0)
		_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_dome)
	if _dome != null:
		_dome.visible = shielded
		if shielded:
			_dome.rotation.y = _time * 0.8
			# Fades out over its last second.
			_dome.material_override.albedo_color = Color(0.7, 0.9, 1.0,
				(0.45 + 0.15 * sin(_time * 9.0)) * clampf(source.shield_time, 0.0, 1.0))
	else:
		visible = not shielded or fmod(_time, 0.2) < 0.13


## Running gear: every road wheel finds the sand under it and moves up or
## down on its suspension arm, and the lower track run is strung from wheel
## to wheel, so it bends over bumps and hangs into dips.
func _ride(delta: float, first: bool, k: float) -> void:
	var blend: float = 1.0 if first else minf(delta * 16.0, 1.0)
	for s in _road.size():
		var row: Array = _road[s]
		var z: float = 0.265 * (-1.0 if s == 0 else 1.0)
		# Track path: rear idler, the seven wheels, front sprocket.
		var pts: Array[Vector2] = [Vector2(-0.47, 0.075)]
		for entry in row:
			var wheel: MeshInstance3D = entry[0]
			if is_instance_valid(wheel):
				var spot: Vector3 = transform * Vector3(entry[1], 0.0, entry[2])
				var gap: float = (Terrain.height(spot.x, spot.z) - spot.y) / k
				var want: float = WHEEL_Y + clampf(gap, -WHEEL_DROP, WHEEL_RISE)
				wheel.position.y = lerpf(wheel.position.y, want, blend)
				pts.append(Vector2(entry[1], wheel.position.y - 0.071))
			else:
				pts.append(Vector2(entry[1], WHEEL_Y - 0.071))
		pts.append(Vector2(0.43, 0.075))
		var stretch: Array = _links[s]
		for i in stretch.size():
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var link: MeshInstance3D = stretch[i]
			link.position = Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, z)
			link.rotation.z = atan2(b.y - a.y, b.x - a.x)
			link.scale.x = a.distance_to(b) / LINK_LEN * 1.04


## Hull on springs. It squats when the tank pulls away, dips when it stops,
## rocks back from the gun's kick, and bounces when the ground drops away or
## comes up under it. All of it settles like a heavy vehicle.
func _spring(delta: float, speed: float, recoil: float, gun_turn: float) -> void:
	var dt: float = minf(delta, 0.05)
	# Speeds are eased first, so a sudden start reads as a push, not a spike.
	var eased: float = lerpf(_speed, speed, minf(dt * 6.0, 1.0))
	var accel: float = clampf((eased - _speed) / dt, -25.0, 25.0)
	_speed = eased
	# Sound follows the throttle: idle fades into the working engine, the
	# tracks clatter louder and faster with speed.
	var go: float = clampf(absf(eased) / 3.5, 0.0, 1.0)
	_own = (-11.0 if source.is_player else 0.0) + Sfx.fall(global_position)
	if _snd_idle != null:
		_snd_idle.volume_db = lerpf(-10.0, -24.0, go) + _own
		_snd_idle.pitch_scale = 1.0 + 0.2 * go
	if _snd_move != null:
		_snd_move.volume_db = lerpf(-50.0, -7.0, sqrt(go)) + _own
		_snd_move.pitch_scale = 0.85 + 0.25 * go
	if _snd_tracks != null:
		_snd_tracks.volume_db = lerpf(-50.0, -9.0, sqrt(go)) + _own
		_snd_tracks.pitch_scale = 0.75 + 0.35 * go
	# A damaged tank runs rough: a broken rattle comes in as health drops,
	# slow and uneven at idle, faster on the move.
	if _snd_broken != null:
		var hurt: float = 1.0 - float(source.hp) / float(maxi(source.max_hp, 1))
		var rough: float = clampf((hurt - 0.3) / 0.5, 0.0, 1.0)
		_snd_broken.volume_db = (lerpf(-50.0, -7.0, sqrt(rough)) if rough > 0.0 else -60.0) + _own
		_snd_broken.pitch_scale = 0.8 + 0.4 * go
	var climb: float = lerpf(_climb, (position.y - _last_y) / dt, minf(dt * 10.0, 1.0))
	_last_y = position.y
	var jolt: float = clampf((climb - _climb) / dt, -40.0, 40.0)
	_climb = climb
	if recoil > _last_recoil + 0.5:
		_pitch_v += 0.7 * cos(gun_turn)
		_roll_v -= 0.7 * sin(gun_turn)
	_last_recoil = recoil
	_pitch_v += (-SPRING * _pitch - DAMP * _pitch_v + accel * 0.11) * dt
	_roll_v += (-SPRING * _roll - DAMP * _roll_v) * dt
	_heave_v += (-SPRING * _heave - DAMP * _heave_v - jolt * 0.12) * dt
	_pitch = clampf(_pitch + _pitch_v * dt, -0.1, 0.1)
	_roll = clampf(_roll + _roll_v * dt, -0.08, 0.08)
	_heave = clampf(_heave + _heave_v * dt, -0.035, 0.035)
	_body.rotation = Vector3(_roll, 0.0, _pitch)
	_body.position.y = _heave
