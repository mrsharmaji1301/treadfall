extends CanvasLayer
## The workshop: a panel that comes up between waves with a countdown to
## the next one. Gold earned from kills buys upgrades here. The battle is
## not paused; the mouse is a pointer while the panel is up and the tank's
## guns rest (see Cfg.shop_open). All buying goes through mode.buy().

const Ui := preload("res://ui/ui_kit.gd")
const ORDER := ["hull", "fire", "heavy", "engine", "shield", "base_fix", "base_up", "life"]
const TILE := Vector2(196, 128)

## The game mode: price(), buy(), level(), break_left(), skip_break().
var mode
var _clock: Label
var _gold: Label
var _tiles: Dictionary = {}


func _ready() -> void:
	layer = 5
	var back := Panel.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.05, 0.045, 0.9)
	box.border_color = Cfg.COL_ACCENT
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	back.add_theme_stylebox_override("panel", box)
	back.position = Vector2(215, 168)
	back.size = Vector2(850, 400)
	add_child(back)
	var head := Ui.label("WORKSHOP", 26, Cfg.COL_ACCENT)
	head.position = Vector2(240, 178)
	add_child(head)
	_clock = Ui.label("", 26, Cfg.COL_WARN)
	_clock.position = Vector2(480, 178)
	_clock.size = Vector2(320, 34)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_clock)
	_gold = Ui.label("", 24, Color(1.0, 0.85, 0.3))
	_gold.position = Vector2(800, 180)
	_gold.size = Vector2(240, 32)
	_gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_gold)
	for i in ORDER.size():
		var key: String = ORDER[i]
		var u: Dictionary = Cfg.UPGRADES[key]
		var b := Button.new()
		b.position = Vector2(236 + (i % 4) * (TILE.x + 8), 224 + (i / 4) * (TILE.y + 8))
		b.size = TILE
		b.focus_mode = Control.FOCUS_NONE
		for state in ["normal", "hover", "pressed", "disabled"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = {"normal": Color(0.13, 0.13, 0.11), "hover": Color(0.24, 0.22, 0.14),
				"pressed": Color(0.3, 0.42, 0.2), "disabled": Color(0.08, 0.08, 0.075)}[state]
			sb.border_color = Cfg.COL_ACCENT if state != "disabled" else Color(0.3, 0.3, 0.28)
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(6)
			b.add_theme_stylebox_override(state, sb)
		b.pressed.connect(func() -> void:
			mode.buy(key)
			_refresh())
		add_child(b)
		var pic := TextureRect.new()
		pic.texture = Ui.icon(u["icon"])
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.position = Vector2(8, 8)
		pic.size = Vector2(46, 46)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(pic)
		var name := Ui.label(u["name"], 16, Cfg.COL_UI)
		name.position = Vector2(60, 8)
		name.size = Vector2(130, 22)
		b.add_child(name)
		var lvl := Ui.label("", 14, Cfg.COL_GOOD)
		lvl.position = Vector2(60, 30)
		lvl.size = Vector2(130, 20)
		b.add_child(lvl)
		var says := Ui.label(u["says"], 13, Color(Cfg.COL_UI, 0.75))
		says.position = Vector2(8, 58)
		says.custom_minimum_size = Vector2(180, 0)
		says.size = Vector2(180, 36)
		says.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_child(says)
		var cost := Ui.label("", 17, Color(1.0, 0.85, 0.3))
		cost.position = Vector2(8, 100)
		cost.size = Vector2(180, 22)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.add_child(cost)
		for l in [name, lvl, says, cost]:
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tiles[key] = [b, lvl, cost, pic]
	var go := Ui.button("START NOW", Cfg.COL_ACCENT)
	go.custom_minimum_size = Vector2(240, 44)
	go.size = Vector2(240, 44)
	go.position = Vector2(520, 508)
	go.focus_mode = Control.FOCUS_NONE
	go.add_theme_font_size_override("font_size", 18)
	go.pressed.connect(func() -> void: mode.skip_break())
	add_child(go)
	var tip := Ui.label("Click to buy with the gold from your kills", 14, Color(Cfg.COL_UI, 0.7))
	tip.position = Vector2(240, 522)
	add_child(tip)
	_refresh()


func _refresh() -> void:
	for key in _tiles:
		var u: Dictionary = Cfg.UPGRADES[key]
		var cost: int = mode.price(key)
		var t: Array = _tiles[key]
		var can: bool = cost >= 0 and GameState.gold >= cost
		if key == "base_fix" and GameState.core_hp >= GameState.core_max:
			can = false
		t[0].disabled = not can
		t[3].modulate = Color(1, 1, 1) if can else Color(0.5, 0.5, 0.5, 0.7)
		var top: int = int(u["max"])
		t[1].text = ("LEVEL %d / %d" % [mode.level(key), top]) if top > 0 \
			else ("BOUGHT %d" % mode.level(key) if mode.level(key) > 0 else "")
		t[2].text = "MAXED" if cost < 0 else "%d GOLD" % cost
		t[2].add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.3) if can else Color(0.65, 0.4, 0.3))


func _process(_delta: float) -> void:
	_clock.text = "NEXT WAVE IN %d" % ceili(mode.break_left())
	_gold.text = "GOLD %d" % GameState.gold
	_refresh()
