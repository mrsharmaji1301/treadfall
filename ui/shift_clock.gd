extends CanvasLayer
## THE SHIFT on screen: a small sun-and-moon clock under the map that says
## how long until the light changes, and big warnings when it does.
## Reads GameState; the clock node (world/day_cycle.gd) sends the warnings.

const Ui := preload("res://ui/ui_kit.gd")

var mode
var cycle
var _dial: Control
var _text: Label
var _warn: Label
var _sub: Label
var _tween: Tween
var _count: int = -1


func _ready() -> void:
	layer = 2
	var top: float = 54.0 + 264.0 * Cfg.rows / float(Cfg.cols) + 26.0
	var back := Panel.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Cfg.COL_PANEL
	box.border_color = Cfg.COL_ACCENT
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	back.add_theme_stylebox_override("panel", box)
	back.position = Vector2(994, top)
	back.size = Vector2(272, 40)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	_dial = Control.new()
	_dial.position = back.position + Vector2(22, 20)
	_dial.draw.connect(_paint_dial)
	add_child(_dial)
	_text = Ui.label("", 18, Cfg.COL_UI)
	_text.position = back.position + Vector2(44, 7)
	_text.size = Vector2(222, 26)
	add_child(_text)
	_warn = Ui.centered("", 40, Cfg.COL_WARN, 150.0)
	_sub = Ui.centered("", 20, Cfg.COL_UI, 200.0)
	for l in [_warn, _sub]:
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 8)
		l.modulate.a = 0.0
		add_child(l)
	if cycle != null:
		cycle.warned.connect(func(to_night: bool) -> void: _count = int(Cfg.SHIFT_WARN))
		cycle.shifted.connect(_on_shift)


func _process(_delta: float) -> void:
	var n: float = GameState.night
	var name := "NIGHT" if GameState.is_night else "DAY"
	var left: int = ceili(GameState.phase_left)
	if GameState.phase_left <= 0.0:
		_text.text = "DUSK  -  NIGHT IS FALLING" if not GameState.is_night else "DAWN  -  LIGHT RETURNS"
	else:
		_text.text = "%s %d     %d:%02d" % [name, GameState.day_no, left / 60, left % 60]
	_text.add_theme_color_override("font_color", Cfg.COL_UI.lerp(Color(0.72, 0.62, 1.0), n))
	_dial.queue_redraw()
	# Countdown to the change, big in the middle of the screen.
	if _count >= 0 and GameState.phase_left > 0.0:
		var now: int = ceili(GameState.phase_left)
		if now != _count:
			_count = now
			if GameState.is_night:
				_show("DAWN IN %d" % now, "Portals close at first light", Color(1.0, 0.8, 0.4), 0.9)
			else:
				_show("NIGHT FALLS IN %d" % now, "Sight will drop, portals will open", Color(0.75, 0.6, 1.0), 0.9)
	elif GameState.phase_left <= 0.0:
		_count = -1


func _on_shift(to_night: bool) -> void:
	_count = -1
	if to_night:
		_show("THE SHIFT  -  NIGHT", "Portals are open.  Everyone sees less.  Gunfire still gives you away.",
			Color(0.75, 0.6, 1.0), 3.0)
	else:
		_show("THE SHIFT  -  DAY", "Portals are shut.  Eyes reach far again.", Color(1.0, 0.85, 0.45), 2.5)


func _show(big: String, small: String, color: Color, hold: float) -> void:
	_warn.text = big
	_sub.text = small
	_warn.add_theme_color_override("font_color", color)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_warn.modulate.a = 1.0
	_sub.modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_interval(hold)
	_tween.set_parallel(true)
	_tween.tween_property(_warn, "modulate:a", 0.0, 0.5)
	_tween.tween_property(_sub, "modulate:a", 0.0, 0.5)


## The sun by day, the moon by night, a ring showing how much of the
## phase is left.
func _paint_dial() -> void:
	var n: float = GameState.night
	_dial.draw_circle(Vector2.ZERO, 14.0, Color(0.06, 0.06, 0.08))
	var full: float = Cfg.NIGHT_TIME if GameState.is_night else Cfg.DAY_TIME
	var part: float = clampf(GameState.phase_left / full, 0.0, 1.0)
	var ring := Color(1.0, 0.8, 0.3).lerp(Color(0.7, 0.6, 1.0), n)
	_dial.draw_arc(Vector2.ZERO, 13.0, -PI * 0.5, -PI * 0.5 + TAU * part, 32, ring, 2.5)
	if n < 0.5:
		_dial.draw_circle(Vector2.ZERO, 7.0, Color(1.0, 0.82, 0.3))
		for i in 8:
			var a: float = TAU * i / 8.0
			_dial.draw_line(Vector2.from_angle(a) * 8.5, Vector2.from_angle(a) * 10.5, Color(1.0, 0.82, 0.3), 1.5)
	else:
		_dial.draw_circle(Vector2.ZERO, 7.5, Color(0.85, 0.85, 1.0))
		_dial.draw_circle(Vector2(3.5, -2.5), 6.5, Color(0.06, 0.06, 0.08))
