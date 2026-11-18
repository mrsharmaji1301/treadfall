extends RefCounted
## Desert terrain shape. The battlefield itself has gentle swells; outside it
## the ground rises into a sand berm and then rolling dunes with sharp crests.
## Everything in the 3D view asks this script how high the ground is.

## Height of every water surface on the map.
const WATER_LEVEL := -0.2
const BASIN := 0.5
const DUNE_H := 0.7
## The map's water and dune cells, blurred into soft fields. R samples per
## cell, with PAD cells of margin all round.
const R := 2
const PAD := 3

static var _dune: FastNoiseLite
static var _roll: FastNoiseLite
static var _wet := PackedFloat32Array()
static var _hill := PackedFloat32Array()
static var _chan := PackedFloat32Array()
static var _road := PackedFloat32Array()
static var _bank := PackedFloat32Array()
## Palm groves and the green belt along the water, as soft fields.
static var _grove := PackedFloat32Array()
static var _green := PackedFloat32Array()
static var _patch: FastNoiseLite
## Extra depth of the river channel below a shallow basin.
const CHANNEL := 0.8
static var _gw: int = 0
static var _gh: int = 0


## Reads the arena's water (W) and dune (D) cells. Call before building.
static func setup(arena) -> void:
	_ready_noise()
	_gw = (Cfg.cols + PAD * 2) * R
	_gh = (Cfg.rows + PAD * 2) * R
	_wet = PackedFloat32Array()
	_wet.resize(_gw * _gh)
	_hill = PackedFloat32Array()
	_hill.resize(_gw * _gh)
	for key in arena.water:
		var cell: Vector2i = key
		for j in R:
			for i in R:
				_wet[((cell.y + PAD) * R + j) * _gw + (cell.x + PAD) * R + i] = 1.0
	for pass_no in 3:
		_wet = _blur(_wet)
	_bank = arena.river_row
	_road = PackedFloat32Array()
	_road.resize(_gw * _gh)
	for key in arena.roads:
		var cell: Vector2i = key
		for j in R:
			for i in R:
				_road[((cell.y + PAD) * R + j) * _gw + (cell.x + PAD) * R + i] = 1.0
	_road = _blur(_road)
	_grove = PackedFloat32Array()
	_grove.resize(_gw * _gh)
	for key in arena.decor:
		if arena.decor[key] != "T":
			continue
		var cell: Vector2i = key
		for j in R:
			for i in R:
				_grove[((cell.y + PAD) * R + j) * _gw + (cell.x + PAD) * R + i] = 1.0
	for pass_no in 2:
		_grove = _blur(_grove)
	_green = _wet.duplicate()
	for pass_no in 6:
		_green = _blur(_green)
	_chan = PackedFloat32Array()
	_chan.resize(_gw * _gh)
	for key in arena.deep:
		var cell: Vector2i = key
		for j in R:
			for i in R:
				_chan[((cell.y + PAD) * R + j) * _gw + (cell.x + PAD) * R + i] = 1.0
	for pass_no in 2:
		_chan = _blur(_chan)
	for key in arena.dunes:
		var cell: Vector2i = key
		var cx: float = cell.x + 0.5
		var cz: float = cell.y + 0.5
		for j in range((cell.y + PAD - 3) * R, (cell.y + PAD + 4) * R):
			for i in range((cell.x + PAD - 3) * R, (cell.x + PAD + 4) * R):
				var sx: float = (i + 0.5) / R - PAD
				var sz: float = (j + 0.5) / R - PAD
				var d: float = Vector2(sx - cx, sz - cz).length()
				var v: float = 1.0 - smoothstep(0.0, 2.3, d)
				var k: int = j * _gw + i
				_hill[k] = maxf(_hill[k], v)


static func _blur(src: PackedFloat32Array) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(src.size())
	var out := PackedFloat32Array()
	out.resize(src.size())
	for j in _gh:
		for i in _gw:
			var k: int = j * _gw + i
			tmp[k] = 0.25 * src[j * _gw + maxi(i - 1, 0)] + 0.5 * src[k] \
				+ 0.25 * src[j * _gw + mini(i + 1, _gw - 1)]
	for j in _gh:
		for i in _gw:
			var k: int = j * _gw + i
			out[k] = 0.25 * tmp[maxi(j - 1, 0) * _gw + i] + 0.5 * tmp[k] \
				+ 0.25 * tmp[mini(j + 1, _gh - 1) * _gw + i]
	return out


static func _sample(field: PackedFloat32Array, x: float, z: float) -> float:
	if _gw == 0:
		return 0.0
	var fx: float = (x + PAD) * R - 0.5
	var fz: float = (z + PAD) * R - 0.5
	if fx < 0.0 or fz < 0.0 or fx >= _gw - 1 or fz >= _gh - 1:
		return 0.0
	var i: int = int(fx)
	var j: int = int(fz)
	var tx: float = fx - i
	var tz: float = fz - j
	var k: int = j * _gw + i
	return lerpf(lerpf(field[k], field[k + 1], tx),
		lerpf(field[k + _gw], field[k + _gw + 1], tx), tz)


## How much a point is on a road, 0..1.
static func road(x: float, z: float) -> float:
	return _sample(_road, x, z)


## How far a point is into the enemy's bank, 0 (our side, or no river) .. 1.
static func far_bank(x: float, z: float) -> float:
	if _bank.is_empty():
		return 0.0
	var i: int = clampi(int(x), 0, _bank.size() - 1)
	return smoothstep(1.0, 9.0, _bank[i] - z)


## How much a point belongs to a water basin, 0..1. Shores wander a little.
static func wetness(x: float, z: float) -> float:
	var w: float = _sample(_wet, x, z)
	if w <= 0.01:
		return 0.0
	return clampf(w + 0.1 * _roll.get_noise_2d(x * 2.3 + 9.0, z * 2.3), 0.0, 1.0)


## Depth of water over the ground at a point. Zero or less means dry.
static func water_depth(x: float, z: float) -> float:
	if _sample(_wet, x, z) <= 0.01:
		return 0.0
	return WATER_LEVEL - height(x, z)


static func _ready_noise() -> void:
	if _dune != null:
		return
	_dune = FastNoiseLite.new()
	_dune.seed = 21
	_dune.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_dune.frequency = 0.028
	_dune.fractal_type = FastNoiseLite.FRACTAL_NONE
	_roll = FastNoiseLite.new()
	_roll.seed = 8
	_roll.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_roll.frequency = 0.08
	_roll.fractal_octaves = 2
	# The same patches the ground cover uses, so dry earth lies under scrub.
	_patch = FastNoiseLite.new()
	_patch.seed = 5
	_patch.frequency = 0.09


static func height(x: float, z: float) -> float:
	_ready_noise()
	var w := float(Cfg.cols)
	var h := float(Cfg.rows)
	var dx: float = maxf(maxf(-x, x - w), 0.0)
	var dz: float = maxf(maxf(-z, z - h), 0.0)
	var out: float = sqrt(dx * dx + dz * dz)  # distance outside the battlefield
	var swell: float = 0.16 * _roll.get_noise_2d(x, z)
	var wet: float = wetness(x, z)
	var hill: float = _sample(_hill, x, z)
	if wet > 0.0 or hill > 0.0:
		swell = swell * (1.0 - 0.7 * wet) - BASIN * smoothstep(0.25, 0.8, wet) \
			+ DUNE_H * hill * (0.85 + 0.3 * _roll.get_noise_2d(x * 0.9, z * 0.9 + 30.0))
		if wet > 0.5:
			swell -= CHANNEL * smoothstep(0.3, 0.85, _sample(_chan, x, z))
	var crest: float = 1.0 - absf(_dune.get_noise_2d(x, z))
	var dunes: float = 3.4 * crest * crest + 1.3 * _roll.get_noise_2d(x * 0.3, z * 0.3) + 0.4
	var berm: float = 0.5 * smoothstep(0.2, 1.1, out) * (1.0 - smoothstep(1.5, 3.2, out))
	return lerpf(swell, dunes, smoothstep(2.0, 15.0, out)) + berm


static func normal(x: float, z: float) -> Vector3:
	var e := 0.2
	return Vector3(height(x - e, z) - height(x + e, z), 2.0 * e,
		height(x, z - e) - height(x, z + e)).normalized()


## Transform that sits something on the ground at (x, z), facing `heading`
## (game angle), tilted to the slope. `lift` raises it above the sand.
static func ground_xf(x: float, z: float, heading: float, lift: float = 0.0) -> Transform3D:
	var up := normal(x, z)
	var fwd := Vector3(cos(heading), 0.0, sin(heading))
	fwd = (fwd - up * fwd.dot(up)).normalized()
	return Transform3D(Basis(fwd, up, fwd.cross(up)), Vector3(x, height(x, z) + lift, z))


## Transform for a vehicle: it rests on four points (nose, tail, both
## sides), so it pitches and rolls over crests and dips instead of digging in.
static func vehicle_xf(x: float, z: float, heading: float, half_len: float,
		half_wid: float) -> Transform3D:
	var fwd := Vector3(cos(heading), 0.0, sin(heading))
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	var hf: float = height(x + fwd.x * half_len, z + fwd.z * half_len)
	var hb: float = height(x - fwd.x * half_len, z - fwd.z * half_len)
	var hr: float = height(x + side.x * half_wid, z + side.z * half_wid)
	var hl: float = height(x - side.x * half_wid, z - side.z * half_wid)
	var ax: Vector3 = (fwd * 2.0 * half_len + Vector3.UP * (hf - hb)).normalized()
	var az: Vector3 = (side * 2.0 * half_wid + Vector3.UP * (hr - hl)).normalized()
	var up: Vector3 = az.cross(ax).normalized()
	az = ax.cross(up)
	var y: float = maxf((hf + hb + hr + hl) * 0.25, height(x, z) - 0.04)
	return Transform3D(Basis(ax, up, az), Vector3(x, y, z))


static func build_mesh() -> ArrayMesh:
	# The browser version uses a coarser grid: a quarter of the triangles
	# to draw, and the map is built four times faster.
	var step := 1.0 if OS.has_feature("web") else 0.5
	var x0 := -46.0
	var z0 := -42.0
	var nx: int = int((float(Cfg.cols) + 92.0) / step) + 1
	var nz: int = int((float(Cfg.rows) + 72.0) / step) + 1
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for j in nz:
		for i in nx:
			heights[j * nx + i] = height(x0 + i * step, z0 + j * step)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(nx * nz)
	normals.resize(nx * nz)
	colors.resize(nx * nz)
	var splat_a := PackedFloat32Array()
	var splat_b := PackedFloat32Array()
	splat_a.resize(nx * nz * 4)
	splat_b.resize(nx * nz * 4)
	for j in nz:
		for i in nx:
			var k: int = j * nx + i
			var x: float = x0 + i * step
			var z: float = z0 + j * step
			verts[k] = Vector3(x, heights[k], z)
			var hl: float = heights[j * nx + maxi(i - 1, 0)]
			var hr: float = heights[j * nx + mini(i + 1, nx - 1)]
			var hu: float = heights[maxi(j - 1, 0) * nx + i]
			var hd: float = heights[mini(j + 1, nz - 1) * nx + i]
			normals[k] = Vector3(hl - hr, 2.0 * step, hu - hd).normalized()
			# Broad colour drift so the ground never looks like one repeated tile.
			var tint: float = 0.94 + 0.08 * _roll.get_noise_2d(x * 0.5 + 40.0, z * 0.5)
			var dx: float = maxf(maxf(-x, x - float(Cfg.cols)), 0.0)
			var dz: float = maxf(maxf(-z, z - float(Cfg.rows)), 0.0)
			var outside: float = smoothstep(2.0, 15.0, sqrt(dx * dx + dz * dz))
			var grit: float = _roll.get_noise_2d(x * 3.1, z * 3.1)
			# Which ground lies here. The shader blends one texture per weight.
			var far: float = far_bank(x, z)
			var worn: float = _sample(_road, x, z)
			if worn > 0.02:
				worn = smoothstep(0.2, 0.75, worn + 0.25 * grit)
			var damp := 0.0
			var bed := 0.0
			var deep := 0.0
			if _sample(_wet, x, z) > 0.01:
				var over: float = heights[k] - WATER_LEVEL
				damp = 1.0 - smoothstep(-0.03, 0.2, over + 0.05 * grit)
				bed = smoothstep(0.02, 0.22, -over)
				deep = smoothstep(0.35, 0.8, -over)
			var lush: float = smoothstep(0.06, 0.3, _sample(_green, x, z) + 0.05 * grit) * (1.0 - 0.8 * far)
			var grove: float = smoothstep(0.25, 0.7, _sample(_grove, x, z) + 0.15 * grit)
			var scrub: float = smoothstep(0.12, 0.3, _patch.get_noise_2d(x, z)) * (1.0 - outside)
			var dune: float = maxf(outside, _sample(_hill, x, z))
			colors[k] = Color(tint, tint * 0.99, tint * 0.975, dune)
			splat_a[k * 4] = worn
			splat_a[k * 4 + 1] = scrub
			splat_a[k * 4 + 2] = far
			splat_a[k * 4 + 3] = grove
			splat_b[k * 4] = damp
			splat_b[k * 4 + 1] = bed
			splat_b[k * 4 + 2] = deep
			splat_b[k * 4 + 3] = lush
	var indices := PackedInt32Array()
	indices.resize((nx - 1) * (nz - 1) * 6)
	var n: int = 0
	for j in nz - 1:
		for i in nx - 1:
			var a: int = j * nx + i
			var b: int = a + 1
			var c: int = a + nx
			var d: int = c + 1
			indices[n] = a
			indices[n + 1] = b
			indices[n + 2] = c
			indices[n + 3] = b
			indices[n + 4] = d
			indices[n + 5] = c
			n += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = splat_a
	arrays[Mesh.ARRAY_CUSTOM1] = splat_b
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	return mesh


## Flat water surface over every basin, on the same grid as the terrain.
## Vertex colour carries the depth, which the water shader turns into
## colour, foam and a soft shoreline. Returns null if the map has no water.
static func build_water_mesh() -> ArrayMesh:
	var step := 0.5
	var nx: int = int((Cfg.cols + 2.0) / step) + 1
	var nz: int = int((Cfg.rows + 2.0) / step) + 1
	var depth := PackedFloat32Array()
	depth.resize(nx * nz)
	for j in nz:
		for i in nx:
			depth[j * nx + i] = water_depth(-1.0 + i * step, -1.0 + j * step)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for j in nz - 1:
		for i in nx - 1:
			var ids: Array[int] = [j * nx + i, j * nx + i + 1, (j + 1) * nx + i,
				j * nx + i + 1, (j + 1) * nx + i + 1, (j + 1) * nx + i]
			var wet := false
			for id in ids:
				if depth[id] > 0.0:
					wet = true
			if not wet:
				continue
			for id in ids:
				verts.append(Vector3(-1.0 + (id % nx) * step, WATER_LEVEL, -1.0 + (id / nx) * step))
				normals.append(Vector3.UP)
				var d: float = clampf(depth[id] / 0.3, 0.0, 1.0)
				# Green carries how far down the river channel goes.
				colors.append(Color(d, clampf((depth[id] - 0.35) / CHANNEL, 0.0, 1.0), d, 1.0))
	if verts.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
