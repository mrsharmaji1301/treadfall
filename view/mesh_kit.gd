extends RefCounted
## Small helpers for building models out of shaped parts.


## Extrudes a convex outline (in the XY plane) along Z, centred on Z = 0.
## Used with double-sided materials, so winding order does not matter.
static func prism(outline: PackedVector2Array, depth: float,
		xf: Transform3D = Transform3D.IDENTITY) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat, hard-edged plates
	var h := depth * 0.5
	var n := outline.size()
	for i in range(1, n - 1):
		_tri(st, xf, _v(outline[0], h), _v(outline[i], h), _v(outline[i + 1], h))
		_tri(st, xf, _v(outline[0], -h), _v(outline[i + 1], -h), _v(outline[i], -h))
	for i in n:
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % n]
		_tri(st, xf, _v(a, h), _v(a, -h), _v(b, -h))
		_tri(st, xf, _v(a, h), _v(b, -h), _v(b, h))
	st.generate_normals()
	st.index()
	return st.commit()


## Faceted solid between two convex outlines (x, z) at heights y0 and y1.
## Both outlines need the same number of points. Gives sloped armour plates.
static func loft(bottom: PackedVector2Array, y0: float, top: PackedVector2Array,
		y1: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var n := bottom.size()
	var xf := Transform3D.IDENTITY
	for i in range(1, n - 1):
		_tri(st, xf, _f(bottom[0], y0), _f(bottom[i], y0), _f(bottom[i + 1], y0))
		_tri(st, xf, _f(top[0], y1), _f(top[i + 1], y1), _f(top[i], y1))
	for i in n:
		var j := (i + 1) % n
		_tri(st, xf, _f(bottom[i], y0), _f(top[i], y1), _f(top[j], y1))
		_tri(st, xf, _f(bottom[i], y0), _f(top[j], y1), _f(bottom[j], y0))
	st.generate_normals()
	st.index()
	return st.commit()


static func _f(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## Adds a mesh with a position and rotation to a list for merge().
static func put(list: Array, mesh: Mesh, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	list.append([mesh, Transform3D(Basis.from_euler(rot), pos)])


## Joins many small parts into one mesh, so a detailed model costs one draw
## call per material instead of one per part.
static func merge(list: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for entry in list:
		st.append_from(entry[0], 0, entry[1])
	return st.commit()


static func _v(p: Vector2, z: float) -> Vector3:
	return Vector3(p.x, p.y, z)


static func _tri(st: SurfaceTool, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(xf * a)
	st.add_vertex(xf * b)
	st.add_vertex(xf * c)


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func cylinder(radius: float, height: float, segments: int = 12) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


static func part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## Weathered boulder: a sphere pushed about by noise, then cut by a few
## random planes so it gets flat faces and real edges.
static func rock(seed_value: int, detail: int = 22) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = detail
	sphere.rings = maxi(detail / 2, 3)
	var arrays: Array = sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 1.3
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var planes: Array[Plane] = []
	for i in 8:
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 1.0),
			rng.randf_range(-1.0, 1.0)).normalized()
		planes.append(Plane(dir, rng.randf_range(0.27, 0.43)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in indices:
		var v: Vector3 = verts[i]
		v *= 1.0 + 0.3 * n.get_noise_3d(v.x, v.y, v.z) + 0.07 * n.get_noise_3d(v.x * 4.0, v.y * 4.0, v.z * 4.0)
		for pl in planes:
			var over: float = pl.distance_to(v)
			if over > 0.0:
				v -= pl.normal * over * 0.9
		st.add_vertex(v)
	st.index()
	st.generate_normals()
	return st.commit()


## Palm trunk: a thick tube that bends as it rises, swollen at the foot and
## again under the crown where the old frond bases sit. `lean` is how far
## the top ends up from the base. The top is at (lean.x, height, lean.y).
static func palm_trunk(height: float, lean: Vector2, radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 12
	var sides := 10
	for r in rings:
		var t: float = float(r) / float(rings - 1)
		var bend: float = pow(t, 1.7)
		var centre := Vector3(lean.x * bend, height * t, lean.y * bend)
		var rad: float = radius * (1.0 - 0.3 * t) + radius * 0.55 * exp(-t * 9.0) \
			+ radius * 0.5 * smoothstep(0.8, 0.95, t) * (1.0 - smoothstep(0.95, 1.0, t) * 0.5)
		for k in sides + 1:
			var a: float = TAU * k / sides
			var out := Vector3(cos(a), 0.0, sin(a))
			st.set_normal(out)
			st.set_uv(Vector2(2.0 * k / sides, t * height * 1.1))
			st.add_vertex(centre + out * rad)
	for r in rings - 1:
		for k in sides:
			var a: int = r * (sides + 1) + k
			var c: int = a + sides + 1
			st.add_index(a)
			st.add_index(c)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(c)
			st.add_index(c + 1)
	st.generate_tangents()
	return st.commit()


## Palm crown with real volume. Fronds leave `top` in every direction and at
## every height: young ones stand up in the middle, the rest arch out and
## droop, and dead brown ones hang down against the trunk. Each frond bends
## along its length, twists, and is arched across its width, so it never
## reads as a flat card. `dry` 0..1 gives a thirstier, yellower tree.
static func palm_crown(top: Vector3, rng: RandomNumberGenerator, count: int,
		length: float, dry: float, dead: int = -1) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var golden := 2.39996
	for f in count:
		var tier: float = (f + rng.randf()) / count          # 0 top .. 1 bottom
		var yaw: float = f * golden + rng.randf_range(-0.25, 0.25)
		var pitch: float = deg_to_rad(lerpf(78.0, -8.0, pow(tier, 0.8)) + rng.randf_range(-8.0, 8.0))
		var droop: float = deg_to_rad(lerpf(55.0, 120.0, tier) + rng.randf_range(-10.0, 15.0))
		var reach: float = length * lerpf(0.7, 1.1, sin(tier * PI)) * rng.randf_range(0.9, 1.1)
		var g: float = rng.randf_range(0.5, 0.8)
		var shade := Color(g * 0.8, g, g * 0.62)
		if rng.randf() < 0.12 + dry * 0.5:
			shade = shade.lerp(Color(g * 1.25, g * 0.95, g * 0.4), 0.7)
		_frond(st, top, yaw, pitch, droop, reach, shade, rng)
	# Dead fronds hanging in a skirt under the crown.
	for f in (5 + int(dry * 4.0)) if dead < 0 else dead:
		var g: float = rng.randf_range(0.45, 0.7)
		_frond(st, top - Vector3(0.0, 0.06, 0.0), rng.randf() * TAU, deg_to_rad(rng.randf_range(-35.0, -15.0)),
			deg_to_rad(rng.randf_range(40.0, 60.0)), length * rng.randf_range(0.55, 0.75),
			Color(g * 1.15, g * 0.8, g * 0.42), rng)
	st.generate_normals()
	st.index()
	return st.commit()


static func _frond(st: SurfaceTool, from: Vector3, yaw: float, pitch: float, droop: float,
		reach: float, shade: Color, rng: RandomNumberGenerator) -> void:
	var dir := Vector3(cos(yaw), 0.0, sin(yaw))
	var side_h := Vector3(-dir.z, 0.0, dir.x)
	var width: float = reach * 0.42
	var twist: float = rng.randf_range(-0.7, 0.7)
	var segs := 7
	var p := from
	var rows: Array = []
	for s in segs + 1:
		var t: float = float(s) / float(segs)
		var ang: float = pitch - droop * t * t * 0.5 - droop * t * 0.5
		var along := dir * cos(ang) + Vector3.UP * sin(ang)
		var lift := Vector3.UP * cos(ang) - dir * sin(ang)
		var roll: float = twist * t
		var side := side_h * cos(roll) + lift * sin(roll)
		var up := lift * cos(roll) - side_h * sin(roll)
		# Across the frond: leaflets rise off the rib, then hang at the tips.
		var tint := Color(shade.r, shade.g, shade.b) * lerpf(0.55, 1.0, t)
		rows.append([
			p - side * width * 0.46 - up * width * 0.2,
			p - side * width * 0.25 + up * width * 0.07,
			p,
			p + side * width * 0.25 + up * width * 0.07,
			p + side * width * 0.46 - up * width * 0.2,
			1.0 - t, tint])
		p += along * (reach / segs)
	for s in segs:
		var a: Array = rows[s]
		var b: Array = rows[s + 1]
		for h in 4:
			var u0: float = 0.25 * h
			var u1: float = 0.25 * h + 0.25
			_leaf(st, a[h], Vector2(u0, a[5]), a[6])
			_leaf(st, a[h + 1], Vector2(u1, a[5]), a[6])
			_leaf(st, b[h], Vector2(u0, b[5]), b[6])
			_leaf(st, a[h + 1], Vector2(u1, a[5]), a[6])
			_leaf(st, b[h + 1], Vector2(u1, b[5]), b[6])
			_leaf(st, b[h], Vector2(u0, b[5]), b[6])


static func _leaf(st: SurfaceTool, p: Vector3, uv: Vector2, color: Color) -> void:
	st.set_color(color)
	st.set_uv(uv)
	st.add_vertex(p)


## Grass tuft: three upright crossed cards, one unit tall, rooted at y = 0.
static func tuft() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var a: float = PI * i / 3.0
		var side := Vector3(cos(a), 0.0, sin(a)) * 0.5
		var corners: Array = [[-side, Vector2(0, 1)], [side, Vector2(1, 1)],
			[-side + Vector3.UP, Vector2(0, 0)], [side, Vector2(1, 1)],
			[side + Vector3.UP, Vector2(1, 0)], [-side + Vector3.UP, Vector2(0, 0)]]
		for c in corners:
			st.set_normal(Vector3.UP)  # lit like the ground it grows from
			st.set_uv(c[1])
			st.add_vertex(c[0])
	st.index()
	return st.commit()


## Flat card lying on the ground or the water, one unit across.
static func pad() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners: Array = [[Vector3(-0.5, 0, -0.5), Vector2(0, 0)], [Vector3(0.5, 0, -0.5), Vector2(1, 0)],
		[Vector3(-0.5, 0, 0.5), Vector2(0, 1)], [Vector3(0.5, 0, -0.5), Vector2(1, 0)],
		[Vector3(0.5, 0, 0.5), Vector2(1, 1)], [Vector3(-0.5, 0, 0.5), Vector2(0, 1)]]
	for c in corners:
		st.set_normal(Vector3.UP)
		st.set_uv(c[1])
		st.add_vertex(c[0])
	st.index()
	return st.commit()


## --- Building models out of many small parts ------------------------------
## Parts are collected per material in a `bins` dictionary and joined at the
## end, so a detailed model costs one draw call per material.

static func add(bins: Dictionary, material: Material, mesh: Mesh, pos: Vector3,
		rot: Vector3 = Vector3.ZERO) -> void:
	if not bins.has(material):
		bins[material] = []
	bins[material].append([mesh, Transform3D(Basis.from_euler(rot), pos)])


## A square bar from a to b.
static func beam(bins: Dictionary, material: Material, a: Vector3, b: Vector3, thick: float) -> void:
	var d: Vector3 = b - a
	if not bins.has(material):
		bins[material] = []
	bins[material].append([box(Vector3(thick, d.length(), thick)),
		Transform3D(Basis(Quaternion(Vector3.UP, d.normalized())), (a + b) * 0.5)])


## Joins every bin into one MeshInstance3D under `parent`. Returns them.
static func flush(bins: Dictionary, parent: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for material in bins:
		out.append(part(parent, merge(bins[material]), material, Vector3.ZERO))
	bins.clear()
	return out


## Regular outline with n corners, for loft(). `stretch` scales x and z.
static func ngon(radius: float, n: int, turn: float = 0.0,
		stretch: Vector2 = Vector2.ONE, shift: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a: float = turn + TAU * i / n
		pts.append(Vector2(cos(a) * radius * stretch.x, sin(a) * radius * stretch.y) + shift)
	return pts


static func rect(hx: float, hz: float, shift: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-hx, -hz) + shift, Vector2(hx, -hz) + shift,
		Vector2(hx, hz) + shift, Vector2(-hx, hz) + shift])


## Cylinder with different top and bottom radius (a cone when top is 0).
static func cone(bottom: float, top: float, height: float, segments: int = 12) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


static func _bag() -> Mesh:
	var m := CapsuleMesh.new()
	m.radius = 0.06
	m.height = 0.27
	m.radial_segments = 8
	m.rings = 2
	return m


## A row of sandbags from a to b (on the ground plane), `rows` high.
static func bag_row(bins: Dictionary, material: Material, a: Vector3, b: Vector3, rows: int = 2) -> void:
	var d: Vector3 = b - a
	var yaw: float = atan2(-d.z, d.x)
	var count: int = maxi(int(d.length() / 0.24), 1)
	var bag := _bag()
	for row in rows:
		for i in count + (0 if row % 2 == 0 else -1):
			var t: float = (i + (0.5 if row % 2 == 0 else 1.0)) / count
			var xf := Transform3D(Basis.from_euler(Vector3(0.0, yaw + sin(i * 7.3 + row) * 0.12, PI * 0.5)),
				a + d * t + Vector3(0.0, 0.045 + row * 0.085, 0.0))
			xf.basis = xf.basis * Basis.from_scale(Vector3(0.75, 1.0, 1.0))
			if not bins.has(material):
				bins[material] = []
			bins[material].append([bag, xf])


## A ring of sandbags, with a gap of `gap` radians centred on `gap_at`.
static func bag_ring(bins: Dictionary, material: Material, radius: float, y: float,
		rows: int = 2, gap_at: float = 0.0, gap: float = 0.0) -> void:
	var count: int = maxi(int(TAU * radius / 0.25), 6)
	var bag := _bag()
	for row in rows:
		for i in count:
			var a: float = TAU * (i + 0.5 * (row % 2)) / count
			if gap > 0.0 and absf(angle_difference(a, gap_at)) < gap * 0.5:
				continue
			var xf := Transform3D(Basis.from_euler(Vector3(0.0, -a + PI * 0.5 + sin(i * 5.1) * 0.1, PI * 0.5)),
				Vector3(cos(a) * radius, y + 0.045 + row * 0.085, sin(a) * radius))
			xf.basis = xf.basis * Basis.from_scale(Vector3(0.75, 1.0, 1.0))
			if not bins.has(material):
				bins[material] = []
			bins[material].append([bag, xf])
