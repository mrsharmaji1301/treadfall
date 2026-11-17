extends "res://modes/base_defense.gd"
## Base Defense played online, on the lobby host's PC. The seats after the
## host are the allies: a seat with a player in it is driven by that
## player's controls, the rest by the computer as in the offline game.

const Replicator := preload("res://net/replicator.gd")
const RemoteController := preload("res://net/remote_controller.gd")

## Ally number -> {"peer", "name", "look", "tank", "input", "kept", "upgrades"}.
var humans: Dictionary = {}
var _rep
var _saved: Array = []


func _ready() -> void:
	_saved = [Cfg.allies, Cfg.difficulty, Cfg.endless]
	Cfg.difficulty = clampi(int(Net.lobby["difficulty"]), 0, 2)
	Cfg.endless = bool(Net.lobby["endless"])
	var seats: int = 0
	var slots: Array = Net.lobby["slots"]
	for i in range(1, slots.size()):
		var s: Dictionary = slots[i]
		if s["kind"] == "closed":
			continue
		if s["kind"] == "human":
			humans[seats] = {"peer": int(s["peer"]), "name": str(s["name"]), "look": s["look"],
				"tank": null, "input": {}, "kept": {}, "upgrades": {}}
		seats += 1
	Cfg.allies = seats
	_rep = Replicator.new()
	_rep.mode = self
	child_entered_tree.connect(_rep.on_child)
	super._ready()
	add_child(_rep)
	arena.tile_damaged.connect(func(cell: Vector2i) -> void: Net.send_all([Net.S_TILE, cell, false]))
	arena.tile_destroyed.connect(func(cell: Vector2i) -> void: Net.send_all([Net.S_TILE, cell, true]))
	# THE SHIFT: a tank going through a portal flashes the gates on every PC.
	var gates: Array = get_tree().get_nodes_in_group("portals")
	for k in gates.size():
		gates[k].used.connect(func(_t, from: Vector2, to: Vector2) -> void:
			Net.fx(self, "portal", [k, from, to]))
	Net.game_message.connect(_on_net)
	Net.peer_left.connect(_on_peer_left)
	Net.drain()


func _exit_tree() -> void:
	super._exit_tree()
	if _saved.size() == 3:
		Cfg.allies = _saved[0]
		Cfg.difficulty = _saved[1]
		Cfg.endless = _saved[2]


## With a big team the attackers stop growing after five allies, so the
## host's PC is not swamped (each ally adds a third more enemies offline).
const ALLY_CAP := 5


func _max_active() -> int:
	var seats: int = Cfg.allies
	Cfg.allies = mini(seats, ALLY_CAP)
	var n: int = super._max_active()
	Cfg.allies = seats
	return n


func _start_next_wave() -> void:
	var seats: int = Cfg.allies
	Cfg.allies = mini(seats, ALLY_CAP)
	super._start_next_wave()
	Cfg.allies = seats


func _spawn_ally(i: int) -> void:
	if humans.has(i):
		_spawn_human(i)
	else:
		super._spawn_ally(i)


## The tank of the player in ally seat `i`: built like the host's own, with
## that player's design, paint and workshop upgrades.
func _spawn_human(i: int) -> void:
	var h: Dictionary = humans[i]
	var up: Dictionary = h["upgrades"]
	var side: float = -1.0 if i % 2 == 0 else 1.0
	var row: int = i / 2
	var cell: Vector2i = _open_cell(arena.player_spawn + Vector2i(int(side) * (2 + row), row))
	var t = Tank.new()
	t.team = Cfg.TEAM_PLAYER
	t.is_player = true
	t.speed = Cfg.PLAYER_SPEED * (1.0 + 0.06 * int(up.get("engine", 0)))
	t.fire_cooldown = Cfg.PLAYER_FIRE_CD * pow(0.92, int(up.get("fire", 0)))
	t.special_cd_mul = pow(0.88, int(up.get("heavy", 0)))
	t.shell_speed = Cfg.PLAYER_SHELL_SPEED
	t.shell_range = Cfg.PLAYER_RANGE
	t.turret_turn_speed = Cfg.PLAYER_TURRET_SPEED
	# Cfg.fit_player reads the local player's choices: lend it this player's.
	var mine := [Cfg.my_tank, Cfg.my_skin, Cfg.my_wear, Cfg.my_tint]
	var look: Array = h["look"] if h["look"] is Array and h["look"].size() == 4 else mine
	Cfg.my_tank = clampi(int(look[0]), 0, Cfg.TANKS.size() - 1)
	Cfg.my_skin = clampi(int(look[1]), 0, Cfg.SKINS.size() - 1)
	Cfg.my_wear = clampi(int(look[2]), 0, Cfg.WEARS.size() - 1)
	Cfg.my_tint = clampi(int(look[3]), 0, Cfg.TINTS.size() - 1)
	Cfg.fit_player(t, Cfg.player_hull() + int(up.get("hull", 0)))
	Cfg.my_tank = mine[0]
	Cfg.my_skin = mine[1]
	Cfg.my_wear = mine[2]
	Cfg.my_tint = mine[3]
	t.hull_angle = -PI * 0.5
	t.turret_angle = -PI * 0.5
	t.aim_angle = -PI * 0.5
	t.shield_time = Cfg.SPAWN_SHIELD
	t.position = arena.cell_center(cell)
	t.stock = h["kept"]
	t.set_meta("owner", int(h["peer"]))
	var rc = RemoteController.new()
	rc.input = h["input"]
	t.add_child(rc)
	add_child(t)
	t.died.connect(_on_human_died.bind(i))
	h["tank"] = t
	view.add_tank(t)
	Fx.dust(self, t.position, 14)


## A player's tank is lost: it costs the team a life, like the host's.
func _on_human_died(_tank, _by_player: bool, i: int) -> void:
	if is_over:
		return
	GameState.lives -= 1
	if GameState.lives <= 0:
		_finish(false)
	else:
		_ally_wait[i] = 1.5


func _human_of(peer: int) -> int:
	for i in humans:
		if int(humans[i]["peer"]) == peer:
			return i
	return -1


func _on_net(from: int, msg: Array) -> void:
	var i: int = _human_of(from)
	if i < 0:
		return
	var h: Dictionary = humans[i]
	match int(msg[0]):
		Net.C_INPUT:
			if msg.size() < 4 or not msg[1] is Vector2:
				return
			var bits: int = int(msg[3])
			h["input"]["move"] = msg[1]
			h["input"]["aim"] = float(msg[2])
			h["input"]["fire"] = bits & 1 != 0
			h["input"]["alt"] = bits & 2 != 0
			var t = h["tank"]
			if is_instance_valid(t) and t.alive:
				for k in t.ITEMS.size():
					if bits & (4 << k) != 0:
						t.use_item(t.ITEMS[k])
		Net.C_BUY:
			if msg.size() > 1 and Cfg.UPGRADES.has(str(msg[1])) and Cfg.shop_open:
				_buy_for(i, str(msg[1]))
		Net.C_SKIP:
			skip_break()


## Runs the workshop rules (buy) for another player's tank and upgrades.
## The gold is the team's.
func _buy_for(i: int, key: String) -> void:
	var h: Dictionary = humans[i]
	var held := [player, _kept, upgrades]
	player = h["tank"] if is_instance_valid(h["tank"]) else null
	_kept = h["kept"]
	upgrades = h["upgrades"]
	buy(key)
	player = held[0]
	_kept = held[1]
	upgrades = held[2]


## A player dropped out: the computer takes that seat.
func _on_peer_left(peer: int) -> void:
	var i: int = _human_of(peer)
	if i < 0:
		return
	var h: Dictionary = humans[i]
	humans.erase(i)
	hud.show_banner("%s LEFT" % str(h["name"]).to_upper(), Cfg.COL_WARN)
	var t = h["tank"]
	if is_instance_valid(t) and t.alive:
		t.alive = false
		t.queue_free()
	if not is_over:
		_ally_wait[i] = 1.0


func _finish(victory: bool) -> void:
	var was: bool = is_over
	super._finish(victory)
	if not was:
		Net.send_all([Net.S_OVER, victory])
