extends CanvasLayer
## Top bar and centre banner. Reads GameState every frame.

const Ui := preload("res://ui/ui_kit.gd")
const Sfx := preload("res://fx/sfx.gd")

var _labels: Dictionary = {}
var _banner: Label
var _fps: Label
var _tween: Tween
## Glow around the screen edge: red when the base is hit, amber when you are.
var _edge: TextureRect
var _flash := 0.0
var _flash_color := Color(1.0, 0.1, 0.05)
var _last_core: int = -1
var _last_hull: int = -1
var _clock := 0.0


func _ready() -> void:
	_edge = TextureRect.new()
	_edge.texture = _edge_texture()
	_edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_edge.stretch_mode = TextureRect.STRETCH_SCALE
	_edge.size = Vector2(1280, 720)
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.modulate = Color(1, 1, 1, 0)
	add_child(_edge)
	var strip := ColorRect.new()
	strip.color = Color(0, 0, 0, 0.5)
	strip.size = Vector2(1280, 46)
	add_child(strip)
	# The painted steel bar over it, when the picture is there.
	var plate := Ui.art("hud_top_bar.png")
	if plate != null:
		var bar_art := TextureRect.new()
		bar_art.texture = plate
		bar_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bar_art.stretch_mode = TextureRect.STRETCH_SCALE
		bar_art.size = Vector2(1280, 48)
		bar_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar_art)
	var bar := HBoxContainer.new()
	bar.position = Vector2(40, 9)
	bar.size = Vector2(1200, 30)
	bar.add_theme_constant_override("separation", 34)
	add_child(bar)
	for key in ["wave", "incoming", "core", "hull", "lives", "gold", "score"]:
		var l := Ui.label("", 20, Cfg.COL_UI)
		bar.add_child(l)
		_labels[key] = l
	_labels["core"].add_theme_color_override("font_color", Cfg.COL_GOOD)
	_labels["hull"].add_theme_color_override("font_color", Cfg.COL_ACCENT)
	_labels["gold"].add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_fps = Ui.label("", 16, Cfg.COL_GOOD)
	_fps.position = Vector2(12, 52)
	_fps.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps.add_theme_constant_override("outline_size", 4)
	add_child(_fps)
	_banner = Ui.centered("", 42, Cfg.COL_UI, 96.0)
	_banner.modulate.a = 0.0
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 8)
	# A steel plate behind the words; it fades with them.
	var back := Ui.art("hud_banner.png")
	if back != null:
		var slab := TextureRect.new()
		slab.texture = back
		slab.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slab.stretch_mode = TextureRect.STRETCH_SCALE
		slab.size = Vector2(440, 104)
		slab.position = Vector2(420, -24)
		slab.modulate = Color(1, 1, 1, 0.88)
		slab.show_behind_parent = true
		slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_banner.add_child(slab)
	add_child(_banner)


## White frame that is clear in the middle and solid at the screen edge.
func _edge_texture() -> ImageTexture:
	var img := Image.create(160, 90, false, Image.FORMAT_RGBA8)
	for y in 90:
		for x in 160:
			var u: float = absf(x - 79.5) / 79.5
			var v: float = absf(y - 44.5) / 44.5
			var d: float = maxf(smoothstep(0.78, 1.0, u), smoothstep(0.62, 1.0, v))
			img.set_pixel(x, y, Color(1, 1, 1, d * d))
	return ImageTexture.create_from_image(img)


func _warn(delta: float) -> void:
	_clock += delta
	if _last_core >= 0 and GameState.core_hp < _last_core:
		_flash = 1.0
		_flash_color = Color(1.0, 0.08, 0.04)
		Sfx.flat(self, "base_alarm", -10.0)
	elif _last_hull >= 0 and GameState.player_hp < _last_hull and _flash < 0.5:
		_flash = 0.55
		_flash_color = Color(1.0, 0.55, 0.1)
	_last_core = GameState.core_hp
	_last_hull = GameState.player_hp
	_flash = maxf(_flash - delta * 1.1, 0.0)
	var glow: float = _flash
	# Base nearly gone: the border keeps pulsing red.
	if GameState.core_hp > 0 and GameState.core_hp * 3 <= GameState.core_max and _flash < 0.4:
		_flash_color = Color(1.0, 0.08, 0.04)
		glow = maxf(glow, 0.22 + 0.18 * sin(_clock * 5.0))
	_edge.modulate = Color(_flash_color.r, _flash_color.g, _flash_color.b, glow)


func _process(delta: float) -> void:
	_warn(delta)
	_labels["wave"].text = "WAVE %d/%d" % [GameState.wave, GameState.total_waves] \
		if GameState.total_waves > 0 else "WAVE %d" % GameState.wave
	_fps.visible = Cfg.show_fps
	if Cfg.show_fps:
		# Where a frame's time goes, to tell a slow computer from slow game code.
		_fps.text = "%d FPS   game %.1f ms   physics %.1f ms   draws %d" % [Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]
	_labels["incoming"].text = "INCOMING %d" % GameState.incoming
	_labels["core"].text = "BASE %d/%d" % [GameState.core_hp, GameState.core_max]
	_labels["hull"].text = "HULL %d/%d" % [GameState.player_hp, GameState.player_max]
	_labels["lives"].text = "LIVES %d" % GameState.lives
	_labels["gold"].text = "GOLD %d" % GameState.gold
	_labels["score"].text = "SCORE %d" % GameState.score


func show_banner(text: String, color: Color) -> void:
	Net.banner(text, color)
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.modulate.a = 1.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(1.2)
	_tween.tween_property(_banner, "modulate:a", 0.0, 0.6)
