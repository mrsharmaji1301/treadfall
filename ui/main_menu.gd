extends CanvasLayer
## Title screen.

signal look_test_requested
signal start_requested

const Ui := preload("res://ui/ui_kit.gd")
const Settings := preload("res://ui/settings_panel.gd")
const Customize := preload("res://ui/customize.gd")
const TankShow := preload("res://ui/tank_show.gd")
const Lobby := preload("res://ui/lobby.gd")

var _box: VBoxContainer
var _panel
var _show


func _ready() -> void:
	add_child(Ui.backdrop("menu_background.jpg", 0.35))
	var plate := Ui.frame("menu_logo_plate.png", Vector2(310, 52), Vector2(660, 196), 150, true)
	if plate != null:
		add_child(plate)

	var title := Ui.centered("TREADFALL", 84, Cfg.COL_ACCENT, 84.0)
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03))
	title.add_theme_constant_override("outline_size", 10)
	add_child(title)
	var tag := Ui.centered("DESERT ARMOUR. HOLD THE BASE.", 20, Cfg.COL_UI, 190.0)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_constant_override("outline_size", 6)
	add_child(tag)

	# The player's chosen tank turns slowly behind the buttons.
	_show = TankShow.new()
	_show.position = Vector2(770, 236)
	_show.size = Vector2(500, 400)
	add_child(_show)
	_box = VBoxContainer.new()
	_box.position = Vector2(470, 262)
	_box.add_theme_constant_override("separation", 4)
	add_child(_box)
	var look := Ui.button("FREE ROAM (RIVER MAP)", Cfg.COL_ACCENT)
	look.pressed.connect(func() -> void: look_test_requested.emit())
	_box.add_child(look)
	var play := Ui.button("BASE DEFENSE (OASIS MAP)", Cfg.COL_ACCENT)
	play.pressed.connect(_open_setup)
	_box.add_child(play)
	var garage := Ui.button("CUSTOMIZE TANK", Cfg.COL_ACCENT)
	garage.pressed.connect(_open_customize)
	_box.add_child(garage)
	var multi := Ui.button("MULTIPLAYER", Cfg.COL_ACCENT)
	multi.pressed.connect(open_lobby)
	_box.add_child(multi)
	var opts := Ui.button("SETTINGS", Cfg.COL_UI)
	opts.pressed.connect(_open_settings)
	_box.add_child(opts)
	var quit := Ui.button("QUIT", Cfg.COL_WARN)
	quit.pressed.connect(func() -> void: get_tree().quit())
	# A browser tab is closed by the player, not by the game.
	quit.visible = not OS.has_feature("web")
	_box.add_child(quit)
	look.grab_focus()

	var strip := ColorRect.new()
	strip.color = Color(0, 0, 0, 0.55)
	strip.position = Vector2(0, 640)
	strip.size = Vector2(1280, 80)
	add_child(strip)
	add_child(Ui.centered("Move: WASD / arrows     Aim: mouse     Rapid fire: left click     Heavy shot: right click     Power-ups: 1 to 5     Camera: C     Pause: Esc",
		18, Color(Cfg.COL_UI, 0.9), 648.0))
	add_child(Ui.centered("Made by SharmaJi", 14, Color(Cfg.COL_UI, 0.6), 684.0))


## Base Defense set-up page: solo or co-op with computer allies, how many
## allies, and the difficulty. START begins the battle.
func _open_setup() -> void:
	_box.visible = false
	var page := VBoxContainer.new()
	page.position = Vector2(470, 250)
	page.add_theme_constant_override("separation", 2)
	add_child(page)
	var picked: Array = [maxi(Cfg.allies, 2)]
	var kind := Ui.button("", Cfg.COL_ACCENT)
	var count := Ui.button("", Cfg.COL_UI)
	var show := func() -> void:
		kind.text = "SOLO" if Cfg.allies == 0 else "CO-OP WITH COMPUTER"
		count.text = "ALLIES: %d" % picked[0]
		count.visible = Cfg.allies > 0
	kind.pressed.connect(func() -> void:
		Cfg.allies = picked[0] if Cfg.allies == 0 else 0
		Cfg.save_settings()
		show.call())
	count.pressed.connect(func() -> void:
		picked[0] = picked[0] % 4 + 1
		Cfg.allies = picked[0]
		Cfg.save_settings()
		show.call())
	page.add_child(kind)
	page.add_child(count)
	var level := Ui.button("", Cfg.COL_UI)
	level.pressed.connect(func() -> void:
		Cfg.difficulty = (Cfg.difficulty + 1) % 3
		Cfg.save_settings()
		level.text = "DIFFICULTY: " + Cfg.DIFFICULTY_NAMES[Cfg.difficulty])
	level.text = "DIFFICULTY: " + Cfg.DIFFICULTY_NAMES[Cfg.difficulty]
	page.add_child(level)
	var waves := Ui.button("", Cfg.COL_UI)
	waves.pressed.connect(func() -> void:
		Cfg.endless = not Cfg.endless
		Cfg.save_settings()
		waves.text = "WAVES: ENDLESS (SURVIVAL)" if Cfg.endless else "WAVES: 5 (SHORT BATTLE)")
	waves.text = "WAVES: ENDLESS (SURVIVAL)" if Cfg.endless else "WAVES: 5 (SHORT BATTLE)"
	page.add_child(waves)
	var go := Ui.button("START", Cfg.COL_ACCENT)
	go.pressed.connect(func() -> void: start_requested.emit())
	page.add_child(go)
	var back := Ui.button("BACK", Cfg.COL_WARN)
	back.pressed.connect(func() -> void:
		page.queue_free()
		_box.visible = true
		_box.get_child(1).grab_focus())
	page.add_child(back)
	show.call()
	kind.grab_focus()


func _open_customize() -> void:
	_box.visible = false
	_show.visible = false
	_panel = Customize.new()
	_panel.closed.connect(func() -> void:
		_panel.queue_free()
		_box.visible = true
		_show.visible = true
		_show.refresh()
		_box.get_child(2).grab_focus())
	add_child(_panel)


## The MULTIPLAYER page: lobby list and lobbies. `note` is shown at its top.
func open_lobby(note: String = "") -> void:
	_box.visible = false
	_show.visible = false
	_panel = Lobby.new()
	_panel.note = note
	_panel.closed.connect(func() -> void:
		_panel.queue_free()
		_box.visible = true
		_show.visible = true
		_box.get_child(3).grab_focus())
	add_child(_panel)


func _open_settings() -> void:
	_box.visible = false
	_panel = Settings.new()
	_panel.closed.connect(func() -> void:
		_panel.queue_free()
		_box.visible = true
		_box.get_child(0).grab_focus())
	add_child(_panel)
