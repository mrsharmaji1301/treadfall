extends CanvasLayer
## The power-up bar. Slots, left to right:
##   LMB  the quick gun            RMB  the special weapon (heavy shot,
##                                      or missiles / mines while loaded)
##   1 repair kit   2 speed boost   3 rapid fire   4 double damage   5 shield
##        collected ones are stored; the number key sets one off
##   armour  passive, works from the moment it is collected
## A soft green glow behind a slot means that power-up is working now.
## While the game is paused the whole bar can be dragged with the mouse;
## its place is remembered (Cfg.bar_pos).

const Ui := preload("res://ui/ui_kit.gd")
## What each slot shows: [icon, key label, stored item name or ""].
const SLOTS := [
	["cannon", "LMB", ""], ["heavy", "RMB", ""],
	["repair", "1", "repair"], ["boost", "2", "boost"], ["rapid", "3", "rapid"],
	["double", "4", "cannon"], ["shield", "5", "shield"],
	["armour", "", ""],
]
const STEP := 72.0
const WIDE := 588.0
const HIGH := 80.0

## The game mode. Its `player` tank is read every frame.
var mode
var _root: Control
var _icons: Array[TextureRect] = []
var _frames: Array[TextureRect] = []
var _glows: Array[Panel] = []
var _slot_off: Texture2D
var _slot_on: Texture2D
var _notes: Array[Label] = []
var _counts: Array[Label] = []
var _bars: Array[ColorRect] = []
var _reload: Array[ColorRect] = []
var _special := {}
## Says when the tank is hidden in water, above the bar.
var _camo: Label
var _hint: Label
var _grab := false
var _grab_off := Vector2.ZERO


func _ready() -> void:
	# Keeps running while paused, so the bar can be dragged then.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.position = Cfg.bar_pos
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var panel := Panel.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Cfg.COL_PANEL
	box.border_color = Cfg.COL_ACCENT
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", box)
	panel.size = Vector2(WIDE, HIGH)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(panel)
	_slot_off = Ui.art("hud_slot.png")
	_slot_on = Ui.art("hud_slot_active.png")
	for i in SLOTS.size():
		var at := Vector2(10 + i * STEP, 8)
		# The green glow that shows a power-up at work, behind the slot.
		var glow := Panel.new()
		var lit := StyleBoxFlat.new()
		lit.bg_color = Color(0.3, 1.0, 0.35, 0.3)
		lit.set_corner_radius_all(10)
		lit.shadow_color = Color(0.25, 1.0, 0.3, 0.5)
		lit.shadow_size = 9
		glow.add_theme_stylebox_override("panel", lit)
		glow.position = at + Vector2(3, 3)
		glow.size = Vector2(58, 58)
		glow.visible = false
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(glow)
		_glows.append(glow)
		var inset := 0.0
		if _slot_off != null:
			# Steel slot frame; the icon sits inside it.
			var cell := TextureRect.new()
			cell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			cell.stretch_mode = TextureRect.STRETCH_SCALE
			cell.position = at
			cell.size = Vector2(64, 64)
			cell.texture = _slot_off
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_root.add_child(cell)
			_frames.append(cell)
			inset = 11.0
		var slot := TextureRect.new()
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.position = at + Vector2(inset, inset)
		slot.size = Vector2(64 - inset * 2.0, 64 - inset * 2.0)
		slot.texture = Ui.icon(SLOTS[i][0])
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(slot)
		_icons.append(slot)
		if i < 2:
			# Dark shutter that drains away as the weapon reloads.
			var shutter := ColorRect.new()
			shutter.color = Color(0, 0, 0, 0.62)
			shutter.position = at
			shutter.size = Vector2(64, 0)
			shutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_root.add_child(shutter)
			_reload.append(shutter)
		var bar := ColorRect.new()
		bar.color = Cfg.COL_GOOD
		bar.position = at + Vector2(0, 60)
		bar.size = Vector2(0, 4)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(bar)
		_bars.append(bar)
		# Number keys are drawn big and bright: they are what to press.
		var key: String = SLOTS[i][1]
		var number := Ui.label(key, 17 if key.length() == 1 else 13,
			Color(1.0, 0.92, 0.5) if key.length() == 1 else Cfg.COL_UI)
		number.position = at + Vector2(5, -1 if key.length() == 1 else 1)
		number.add_theme_color_override("font_outline_color", Color.BLACK)
		number.add_theme_constant_override("outline_size", 4)
		_root.add_child(number)
		var count := Ui.label("", 15, Color.WHITE)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.position = at + Vector2(0, 0)
		count.size = Vector2(61, 20)
		count.add_theme_color_override("font_outline_color", Color.BLACK)
		count.add_theme_constant_override("outline_size", 4)
		_root.add_child(count)
		_counts.append(count)
		var note := Ui.label("", 15, Color(0.6, 1.0, 0.6))
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		note.position = at + Vector2(0, 40)
		note.size = Vector2(61, 20)
		note.add_theme_color_override("font_outline_color", Color.BLACK)
		note.add_theme_constant_override("outline_size", 4)
		_root.add_child(note)
		_notes.append(note)
	for kind in ["heavy", "missile", "mine"]:
		_special[kind] = Ui.icon(kind)
	_camo = Ui.label("", 17, Cfg.COL_GOOD)
	_camo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_camo.position = Vector2(0, -28)
	_camo.size = Vector2(WIDE, 24)
	_camo.add_theme_color_override("font_outline_color", Color.BLACK)
	_camo.add_theme_constant_override("outline_size", 5)
	_root.add_child(_camo)
	_hint = Ui.label("DRAG TO MOVE", 16, Color(1.0, 0.92, 0.5))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.position = Vector2(0, -26)
	_hint.size = Vector2(WIDE, 24)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.visible = false
	_root.add_child(_hint)


## Dragging, only while the pause screen is up.
func _input(event: InputEvent) -> void:
	if not Cfg.hud_edit:
		_grab = false
		return
	var mouse: Vector2 = _root.get_viewport().get_mouse_position()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and Rect2(_root.position, Vector2(WIDE, HIGH)).has_point(mouse):
			_grab = true
			_grab_off = mouse - _root.position
			get_viewport().set_input_as_handled()
		elif not event.pressed and _grab:
			_grab = false
			Cfg.bar_pos = _root.position
			Cfg.save_settings()
	elif event is InputEventMouseMotion and _grab:
		var to: Vector2 = mouse - _grab_off
		_root.position = Vector2(clampf(to.x, 0.0, 1280.0 - WIDE), clampf(to.y, 30.0, 720.0 - HIGH))


func _process(_delta: float) -> void:
	# On top of the pause screen while it can be dragged.
	layer = 11 if Cfg.hud_edit else 1
	_hint.visible = Cfg.hud_edit
	if not _grab and _root.position != Cfg.bar_pos:
		_root.position = Cfg.bar_pos
	var tank = mode.player if mode != null else null
	if not is_instance_valid(tank) or not tank.alive:
		tank = null
	if Cfg.hud_edit:
		_camo.text = ""
	elif tank != null and tank.concealed():
		_camo.text = "SUBMERGED  -  only the gun shows" if tank.submerged \
			else "CAMOUFLAGED  -  hidden in the water"
		_camo.add_theme_color_override("font_color", Color(0.5, 1.0, 0.45))
	elif tank != null and tank.in_water:
		_camo.text = "SPOTTED  -  hidden again in %.1f s" % tank.exposed
		_camo.add_theme_color_override("font_color", Color(1.0, 0.7, 0.25))
	else:
		_camo.text = ""
	for i in SLOTS.size():
		var item: String = SLOTS[i][2]
		var lit := i < 2
		var working := false
		var text := ""
		var have := ""
		var left := 0.0
		if tank != null:
			if item != "":
				var n: int = int(tank.stock.get(item, 0))
				have = "x%d" % n if n > 0 else ""
				left = tank.shield_time if item == "shield" else tank.buff_left(item)
				if item == "repair":
					left = 0.0
				working = left > 0.0
				lit = n > 0 or working
				text = "%ds" % ceili(left) if working else ""
			elif SLOTS[i][0] == "heavy":
				if _special.get(tank.special) is Texture2D:
					_icons[i].texture = _special[tank.special]
				have = "x%d" % tank.special_ammo if tank.special_ammo > 0 else ""
				working = tank.special != "heavy"
			elif SLOTS[i][0] == "cannon":
				text = "x2" if tank.buff_left("cannon") > 0.0 else ""
			elif SLOTS[i][0] == "armour":
				var plates: int = int(tank.picked.get("armour", 0))
				lit = plates > 0
				working = plates > 0
				have = "+%d" % plates if plates > 0 else ""
		_icons[i].modulate = Color(1, 1, 1, 1) if lit else Color(0.45, 0.45, 0.45, 0.55)
		if i < _frames.size() and _slot_on != null:
			_frames[i].texture = _slot_on if lit and i >= 2 else _slot_off
		_glows[i].visible = working
		_notes[i].text = text
		_counts[i].text = have
		_bars[i].size.x = 64.0 * clampf(left / 16.0, 0.0, 1.0)
	_reload[0].size.y = 64.0 * (tank.cooldown_fraction() if tank != null else 0.0)
	_reload[1].size.y = 64.0 * (tank.special_fraction() if tank != null else 0.0)
