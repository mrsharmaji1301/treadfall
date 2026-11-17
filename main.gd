extends Node
## Entry point: switches between the menu and a game mode, and owns pause
## and end screens.

const MainMenu := preload("res://ui/main_menu.gd")
const Overlay := preload("res://ui/overlay.gd")
const BaseDefense := preload("res://modes/base_defense.gd")
const LookTest := preload("res://modes/look_test.gd")
const Ui := preload("res://ui/ui_kit.gd")
const Settings := preload("res://ui/settings_panel.gd")
const Reticle := preload("res://ui/reticle.gd")
const NetHost := preload("res://modes/net_base_defense.gd")
const NetClient := preload("res://modes/net_client.gd")

var _menu
var _mode
var _overlay
var _mode_script = BaseDefense
var _reticle
var _in_settings := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("main")
	Net.game_starting.connect(_on_net_start)
	Net.back_in_lobby.connect(_on_net_lobby)
	Net.left_lobby.connect(_on_net_left)
	_show_menu()


## The aiming mark is drawn by the game (ui/reticle.gd) while playing, and
## the Windows pointer is hidden. Menus and pause use the normal pointer.
func _set_aim(on: bool) -> void:
	on = on and is_instance_valid(_reticle)
	if is_instance_valid(_reticle):
		_reticle.visible = on
	if not on:
		var was_held: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if was_held:
			Input.warp_mouse(Cfg.aim_pos)
	elif is_equal_approx(Cfg.aim_speed, 1.0):
		# Normal speed: the Windows pointer drives the mark, hidden and kept
		# inside the window.
		# In a window the pointer is free to leave; fullscreen keeps it in.
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if Cfg.display_mode == 2 or OS.has_feature("web") \
			else Input.MOUSE_MODE_CONFINED_HIDDEN
	else:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Cfg.aim_pos = get_viewport().get_mouse_position()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Online: the lobby host pressed START. The host runs the battle, the
## others show it.
func _on_net_start() -> void:
	_start(NetHost if Net.is_host() else NetClient)


## Online: after a battle everyone goes back to the lobby page.
func _on_net_lobby() -> void:
	_show_menu()
	_menu.open_lobby()


## Online: the lobby closed or the connection dropped during a battle.
func _on_net_left(reason: String) -> void:
	if _mode != null:
		_show_menu()
		_menu.open_lobby(reason)


func _leave_online() -> void:
	_show_menu()
	Net.leave_lobby()
	Net.close()


## The workshop between waves opened or closed: pointer or aiming mark.
func shop_changed() -> void:
	if not get_tree().paused and is_instance_valid(_mode) and not _mode.is_over:
		_set_aim(not Cfg.shop_open)


func _unhandled_input(event: InputEvent) -> void:
	# F11 switches between fullscreen and a window.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		Cfg.display_mode = 2 if Cfg.display_mode != 2 else 0
		Cfg.apply_display()
		Cfg.save_settings()
		if is_instance_valid(_reticle) and _reticle.visible:
			_set_aim(not Cfg.shop_open)
		return
	if not event.is_action_pressed("pause"):
		return
	if not is_instance_valid(_mode) or _mode.is_over:
		return
	if _in_settings:
		_pause()
	elif get_tree().paused or (Net.playing() and is_instance_valid(_overlay)):
		_resume()
	else:
		_pause()


func _clear() -> void:
	Cfg.hud_edit = false
	_in_settings = false
	get_tree().paused = false
	for n in [_menu, _mode, _overlay, _reticle]:
		if is_instance_valid(n):
			n.queue_free()
	_menu = null
	_mode = null
	_overlay = null


func _show_menu() -> void:
	_clear()
	_set_aim(false)
	_menu = MainMenu.new()
	_menu.start_requested.connect(_start.bind(BaseDefense))
	_menu.look_test_requested.connect(_start.bind(LookTest))
	add_child(_menu)


func _start(mode_script) -> void:
	_mode_script = mode_script
	_restart()


func _restart() -> void:
	_clear()
	# Building a map takes a moment: show the loading picture first.
	var wait := CanvasLayer.new()
	wait.layer = 20
	wait.add_child(Ui.backdrop("loading_screen.jpg", 0.25))
	var note := Ui.centered("LOADING", 40, Cfg.COL_ACCENT, 600.0)
	note.add_theme_color_override("font_outline_color", Color.BLACK)
	note.add_theme_constant_override("outline_size", 8)
	wait.add_child(note)
	add_child(wait)
	await get_tree().process_frame
	await get_tree().process_frame
	wait.queue_free()
	_mode = _mode_script.new()
	_mode.process_mode = Node.PROCESS_MODE_PAUSABLE
	_mode.finished.connect(_on_finished)
	add_child(_mode)
	_reticle = Reticle.new()
	_reticle.mode = _mode
	add_child(_reticle)
	_set_aim(true)


func _show_overlay(title: String, color: Color, subtitle: String, buttons: Array) -> void:
	_in_settings = false
	Cfg.hud_edit = false
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_set_aim(false)
	_overlay = Overlay.new()
	_overlay.setup(title, color, subtitle, buttons)
	add_child(_overlay)


func _pause() -> void:
	# An online battle cannot stop for one player: only the menu opens.
	if Net.playing():
		_show_overlay("MENU", Cfg.COL_ACCENT, "The battle goes on while this is open", [
			["RESUME", _resume], ["SETTINGS", _pause_settings], ["LEAVE BATTLE", _leave_online]])
		return
	get_tree().paused = true
	_show_overlay("PAUSED", Cfg.COL_ACCENT, "Drag the power-up bar with the mouse to move it", [
		["RESUME", _resume], ["SETTINGS", _pause_settings], ["RESTART", _restart],
		["MAIN MENU", _show_menu]])
	Cfg.hud_edit = true


## Settings from the pause screen. Closing them returns to the pause screen.
func _pause_settings() -> void:
	Cfg.hud_edit = false
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = CanvasLayer.new()
	_overlay.layer = 12
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = Vector2(1280, 720)
	_overlay.add_child(dim)
	var page := Settings.new()
	page.closed.connect(_pause)
	_overlay.add_child(page)
	add_child(_overlay)
	_in_settings = true


func _resume() -> void:
	Cfg.hud_edit = false
	get_tree().paused = false
	_set_aim(not Cfg.shop_open)
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null


func _on_finished(victory: bool) -> void:
	var mode = _mode
	await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(mode) or mode != _mode:
		return
	get_tree().paused = true
	var stats := "SCORE %d     GOLD %d     WAVE %d/%d" % [
		GameState.score, GameState.gold, GameState.wave, GameState.total_waves]
	if GameState.total_waves == 0:
		stats = "SCORE %d     GOLD %d     REACHED WAVE %d" % [
			GameState.score, GameState.gold, GameState.wave]
	var buttons := [["PLAY AGAIN", _restart], ["MAIN MENU", _show_menu]]
	if Net.playing():
		buttons = [["LEAVE", _leave_online]]
		if Net.is_host():
			buttons.push_front(["BACK TO LOBBY", Net.back_to_lobby])
		else:
			stats += "\nWaiting for the host"
	if victory:
		_show_overlay("VICTORY", Cfg.COL_GOOD, stats, buttons)
	else:
		_show_overlay("BASE LOST" if GameState.core_hp <= 0 else "OUT OF LIVES",
			Cfg.COL_WARN, stats, buttons)
