extends CanvasLayer
## The aiming mark. It is drawn by the game, not by Windows, so it always
## shows. Style, colour and size come from the settings (Cfg.cross_*).
## An amber cross over it means the aim point is out of gun range.

const AMBER := Color(1.0, 0.62, 0.15)
const INK := Color(0, 0, 0, 0.95)
const HALO := Color(1, 1, 1, 0.5)

## The game mode: gives `player`.
var mode
var _mark: Control
var _far := false


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mark = Control.new()
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.draw.connect(func() -> void: paint(_mark, _far))
	add_child(_mark)


func _input(event: InputEvent) -> void:
	# With a changed aim speed the pointer is captured and the mark is moved
	# by the raw mouse movement times that speed.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var room: Vector2 = _mark.get_viewport_rect().size
		Cfg.aim_pos = (Cfg.aim_pos + event.relative * Cfg.aim_speed).clamp(Vector2.ZERO, room)


func _process(_delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not Cfg.has_meta("aim_test"):
		Cfg.aim_pos = _mark.get_viewport().get_mouse_position()
	_mark.position = Cfg.aim_pos
	var far := false
	if mode != null and is_instance_valid(mode) and is_instance_valid(mode.get("player")):
		var view = get_tree().get_first_node_in_group("world_view")
		if view != null and mode.player.alive:
			far = view.mouse_ground().distance_to(mode.player.global_position) > mode.player.shell_range
	if far != _far:
		_far = far
		_mark.queue_redraw()


## Draws the mark round (0, 0) of `on`. Also used by the settings preview.
static func paint(on: Control, far: bool) -> void:
	var s: float = Cfg.cross_size * 0.5
	var col: Color = Cfg.CROSS_COLORS[Cfg.cross_color][1]
	var w: float = maxf(2.0, s * 0.15)
	match Cfg.cross_style:
		0:
			# Two black rings and a coloured dot. A thin pale edge keeps
			# the rings readable over dark ground and water.
			for r in [s - w * 0.5, s * 0.55]:
				on.draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, HALO, w + 2.0, true)
			for r in [s - w * 0.5, s * 0.55]:
				on.draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, INK, w, true)
			var dot: float = maxf(2.0, s * 0.17)
			on.draw_circle(Vector2.ZERO, dot + 1.0, INK)
			on.draw_circle(Vector2.ZERO, dot, col)
		1:
			for pass_no in 2:
				var c: Color = INK if pass_no == 0 else col
				var lw: float = w + 3.0 if pass_no == 0 else w
				var g: float = 1.5 if pass_no == 0 else 0.0
				on.draw_arc(Vector2.ZERO, s * 0.6, 0.0, TAU, 48, c, lw, true)
				for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
					on.draw_line(dir * (s * 0.72 - g), dir * (s + g), c, lw, true)
				on.draw_circle(Vector2.ZERO, maxf(1.5, s * 0.1) + g, c)
		2:
			for pass_no in 2:
				var c: Color = INK if pass_no == 0 else col
				var lw: float = w + 3.0 if pass_no == 0 else w
				var g: float = 1.5 if pass_no == 0 else 0.0
				for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
					on.draw_line(dir * (s * 0.3 - g), dir * (s + g), c, lw, true)
				on.draw_circle(Vector2.ZERO, maxf(1.5, s * 0.08) + g, c)
		_:
			on.draw_circle(Vector2.ZERO, s + 2.0, INK)
			on.draw_circle(Vector2.ZERO, s, col)
			on.draw_circle(Vector2.ZERO, s * 0.35, INK)
	if far:
		for pass_no in 2:
			var c: Color = INK if pass_no == 0 else AMBER
			var lw: float = w + 3.0 if pass_no == 0 else w
			for dir in [Vector2(1, 1), Vector2(1, -1)]:
				var d: Vector2 = dir.normalized() * maxf(7.0, s * 0.5)
				on.draw_line(-d, d, c, lw, true)
