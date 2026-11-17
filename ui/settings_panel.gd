extends Control
## The settings page, opened from the main menu and from the pause screen.
## Tabs: GRAPHICS, DISPLAY, AUDIO, CONTROLS (crosshair and aiming), HUD.
## Every change works at once and is saved at once (Cfg.save_settings).

signal closed

const Ui := preload("res://ui/ui_kit.gd")
const Reticle := preload("res://ui/reticle.gd")
const TABS := ["GRAPHICS", "DISPLAY", "AUDIO", "CONTROLS", "HUD"]
const ROW := 38.0

var _preview: Control
var _page: Control
var _rows: VBoxContainer
var _tab_buttons: Array[Button] = []
var _tab: int = 0
var _preset: Button


func _ready() -> void:
	var back := ColorRect.new()
	back.color = Color(0.035, 0.035, 0.03, 0.96)
	back.position = Vector2(150, 30)
	back.size = Vector2(980, 670)
	add_child(back)
	var edge := ReferenceRect.new()
	edge.border_color = Cfg.COL_ACCENT
	edge.border_width = 2.0
	edge.editor_only = false
	edge.position = back.position
	edge.size = back.size
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(edge)
	var head := Ui.label("SETTINGS", 30, Cfg.COL_ACCENT)
	head.position = Vector2(180, 40)
	add_child(head)
	for i in TABS.size():
		var b := _small(TABS[i], 150.0)
		b.position = Vector2(180 + i * 158, 88)
		b.pressed.connect(_show_tab.bind(i))
		add_child(b)
		_tab_buttons.append(b)
	var done := _small("BACK", 200.0)
	done.position = Vector2(900, 642)
	done.pressed.connect(func() -> void: closed.emit())
	add_child(done)
	_show_tab(0)
	_tab_buttons[0].grab_focus()


## A compact steel button for tabs and rows.
func _small(text: String, wide: float) -> Button:
	var b := Ui.button(text, Cfg.COL_UI)
	b.custom_minimum_size = Vector2(wide, ROW - 2.0)
	b.size = Vector2(wide, ROW - 2.0)
	b.add_theme_font_size_override("font_size", 17)
	return b


func _show_tab(i: int) -> void:
	_tab = i
	if is_instance_valid(_page):
		_page.queue_free()
	_preview = null
	_preset = null
	_page = Control.new()
	add_child(_page)
	_rows = VBoxContainer.new()
	_rows.position = Vector2(190, 140)
	_rows.add_theme_constant_override("separation", 2)
	_page.add_child(_rows)
	for t in _tab_buttons.size():
		_tab_buttons[t].modulate = Color(1, 1, 1) if t == i else Color(0.62, 0.62, 0.62)
	match i:
		0: _graphics()
		1: _display()
		2: _audio()
		3: _controls()
		4: _hud()


func _note(text: String, at: Vector2, wide: float, size: int = 15) -> Label:
	var l := Ui.label(text, size, Color(Cfg.COL_UI, 0.8))
	l.position = at
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(wide, 0)
	l.size = Vector2(wide, 0)
	_page.add_child(l)
	return l


func _graphics() -> void:
	_preset = _cycle("PRESET", Cfg.QUALITY_NAMES.slice(0, 4), mini(Cfg.quality, 3),
		func(i: int) -> void:
			Cfg.set_preset(i)
			Cfg.gfx_probe = false
			_refresh.call_deferred())
	if Cfg.quality == 4:
		_preset.text = "CUSTOM"
	_slide("RESOLUTION SCALE", 50.0, 100.0, 5.0, float(Cfg.gfx["scale"]),
		func(v: float) -> String:
			_custom("scale", int(v))
			return "%d %%" % int(v))
	_cycle("SHADOWS", Cfg.SHADOW_NAMES, int(Cfg.gfx["shadows"]),
		func(i: int) -> void: _custom("shadows", i))
	_cycle("ANTI-ALIASING", Cfg.AA_NAMES, int(Cfg.gfx["aa"]),
		func(i: int) -> void: _custom("aa", i))
	_toggle("CONTACT SHADING", bool(Cfg.gfx["ssao"]), func(on: bool) -> void: _custom("ssao", on))
	_toggle("GLOW", bool(Cfg.gfx["glow"]), func(on: bool) -> void: _custom("glow", on))
	_toggle("HEAT HAZE FOG", bool(Cfg.gfx["fog"]), func(on: bool) -> void: _custom("fog", on))
	_toggle("BOUNCED LIGHT", bool(Cfg.gfx["gi"]), func(on: bool) -> void: _custom("gi", on))
	_cycle("PLANTS (NEXT BATTLE)", Cfg.FOLIAGE_NAMES, int(Cfg.gfx["foliage"]),
		func(i: int) -> void: _custom("foliage", i))
	var auto := _small("AUTO-DETECT FOR THIS PC", 300.0)
	auto.pressed.connect(func() -> void:
		Cfg.auto_graphics()
		Cfg.apply_graphics()
		_refresh.call_deferred())
	_rows.add_child(auto)
	_note("THIS COMPUTER\n" + (Cfg.gfx_found if Cfg.gfx_found != "" else "not checked yet"),
		Vector2(770, 150), 330)
	_note("The game picks a level by itself on its first start. LOW is for laptops without a graphics card. "
		+ "If the game is not smooth, lower RESOLUTION SCALE and SHADOWS first: they matter most.",
		Vector2(770, 260), 330)


## A single option changed by hand: the preset becomes CUSTOM.
func _custom(key: String, value) -> void:
	if Cfg.gfx[key] == value:
		return
	Cfg.gfx[key] = value
	Cfg.quality = 4
	Cfg.gfx_probe = false
	if _preset != null:
		_preset.text = "CUSTOM"
	Cfg.apply_graphics()


func _refresh() -> void:
	Cfg.apply_graphics()
	Cfg.save_settings()
	_show_tab(_tab)


func _display() -> void:
	_cycle("DISPLAY (F11)", Cfg.DISPLAY_NAMES, Cfg.display_mode,
		func(i: int) -> void:
			Cfg.display_mode = i
			Cfg.apply_display())
	_toggle("VSYNC", Cfg.vsync, func(on: bool) -> void:
		Cfg.vsync = on
		Cfg.apply_graphics())
	_cycle("FPS LIMIT", Cfg.FPS_CAPS.map(func(n): return "NO LIMIT" if n == 0 else str(n)),
		maxi(Cfg.FPS_CAPS.find(Cfg.fps_cap), 0),
		func(i: int) -> void:
			Cfg.fps_cap = Cfg.FPS_CAPS[i]
			Cfg.apply_graphics())
	_toggle("SHOW FPS", Cfg.show_fps, func(on: bool) -> void: Cfg.show_fps = on)
	_note("FULLSCREEN uses the monitor's own resolution. An FPS limit of 30 or 60 keeps a laptop cooler and quieter.",
		Vector2(770, 150), 330)


func _audio() -> void:
	_slide("VOLUME", 0.0, 100.0, 5.0, Cfg.volume,
		func(v: float) -> String:
			Cfg.volume = int(v)
			Cfg.apply_volume()
			return "%d %%" % int(v))


func _controls() -> void:
	_cycle("CROSSHAIR STYLE", Cfg.CROSS_STYLES, Cfg.cross_style,
		func(i: int) -> void: Cfg.cross_style = i)
	_cycle("CROSSHAIR COLOUR", Cfg.CROSS_COLORS.map(func(c): return c[0]), Cfg.cross_color,
		func(i: int) -> void: Cfg.cross_color = i)
	_slide("CROSSHAIR SIZE", Cfg.CROSS_MIN, Cfg.CROSS_MAX, 1.0, Cfg.cross_size,
		func(v: float) -> String:
			Cfg.cross_size = int(v)
			return "%d px" % int(v))
	_slide("AIM SENSITIVITY", Cfg.AIM_MIN, Cfg.AIM_MAX, 0.05, Cfg.aim_speed,
		func(v: float) -> String:
			Cfg.aim_speed = v
			return "%.2f x" % v)
	# Live preview on a sand and a dark patch, to judge it on both.
	for i in 2:
		var patch := ColorRect.new()
		patch.color = Color(0.78, 0.66, 0.45) if i == 0 else Color(0.1, 0.16, 0.17)
		patch.position = Vector2(830 + i * 120, 140)
		patch.size = Vector2(120, 170)
		_page.add_child(patch)
	_preview = Control.new()
	_preview.position = Vector2(950, 225)
	_preview.draw.connect(func() -> void:
		for x in [-60.0, 60.0]:
			_preview.draw_set_transform(Vector2(x, 0.0))
			Reticle.paint(_preview, false))
	_page.add_child(_preview)
	_note("KEYS\nDrive: W A S D or arrows\nAim: mouse\nRapid fire: left click or Space\n"
		+ "Special weapon: right click, E or Shift\nStored power-ups: 1 repair, 2 speed, 3 rapid fire, "
		+ "4 double damage, 5 shield\nCamera: C      Zoom: mouse wheel\nFullscreen: F11      Pause: Esc",
		Vector2(190, 330), 620, 17)


func _hud() -> void:
	var reset := _small("PUT THE POWER-UP BAR BACK", 300.0)
	reset.pressed.connect(func() -> void:
		Cfg.bar_pos = Cfg.BAR_HOME
		Cfg.save_settings())
	_rows.add_child(reset)
	_toggle("SHOW FPS", Cfg.show_fps, func(on: bool) -> void: Cfg.show_fps = on)
	_note("To move the power-up bar: pause the battle (Esc) and drag the bar with the mouse. "
		+ "Its place is remembered.\n\nA green glow behind a slot means that power-up is working now. "
		+ "Slots with a number wait for that key.",
		Vector2(190, 240), 560, 17)


func _changed() -> void:
	Cfg.save_settings()
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_redraw()


func _row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var cap := Ui.label(title, 18, Cfg.COL_UI)
	cap.custom_minimum_size = Vector2(250, ROW)
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(cap)
	_rows.add_child(row)
	return row


## A button that steps through `names`; `apply` gets the new index.
func _cycle(title: String, names: Array, at: int, apply: Callable) -> Button:
	var row := _row(title)
	var b := _small(str(names[at]), 240.0)
	b.set_meta("at", at)
	b.pressed.connect(func() -> void:
		var i: int = (int(b.get_meta("at")) + 1) % names.size()
		b.set_meta("at", i)
		b.text = str(names[i])
		apply.call(i)
		_changed())
	row.add_child(b)
	return b


## An ON / OFF button.
func _toggle(title: String, at: bool, apply: Callable) -> Button:
	return _cycle(title, ["OFF", "ON"], 1 if at else 0, func(i: int) -> void: apply.call(i == 1))


## A slider; `apply` stores the value and returns the text shown beside it.
func _slide(title: String, lo: float, hi: float, step: float, at: float, apply: Callable) -> void:
	var row := _row(title)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = at
	s.custom_minimum_size = Vector2(170, ROW)
	row.add_child(s)
	var out := Ui.label(apply.call(at), 18, Cfg.COL_ACCENT)
	out.custom_minimum_size = Vector2(70, ROW)
	out.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(out)
	s.value_changed.connect(func(v: float) -> void:
		out.text = apply.call(v)
		_changed())
