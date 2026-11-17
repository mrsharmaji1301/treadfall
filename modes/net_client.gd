extends Node2D
## An online battle as seen by a player who is not the host. Nothing is
## decided here: the host says what exists and where it is, and this scene
## keeps a stand-in for each tank, shell, mine and power-up so that the 3D
## view, the HUD and the minimap work exactly as they do offline.

signal finished(victory: bool)

const Arena := preload("res://world/arena.gd")
const Levels := preload("res://world/levels.gd")
const Tank := preload("res://entities/tank.gd")
const Shell := preload("res://entities/shell.gd")
const Mine := preload("res://entities/mine.gd")
const Pickup := preload("res://entities/pickup.gd")
const CoreBase := preload("res://entities/core_base.gd")
const Hud := preload("res://ui/hud.gd")
const WorldView := preload("res://view/world_view.gd")
const Fx := preload("res://fx/fx.gd")
const Sfx := preload("res://fx/sfx.gd")
const Shop := preload("res://ui/shop.gd")
const SlotBar := preload("res://ui/slot_bar.gd")
const Minimap := preload("res://ui/minimap.gd")
const Structure := preload("res://entities/structure.gd")
const NetInput := preload("res://net/net_input.gd")
const Shift := preload("res://modes/shift.gd")

## Seconds between the host's position reports.
const TICK := 0.05

var arena
var core
var player
var hud
var view
var is_over := false
## This player's workshop upgrades, as the host counts them.
var upgrades: Dictionary = {}

var _nodes: Dictionary = {}
var _kinds: Dictionary = {}
## Tank number -> [from pos, to pos, from hull, to hull, from turret, to turret, progress].
var _glide: Dictionary = {}
var _shop
var _break := 0.0
var _close := true
var _saved: Array = []


func _ready() -> void:
	add_to_group("shaker")
	_saved = [Cfg.difficulty, Cfg.endless]
	Cfg.difficulty = clampi(int(Net.lobby.get("difficulty", 1)), 0, 2)
	Cfg.endless = bool(Net.lobby.get("endless", true))
	GameState.reset(0 if Cfg.endless else Cfg.WAVES.size())
	Structure.reset()
	visible = false

	arena = Arena.new()
	add_child(arena)
	arena.build(Levels.OASIS)

	core = CoreBase.new()
	core.position = arena.cell_center(arena.core_cell)
	add_child(core)

	view = WorldView.new()
	add_child(view)
	view.build(arena)
	view.add_core(core)

	hud = Hud.new()
	add_child(hud)
	var slots = SlotBar.new()
	slots.mode = self
	add_child(slots)
	var radar = Minimap.new()
	radar.mode = self
	add_child(radar)

	# THE SHIFT: the same gates and clock as the host. The gates here only
	# show; the clock runs between the host's reports to stay smooth.
	Shift.setup(self)
	for g in get_tree().get_nodes_in_group("portals"):
		g.set_physics_process(false)

	var pad = NetInput.new()
	pad.mode = self
	add_child(pad)

	Net.game_message.connect(_on_net)
	Net.drain()


func _exit_tree() -> void:
	Cfg.shop_open = false
	if _saved.size() == 2:
		Cfg.difficulty = _saved[0]
		Cfg.endless = _saved[1]


func shake(amount: float) -> void:
	view.shake(amount)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera"):
		_close = not _close
		view.set_follow(player if _close and _player_alive() else null)


func _player_alive() -> bool:
	return is_instance_valid(player) and player.alive


# --- what the workshop panel asks of a game mode -----------------------------

func level(key: String) -> int:
	return int(upgrades.get(key, 0))


func price(key: String) -> int:
	var u: Dictionary = Cfg.UPGRADES[key]
	if int(u["max"]) > 0 and level(key) >= int(u["max"]):
		return -1
	return roundi(float(u["cost"]) * (1.0 + float(u["grow"]) * level(key)) / 10.0) * 10


func buy(key: String) -> bool:
	Net.send_host([Net.C_BUY, key])
	return true


func break_left() -> float:
	return maxf(_break, 0.0)


func skip_break() -> void:
	Net.send_host([Net.C_SKIP])


func _set_shop(open: bool) -> void:
	if open == is_instance_valid(_shop):
		return
	if open:
		_shop = Shop.new()
		_shop.mode = self
		add_child(_shop)
	else:
		_shop.queue_free()
		_shop = null
	Cfg.shop_open = open
	get_tree().call_group("main", "shop_changed")


# --- messages from the host --------------------------------------------------

func _on_net(from: int, msg: Array) -> void:
	if from != Net.HOST:
		return
	match int(msg[0]):
		Net.S_SPAWN:
			_spawn(int(msg[1]), str(msg[2]), msg[3])
		Net.S_GONE:
			_gone(int(msg[1]), bool(msg[2]))
		Net.S_STATE:
			_state(msg[1], msg[2], msg[3], msg[4])
		Net.S_FX:
			_fx(str(msg[1]), msg[2])
		Net.S_TILE:
			_tile(msg[1], bool(msg[2]))
		Net.S_BANNER:
			hud.show_banner(str(msg[1]), msg[2])
		Net.S_OVER:
			if not is_over:
				is_over = true
				_set_shop(false)
				finished.emit(bool(msg[1]))


func _spawn(nid: int, kind: String, p: Dictionary) -> void:
	var n
	match kind:
		"tank":
			n = Tank.new()
			n.team = int(p["team"])
			n.color = p["color"]
			n.skin = str(p["skin"])
			n.wear = str(p["wear"])
			n.model = int(p["model"])
			n.size_scale = float(p["scale"])
			n.hp = int(p["hp"])
			n.max_hp = int(p["max"])
			n.shell_range = float(p["range"])
			n.dummy = bool(p["dummy"])
			n.hull_angle = float(p["hull"])
			n.turret_angle = float(p["turret"])
			n.is_player = int(p["owner"]) == Net.my_id
		"shell":
			n = Shell.new()
			n.team = int(p["team"])
			n.heavy = bool(p["heavy"])
			n.homing = bool(p["homing"])
			n.velocity = p["vel"]
			n.rotation = n.velocity.angle()
		"mine":
			n = Mine.new()
			n.team = int(p["team"])
		"pickup":
			n = Pickup.new()
			n.kind = str(p["kind"])
			n.cache = bool(p["cache"])
			n.life = float(p["life"])
		_:
			return
	n.position = p["pos"]
	add_child(n)
	# A stand-in: the host moves it, it decides nothing itself.
	n.set_physics_process(false)
	_nodes[nid] = n
	_kinds[nid] = kind
	match kind:
		"tank":
			view.add_tank(n)
			if n.is_player:
				player = n
				view.set_tank(n)
				if _close:
					view.set_follow(n)
		"shell":
			view.add_shell(n)
			if n.homing:
				Sfx.at(view, "missile_launch", view.spot(n.position), -2.0)
		"mine":
			view.add_mine(n)
			Sfx.at(view, "mine_drop", view.spot(n.position), -4.0)
		"pickup":
			view.add_pickup(n)


func _gone(nid: int, dead: bool) -> void:
	var n = _nodes.get(nid)
	var kind: String = _kinds.get(nid, "")
	_nodes.erase(nid)
	_kinds.erase(nid)
	_glide.erase(nid)
	if not is_instance_valid(n):
		return
	if kind == "tank" and dead:
		n.alive = false
		if n == player:
			shake(16.0)
	elif kind == "pickup" and n.life > 0.5:
		Sfx.flat(self, "pickup", -4.0)
	n.queue_free()


func _state(tanks: PackedFloat32Array, shells: PackedFloat32Array, gs: Array, extra: Dictionary) -> void:
	for i in range(0, tanks.size() - 9, 10):
		var nid: int = int(tanks[i])
		var t = _nodes.get(nid)
		if not is_instance_valid(t):
			continue
		var to := Vector2(tanks[i + 1], tanks[i + 2])
		# A respawn or a long gap: jump there instead of sliding.
		if not _glide.has(nid) or t.position.distance_to(to) > 200.0:
			t.position = to
			t.hull_angle = tanks[i + 3]
			t.turret_angle = tanks[i + 4]
		_glide[nid] = [t.position, to, t.hull_angle, tanks[i + 3], t.turret_angle, tanks[i + 4], 0.0]
		t.hp = int(tanks[i + 5])
		t.max_hp = int(tanks[i + 6])
		var flags: int = int(tanks[i + 7])
		t.in_water = flags & 1 != 0
		t.submerged = flags & 2 != 0
		t.shield_time = tanks[i + 8]
		t.recoil = maxf(t.recoil, tanks[i + 9])
	for i in range(0, shells.size() - 4, 5):
		var s = _nodes.get(int(shells[i]))
		if not is_instance_valid(s):
			continue
		var at := Vector2(shells[i + 1], shells[i + 2])
		s.velocity = Vector2(shells[i + 3], shells[i + 4])
		s.rotation = s.velocity.angle()
		s.position = at if s.position.distance_to(at) > 40.0 else s.position.lerp(at, 0.35)
	GameState.score = int(gs[0])
	GameState.gold = int(gs[1])
	GameState.wave = int(gs[2])
	GameState.total_waves = int(gs[3])
	GameState.lives = int(gs[4])
	GameState.incoming = int(gs[5])
	GameState.core_hp = int(gs[6])
	GameState.core_max = int(gs[7])
	_break = float(gs[8])
	core.hp = GameState.core_hp
	core.max_hp = GameState.core_max
	if core.alive and core.hp <= 0:
		core.alive = false
	_set_shop(bool(gs[9]) and not is_over)
	var cycle = get_meta("cycle", null)
	if gs.size() > 12 and is_instance_valid(cycle) and str(gs[11]) != "":
		GameState.day_no = int(gs[10])
		if cycle.phase != str(gs[11]):
			# The host's clock moved on: step this one the same way, so the
			# warnings and the banner still show.
			var was_night: bool = GameState.is_night
			cycle.phase = str(gs[11])
			GameState.is_night = cycle.phase == "night" or cycle.phase == "dawn"
			if GameState.is_night != was_night:
				cycle.shifted.emit(GameState.is_night)
		cycle._left = float(gs[12])
	for nid in extra:
		var t = _nodes.get(int(nid))
		var e: Array = extra[nid]
		if not is_instance_valid(t) or not t.is_player or e.size() < 11:
			continue
		t.stock = e[0]
		t.buffs = e[1]
		t.picked = e[2]
		t.special = str(e[3])
		t.special_ammo = int(e[4])
		t._cd = float(e[5])
		t.fire_cooldown = float(e[6])
		t._cd2 = float(e[7])
		t.special_cd_mul = float(e[8])
		t.exposed = float(e[9])
		upgrades = e[10]


func _fx(name: String, a: Array) -> void:
	match name:
		"heal":
			Fx.heal(self, a[0])
		"dust":
			Fx.dust(self, a[0], int(a[1]))
		"hit":
			Fx.hit(self, a[0], str(a[1]))
		"muzzle":
			Fx.muzzle(self, a[0], a[1], bool(a[2]))
		"explosion":
			Fx.explosion(self, a[0], bool(a[1]), float(a[2]))
		"portal":
			var gates: Array = get_tree().get_nodes_in_group("portals")
			var k: int = int(a[0])
			if k >= 0 and k < gates.size():
				gates[k].used.emit(null, a[1], a[2])


## A wall block was chipped or knocked down on the host.
func _tile(cell: Vector2i, destroyed: bool) -> void:
	if not destroyed:
		arena.tile_damaged.emit(cell)
		return
	if arena.tile_at(cell) == arena.EMPTY:
		return
	arena.grid[cell.y][cell.x] = arena.EMPTY
	arena._hp.erase(cell)
	if arena._shapes.has(cell):
		arena._shapes[cell].queue_free()
		arena._shapes.erase(cell)
	arena.tile_destroyed.emit(cell)


func _process(delta: float) -> void:
	GameState.player_hp = player.hp if _player_alive() else 0
	if _player_alive():
		GameState.player_max = player.max_hp
	GameState.slots[0]["cd"] = player.cooldown_fraction() if _player_alive() else 1.0
	_break = maxf(_break - delta, 0.0)
	for nid in _nodes:
		var n = _nodes[nid]
		if not is_instance_valid(n):
			continue
		match _kinds[nid]:
			"tank":
				n.recoil = maxf(n.recoil - delta * 6.0, 0.0)
				n.shield_time = maxf(n.shield_time - delta, 0.0)
				n._cd = maxf(n._cd - delta, 0.0)
				n._cd2 = maxf(n._cd2 - delta, 0.0)
				if _glide.has(nid):
					var g: Array = _glide[nid]
					g[6] = minf(float(g[6]) + delta / TICK, 1.0)
					n.position = g[0].lerp(g[1], g[6])
					n.hull_angle = lerp_angle(g[2], g[3], g[6])
					n.turret_angle = lerp_angle(g[4], g[5], g[6])
			"shell":
				n.position += n.velocity * delta
			"mine":
				n.arm -= delta
			"pickup":
				if not n.cache:
					n.life -= delta
