extends RefCounted
## THE SHIFT, put into a game mode with one call: the day/night clock, two
## pairs of portal gates, and the clock on screen. A mode calls
## Shift.setup(self) after its arena and view are built. The clock node is
## kept as the mode's meta "cycle".

const DayCycle := preload("res://world/day_cycle.gd")
const Portal := preload("res://entities/portal.gd")
const PortalView := preload("res://view/portal_view.gd")
const ShiftClock := preload("res://ui/shift_clock.gd")


static func setup(mode) -> void:
	var cycle = DayCycle.new()
	mode.add_child(cycle)
	mode.set_meta("cycle", cycle)
	var arena = mode.arena
	var c: int = Cfg.cols
	var r: int = Cfg.rows
	# Pair one joins the left and right edges; pair two runs corner to
	# corner, from near our base to the enemy's side.
	var pairs := [[Vector2i(2, r / 2), Vector2i(c - 3, r / 2)],
		[Vector2i(3, r - 3), Vector2i(c - 4, 2)]]
	var taken: Array = []
	for pair in pairs:
		var a: Vector2i = _spot(arena, pair[0], taken)
		taken.append(a)
		var b: Vector2i = _spot(arena, pair[1], taken)
		taken.append(b)
		var ga = _gate(mode, arena, a)
		var gb = _gate(mode, arena, b)
		ga.partner = gb
		gb.partner = ga
	var clock = ShiftClock.new()
	clock.mode = mode
	clock.cycle = cycle
	mode.add_child(clock)


static func _gate(mode, arena, cell: Vector2i):
	var g = Portal.new()
	g.position = arena.cell_center(cell)
	# Leave towards the middle of the map.
	var mid := Vector2(Cfg.cols, Cfg.rows) * 0.5 * Cfg.CELL
	g.exit_dir = (mid - g.position).normalized()
	mode.add_child(g)
	var v = PortalView.new()
	v.setup(g)
	mode.view.add_child(v)
	return g


## True if a tank can stand on this cell.
static func _open(arena, cell: Vector2i) -> bool:
	if cell.x < 1 or cell.y < 1 or cell.x >= Cfg.cols - 1 or cell.y >= Cfg.rows - 1:
		return false
	return arena.tile_at(cell) == arena.EMPTY and not arena.water.has(cell) \
		and not arena.deep.has(cell) and not arena.built.has(cell) and cell != arena.core_cell


## The open cell nearest to `want` with open ground all round it, away
## from spawn points and other gates.
static func _spot(arena, want: Vector2i, taken: Array) -> Vector2i:
	var keep_off: Array = taken + [arena.player_spawn, arena.core_cell]
	keep_off.append_array(arena.enemy_spawns)
	for ring in 12:
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var cell := want + Vector2i(dx, dy)
				var ok := true
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						if not _open(arena, cell + Vector2i(ox, oy)):
							ok = false
				for k in keep_off:
					if absi(k.x - cell.x) + absi(k.y - cell.y) < 3:
						ok = false
				if ok:
					return cell
	return want
