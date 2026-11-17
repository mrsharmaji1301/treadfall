extends CanvasLayer
## Dimmed screen with a title and buttons: pause, victory and defeat.

const Ui := preload("res://ui/ui_kit.gd")

var _first: Button


## buttons is a list of [text, Callable] pairs.
func setup(title: String, color: Color, subtitle: String, buttons: Array) -> void:
	layer = 10
	# Victory and defeat get their own picture; pause just dims the game.
	if title == "PAUSED" or title == "MENU":
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.7)
		dim.size = Vector2(1280, 720)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)
	else:
		add_child(Ui.backdrop("victory_screen.jpg" if title == "VICTORY" else "defeat_screen.jpg", 0.3))
	var head := Ui.centered(title, 68, color, 150.0)
	var sub := Ui.centered(subtitle, 24, Cfg.COL_UI, 250.0)
	for l in [head, sub]:
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 8)
		add_child(l)
	var box := VBoxContainer.new()
	box.position = Vector2(470, 310)
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	for entry in buttons:
		var b := Ui.button(entry[0], color)
		b.pressed.connect(entry[1])
		box.add_child(b)
		if _first == null:
			_first = b


func _ready() -> void:
	if _first != null:
		_first.grab_focus()
