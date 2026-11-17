extends Node
## Developer check: starts a mode, drives and shoots for a while, saves
## screenshots and prints what it measured.
## Run: godot res://tools/smoke.tscn -- <mode> [seconds]
## Modes: menu, settings, river, river2, deep, loot, enemy, range, oasis.
const Main := preload("res://main.gd")
var _t := 0.0
var _main
var _shots := 0
var _len := 12.0
var _mode := "river"
var _m
var _seen: Dictionary = {}
var _from := Vector2.ZERO
var _kills := 0
var _frames := 0
var _slow := 0.0
var _loud := -200.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args: Array = Array(OS.get_cmdline_user_args())
	# Started from the editor (no arguments): take the job from a file.
	var job := ProjectSettings.globalize_path("res://_preview/smoke_job.txt")
	if args.is_empty() and FileAccess.file_exists(job):
		args = Array(FileAccess.get_file_as_string(job).strip_edges().split(" ", false))
	if args.size() > 0:
		_mode = args[0]
	if args.size() > 1:
		_len = float(args[1])
	# The test puts the aiming mark at a fixed spot (no real mouse here).
	Cfg.set_meta("aim_test", true)
	Cfg.aim_pos = Vector2(1180, 150) if _mode == "range" else Vector2(790, 300)
	_main = Main.new()
	add_child(_main)
	await get_tree().process_frame
	if _mode == "settings":
		_main._menu._open_settings()
		# Save, change in memory, load back: the saved value must return.
		var was: int = Cfg.cross_size
		Cfg.save_settings()
		Cfg.cross_size = 77
		Cfg.load_settings()
		_say(["SETTINGS file ", Cfg.settings_path(), " saved and read back: ", Cfg.cross_size == was])
		return
	if _mode.begins_with("custom"):
		if _mode.length() > 6:
			Cfg.my_tank = int(_mode.substr(6))
			Cfg.my_skin = Cfg.my_tank % Cfg.SKINS.size()
			Cfg.my_wear = 0
		_main._menu._open_customize()
		return
	if _mode == "menu":
		return
	if _mode == "setup":
		Cfg.allies = 3
		_main._menu._open_setup()
		return
	if _mode == "nightbd" or _mode == "nightgate":
		if _mode == "nightgate":
			set_meta("gate", true)
		_mode = "oasis"
		set_meta("night", true)
	if _mode == "oasis" or _mode == "coop" or _mode == "pause" or _mode == "psettings" or _mode == "shop":
		Cfg.allies = 4 if _mode == "coop" else 0
		_main._menu.start_requested.emit()
	else:
		_main._menu.look_test_requested.emit()
	while not is_instance_valid(_main._mode):
		await get_tree().process_frame
	_m = _main._mode
	var arena = _m.arena
	if _mode == "oasis" or _mode == "coop" or _mode == "pause" or _mode == "psettings" or _mode == "shop":
		if has_meta("night"):
			_m.get_meta("cycle").force(true)
			if has_meta("gate"):
				var g = get_tree().get_nodes_in_group("portals")[0]
				_m.player.global_position = g.global_position + Vector2(0, 150)
				_say(["GATE at ", g.global_position, " player ", _m.player.global_position])
			_say(["NIGHT forced, night=", GameState.night, " portals ", get_tree().get_nodes_in_group("portals").size()])
		# Power-up bar check: stored items, two set off, armour collected.
		var p = _m.player
		p.stock = {"repair": 2, "boost": 2, "rapid": 1, "shield": 1}
		_say(["ITEMS boost used ", p.use_item("boost"), ", shield used ", p.use_item("shield"),
			", repair on a whole hull refused ", not p.use_item("repair"), ", stock ", p.stock])
		_m.Pickup.apply("armour", p)
		_say(["WAVES 6: ", Cfg.wave_list(6).size(), " tanks, 12: ", Cfg.wave_list(12).size(),
			", hull x", Cfg.wave_hull(12), "  DETECT level ", Cfg.detect_quality(), " ", Cfg.gfx_found])
		if _mode == "shop":
			GameState.gold = 700
			_m._break_timer = 10.0
			_m._open_shop()
			_say(["SHOP bought hull ", _m.buy("hull"), ", fire ", _m.buy("fire"), ", base up ", _m.buy("base_up"),
				", base repair on a whole base refused ", not _m.buy("base_fix"), ", gold left ", GameState.gold,
				", hull ", p.max_hp, ", base ", GameState.core_hp, "/", GameState.core_max])
		if _mode == "pause" or _mode == "psettings":
			await get_tree().create_timer(1.5).timeout
			_main._pause()
			if _mode == "psettings":
				_main._pause_settings()
		return
	_say(["GATES ", get_tree().get_nodes_in_group("portals").map(func(g): return g.global_position)])
	_report_loot(arena)
	_m.player.hp = 99
	_m.player.max_hp = 99
	match _mode:
		"skins":
			# A parade of enemy tanks beside the player, one paint job each.
			for i in 10:
				var cell: Vector2i = arena.player_spawn + Vector2i(-4 + (i % 5) * 2, -2 - (i / 5) * 2)
				if arena.tile_at(cell) == arena.EMPTY:
					var t = _m._add_tank(cell, Color.WHITE, 1.0, Cfg.TEAM_ENEMY, 6)
					t.dummy = true
		"river2":
			var col: int = arena.player_spawn.x + 6
			_m.player.position = arena.cell_center(Vector2i(col, int(arena.river_row[col]) + 4))
		"deep":
			var best := Vector2i(-1, -1)
			for cell in arena.deep:
				if best.x < 0 or absi(cell.x - arena.player_spawn.x + 9) < absi(best.x - arena.player_spawn.x + 9):
					best = cell
			_m.player.position = arena.cell_center(best)
			_say(["DEEP start cell ", best])
		"loot":
			# The cache with the most palms round it.
			var pick: Vector2i = arena.loot_cells[0]
			var most := -1
			for cell in arena.loot_cells:
				var n := 0
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						if arena.decor.get(cell + Vector2i(dx, dy), "") == "T":
							n += 1
				if n > most:
					most = n
					pick = cell
			_m.player.position = arena.cell_center(pick)
			_say(["LOOT pocket ", pick, " palms within 2 cells: ", most])
		"enemy":
			_m.player.position = arena.cell_center(arena.enemy_core_cell + Vector2i(-1, 1))
			_m.view._zoom_follow = 0.45
		"home":
			_m.player.position = _m.core.position + Vector2(-60, 20)
			_m.view._zoom_follow = 0.45
		"tower", "turret", "artillery", "guard":
			for n in _m.get_children():
				if n.get("kind") == _mode and n.get("team") == Cfg.TEAM_PLAYER:
					_m.player.position = n.position + Vector2(-62, 10)
					break
			_m.view._zoom_follow = 0.45
	_from = _m.player.position


## Independent check on the built map: flood from the player's start over
## cells with no wall, palm or rock, and see that every cache is reached.
func _report_loot(arena) -> void:
	var open: Dictionary = {arena.player_spawn: true}
	var queue: Array = [arena.player_spawn]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for s in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + s
			if n.x < 0 or n.y < 0 or n.x >= Cfg.cols or n.y >= Cfg.rows or open.has(n):
				continue
			if arena.tile_at(n) != arena.EMPTY or arena.built.has(n):
				continue
			open[n] = true
			queue.append(n)
	var ok := 0
	for cell in arena.loot_cells:
		if open.has(cell):
			ok += 1
		else:
			_say(["LOOT UNREACHABLE ", cell])
	_say(["LOOT reachable ", ok, " of ", arena.loot_cells.size()])


func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	_slow = maxf(_slow, delta)
	_loud = maxf(_loud, AudioServer.get_bus_peak_volume_left_db(0, 0))
	var drive: bool = _mode in ["river", "river2", "oasis"]
	if _mode == "coop" and is_instance_valid(_m) and is_instance_valid(_m.player):
		_m.player.shield_time = 5.0  # the test player just watches
	if drive:
		Input.action_press("move_up") if fmod(_t, 6.0) < 4.0 else Input.action_release("move_up")
		Input.action_press("move_right") if fmod(_t, 6.0) > 3.0 else Input.action_release("move_right")
		Input.action_press("fire") if fmod(_t, 2.0) < 1.0 else Input.action_release("fire")
	elif _mode == "deep":
		# Sit still for the first picture, then drive along the channel.
		Input.action_press("move_right") if _t > _len / 3.0 + 0.5 else Input.action_release("move_right")
	elif _mode == "range":
		Input.action_press("fire")
		Input.action_press("fire_alt") if fmod(_t, 3.0) < 1.5 else Input.action_release("fire_alt")
	if is_instance_valid(_m):
		for n in _m.get_children():
			if n.get("reach") != null and n.get("_flown") != null:
				_seen[n.get_instance_id()] = [n.by_player, n.heavy, n._flown, n.reach]
	if _mode == "coop" and is_instance_valid(_m):
		_kills = maxi(_kills, 0)
	if _t > (_shots + 1) * _len / 3.0 and DisplayServer.get_name() != "headless":
		_shots += 1
		if _shots == 1:
			var ev := InputEventAction.new()
			ev.action = "camera"
			ev.pressed = true
			Input.parse_input_event(ev)
		var dir: String = ProjectSettings.globalize_path("res://_preview/shots")
		DirAccess.make_dir_recursive_absolute(dir)
		get_viewport().get_texture().get_image().save_png(dir.path_join("smoke_%s_%d.png" % [_mode, _shots]))
	if _t > _len:
		if _mode == "coop" and is_instance_valid(_m):
			var mates := 0
			var moved := 0
			for t in get_tree().get_nodes_in_group("tanks"):
				if t.team == Cfg.TEAM_PLAYER and not t.is_player and t.alive:
					mates += 1
					if t.position.distance_to(_m.arena.cell_center(_m.arena.player_spawn)) > 200.0:
						moved += 1
			_say(["COOP allies alive ", mates, ", left the start area ", moved, ", wave ", GameState.wave,
				", score ", GameState.score, ", base ", GameState.core_hp, ", enemies alive ", _m._alive_enemies])
		if is_instance_valid(_m) and _mode != "oasis" and _mode != "coop":
			var p = _m.player
			_say(["PLAYER moved ", snappedf(p.position.distance_to(_from), 1.0), " px, submerged ", p.submerged,
				", concealed ", p.concealed(), ", alive ", p.alive])
		var far: Dictionary = {}
		for id in _seen:
			var e: Array = _seen[id]
			var key: String = ("player" if e[0] else "other") + (" heavy" if e[1] else "")
			var was: Array = far.get(key, [0.0, 0.0, 0])
			far[key] = [maxf(was[0], e[2]), e[3], was[2] + 1]
		for key in far:
			_say(["SHELLS ", key, ": ", far[key][2], " fired, longest flight ", snappedf(far[key][0], 1.0),
				" px, limit ", far[key][1]])
		_say(["MACHINE window ", DisplayServer.window_get_size(), " mode ", DisplayServer.window_get_mode(),
			" screen ", DisplayServer.screen_get_size(), " gpu ", RenderingServer.get_video_adapter_name(),
			" graphics ", Cfg.QUALITY_NAMES[Cfg.quality]])
		_say(["SPEED average fps ", snappedf(_frames / _t, 0.1), ", slowest frame ", snappedf(_slow * 1000.0, 1.0), " ms"])
		_say(["SOUND device ", AudioServer.get_output_device(), ", loudest master peak ", snappedf(_loud, 0.1), " dB"])
		_say(["SMOKE DONE ", _mode, " fps ", Engine.get_frames_per_second()])
		get_tree().quit()


## Prints a line and also adds it to _preview/smoke_log.txt in the project.
func _say(parts: Array) -> void:
	var line := ""
	for part in parts:
		line += str(part)
	print(line)
	var path := ProjectSettings.globalize_path("res://_preview/smoke_log.txt")
	var f := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) \
		else FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(line)
		f.close()
