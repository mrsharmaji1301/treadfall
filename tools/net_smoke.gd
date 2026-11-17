extends Node
## Developer check for online play. Start the lobby server, then two copies:
##   godot --headless res://tools/net_smoke.tscn -- host 25 [ws://127.0.0.1:8765]
##   godot --headless res://tools/net_smoke.tscn -- join 25 [ws://127.0.0.1:8765]
## The host makes a lobby, waits for the other copy, starts Base Defense and
## both print what they saw at the end.
const Main := preload("res://main.gd")
var _role := "host"
var _len := 25.0
var _main
var _t := 0.0
var _playing := false
var _start_pos := Vector2.ZERO
var _seen_shells := 0
var _seen_tanks := 0
var _banners: Array = []
var _lists := 0
var _joined := false
## Extra things to try: "", "quit", "hostquit", "over", "shop".
var _case := ""
var _step := 0


func _say(parts: Array) -> void:
	print("[NET %s] " % _role, "".join(parts.map(func(p): return str(p))))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args: Array = Array(OS.get_cmdline_user_args())
	if args.size() > 0:
		_role = args[0]
	if args.size() > 1:
		_len = float(args[1])
	if args.size() > 3:
		_case = args[3]
	Cfg.set_meta("aim_test", true)
	Net.server_url = args[2] if args.size() > 2 else Net.DEFAULT_SERVER
	Net.player_name = "HostBot" if _role == "host" else "JoinBot"
	_main = Main.new()
	add_child(_main)
	await get_tree().process_frame
	Net.problem.connect(func(text: String) -> void: _say(["PROBLEM ", text]))
	Net.left_lobby.connect(func(text: String) -> void: _say(["LEFT LOBBY ", text]))
	Net.peer_left.connect(func(peer: int) -> void: _say(["PEER LEFT ", peer, " at ", snappedf(_t, 0.1)]))
	Net.lobbies_listed.connect(_on_list)
	Net.lobby_changed.connect(_on_lobby)
	Net.game_starting.connect(func() -> void:
		_say(["battle starting, seats ", Net.lobby["slots"].map(func(s): return s["kind"])])
		_playing = true
		_t = 0.0)
	_main._menu.open_lobby()
	if _role == "host":
		while Net.status != Net.ONLINE:
			await get_tree().process_frame
		Net.create_lobby(false)


func _on_list(list: Array) -> void:
	_lists += 1
	if _role != "join" or _joined or list.is_empty():
		return
	_joined = true
	_say(["lobby list: ", list])
	Net.join_lobby(int(list[0]["id"]))


func _on_lobby() -> void:
	if _role == "host" and not _joined and Net.lobby["slots"][1]["kind"] == "human":
		_joined = true
		_say(["player joined: ", Net.lobby["slots"][1]["name"], ", code ", Net.room.get("code")])
		if _case == "ten":
			for k in range(2, Net.SLOTS):
				Net.lobby["slots"][k]["kind"] = "cpu"
		Net.set_option("difficulty", 0)
		Net.start_game.call_deferred()


func _process(delta: float) -> void:
	_t += delta
	if not _playing:
		if _t > 30.0:
			_say(["FAIL: no battle after 30 s, status ", Net.status])
			get_tree().quit(1)
		return
	var m = _main._mode
	if _case != "" and _cases(m):
		return
	if not is_instance_valid(m):
		return
	if _role == "join":
		# Drive right and up, firing, then try a workshop purchase.
		Cfg.set_meta("net_test_input", {"move": Vector2(0.6, -1.0) if _t < 6.0 else Vector2(-1, 0),
			"aim": -PI * 0.5, "fire": true, "alt": int(_t) % 3 == 0})
		if is_instance_valid(m.player) and _start_pos == Vector2.ZERO:
			_start_pos = m.player.position
		_seen_shells = maxi(_seen_shells, m._kinds.values().count("shell"))
		_seen_tanks = maxi(_seen_tanks, m._kinds.values().count("tank"))
	if _t >= _len:
		_report(m)
		set_process(false)
		# Stay a moment so the other PC can finish its own report.
		await get_tree().create_timer(5.0).timeout
		get_tree().quit(0)


func _report(m) -> void:
	var tanks: Array = []
	for t in get_tree().get_nodes_in_group("tanks"):
		tanks.append("%s team%d hp%d/%d at %s" % ["ME" if t == m.player else ("human" if t.is_player else "cpu"),
			t.team, t.hp, t.max_hp, Vector2i(t.position)])
	_say(["wave ", GameState.wave, " score ", GameState.score, " gold ", GameState.gold,
		" lives ", GameState.lives, " base ", GameState.core_hp, "/", GameState.core_max])
	_say(["tanks: ", tanks.size(), " ", tanks if tanks.size() < 9 else "", " fps ", Engine.get_frames_per_second(),
		" seats ", Net.lobby.get("slots", []).size()])
	if _role == "join":
		var moved: float = m.player.position.distance_to(_start_pos) if is_instance_valid(m.player) else -1.0
		_say(["my tank moved ", snappedf(moved, 1.0), " px, most shells seen at once ", _seen_shells,
			", most tanks ", _seen_tanks, ", walls open ", _open_walls(m)])
		_say(["RESULT ", "PASS" if moved > 60.0 and _seen_shells > 0 and _seen_tanks >= 3 else "FAIL"])
	else:
		_say(["humans ", m.humans.keys(), " seats ", Net.lobby["slots"].map(func(s): return [s["kind"], s["peer"]]),
			" modes running ", get_tree().root.find_children("*", "Node2D", true, false).filter(func(n): return n.has_signal("finished")).size()])
		var h = m.humans.get(0)
		_say(["remote player tank: ", (Vector2i(h["tank"].position) if h and is_instance_valid(h["tank"]) else "none"),
			", walls open ", _open_walls(m)])


## How many wall cells are gone: must match on both PCs.
func _open_walls(m) -> int:
	var n := 0
	for row in m.arena.grid:
		n += row.count(m.arena.EMPTY)
	return n


## The extra cases. Returns true when the normal run should not go on.
func _cases(m) -> bool:
	var host: bool = _role == "host"
	match _case:
		"quit":
			# The joining player's game is closed mid-battle.
			if not host and _t > 10.0:
				_say(["closing my game now"])
				get_tree().quit(0)
				set_process(false)
				return true
		"hostquit":
			if host and _t > 10.0:
				_say(["closing the host's game now"])
				get_tree().quit(0)
				set_process(false)
				return true
			if not host and _t > 14.0:
				_say(["after the host left: status ", Net.status, ", battle scene ", is_instance_valid(m),
					", menu ", is_instance_valid(_main._menu), ", lobby page ",
					is_instance_valid(_main._menu) and is_instance_valid(_main._menu._panel)])
				_say(["RESULT ", "PASS" if not is_instance_valid(m) and Net.status == Net.ONLINE else "FAIL"])
				get_tree().quit(0)
				set_process(false)
				return true
		"over":
			if host and _step == 0 and _t > 8.0 and is_instance_valid(m):
				_step = 1
				_say(["ending the battle (base lost)"])
				m._finish(false)
			if host and _step == 1 and _t > 12.0:
				_step = 2
				_say(["end screen up: ", is_instance_valid(_main._overlay), ", back to the lobby"])
				Net.back_to_lobby()
			if not host and _step == 0 and _t > 11.0:
				_step = 1
				_say(["end screen up: ", is_instance_valid(_main._overlay), ", over ", is_instance_valid(m) and m.is_over])
			if _step < 3 and _t > 14.0 and not Net.in_game:
				_step = 3
				_say(["in the lobby again: status ", Net.status, ", lobby page ",
					is_instance_valid(_main._menu) and is_instance_valid(_main._menu._panel), ", seats ",
					Net.lobby["slots"].map(func(s): return s["kind"])])
				if host:
					_say(["starting a second battle"])
					Net.start_game()
			return _step < 3 and _t > 8.5
		"night":
			# The host's clock jumps to night; the other PC must follow.
			var cyc = m.get_meta("cycle", null) if is_instance_valid(m) else null
			if host and _step == 0 and _t > 5.0 and is_instance_valid(cyc):
				_step = 1
				cyc.force(true)
				_say(["forced night on the host"])
			if not host and _step == 0 and _t > 9.0 and is_instance_valid(cyc):
				_step = 1
				_say(["night here: ", GameState.is_night, " (", snappedf(GameState.night, 0.01), "), phase ",
					cyc.phase, ", gates ", get_tree().get_nodes_in_group("portals").size()])
				_say(["RESULT ", "PASS" if GameState.is_night and cyc.phase == "night" else "FAIL"])
		"shop":
			if host and _step == 0 and _t > 5.0 and is_instance_valid(m):
				_step = 1
				GameState.gold = 500
				m._break_timer = 30.0
				m._open_shop()
				_say(["workshop opened, gold 500"])
			if not host and _step == 0 and _t > 8.0 and is_instance_valid(m):
				_step = 1
				_say(["workshop showing: ", is_instance_valid(m._shop), ", gold ", GameState.gold, ", hull ",
					m.player.max_hp if is_instance_valid(m.player) else -1, ", buying hull and engine"])
				m.buy("hull")
				m.buy("engine")
			if _step == 1 and _t > 11.0 and is_instance_valid(m):
				_step = 2
				if host:
					_say(["gold now ", GameState.gold, ", host upgrades ", m.upgrades, ", player upgrades ",
						m.humans[0]["upgrades"]])
				else:
					_say(["gold now ", GameState.gold, ", my upgrades ", m.upgrades, ", hull ",
						m.player.max_hp if is_instance_valid(m.player) else -1])
					_say(["RESULT ", "PASS" if m.level("hull") == 1 and m.level("engine") == 1 and GameState.gold < 500 else "FAIL"])
	return false
