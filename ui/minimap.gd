extends CanvasLayer
## Minimap with a radar, top right. The map itself is always drawn, with an
## outline of the part of it that is on screen. Every enemy inside that
## on-screen area is always shown as a solid red blip, in any camera view;
## zoom out and the radar covers more. The scanner cone follows the gun; its sweep is decoration only.
## Friends are green: your tank, the base. Every tank blip carries a pointer
## showing where its hull is heading.

const Ui := preload("res://ui/ui_kit.gd")

const WIDTH := 264.0
const SWEEP_TIME := 2.2

## The game mode: gives `arena`, `player`, and `core` if it has one.
var mode
var _panel: Control
var _map: ImageTexture
var _img: Image
var _scale := 1.0
var _angle := 0.0
var _view = null


func _ready() -> void:
	var arena = mode.arena
	_scale = WIDTH / float(Cfg.cols * Cfg.CELL)
	var size := Vector2(WIDTH, WIDTH * Cfg.rows / float(Cfg.cols))
	var frame := Panel.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Cfg.COL_PANEL
	box.border_color = Cfg.COL_ACCENT
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", box)
	frame.position = Vector2(1280.0 - WIDTH - 22.0, 54.0)
	frame.size = size + Vector2(8, 8)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	_panel = Control.new()
	_panel.position = frame.position + Vector2(4, 4)
	_panel.size = size
	_panel.clip_contents = true
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.draw.connect(_paint)
	add_child(_panel)
	_img = Image.create(Cfg.cols, Cfg.rows, false, Image.FORMAT_RGB8)
	for y in Cfg.rows:
		for x in Cfg.cols:
			_img.set_pixel(x, y, _cell_color(arena, Vector2i(x, y)))
	_map = ImageTexture.create_from_image(_img)
	arena.tile_destroyed.connect(_on_tile_destroyed)
	# Steel bezel over the plain border.
	var bezel := Ui.frame("hud_panel.png", frame.position - Vector2(14, 14),
		frame.size + Vector2(28, 28), 26, false, 128)
	if bezel != null:
		add_child(bezel)


func _cell_color(arena, cell: Vector2i) -> Color:
	if arena.deep.has(cell):
		return Color(0.06, 0.2, 0.36)
	if arena.water.has(cell):
		return Color(0.16, 0.42, 0.5)
	if arena.dunes.has(cell):
		return Color(0.5, 0.43, 0.3)
	if arena.roads.has(cell):
		return Color(0.47, 0.4, 0.3)
	if arena.decor.has(cell):
		return Color(0.2, 0.36, 0.16) if arena.decor[cell] == "T" else Color(0.34, 0.27, 0.2)
	var t: int = arena.tile_at(cell)
	if t == arena.PLATING:
		return Color(0.52, 0.34, 0.22)
	if t == arena.ALLOY:
		return Color(0.5, 0.5, 0.48)
	var shade: float = 0.36 + 0.02 * ((cell.x + cell.y) % 2)
	return Color(shade, shade * 0.86, shade * 0.62)


func _on_tile_destroyed(cell: Vector2i) -> void:
	_img.set_pixel(cell.x, cell.y, _cell_color(mode.arena, cell))
	_map.update(_img)


func _process(delta: float) -> void:
	_angle = fposmod(_angle + TAU * delta / SWEEP_TIME, TAU)
	if _view == null or not is_instance_valid(_view):
		_view = get_tree().get_first_node_in_group("world_view")
	_panel.queue_redraw()


func _paint() -> void:
	var c: Control = _panel
	c.draw_texture_rect(_map, Rect2(Vector2.ZERO, c.size), false)
	var me = mode.player
	var on: bool = is_instance_valid(me) and me.alive
	if on:
		# The scanner cone points where the gun points and turns with it.
		# Inside it a bright line swings from edge to edge, for show.
		var here: Vector2 = me.global_position * _scale
		var reach: float = float(me.shell_range) * _scale * 2.4
		var facing: float = me.turret_angle
		var half := 0.5
		var fan := PackedVector2Array([here])
		for i in 13:
			fan.append(here + Vector2.RIGHT.rotated(facing - half + half * 2.0 * i / 12.0) * reach)
		c.draw_colored_polygon(fan, Color(0.35, 1.0, 0.45, 0.16))
		for edge in [-half, half]:
			c.draw_line(here, here + Vector2.RIGHT.rotated(facing + edge) * reach, Color(0.35, 1.0, 0.45, 0.55), 1.0)
		var swing: float = sin(_angle) * half
		for i in 8:
			var a: float = facing + clampf(swing - signf(cos(_angle)) * i * 0.04, -half, half)
			c.draw_line(here, here + Vector2.RIGHT.rotated(a) * reach,
				Color(0.5, 1.0, 0.6, 0.5 * (1.0 - i / 8.0)), 1.5)
	if _view != null and is_instance_valid(_view):
		# Outline of what the camera is showing.
		var patch: PackedVector2Array = _view.view_patch()
		for i in 4:
			c.draw_line(patch[i] * _scale, patch[(i + 1) % 4] * _scale, Color(1, 1, 1, 0.55), 1.0)
	var core = mode.get("core")
	if core != null and is_instance_valid(core) and core.alive:
		var at: Vector2 = core.global_position * _scale
		c.draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), Color(0.3, 1.0, 0.4))
		c.draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), Color(0, 0, 0, 0.8), false, 1.0)
	for item in get_tree().get_nodes_in_group("pickups"):
		if not item.cache:
			c.draw_circle(item.global_position * _scale, 2.0, Color(1.0, 0.9, 0.3))
	# Defences: squares for guns, triangles for towers. Our towers show
	# what they can see as a faint circle.
	var towers: Array = []
	for b in get_tree().get_nodes_in_group("structures"):
		if not b.alive:
			continue
		var ours: bool = b.team == Cfg.TEAM_PLAYER
		var tone := Color(0.3, 1.0, 0.4) if ours else Color(1.0, 0.25, 0.18)
		var bp: Vector2 = b.global_position * _scale
		if b.kind == "tower":
			c.draw_colored_polygon(PackedVector2Array([bp + Vector2(0, -4), bp + Vector2(3.5, 3),
				bp + Vector2(-3.5, 3)]), tone)
			if ours:
				towers.append(b)
				c.draw_arc(bp, b.sight() * _scale, 0.0, TAU, 32, Color(0.3, 1.0, 0.4, 0.22), 1.0)
		else:
			var half: float = 3.0 if b.kind == "guard" else 2.2
			c.draw_rect(Rect2(bp - Vector2(half, half), Vector2(half, half) * 2.0), tone)
	var foe = mode.get("enemy_core")
	if foe != null and is_instance_valid(foe) and foe.alive:
		var fp: Vector2 = foe.global_position * _scale
		c.draw_rect(Rect2(fp - Vector2(4, 4), Vector2(8, 8)), Color(1.0, 0.25, 0.18))
		c.draw_rect(Rect2(fp - Vector2(4, 4), Vector2(8, 8)), Color(0, 0, 0, 0.8), false, 1.0)
	var seen: bool = _view != null and is_instance_valid(_view)
	for t in get_tree().get_nodes_in_group("tanks"):
		if not t.alive:
			continue
		if t.team == Cfg.TEAM_PLAYER:
			_blip(c, t, Color(0.3, 1.0, 0.4))
		elif GameState.night > 0.5:
			# THE SHIFT: at night only what our tanks or towers can see.
			if _near_ours(t) or _watched(t, towers):
				_blip(c, t, Color(1.0, 0.18, 0.12))
		elif (seen and _view.on_screen(t.global_position)) or _watched(t, towers):
			_blip(c, t, Color(1.0, 0.18, 0.12))
	# Portal gates: violet rings, bright and pulsing while open.
	for g in get_tree().get_nodes_in_group("portals"):
		var gp: Vector2 = g.global_position * _scale
		var open: bool = g.is_open()
		var tone := Color(0.75, 0.5, 1.0, 1.0 if open else 0.8)
		c.draw_arc(gp, 4.5 + (sin(_angle * 3.0) * 1.2 if open else 0.0), 0.0, TAU, 16, tone, 2.0)
	# The map dims at night.
	if GameState.night > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.02, 0.02, 0.08, 0.35 * GameState.night))


## True if one of our own tanks is close enough to see it in the dark.
func _near_ours(tank) -> bool:
	for t in get_tree().get_nodes_in_group("tanks"):
		if t.alive and t.team == Cfg.TEAM_PLAYER \
				and t.global_position.distance_to(tank.global_position) < Cfg.NIGHT_VISION:
			return true
	return false


## True if one of our watch towers can see this tank.
func _watched(tank, towers: Array) -> bool:
	for b in towers:
		if b.global_position.distance_to(tank.global_position) < b.sight() * lerpf(1.0, 0.75, GameState.night):
			return true
	return false


## A dot with a pointer on the side the tank's hull is heading.
func _blip(c: Control, tank, color: Color) -> void:
	var at: Vector2 = tank.global_position * _scale
	var dir := Vector2.RIGHT.rotated(tank.hull_angle)
	var side := dir.orthogonal()
	c.draw_circle(at, 3.6, Color(0, 0, 0, color.a * 0.8))
	c.draw_circle(at, 2.8, color)
	c.draw_colored_polygon(PackedVector2Array([at + dir * 9.0, at + dir * 4.0 + side * 3.0,
		at + dir * 4.0 - side * 3.0]), color)
