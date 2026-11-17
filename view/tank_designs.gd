extends RefCounted
## The detailed tank designs 1..15 (design 0 is built in tank_model.gd).
## Every design is our own shape, made in the manner of one country's
## modern tank: the outline of the turret, the number of road wheels, the
## kind of armour tiles, sights, gun stations, racks and gun are what set
## them apart. build() returns the same part set tank_model.gd uses.
##
## Turret parts are in turret space: origin at the turret ring, +X towards
## the gun, +Y up. Hull parts are in hull space.

const Kit := preload("res://view/mesh_kit.gd")
const ALONG_X := Vector3(0.0, 0.0, -PI * 0.5)
const ALONG_Z := Vector3(PI * 0.5, 0.0, 0.0)


static func _box(list: Array, size: Vector3, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	Kit.put(list, Kit.box(size), pos, rot)


static func _cyl(list: Array, radius: float, length: float, pos: Vector3,
		rot: Vector3 = Vector3.ZERO, segments: int = 10) -> void:
	Kit.put(list, Kit.cylinder(radius, length, segments), pos, rot)


## Six-cornered turret outline, the same left and right: rear edge at
## -back (half width wr), widest point at xm (half width wm), nose at xf
## (half width wf).
static func _hex(back: float, wr: float, xm: float, wm: float, xf: float, wf: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-back, -wr), Vector2(xm, -wm), Vector2(xf, -wf),
		Vector2(xf, wf), Vector2(xm, wm), Vector2(-back, wr)])


## A grid of armour tiles lying in the local X-Z plane of `rot`, centred
## on `at`. size.y is the tile thickness.
static func _tiles(list: Array, at: Vector3, rot: Vector3, cols: int, rows: int,
		size: Vector3, gap: float = 0.006) -> void:
	var b := Basis.from_euler(rot)
	var mesh := Kit.box(size)
	for c in cols:
		for r in rows:
			var off := Vector3((c - (cols - 1) * 0.5) * (size.x + gap), 0.0,
				(r - (rows - 1) * 0.5) * (size.z + gap))
			list.append([mesh, Transform3D(b, at + b * off)])


## Tiles standing along a straight stretch of turret wall from a to b
## (x, z pairs), leaning back a little, `rows` high.
static func _wall_tiles(list: Array, a: Vector2, b: Vector2, y: float, count: int, rows: int,
		tall: float, thick: float = 0.022, lean: float = 0.25) -> void:
	var dir: Vector2 = (b - a)
	var length: float = dir.length()
	var yaw: float = -atan2(dir.y, dir.x)
	var out := Vector2(-dir.y, dir.x).normalized()
	if out.dot((a + b) * 0.5) < 0.0:
		out = -out
		lean = -lean
	var wide: float = length / count - 0.006
	var mesh := Kit.box(Vector3(wide, tall, thick))
	for i in count:
		for r in rows:
			var p: Vector2 = a + dir * ((i + 0.5) / count) + out * (thick * 0.5 - r * 0.012)
			var basis := Basis.from_euler(Vector3(0.0, yaw, 0.0)) * Basis.from_euler(Vector3(lean, 0.0, 0.0))
			list.append([mesh, Transform3D(basis, Vector3(p.x, y + r * (tall + 0.006), p.y))])


## Commander's all-round sight: a post with a glazed head.
static func _sight(dark: Array, steel: Array, at: Vector3, tall: float, head: float = 0.05) -> void:
	_cyl(dark, 0.026, tall, at + Vector3(0.0, tall * 0.5, 0.0))
	_box(dark, Vector3(head, head, head * 0.9), at + Vector3(0.0, tall + head * 0.5, 0.0))
	_box(steel, Vector3(0.006, head * 0.6, head * 0.6), at + Vector3(head * 0.5, tall + head * 0.5, 0.0))


## Gunner's sight housing: a low armoured box with a window.
static func _gun_sight(dark: Array, steel: Array, at: Vector3, size: Vector3) -> void:
	_box(dark, size, at + Vector3(0.0, size.y * 0.5, 0.0))
	_box(steel, Vector3(0.006, size.y * 0.55, size.z * 0.6), at + Vector3(size.x * 0.5, size.y * 0.55, 0.0))


## Remote gun station: pedestal, cradle, machine gun, ammunition box.
static func _rws(dark: Array, steel: Array, at: Vector3) -> void:
	_cyl(dark, 0.022, 0.03, at + Vector3(0.0, 0.015, 0.0))
	_box(dark, Vector3(0.06, 0.04, 0.045), at + Vector3(0.0, 0.05, 0.0))
	_box(steel, Vector3(0.035, 0.045, 0.03), at + Vector3(0.0, 0.05, 0.04))
	_cyl(steel, 0.0075, 0.17, at + Vector3(0.1, 0.055, 0.0), ALONG_X, 6)
	_box(steel, Vector3(0.03, 0.03, 0.03), at + Vector3(0.025, 0.085, -0.012))


## Hand-worked machine gun on a pintle by a hatch.
static func _mg(steel: Array, at: Vector3, yaw: float = 0.0) -> void:
	var b := Basis.from_euler(Vector3(0.0, yaw, 0.0))
	_cyl(steel, 0.008, 0.05, at + Vector3(0.0, 0.025, 0.0), Vector3.ZERO, 6)
	steel.append([Kit.box(Vector3(0.07, 0.03, 0.025)), Transform3D(b, at + Vector3(0.0, 0.06, 0.0))])
	steel.append([Kit.cylinder(0.0065, 0.16, 6),
		Transform3D(b * Basis.from_euler(ALONG_X), at + Vector3(0.0, 0.062, 0.0) + b * Vector3(0.1, 0.0, 0.0))])
	steel.append([Kit.box(Vector3(0.03, 0.04, 0.04)), Transform3D(b, at + Vector3(0.0, 0.05, 0.0) + b * Vector3(0.0, 0.0, 0.035))])


## Bank of smoke launchers on a turret side.
static func _smoke(steel: Array, x: float, y: float, z: float, count: int, rows: int = 1) -> void:
	var side: float = signf(z)
	for r in rows:
		for j in count:
			Kit.put(steel, Kit.cylinder(0.013, 0.05, 6),
				Vector3(x - j * 0.034, y + r * 0.032, z + (j * 0.005 + r * 0.004) * side),
				Vector3(side * 0.35, 0.0, -PI * 0.5 + 0.55))


## Active protection launcher: an angled box with two tubes.
static func _aps(dark: Array, steel: Array, at: Vector3, side: float) -> void:
	_box(dark, Vector3(0.075, 0.045, 0.05), at, Vector3(0.0, -side * 0.5, 0.0))
	for dx in [-0.018, 0.018]:
		_cyl(steel, 0.011, 0.05, at + Vector3(dx, 0.03, side * 0.012), Vector3(side * 0.6, 0.0, 0.0), 8)


## Open rail basket round the turret rear, with kit stowed in it.
static func _rack(dark: Array, steel: Array, x0: float, x1: float, half: float, y0: float, y1: float) -> void:
	var xm: float = (x0 + x1) * 0.5
	var long: float = absf(x1 - x0)
	for y in [y0, (y0 + y1) * 0.5, y1]:
		_box(steel, Vector3(0.008, 0.008, half * 2.0), Vector3(x0, y, 0.0))
		for side in [-1.0, 1.0]:
			_box(steel, Vector3(long, 0.008, 0.008), Vector3(xm, y, half * side))
	for z in [-half, -half * 0.33, half * 0.33, half]:
		_box(steel, Vector3(0.008, y1 - y0, 0.008), Vector3(x0, (y0 + y1) * 0.5, z))
	_box(steel, Vector3(long, 0.006, half * 2.0), Vector3(xm, y0, 0.0))
	# Stowed kit: rolled tarp, crates, a jerrycan.
	_cyl(dark, 0.03, half * 1.5, Vector3(xm - long * 0.15, y0 + 0.035, 0.0), ALONG_Z, 8)
	_box(dark, Vector3(long * 0.42, (y1 - y0) * 0.7, half * 0.7), Vector3(xm + long * 0.2, y0 + (y1 - y0) * 0.36, half * 0.45))
	_box(dark, Vector3(long * 0.36, (y1 - y0) * 0.55, half * 0.5), Vector3(xm + long * 0.2, y0 + (y1 - y0) * 0.3, -half * 0.5))


## Slat cage: thin bars standing off a box, to catch rockets.
static func _slats(steel: Array, centre: Vector3, long: float, tall: float, z: float, bars: int) -> void:
	for i in bars:
		_box(steel, Vector3(long, 0.007, 0.007), centre + Vector3(0.0, -tall * 0.5 + tall * i / maxf(bars - 1, 1), z))
	for x in [-0.5, 0.0, 0.5]:
		_box(steel, Vector3(0.007, tall, 0.007), centre + Vector3(x * long, 0.0, z))


## Fuel drums across the hull rear, with or without an unditching log.
static func _drums(dark: Array, steel: Array, with_log: bool) -> void:
	for z in [-0.14, 0.14]:
		_cyl(dark, 0.05, 0.24, Vector3(-0.565, 0.3, z), ALONG_Z, 12)
		for dz in [-0.07, 0.07]:
			_cyl(steel, 0.052, 0.012, Vector3(-0.565, 0.3, z + dz), ALONG_Z, 12)
	if with_log:
		_cyl(dark, 0.03, 0.54, Vector3(-0.555, 0.21, 0.0), ALONG_Z, 8)


## The gun. sleeve: a jacketed barrel in banded sections. fume: where the
## bulge of the fume extractor sits (below 0 for none). Returns the tip x.
static func _gun(paint: Array, steel: Array, barrel: float, radius: float, sleeve: bool,
		fume: float, mantlet: Vector3 = Vector3(0.11, 0.11, 0.17)) -> float:
	_box(paint, mantlet, Vector3.ZERO)
	_box(paint, Vector3(mantlet.x * 0.5, mantlet.y * 0.8, mantlet.z * 1.25), Vector3(-0.02, 0.0, 0.0))
	Kit.put(paint, Kit.cone(0.05, 0.036, 0.1, 12), Vector3(0.1, 0.0, 0.0), ALONG_X)
	var tip: float = 0.12 + barrel
	_cyl(paint, radius, barrel, Vector3(0.12 + barrel * 0.5, 0.0, 0.0), ALONG_X, 14)
	if sleeve:
		# Thermal jacket: fatter sections with narrow gaps and strap bands.
		var from: float = 0.16
		var parts: int = 5
		var each: float = (barrel - 0.1) / parts
		for i in parts:
			var x: float = from + each * (i + 0.5)
			if fume > 0.0 and absf(x - fume) < each * 0.55:
				continue
			_cyl(paint, radius + 0.006, each - 0.012, Vector3(x, 0.0, 0.0), ALONG_X, 14)
			_cyl(steel, radius + 0.008, 0.008, Vector3(x - each * 0.5 + 0.012, 0.0, 0.0), ALONG_X, 14)
	if fume > 0.0:
		_cyl(paint, radius + 0.014, 0.16, Vector3(fume, 0.0, 0.0), ALONG_X, 14)
		Kit.put(paint, Kit.cone(radius + 0.004, radius + 0.014, 0.02, 14), Vector3(fume - 0.09, 0.0, 0.0), ALONG_X)
		Kit.put(paint, Kit.cone(radius + 0.014, radius + 0.004, 0.02, 14), Vector3(fume + 0.09, 0.0, 0.0), ALONG_X)
	# Muzzle: a collar and the small mirror the gunner checks the bore with.
	_cyl(steel, radius + 0.005, 0.03, Vector3(tip - 0.018, 0.0, 0.0), ALONG_X, 14)
	_cyl(steel, radius - 0.006, 0.006, Vector3(tip + 0.001, 0.0, 0.0), ALONG_X, 12)
	_box(steel, Vector3(0.02, 0.012, 0.014), Vector3(tip - 0.05, radius + 0.012, 0.0))
	# Coaxial machine gun beside the main gun.
	_cyl(steel, 0.006, 0.07, Vector3(0.08, 0.02, mantlet.z * 0.36), ALONG_X, 6)
	return tip


## One side-skirt plate. kind: "plain", "tall", "slab" (thick add-on
## armour), "era" (tiles bolted on), "flap" (tiles over a rubber apron).
static func _skirt(kind: String) -> ArrayMesh:
	var s: Array = []
	match kind:
		"tall":
			_box(s, Vector3(0.168, 0.15, 0.018), Vector3(0.0, -0.015, 0.0))
			_box(s, Vector3(0.168, 0.012, 0.024), Vector3(0.0, 0.05, 0.0))
			for x in [-0.06, 0.0, 0.06]:
				_box(s, Vector3(0.012, 0.012, 0.026), Vector3(x, 0.03, 0.0))
		"slab":
			_box(s, Vector3(0.168, 0.15, 0.02), Vector3(0.0, -0.015, 0.0))
			_box(s, Vector3(0.15, 0.1, 0.05), Vector3(0.0, 0.0, 0.0))
			for x in [-0.055, 0.055]:
				for y in [-0.03, 0.03]:
					_box(s, Vector3(0.014, 0.014, 0.058), Vector3(x, y, 0.0))
		"era":
			_box(s, Vector3(0.168, 0.12, 0.016), Vector3.ZERO)
			for x in [-0.043, 0.043]:
				for y in [-0.027, 0.03]:
					_box(s, Vector3(0.078, 0.05, 0.04), Vector3(x, y, 0.0))
		"flap":
			_box(s, Vector3(0.168, 0.16, 0.014), Vector3(0.0, -0.02, 0.0))
			for x in [-0.055, 0.0, 0.055]:
				_box(s, Vector3(0.05, 0.085, 0.044), Vector3(x, 0.012, 0.0), Vector3(0.0, 0.0, 0.0))
		_:
			_box(s, Vector3(0.168, 0.12, 0.018), Vector3.ZERO)
			_box(s, Vector3(0.012, 0.012, 0.024), Vector3(-0.06, 0.04, 0.0))
			_box(s, Vector3(0.012, 0.012, 0.024), Vector3(0.06, 0.04, 0.0))
	return Kit.merge(s)


## Tiles on the sloped nose plate of the hull.
static func _nose_tiles(list: Array, cols: int, rows: int) -> void:
	_tiles(list, Vector3(0.39, 0.303, 0.0), Vector3(0.0, 0.0, -0.41), cols, rows,
		Vector3(0.2 / cols - 0.006, 0.02, 0.5 / rows - 0.006))


static func build(m: int, base: Dictionary) -> Dictionary:
	var tp: Array = []  # turret, painted
	var td: Array = []  # turret, darker paint
	var ts: Array = []  # turret, bare steel
	var gp: Array = []  # gun, painted
	var gs: Array = []  # gun, steel
	var hx: Array = []  # hull extras, painted
	var he: Array = []  # hull extras, darker paint
	var hs: Array = []  # hull extras, steel
	var low: PackedVector2Array
	var top: PackedVector2Array
	var h := 0.14
	var tx := -0.04
	var gx := 0.28
	var wheels := 7
	var skirt := "plain"
	var tip := 0.74
	var half := 0.2  # half width of the turret side where fittings hang

	match m:
		1:  # American manner: wide slab turret, long bustle, turbine deck.
			low = _hex(0.36, 0.2, 0.1, 0.245, 0.33, 0.13)
			top = _hex(0.34, 0.18, 0.07, 0.21, 0.22, 0.11)
			h = 0.135
			tx = -0.02
			gx = 0.3
			half = 0.225
			tip = _gun(gp, gs, 0.6, 0.026, false, 0.36, Vector3(0.12, 0.12, 0.2))
			_sight(td, ts, Vector3(0.0, h, -0.12), 0.035, 0.055)
			_gun_sight(td, ts, Vector3(0.12, h, 0.12), Vector3(0.08, 0.05, 0.07))
			_rws(td, ts, Vector3(-0.06, h, 0.1))
			_mg(ts, Vector3(-0.1, h, -0.1), 0.5)
			# Blow-off panels over the ammunition in the bustle.
			for z in [-0.09, 0.0, 0.09]:
				_box(td, Vector3(0.13, 0.008, 0.08), Vector3(-0.24, h + 0.004, z))
			_rack(td, ts, -0.47, -0.36, 0.19, 0.02, 0.11)
			for side in [-1.0, 1.0]:
				_box(td, Vector3(0.2, 0.06, 0.03), Vector3(-0.2, 0.06, (half - 0.015) * side))
				_smoke(ts, 0.14, 0.08, (half - 0.02) * side, 4, 2)
			# Turbine exhaust grille across the hull rear, and a hull phone box.
			for y in [0.2, 0.225, 0.25, 0.275, 0.3]:
				_box(hs, Vector3(0.012, 0.012, 0.36), Vector3(-0.505, y, 0.0))
			_box(he, Vector3(0.03, 0.06, 0.07), Vector3(-0.515, 0.25, 0.26))
		2:  # Russian manner: low angular turret under armour wedges.
			low = _hex(0.27, 0.19, 0.06, 0.235, 0.3, 0.1)
			top = _hex(0.25, 0.15, 0.02, 0.165, 0.15, 0.07)
			h = 0.115
			gx = 0.24
			wheels = 6
			skirt = "era"
			half = 0.2
			tip = _gun(gp, gs, 0.68, 0.024, true, 0.33)
			for side in [-1.0, 1.0]:
				_wall_tiles(tp, Vector2(0.07, 0.24 * side), Vector2(0.3, 0.105 * side), 0.02, 4, 2, 0.045, 0.045)
				_wall_tiles(tp, Vector2(-0.2, 0.2 * side), Vector2(0.04, 0.235 * side), 0.03, 4, 1, 0.06, 0.02, 0.1)
				_smoke(ts, 0.0, 0.1, 0.19 * side, 3)
			# Roof tiles, bustle box in a slat cage, wind sensor.
			_tiles(tp, Vector3(0.06, h + 0.004, 0.0), Vector3(0.0, 0.0, -0.2), 2, 3, Vector3(0.05, 0.016, 0.07))
			_box(td, Vector3(0.14, 0.085, 0.3), Vector3(-0.33, 0.06, 0.0))
			for side in [-1.0, 1.0]:
				_slats(ts, Vector3(-0.33, 0.06, 0.0), 0.16, 0.09, 0.17 * side, 4)
			_slats(ts, Vector3(-0.415, 0.06, 0.0), 0.006, 0.09, 0.0, 4)
			_sight(td, ts, Vector3(-0.06, h, 0.09), 0.03, 0.05)
			_rws(td, ts, Vector3(-0.08, h, -0.08))
			_gun_sight(td, ts, Vector3(0.08, h - 0.01, -0.1), Vector3(0.06, 0.04, 0.05))
			_cyl(ts, 0.005, 0.12, Vector3(-0.22, h + 0.06, 0.0), Vector3.ZERO, 5)
			_nose_tiles(hx, 2, 6)
			_drums(he, hs, true)
		3:  # German manner: arrow-head turret, very long gun.
			low = _hex(0.3, 0.21, 0.1, 0.225, 0.43, 0.035)
			top = _hex(0.28, 0.19, 0.08, 0.2, 0.3, 0.035)
			h = 0.155
			gx = 0.32
			skirt = "slab"
			half = 0.21
			tip = _gun(gp, gs, 0.76, 0.025, true, 0.44, Vector3(0.12, 0.13, 0.15))
			_sight(td, ts, Vector3(-0.02, h, -0.1), 0.05, 0.055)
			_gun_sight(td, ts, Vector3(0.14, h, 0.1), Vector3(0.09, 0.045, 0.07))
			_mg(ts, Vector3(-0.1, h, 0.1), -0.3)
			_rack(td, ts, -0.41, -0.3, 0.19, 0.02, 0.12)
			for side in [-1.0, 1.0]:
				_aps(td, ts, Vector3(-0.12, h + 0.02, 0.17 * side), side)
				_box(td, Vector3(0.16, 0.07, 0.03), Vector3(-0.16, 0.08, (half + 0.012) * side))
				_smoke(ts, 0.06, 0.1, (half + 0.005) * side, 4, 2)
				# Seam lines of the bolted-on arrow armour.
				_box(td, Vector3(0.2, 0.01, 0.006), Vector3(0.26, 0.09, 0.115 * side), Vector3(0.0, 0.52 * side, 0.0))
			_box(he, Vector3(0.1, 0.03, 0.4), Vector3(-0.45, 0.365, 0.0))
			for z in [-0.16, 0.16]:
				_cyl(hs, 0.05, 0.02, Vector3(-0.38, 0.375, z), Vector3.ZERO, 14)
		4:  # Israeli manner: engine in the nose, turret set back, long wedge.
			low = _hex(0.3, 0.2, 0.06, 0.24, 0.45, 0.06)
			top = _hex(0.24, 0.14, -0.06, 0.15, 0.08, 0.05)
			h = 0.125
			tx = -0.15
			gx = 0.38
			wheels = 6
			skirt = "tall"
			half = 0.2
			tip = _gun(gp, gs, 0.6, 0.026, true, 0.36, Vector3(0.1, 0.1, 0.14))
			_sight(td, ts, Vector3(-0.1, h, -0.08), 0.03, 0.05)
			_gun_sight(td, ts, Vector3(0.0, h - 0.005, 0.08), Vector3(0.07, 0.04, 0.06))
			_rws(td, ts, Vector3(-0.16, h, 0.06))
			_mg(ts, Vector3(-0.02, h - 0.01, -0.02), 0.0)
			_rack(td, ts, -0.42, -0.3, 0.17, 0.01, 0.1)
			# Ball-and-chain curtain under the bustle.
			for i in 11:
				var z: float = -0.17 + i * 0.034
				_cyl(ts, 0.004, 0.05, Vector3(-0.4, -0.02, z), Vector3.ZERO, 4)
				_cyl(ts, 0.009, 0.012, Vector3(-0.4, -0.05, z), Vector3.ZERO, 6)
			for side in [-1.0, 1.0]:
				_aps(td, ts, Vector3(-0.2, 0.09, (half + 0.01) * side), side)
				_smoke(ts, -0.02, 0.07, (half + 0.01) * side, 3, 2)
			# Raised engine deck with louvres beside the driver, exhaust on the side.
			_box(he, Vector3(0.24, 0.035, 0.34), Vector3(0.2, 0.347, -0.07))
			for x in [0.11, 0.15, 0.19, 0.23, 0.27, 0.31]:
				_box(hs, Vector3(0.014, 0.012, 0.22), Vector3(x, 0.37, -0.09))
			_box(he, Vector3(0.14, 0.05, 0.03), Vector3(0.2, 0.3, -0.345))
			_box(he, Vector3(0.03, 0.14, 0.2), Vector3(-0.515, 0.25, 0.0))
		5:  # Indian manner: tall square turret with tiles, heavy rifled gun.
			low = _hex(0.31, 0.225, 0.2, 0.225, 0.3, 0.16)
			top = _hex(0.29, 0.2, 0.17, 0.2, 0.24, 0.15)
			h = 0.165
			gx = 0.28
			skirt = "era"
			half = 0.225
			tip = _gun(gp, gs, 0.68, 0.027, true, 0.46, Vector3(0.12, 0.13, 0.2))
			_tiles(tp, Vector3(0.292, 0.085, 0.0), Vector3(0.0, 0.0, -PI * 0.5 + 0.12), 2, 4, Vector3(0.062, 0.022, 0.064))
			for side in [-1.0, 1.0]:
				_wall_tiles(tp, Vector2(-0.05, 0.228 * side), Vector2(0.2, 0.228 * side), 0.035, 4, 2, 0.055, 0.022, 0.06)
				_smoke(ts, -0.12, 0.09, (half + 0.005) * side, 4, 2)
			_tiles(tp, Vector3(0.2, h + 0.004, 0.0), Vector3(0.0, 0.0, -0.05), 1, 4, Vector3(0.07, 0.016, 0.07))
			_sight(td, ts, Vector3(-0.02, h, -0.1), 0.06, 0.06)
			_gun_sight(td, ts, Vector3(0.1, h, 0.11), Vector3(0.1, 0.06, 0.08))
			_rws(td, ts, Vector3(-0.12, h, 0.08))
			_rack(td, ts, -0.42, -0.31, 0.2, 0.02, 0.12)
			_nose_tiles(hx, 2, 5)
		6:  # Korean manner: sharp angled turret, autoloader bustle, long gun.
			low = _hex(0.35, 0.19, 0.08, 0.235, 0.36, 0.09)
			top = _hex(0.33, 0.15, 0.04, 0.18, 0.22, 0.06)
			h = 0.13
			gx = 0.3
			wheels = 6
			skirt = "tall"
			half = 0.205
			tip = _gun(gp, gs, 0.74, 0.025, true, 0.46)
			_sight(td, ts, Vector3(-0.04, h, -0.09), 0.04, 0.05)
			_gun_sight(td, ts, Vector3(0.1, h - 0.005, 0.09), Vector3(0.07, 0.04, 0.06))
			_rws(td, ts, Vector3(-0.12, h, 0.08))
			# Radar plates on the front corners and warning sensors.
			for side in [-1.0, 1.0]:
				_box(td, Vector3(0.05, 0.05, 0.012), Vector3(0.24, 0.08, 0.165 * side), Vector3(0.0, 0.62 * side, 0.3 * 0.0))
				_slats(ts, Vector3(-0.22, 0.065, 0.0), 0.22, 0.09, (half + 0.004) * side, 4)
				_smoke(ts, 0.04, 0.1, (half - 0.005) * side, 3, 2)
				_box(td, Vector3(0.03, 0.025, 0.03), Vector3(-0.3, h + 0.012, 0.13 * side))
			_box(td, Vector3(0.1, 0.006, 0.26), Vector3(-0.27, h + 0.003, 0.0))
			_box(he, Vector3(0.03, 0.1, 0.44), Vector3(-0.515, 0.28, 0.0))
		7:  # British manner: long flat-faced turret, big sight, slab skirts.
			low = _hex(0.37, 0.2, 0.14, 0.23, 0.35, 0.15)
			top = _hex(0.35, 0.17, 0.1, 0.19, 0.26, 0.12)
			h = 0.15
			tx = -0.03
			gx = 0.3
			wheels = 6
			skirt = "slab"
			half = 0.215
			tip = _gun(gp, gs, 0.74, 0.026, true, 0.42, Vector3(0.1, 0.12, 0.13))
			_sight(td, ts, Vector3(0.0, h, -0.09), 0.075, 0.065)
			_gun_sight(td, ts, Vector3(0.14, h, 0.1), Vector3(0.1, 0.05, 0.07))
			_rws(td, ts, Vector3(-0.1, h, 0.09))
			# Add-on armour blocks on the cheeks and stowage bins down the sides.
			for side in [-1.0, 1.0]:
				_box(tp, Vector3(0.2, 0.1, 0.035), Vector3(0.245, 0.07, 0.2 * side), Vector3(0.0, 0.36 * side, 0.0))
				for x in [-0.3, -0.19, -0.08]:
					_box(td, Vector3(0.1, 0.075, 0.04), Vector3(x, 0.075, (half + 0.012) * side))
					_box(ts, Vector3(0.02, 0.008, 0.044), Vector3(x, 0.115, (half + 0.012) * side))
				_smoke(ts, 0.1, 0.13, (half - 0.01) * side, 5)
			_rack(td, ts, -0.47, -0.37, 0.18, 0.03, 0.12)
			_drums(he, hs, false)
		8:  # Japanese manner: small, light and quick, with a sensor mast.
			low = _hex(0.3, 0.18, 0.06, 0.215, 0.31, 0.08)
			top = _hex(0.28, 0.15, 0.03, 0.17, 0.2, 0.05)
			h = 0.13
			gx = 0.27
			wheels = 5
			half = 0.19
			tip = _gun(gp, gs, 0.64, 0.024, true, 0.4, Vector3(0.1, 0.1, 0.13))
			# Bolt-on armour modules stepped along the turret sides.
			for side in [-1.0, 1.0]:
				for i in 3:
					_box(tp, Vector3(0.1, 0.085 - i * 0.008, 0.03), Vector3(-0.22 + i * 0.11, 0.06, (0.192 + i * 0.012) * side),
						Vector3(0.0, -0.1 * side, 0.0))
				_smoke(ts, 0.1, 0.11, (half + 0.01) * side, 4)
				_box(td, Vector3(0.04, 0.03, 0.012), Vector3(0.2, 0.1, 0.13 * side), Vector3(0.0, 0.6 * side, 0.0))
			_sight(td, ts, Vector3(-0.14, h, 0.1), 0.1, 0.055)
			_gun_sight(td, ts, Vector3(0.08, h - 0.005, -0.08), Vector3(0.07, 0.04, 0.06))
			_mg(ts, Vector3(-0.06, h, -0.08), 0.2)
			_box(td, Vector3(0.12, 0.07, 0.3), Vector3(-0.35, 0.07, 0.0))
			_slats(ts, Vector3(-0.415, 0.07, 0.0), 0.006, 0.07, 0.0, 3)
		9:  # French manner: long narrow turret lined with bins, no fume bulge.
			low = _hex(0.41, 0.17, 0.1, 0.2, 0.31, 0.1)
			top = _hex(0.39, 0.14, 0.06, 0.16, 0.2, 0.07)
			h = 0.13
			tx = -0.02
			gx = 0.28
			wheels = 6
			skirt = "tall"
			half = 0.19
			tip = _gun(gp, gs, 0.72, 0.025, true, -1.0, Vector3(0.1, 0.1, 0.12))
			for side in [-1.0, 1.0]:
				for i in 4:
					var x: float = -0.34 + i * 0.105
					_box(td, Vector3(0.098, 0.08, 0.045), Vector3(x, 0.07, (half + 0.01) * side))
					_box(ts, Vector3(0.018, 0.008, 0.05), Vector3(x, 0.112, (half + 0.01) * side))
				_smoke(ts, 0.16, 0.09, (half - 0.03) * side, 3, 2)
			_sight(td, ts, Vector3(-0.02, h, -0.07), 0.05, 0.055)
			_gun_sight(td, ts, Vector3(0.1, h - 0.005, 0.07), Vector3(0.08, 0.045, 0.06))
			_rws(td, ts, Vector3(-0.16, h, 0.05))
			# Louvred ammunition bustle and a slat cage round the hull rear.
			for z in [-0.1, 0.0, 0.1]:
				_box(td, Vector3(0.1, 0.006, 0.07), Vector3(-0.3, h + 0.003, z))
			for side in [-1.0, 1.0]:
				_slats(hs, Vector3(-0.4, 0.27, 0.0), 0.2, 0.12, 0.36 * side, 5)
			_slats(hs, Vector3(-0.55, 0.27, 0.0), 0.006, 0.12, 0.0, 5)
			for z in [-0.24, -0.12, 0.0, 0.12, 0.24]:
				_box(hs, Vector3(0.007, 0.12, 0.007), Vector3(-0.55, 0.27, z))
			_drums(he, hs, false)
		10:  # Chinese manner: tiled arrow front, dazzler box, basket.
			low = _hex(0.3, 0.2, 0.1, 0.23, 0.41, 0.045)
			top = _hex(0.28, 0.17, 0.07, 0.19, 0.27, 0.045)
			h = 0.14
			gx = 0.3
			wheels = 6
			skirt = "era"
			half = 0.21
			tip = _gun(gp, gs, 0.72, 0.025, true, 0.42)
			for side in [-1.0, 1.0]:
				_wall_tiles(tp, Vector2(0.11, 0.232 * side), Vector2(0.41, 0.05 * side), 0.02, 5, 2, 0.05, 0.024, 0.2)
				_smoke(ts, -0.02, 0.1, (half + 0.005) * side, 5)
				_box(td, Vector3(0.14, 0.06, 0.03), Vector3(-0.17, 0.07, (half + 0.012) * side))
			# Laser dazzler: a box with a round lens, rear left of the roof.
			_box(td, Vector3(0.07, 0.06, 0.06), Vector3(-0.18, h + 0.03, -0.09))
			_cyl(ts, 0.02, 0.012, Vector3(-0.142, h + 0.035, -0.09), ALONG_X, 10)
			_sight(td, ts, Vector3(-0.04, h, 0.09), 0.045, 0.055)
			_gun_sight(td, ts, Vector3(0.1, h - 0.005, -0.08), Vector3(0.07, 0.04, 0.06))
			_mg(ts, Vector3(-0.1, h, 0.02), 0.0)
			_rack(td, ts, -0.42, -0.3, 0.18, 0.02, 0.11)
			_nose_tiles(hx, 3, 6)
			_drums(he, hs, false)
		11:  # Turkish manner: big blocky turret, heavy skirts, full sensor fit.
			low = _hex(0.38, 0.21, 0.1, 0.245, 0.36, 0.11)
			top = _hex(0.36, 0.17, 0.06, 0.2, 0.24, 0.08)
			h = 0.15
			tx = -0.03
			gx = 0.31
			skirt = "slab"
			half = 0.22
			tip = _gun(gp, gs, 0.74, 0.026, true, 0.46, Vector3(0.12, 0.12, 0.17))
			_sight(td, ts, Vector3(-0.02, h, -0.1), 0.055, 0.06)
			_gun_sight(td, ts, Vector3(0.12, h, 0.1), Vector3(0.09, 0.05, 0.07))
			_rws(td, ts, Vector3(-0.14, h, 0.09))
			for side in [-1.0, 1.0]:
				_aps(td, ts, Vector3(-0.24, h + 0.02, 0.15 * side), side)
				_box(tp, Vector3(0.22, 0.09, 0.03), Vector3(0.24, 0.07, 0.19 * side), Vector3(0.0, 0.47 * side, 0.0))
				_box(td, Vector3(0.22, 0.07, 0.035), Vector3(-0.2, 0.075, (half + 0.01) * side))
				_smoke(ts, 0.08, 0.12, (half - 0.01) * side, 4, 2)
				_box(td, Vector3(0.035, 0.03, 0.035), Vector3(0.18, h + 0.015, 0.15 * side))
			_rack(td, ts, -0.48, -0.38, 0.19, 0.03, 0.12)
			_box(he, Vector3(0.03, 0.1, 0.44), Vector3(-0.515, 0.28, 0.0))
		12:  # Italian manner: clean sloped faces, side racks, big smoke banks.
			low = _hex(0.3, 0.2, 0.16, 0.22, 0.31, 0.12)
			top = _hex(0.28, 0.17, 0.1, 0.18, 0.2, 0.09)
			h = 0.14
			gx = 0.28
			half = 0.205
			tip = _gun(gp, gs, 0.64, 0.025, true, 0.4, Vector3(0.11, 0.11, 0.15))
			_sight(td, ts, Vector3(-0.02, h, -0.09), 0.05, 0.055)
			_gun_sight(td, ts, Vector3(0.1, h - 0.005, 0.09), Vector3(0.08, 0.04, 0.06))
			_mg(ts, Vector3(-0.1, h, 0.09), -0.2)
			_mg(ts, Vector3(-0.12, h, -0.03), 0.3)
			for side in [-1.0, 1.0]:
				# Bolted cheek plates and an open rail rack along the side.
				_box(tp, Vector3(0.15, 0.085, 0.025), Vector3(0.235, 0.065, 0.185 * side), Vector3(0.0, 0.58 * side, 0.0))
				for y in [0.04, 0.08, 0.12]:
					_box(ts, Vector3(0.24, 0.007, 0.007), Vector3(-0.15, y, (half + 0.03) * side))
				for x in [-0.27, -0.15, -0.03]:
					_box(ts, Vector3(0.007, 0.09, 0.007), Vector3(x, 0.08, (half + 0.03) * side))
					_box(ts, Vector3(0.007, 0.007, 0.03), Vector3(x, 0.04, (half + 0.015) * side))
				_box(td, Vector3(0.12, 0.06, 0.022), Vector3(-0.17, 0.075, (half + 0.014) * side))
				_smoke(ts, 0.1, 0.1, (half - 0.01) * side, 4, 2)
			_rack(td, ts, -0.4, -0.3, 0.18, 0.02, 0.11)
		13:  # Ukrainian manner: deep armour cheeks, tall sight, aprons.
			low = _hex(0.28, 0.2, 0.08, 0.24, 0.33, 0.12)
			top = _hex(0.26, 0.16, 0.03, 0.17, 0.16, 0.07)
			h = 0.12
			gx = 0.25
			wheels = 6
			skirt = "flap"
			half = 0.2
			tip = _gun(gp, gs, 0.7, 0.024, true, 0.34)
			for side in [-1.0, 1.0]:
				# Thick two-layer cheek blocks that stand proud of the turret.
				_box(tp, Vector3(0.26, 0.1, 0.07), Vector3(0.23, 0.06, 0.2 * side), Vector3(0.0, 0.45 * side, 0.12 * 0.0))
				_wall_tiles(tp, Vector2(0.1, 0.275 * side), Vector2(0.36, 0.15 * side), 0.025, 3, 1, 0.08, 0.016, 0.1)
				_wall_tiles(tp, Vector2(-0.2, 0.2 * side), Vector2(0.04, 0.24 * side), 0.03, 3, 1, 0.065, 0.02, 0.1)
				_smoke(ts, -0.02, 0.1, 0.19 * side, 4)
			_tiles(tp, Vector3(0.05, h + 0.004, 0.0), Vector3(0.0, 0.0, -0.22), 2, 4, Vector3(0.05, 0.016, 0.055))
			_sight(td, ts, Vector3(-0.08, h, 0.09), 0.09, 0.055)
			_gun_sight(td, ts, Vector3(0.08, h - 0.01, -0.09), Vector3(0.06, 0.04, 0.05))
			_rws(td, ts, Vector3(-0.1, h, -0.08))
			_box(td, Vector3(0.15, 0.09, 0.32), Vector3(-0.34, 0.06, 0.0))
			_box(ts, Vector3(0.008, 0.07, 0.3), Vector3(-0.418, 0.06, 0.0))
			_nose_tiles(hx, 2, 7)
			_drums(he, hs, true)
		14:  # Pakistani manner: flat welded turret, tile fields, basket.
			low = _hex(0.3, 0.2, 0.12, 0.225, 0.31, 0.12)
			top = _hex(0.28, 0.16, 0.07, 0.17, 0.19, 0.08)
			h = 0.115
			gx = 0.26
			wheels = 6
			skirt = "plain"
			half = 0.2
			tip = _gun(gp, gs, 0.72, 0.024, true, 0.36)
			for side in [-1.0, 1.0]:
				_wall_tiles(tp, Vector2(0.13, 0.228 * side), Vector2(0.31, 0.125 * side), 0.02, 3, 2, 0.042, 0.022, 0.3)
				_smoke(ts, 0.0, 0.09, (half + 0.01) * side, 4, 2)
				_box(td, Vector3(0.14, 0.055, 0.03), Vector3(-0.16, 0.06, (half + 0.012) * side))
			_tiles(tp, Vector3(0.3, 0.055, 0.0), Vector3(0.0, 0.0, -PI * 0.5 + 0.35), 2, 3, Vector3(0.045, 0.02, 0.06))
			_tiles(tp, Vector3(0.11, h + 0.004, 0.0), Vector3(0.0, 0.0, -0.18), 2, 3, Vector3(0.05, 0.014, 0.07))
			_sight(td, ts, Vector3(-0.06, h, 0.09), 0.04, 0.05)
			_gun_sight(td, ts, Vector3(0.06, h - 0.005, -0.09), Vector3(0.06, 0.04, 0.05))
			_mg(ts, Vector3(-0.08, h, -0.06), 0.0)
			_cyl(ts, 0.005, 0.1, Vector3(-0.2, h + 0.05, 0.0), Vector3.ZERO, 5)
			_rack(td, ts, -0.42, -0.3, 0.18, 0.015, 0.1)
			_nose_tiles(hx, 2, 5)
			_drums(he, hs, false)
		_:  # Polish manner: round cast dome under a coat of small bricks.
			low = Kit.ngon(0.255, 14, PI / 14.0, Vector2(1.0, 0.86))
			top = Kit.ngon(0.13, 14, PI / 14.0, Vector2(1.0, 0.86), Vector2(-0.02, 0.0))
			h = 0.115
			gx = 0.22
			wheels = 6
			skirt = "era"
			half = 0.19
			tip = _gun(gp, gs, 0.66, 0.024, true, 0.3)
			# Two rings of bricks round the front of the dome.
			for ring in 2:
				var r: float = 0.225 - ring * 0.05
				var y: float = 0.035 + ring * 0.042
				var n: int = 10 - ring * 2
				for i in n:
					var a: float = -1.35 + 2.7 * i / (n - 1)
					if absf(a) < 0.2:
						continue
					Kit.put(tp, Kit.box(Vector3(0.03, 0.036, 0.05)),
						Vector3(cos(a) * r, y, sin(a) * r * 0.86), Vector3(0.0, -a, 0.75))
			_tiles(tp, Vector3(0.03, h + 0.004, 0.0), Vector3.ZERO, 2, 3, Vector3(0.04, 0.014, 0.05))
			# Searchlight by the gun, snorkel tube, hatch gun, stowage boxes.
			_cyl(td, 0.035, 0.04, Vector3(0.2, 0.1, 0.12), ALONG_X, 12)
			_cyl(ts, 0.03, 0.006, Vector3(0.222, 0.1, 0.12), ALONG_X, 12)
			_cyl(td, 0.024, 0.3, Vector3(-0.25, 0.07, 0.0), ALONG_Z, 8)
			_mg(ts, Vector3(-0.07, h, -0.08), 0.1)
			_gun_sight(td, ts, Vector3(0.06, h - 0.015, 0.08), Vector3(0.05, 0.04, 0.05))
			_cyl(td, 0.05, 0.02, Vector3(-0.07, h + 0.005, -0.08), Vector3.ZERO, 12)
			for side in [-1.0, 1.0]:
				_box(td, Vector3(0.1, 0.05, 0.04), Vector3(-0.14, 0.05, 0.215 * side), Vector3(0.0, 0.25 * side, 0.0))
				_smoke(ts, 0.02, 0.085, 0.19 * side, 4)
			_nose_tiles(hx, 3, 8)
			_drums(he, hs, true)

	Kit.put(tp, Kit.loft(low, 0.0, top, h), Vector3.ZERO)
	# A collar where the turret meets the hull, hatches on every roof.
	_cyl(td, 0.2, 0.012, Vector3(0.0, -0.004, 0.0), Vector3.ZERO, 20)
	_cyl(td, 0.052, 0.014, Vector3(-0.09, h + 0.007, 0.085), Vector3.ZERO, 14)
	_cyl(td, 0.044, 0.012, Vector3(-0.09, h + 0.006, -0.085), Vector3.ZERO, 14)
	for side in [-1.0, 1.0]:
		_box(ts, Vector3(0.012, 0.008, 0.02), Vector3(-0.09 + 0.05, h + 0.012, 0.085 * side))

	var out: Dictionary = base.duplicate()
	out.merge({
		"turret_paint": Kit.merge(tp), "turret_dark": Kit.merge(td),
		"turret_steel": Kit.merge(ts), "gun_paint": Kit.merge(gp), "gun_steel": Kit.merge(gs),
		"basket": false,
		"hull_extra": Kit.merge(he) if not he.is_empty() else null,
		"hull_extra_paint": Kit.merge(hx) if not hx.is_empty() else null,
		"hull_extra_steel": Kit.merge(hs) if not hs.is_empty() else null,
		"skirt": _skirt(skirt), "wheels": wheels,
		"h": h, "tx": tx, "gx": gx, "muzzle": tip + 0.18,
	}, true)
	return out
