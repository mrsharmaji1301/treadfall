extends StaticBody2D
## Tile arena: holds the grid and wall collision. Drawn by view/world_view.gd.
## PLATING is a breakable mud-brick wall, ALLOY is unbreakable concrete.
## The arena sits at the world origin, so local and global positions match.

signal tile_damaged(cell: Vector2i)
signal tile_destroyed(cell: Vector2i)

const Fx := preload("res://fx/fx.gd")

const EMPTY := 0
const PLATING := 1
const ALLOY := 2
const PLATING_HP := 2

var grid: Array = []
var enemy_spawns: Array[Vector2i] = []
var player_spawn := Vector2i(9, 13)
var core_cell := Vector2i(12, 12)
## Natural blockers: cell -> "T" (palm) or "M" (rock ridge).
## Solid like ALLOY.
var decor: Dictionary = {}
## Water cells. Open to tanks and shells, but tanks wade slowly.
var water: Dictionary = {}
## Deep water cells (also listed in `water`). Tanks cannot enter; shells
## and sight pass over.
var deep: Dictionary = {}
var _deep_body: StaticBody2D
## Road cells: packed earth, a little faster to drive on.
var roads: Dictionary = {}
## Where the enemy's Command Centre stands, or (-1, -1) if the map has none.
var enemy_core_cell := Vector2i(-1, -1)
## Defences to build: [cell, kind], kind "tower", "turret", "artillery" or "guard".
var defence_spots: Array = []
## Cells with loot hidden in the jungle.
var loot_cells: Array[Vector2i] = []
## Cells a building stands on. Tanks cannot path through them.
var built: Dictionary = {}
## For each column, the row the river runs along. Empty if there is no river.
var river_row := PackedFloat32Array()
## Dune cells. Open too: tanks climb over them, slower.
var dunes: Dictionary = {}
var _hp: Dictionary = {}
var _shapes: Dictionary = {}


func build(layout: Array) -> void:
	collision_layer = Cfg.LAYER_WALL
	collision_mask = 0
	Cfg.rows = layout.size()
	Cfg.cols = String(layout[0]).length()
	layout = _open_loot(layout)
	var tile_shape := RectangleShape2D.new()
	tile_shape.size = Vector2(Cfg.CELL, Cfg.CELL)
	var trunk_shape := CircleShape2D.new()
	trunk_shape.radius = 11.0
	_deep_body = StaticBody2D.new()
	_deep_body.collision_layer = Cfg.LAYER_DEEP
	_deep_body.collision_mask = 0
	add_child(_deep_body)
	for y in Cfg.rows:
		var row: Array = []
		var line: String = layout[y] if y < layout.size() else ""
		for x in Cfg.cols:
			var ch: String = line[x] if x < line.length() else "."
			var cell := Vector2i(x, y)
			var t: int = EMPTY
			match ch:
				"#":
					t = PLATING
				"X":
					t = ALLOY
				"T", "M":
					t = ALLOY
					decor[cell] = ch
				"D":
					dunes[cell] = true
				"W":
					water[cell] = true
				"R":
					water[cell] = true
					deep[cell] = true
					var ds := CollisionShape2D.new()
					ds.shape = tile_shape
					ds.position = cell_center(cell)
					_deep_body.add_child(ds)
				",":
					roads[cell] = true
				"E":
					enemy_core_cell = cell
					built[cell] = true
				"L":
					loot_cells.append(cell)
				"1", "2", "3", "4":
					defence_spots.append([cell, ["tower", "turret", "artillery", "guard"][int(ch) - 1]])
					built[cell] = true
				"S":
					enemy_spawns.append(cell)
				"P":
					player_spawn = cell
				"C":
					core_cell = cell
			row.append(t)
			if t != EMPTY:
				var cs := CollisionShape2D.new()
				# A palm only blocks at its trunk, so tanks slide round it.
				cs.shape = trunk_shape if ch == "T" else tile_shape
				cs.position = cell_center(cell)
				add_child(cs)
				_shapes[cell] = cs
			if t == PLATING:
				_hp[cell] = PLATING_HP
		grid.append(row)
	_find_river()
	_add_borders()


## Makes sure the tank can drive to every loot cache. A cache that is
## walled in by palms gets a one-cell track cut to it through the grove,
## along the cheapest line. Returns the corrected layout, and reports an
## error if some cache still cannot be reached (rock or concrete all round).
func _open_loot(layout: Array) -> Array:
	var rows: Array = []
	var start := Vector2i(-1, -1)
	var loot: Array[Vector2i] = []
	for y in layout.size():
		var line: String = layout[y]
		var chars: Array = []
		for x in Cfg.cols:
			var ch: String = line[x] if x < line.length() else "."
			chars.append(ch)
			if ch == "P":
				start = Vector2i(x, y)
			elif ch == "L":
				loot.append(Vector2i(x, y))
		rows.append(chars)
	if start.x < 0 or loot.is_empty():
		return layout
	var steps: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var cut: int = 0
	for cache in loot:
		# Everywhere the tank can drive to from its start.
		var open: Dictionary = {start: true}
		var queue: Array[Vector2i] = [start]
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			for s in steps:
				var n: Vector2i = c + s
				if n.x < 0 or n.y < 0 or n.x >= Cfg.cols or n.y >= rows.size() or open.has(n):
					continue
				if "TMX#1234CE".contains(rows[n.y][n.x]):
					continue
				open[n] = true
				queue.append(n)
		if open.has(cache):
			continue
		# Cheapest way out of the pocket: palms cost more than open ground.
		var cost: Dictionary = {cache: 0}
		var from: Dictionary = {}
		var frontier: Array = [[0, cache]]
		var exit := Vector2i(-1, -1)
		while not frontier.is_empty():
			var best: int = 0
			for i in frontier.size():
				if frontier[i][0] < frontier[best][0]:
					best = i
			var item: Array = frontier.pop_at(best)
			var c: Vector2i = item[1]
			if open.has(c):
				exit = c
				break
			for s in steps:
				var n: Vector2i = c + s
				if n.x < 1 or n.y < 1 or n.x >= Cfg.cols - 1 or n.y >= rows.size() - 1:
					continue
				var ch: String = rows[n.y][n.x]
				if "MX#1234CE".contains(ch):
					continue
				var step_cost: int = int(item[0]) + (4 if ch == "T" else 1)
				if not cost.has(n) or step_cost < int(cost[n]):
					cost[n] = step_cost
					from[n] = c
					frontier.append([step_cost, n])
		if exit.x < 0:
			push_error("Loot cache at %s cannot be reached by the tank." % [cache])
			continue
		var at: Vector2i = exit
		while at != cache:
			if rows[at.y][at.x] == "T":
				rows[at.y][at.x] = "."
				cut += 1
			at = from[at]
	if cut == 0:
		return layout
	var fixed: Array = []
	for chars in rows:
		fixed.append("".join(PackedStringArray(chars)))
	return fixed


## Works out where the river runs from its deep cells, column by column.
func _find_river() -> void:
	if deep.is_empty():
		return
	var sum := PackedFloat32Array()
	var count := PackedInt32Array()
	sum.resize(Cfg.cols)
	count.resize(Cfg.cols)
	for key in deep:
		var cell: Vector2i = key
		sum[cell.x] += cell.y + 0.5
		count[cell.x] += 1
	river_row.resize(Cfg.cols)
	var last := -1.0
	for x in Cfg.cols:
		if count[x] > 0:
			last = sum[x] / count[x]
		river_row[x] = last
	# Columns before the first deep cell, and fords, copy a neighbour.
	last = -1.0
	for x in range(Cfg.cols - 1, -1, -1):
		if river_row[x] < 0.0:
			river_row[x] = last if last >= 0.0 else Cfg.rows * 0.5
		elif count[x] > 0:
			last = river_row[x]
	for pass_no in 6:
		var smooth := river_row.duplicate()
		for x in range(1, Cfg.cols - 1):
			smooth[x] = (river_row[x - 1] + river_row[x] * 2.0 + river_row[x + 1]) * 0.25
		river_row = smooth


## True on the far (enemy) bank of the river. Always false with no river.
func is_north(pos: Vector2) -> bool:
	if river_row.is_empty():
		return false
	var x: int = clampi(int(pos.x / Cfg.CELL), 0, Cfg.cols - 1)
	return pos.y / Cfg.CELL < river_row[x]


func _add_borders() -> void:
	var w := float(Cfg.cols * Cfg.CELL)
	var h := float(Cfg.rows * Cfg.CELL)
	var th := 64.0
	var rects: Array[Rect2] = [
		Rect2(-th, -th, w + th * 2.0, th),
		Rect2(-th, h, w + th * 2.0, th),
		Rect2(-th, 0.0, th, h),
		Rect2(w, 0.0, th, h),
	]
	for r in rects:
		var shape := RectangleShape2D.new()
		shape.size = r.size
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = r.get_center()
		add_child(cs)


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < Cfg.cols and cell.y < Cfg.rows


func tile_at(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return ALLOY
	return grid[cell.y][cell.x]


func cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * float(Cfg.CELL)


func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i((pos / float(Cfg.CELL)).floor())


func is_water(pos: Vector2) -> bool:
	return water.has(world_to_cell(pos))


func is_deep(pos: Vector2) -> bool:
	return deep.has(world_to_cell(pos))


## Speed factor of the ground at a point: slower in water and on dunes.
func pace_at(pos: Vector2) -> float:
	var cell := world_to_cell(pos)
	if deep.has(cell):
		return Cfg.DEEP_SLOW
	if water.has(cell):
		return Cfg.WATER_SLOW
	if dunes.has(cell):
		return Cfg.DUNE_SLOW
	if roads.has(cell):
		return Cfg.ROAD_FAST
	return 1.0


## Called by shells. `point` is just inside the wall that was hit.
func damage_at(point: Vector2, amount: int) -> void:
	var cell := world_to_cell(point)
	if tile_at(cell) != PLATING:
		return
	var left: int = int(_hp.get(cell, 0)) - amount
	if left > 0:
		_hp[cell] = left
		Fx.dust(get_parent(), cell_center(cell), 6)
		tile_damaged.emit(cell)
	else:
		grid[cell.y][cell.x] = EMPTY
		_hp.erase(cell)
		if _shapes.has(cell):
			_shapes[cell].queue_free()
			_shapes.erase(cell)
		Fx.dust(get_parent(), cell_center(cell), 18)
		tile_destroyed.emit(cell)
