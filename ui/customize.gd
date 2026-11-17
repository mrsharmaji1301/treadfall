extends Control
## The Customize page of the main menu: choose the tank design, its
## pattern, how dirty it is and its colour. The tank turns on the left;
## its strengths show as bars on the right. Choices are saved at once and
## used for the player's tank in every battle.

signal closed
signal changed

const Ui := preload("res://ui/ui_kit.gd")
const TankShow := preload("res://ui/tank_show.gd")
## The bars: [title, key, value shown as full].
const BARS := [["ARMOUR", "hull", 8.0], ["SPEED", "speed", 1.2], ["FIRE RATE", "fire", 1.25],
	["HEAVY RELOAD", "heavy", 1.3], ["GUN REACH", "reach", 1.25], ["TURRET SPEED", "turret", 1.35]]

var _show
var _name: Label
var _style: Label
var _fills: Array[ColorRect] = []
var _values: Array[Label] = []
var _picks: Array[Label] = []


func _ready() -> void:
	var back := ColorRect.new()
	back.color = Color(0.035, 0.035, 0.03, 0.96)
	back.position = Vector2(110, 30)
	back.size = Vector2(1060, 670)
	add_child(back)
	var edge := ReferenceRect.new()
	edge.border_color = Cfg.COL_ACCENT
	edge.border_width = 2.0
	edge.editor_only = false
	edge.position = back.position
	edge.size = back.size
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(edge)
	var head := Ui.label("CUSTOMIZE YOUR TANK", 30, Cfg.COL_ACCENT)
	head.position = Vector2(140, 40)
	add_child(head)

	# Left: the tank on its turntable, with its name under it.
	var stage := ColorRect.new()
	stage.color = Color(0.09, 0.09, 0.085)
	stage.position = Vector2(140, 96)
	stage.size = Vector2(500, 430)
	add_child(stage)
	_show = TankShow.new()
	_show.position = stage.position
	_show.size = stage.size
	add_child(_show)
	_name = Ui.label("", 30, Cfg.COL_UI)
	_name.position = Vector2(140, 536)
	_name.size = Vector2(500, 38)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_name)
	_style = Ui.label("", 17, Color(Cfg.COL_UI, 0.75))
	_style.position = Vector2(140, 576)
	_style.size = Vector2(500, 24)
	_style.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_style)

	# Right: the four choices, then the strengths.
	var first := _pick(0, "TANK", func(step: int) -> void:
		Cfg.my_tank = posmod(Cfg.my_tank + step, Cfg.TANKS.size()))
	_pick(1, "PATTERN", func(step: int) -> void:
		Cfg.my_skin = posmod(Cfg.my_skin + step, Cfg.SKINS.size()))
	_pick(2, "CONDITION", func(step: int) -> void:
		Cfg.my_wear = posmod(Cfg.my_wear + step, Cfg.WEARS.size()))
	_pick(3, "COLOUR", func(step: int) -> void:
		Cfg.my_tint = posmod(Cfg.my_tint + step, Cfg.TINTS.size()))
	var cap := Ui.label("STRENGTHS", 20, Cfg.COL_ACCENT)
	cap.position = Vector2(680, 296)
	add_child(cap)
	for i in BARS.size():
		var y: float = 334.0 + i * 40.0
		var title := Ui.label(BARS[i][0], 17, Cfg.COL_UI)
		title.position = Vector2(680, y)
		add_child(title)
		var rail := ColorRect.new()
		rail.color = Color(0.16, 0.16, 0.15)
		rail.position = Vector2(850, y + 5)
		rail.size = Vector2(220, 14)
		add_child(rail)
		var fill := ColorRect.new()
		fill.color = Cfg.COL_GOOD
		fill.position = rail.position
		fill.size = Vector2(0, 14)
		add_child(fill)
		_fills.append(fill)
		var value := Ui.label("", 16, Cfg.COL_ACCENT)
		value.position = Vector2(1080, y)
		add_child(value)
		_values.append(value)
	var note := Ui.label("Every design has its own strong and weak sides. Paint is only for looks.",
		14, Color(Cfg.COL_UI, 0.65))
	note.position = Vector2(680, 580)
	add_child(note)
	var done := Ui.button("BACK", Cfg.COL_ACCENT)
	done.custom_minimum_size = Vector2(200, 40)
	done.size = Vector2(200, 40)
	done.add_theme_font_size_override("font_size", 17)
	done.position = Vector2(940, 642)
	done.pressed.connect(func() -> void: closed.emit())
	add_child(done)
	_update()
	first.grab_focus()


## One choice row: title, a button back, the chosen name, a button on.
func _pick(row: int, title: String, step: Callable) -> Button:
	var y: float = 100.0 + row * 46.0
	var cap := Ui.label(title, 18, Cfg.COL_UI)
	cap.position = Vector2(680, y + 6)
	add_child(cap)
	var shown := Ui.label("", 18, Cfg.COL_ACCENT)
	shown.position = Vector2(866, y + 6)
	shown.size = Vector2(200, 26)
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(shown)
	_picks.append(shown)
	var next: Button = null
	for dir in [-1, 1]:
		var b := Ui.button("<" if dir < 0 else ">", Cfg.COL_UI)
		b.custom_minimum_size = Vector2(46, 38)
		b.size = Vector2(46, 38)
		b.add_theme_font_size_override("font_size", 20)
		b.position = Vector2(816 if dir < 0 else 1070, y)
		b.pressed.connect(func() -> void:
			step.call(dir)
			Cfg.save_settings()
			_show.refresh()
			_update()
			changed.emit())
		add_child(b)
		next = b
	return next


func _update() -> void:
	var d: Dictionary = Cfg.TANKS[Cfg.my_tank]
	_name.text = d["name"]
	_style.text = d["style"]
	_picks[0].text = "%d / %d" % [Cfg.my_tank + 1, Cfg.TANKS.size()]
	_picks[1].text = Cfg.SKIN_NAMES[Cfg.my_skin]
	_picks[2].text = Cfg.WEAR_NAMES[Cfg.my_wear]
	_picks[3].text = Cfg.TINTS[Cfg.my_tint][0]
	for i in BARS.size():
		var key: String = BARS[i][1]
		var v: float = float(d[key])
		var text := ""
		if key == "hull":
			text = "%d" % (Cfg.player_hull() + int(v))
			v = Cfg.player_hull() + v
		elif key == "fire" or key == "heavy":
			# Stored as time between shots: turn it into a rate.
			v = 1.0 / v
			text = "%d%%" % roundi(v * 100.0)
		else:
			text = "%d%%" % roundi(v * 100.0)
		_fills[i].size.x = 220.0 * clampf(v / float(BARS[i][2]), 0.05, 1.0)
		_values[i].text = text
