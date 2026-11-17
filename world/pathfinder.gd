extends RefCounted
## Grid pathfinding. Alloy is solid. Plating is passable but costly, so enemies
## prefer open lanes and shoot through plating only when it is worth it.

var astar := AStarGrid2D.new()
var arena
## True for the allies' map: they never drive through the base's walls.
var walls_solid := false


func setup(a) -> void:
	arena = a
	astar.region = Rect2i(0, 0, Cfg.cols, Cfg.rows)
	astar.cell_size = Vector2(Cfg.CELL, Cfg.CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in Cfg.rows:
		for x in Cfg.cols:
			refresh_cell(Vector2i(x, y))


func refresh_cell(cell: Vector2i) -> void:
	var t: int = arena.tile_at(cell)
	astar.set_point_solid(cell, t == arena.ALLOY or arena.built.has(cell)
		or (walls_solid and t == arena.PLATING))
	var weight := 1.0
	if t == arena.PLATING:
		weight = 5.0
	elif arena.deep.has(cell):
		weight = 7.0  # bots keep to the fords unless there is no other way
	elif arena.water.has(cell):
		weight = 2.2
	elif arena.dunes.has(cell):
		weight = 1.8
	elif arena.roads.has(cell):
		weight = 0.8
	astar.set_point_weight_scale(cell, weight)


func path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not astar.is_in_boundsv(from) or not astar.is_in_boundsv(to):
		return empty
	if astar.is_point_solid(from) or astar.is_point_solid(to):
		return empty
	return astar.get_id_path(from, to)
