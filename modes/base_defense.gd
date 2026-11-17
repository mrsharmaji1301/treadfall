extends Node2D
## Base Defense: protect the command post through every wave.
## Later modes can copy this shape: build the arena, spawn tanks, emit finished.

signal finished(victory: bool)

const Arena := preload("res://world/arena.gd")
const Levels := preload("res://world/levels.gd")
const Pathfinder := preload("res://world/pathfinder.gd")
const Tank := preload("res://entities/tank.gd")
const PlayerController := preload("res://entities/player_controller.gd")
const EnemyAI := preload("res://entities/enemy_ai.gd")
const AllyAI := preload("res://entities/ally_ai.gd")
const CoreBase := preload("res://entities/core_base.gd")
const Hud := preload("res://ui/hud.gd")
const WorldView := preload("res://view/world_view.gd")
const Fx := preload("res://fx/fx.gd")
const Pickup := preload("res://entities/pickup.gd")
const Shop := preload("res://ui/shop.gd")
const Shift := preload("res://modes/shift.gd")
const SlotBar := preload("res://ui/slot_bar.gd")
const Minimap := preload("res://ui/minimap.gd")
const Structure := preload("res://entities/structure.gd")

var arena
var pathfinder
var core
var player
var hud
var view
var is_over := false

var _queue: Array = []
var _spawn_timer := 0.0
var _spawn_index: int = 0
var _break_timer := 2.0
var _alive_enemies: int = 0
var _respawn_timer := -1.0
var _close := true
## Co-op: the allies' own route map, and seconds until each one returns.
var _ally_paths
var _ally_wait: Array = []
## The player's stored power-ups, carried over when the tank is lost.
var _kept: Dictionary = {}
## Workshop upgrades bought with gold this battle: name -> level.
var upgrades: Dictionary = {}
var _shop


func _ready() -> void:
	add_to_group("shaker")
	GameState.reset(0 if Cfg.endless else Cfg.WAVES.size())
	Structure.reset()

	# The 2D nodes are the game logic only. The player sees the 3D view.
	visible = false

	arena = Arena.new()
	add_child(arena)
	arena.build(Levels.OASIS)

	pathfinder = Pathfinder.new()
	pathfinder.setup(arena)
	arena.tile_destroyed.connect(pathfinder.refresh_cell)

	core = CoreBase.new()
	core.position = arena.cell_center(arena.core_cell)
	add_child(core)
	core.destroyed.connect(_on_core_destroyed)

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

	# THE SHIFT: day and night, and the portal gates.
	Shift.setup(self)
	_spawn_player()
	if Cfg.allies > 0:
		_ally_paths = Pathfinder.new()
		_ally_paths.walls_solid = true
		_ally_paths.setup(arena)
		arena.tile_destroyed.connect(_ally_paths.refresh_cell)
		for i in Cfg.allies:
			_ally_wait.append(-1.0)
			_spawn_ally(i)
	hud.show_banner("DEFEND THE BASE", Cfg.COL_UI)


func _process(delta: float) -> void:
	GameState.incoming = _queue.size()
	GameState.player_hp = player.hp if _player_alive() else 0
	if _player_alive():
		GameState.player_max = player.max_hp
	GameState.slots[0]["cd"] = player.cooldown_fraction() if _player_alive() else 1.0
	if is_over:
		return

	if _respawn_timer > 0.0:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_spawn_player()

	for i in _ally_wait.size():
		if _ally_wait[i] > 0.0:
			_ally_wait[i] -= delta
			if _ally_wait[i] <= 0.0:
				_spawn_ally(i)

	if _break_timer > 0.0:
		_break_timer -= delta
		if _break_timer <= 0.0:
			_close_shop()
			_start_next_wave()
	elif not _queue.is_empty():
		_spawn_timer -= delta
		if _spawn_timer <= 0.0 and _alive_enemies < _max_active():
			if _spawn_enemy(_queue[0]):
				_queue.pop_front()
				_spawn_timer = Cfg.SPAWN_INTERVAL
	elif _alive_enemies <= 0:
		if GameState.total_waves > 0 and GameState.wave >= GameState.total_waves:
			_finish(true)
		else:
			_break_timer = Cfg.SHOP_TIME
			_open_shop()
			var words := "WAVE CLEARED"
			if GameState.total_waves == 0 and GameState.wave >= Cfg.WAVES.size():
				# Survival: the crew patches the base between waves, and
				# every fifth wave held earns a spare tank.
				if is_instance_valid(core):
					core.hp = mini(core.hp + 2, core.max_hp)
					GameState.core_hp = core.hp
				if GameState.wave % 5 == 0:
					GameState.lives += 1
					words = "WAVE CLEARED  -  BONUS LIFE"
			hud.show_banner(words, Cfg.COL_UI)


## C switches between the camera behind the tank and the whole map.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera"):
		_close = not _close
		view.set_follow(player if _close and _player_alive() else null)


func shake(amount: float) -> void:
	view.shake(amount)


## How many enemy tanks may be on the map at once: grows with the waves.
func _max_active() -> int:
	var i: int = clampi(GameState.wave - 1, 0, Cfg.WAVE_ACTIVE.size() - 1)
	# Survival: one more every three waves past the written ones, up to 7.
	var more: int = mini(maxi(GameState.wave - Cfg.WAVES.size(), 0) / 3, 3)
	return maxi(int(Cfg.WAVE_ACTIVE[i]) + more + int(Cfg.diff()["active"]) + Cfg.allies, 1)


func _player_alive() -> bool:
	return is_instance_valid(player) and player.alive


func _start_next_wave() -> void:
	GameState.wave += 1
	_queue = Cfg.wave_list(GameState.wave)
	# Co-op: each ally brings about a third more attackers.
	var base: Array = _queue.duplicate()
	for i in int(ceil(base.size() * 0.35 * Cfg.allies)):
		_queue.append(base[i % base.size()])
	_spawn_timer = 0.5
	hud.show_banner("WAVE %d" % GameState.wave, Cfg.COL_WARN)


func level(key: String) -> int:
	return int(upgrades.get(key, 0))


## What the next level of a workshop upgrade costs; -1 when it is at its top.
func price(key: String) -> int:
	var u: Dictionary = Cfg.UPGRADES[key]
	if int(u["max"]) > 0 and level(key) >= int(u["max"]):
		return -1
	return roundi(float(u["cost"]) * (1.0 + float(u["grow"]) * level(key)) / 10.0) * 10


## Spends gold on a workshop upgrade. All the rules are here, so a network
## host can run this for any player later.
func buy(key: String) -> bool:
	var cost: int = price(key)
	if cost < 0 or GameState.gold < cost:
		return false
	match key:
		"base_fix":
			if not is_instance_valid(core) or core.hp >= core.max_hp:
				return false
			core.hp = mini(core.hp + 5, core.max_hp)
		"base_up":
			if not is_instance_valid(core):
				return false
			core.max_hp += 4
			core.hp += 4
		"life":
			GameState.lives += 1
		"shield":
			_kept["shield"] = mini(int(_kept.get("shield", 0)) + 1, Tank.STOCK_MAX)
	GameState.gold -= cost
	upgrades[key] = level(key) + 1
	if is_instance_valid(core):
		GameState.core_hp = core.hp
		GameState.core_max = core.max_hp
	# Tank upgrades work at once on the tank in the field.
	if _player_alive():
		match key:
			"hull":
				player.max_hp += 1
				player.hp = player.max_hp
			"fire":
				player.fire_cooldown *= 0.92
			"heavy":
				player.special_cd_mul *= 0.88
			"engine":
				player.speed += Cfg.PLAYER_SPEED * 0.06 * float(Cfg.TANKS[Cfg.my_tank]["speed"])
	return true


func _open_shop() -> void:
	_close_shop()
	_shop = Shop.new()
	_shop.mode = self
	add_child(_shop)
	Cfg.shop_open = true
	get_tree().call_group("main", "shop_changed")


func _close_shop() -> void:
	if is_instance_valid(_shop):
		_shop.queue_free()
	_shop = null
	if Cfg.shop_open:
		Cfg.shop_open = false
		get_tree().call_group("main", "shop_changed")


## Seconds until the next wave starts.
func break_left() -> float:
	return maxf(_break_timer, 0.0)


## START NOW in the workshop.
func skip_break() -> void:
	if _break_timer > 0.0:
		_break_timer = 0.01


func _exit_tree() -> void:
	Cfg.shop_open = false


func _spot_free(pos: Vector2) -> bool:
	for t in get_tree().get_nodes_in_group("tanks"):
		if t.global_position.distance_to(pos) < 46.0:
			return false
	return true


func _spawn_player() -> void:
	var t = Tank.new()
	t.team = Cfg.TEAM_PLAYER
	t.is_player = true
	t.speed = Cfg.PLAYER_SPEED * (1.0 + 0.06 * level("engine"))
	t.fire_cooldown = Cfg.PLAYER_FIRE_CD * pow(0.92, level("fire"))
	t.special_cd_mul = pow(0.88, level("heavy"))
	t.shell_speed = Cfg.PLAYER_SHELL_SPEED
	t.shell_range = Cfg.PLAYER_RANGE
	t.turret_turn_speed = Cfg.PLAYER_TURRET_SPEED
	# The design, paint and its strengths chosen on the Customize page.
	Cfg.fit_player(t, Cfg.player_hull() + level("hull"))
	t.hull_angle = -PI * 0.5
	t.turret_angle = -PI * 0.5
	t.aim_angle = -PI * 0.5
	t.shield_time = Cfg.SPAWN_SHIELD
	t.position = arena.cell_center(arena.player_spawn)
	# Power-ups still in the bar come along to the new tank.
	t.stock = _kept
	t.add_child(PlayerController.new())
	add_child(t)
	t.died.connect(_on_player_died)
	player = t
	view.add_tank(t)
	view.set_tank(t)
	if _close:
		view.set_follow(t)
	Fx.dust(self, t.position, 14)


## The nearest open cell to `want` that no tank is standing on.
func _open_cell(want: Vector2i) -> Vector2i:
	for r in 6:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := want + Vector2i(dx, dy)
				if c.x < 1 or c.y < 1 or c.x >= Cfg.cols - 1 or c.y >= Cfg.rows - 1:
					continue
				if arena.tile_at(c) != arena.EMPTY or arena.built.has(c) or arena.water.has(c) \
						or c == arena.core_cell:
					continue
				if _spot_free(arena.cell_center(c)):
					return c
	return want


## Computer ally number `i`: a tank like the player's, driven by AllyAI.
func _spawn_ally(i: int) -> void:
	var side: float = -1.0 if i % 2 == 0 else 1.0
	var row: int = i / 2
	var cell: Vector2i = _open_cell(arena.player_spawn + Vector2i(int(side) * (2 + row), row))
	var t = Tank.new()
	t.team = Cfg.TEAM_PLAYER
	t.max_hp = Cfg.player_hull()
	t.hp = Cfg.player_hull()
	t.speed = Cfg.PLAYER_SPEED * 0.85
	t.fire_cooldown = 0.9
	t.shell_speed = Cfg.PLAYER_SHELL_SPEED
	t.shell_range = Cfg.PLAYER_RANGE
	t.color = Cfg.ALLY_PAINT
	t.model = (Cfg.my_tank + 1 + i) % Cfg.TANKS.size()
	t.turret_turn_speed = Cfg.ENEMY_TURRET_SPEED
	t.hull_angle = -PI * 0.5
	t.turret_angle = -PI * 0.5
	t.aim_angle = -PI * 0.5
	t.shield_time = Cfg.SPAWN_SHIELD
	t.position = arena.cell_center(cell)
	var ai = AllyAI.new()
	ai.setup(arena, _ally_paths, core, self, false)
	ai.slot = i
	# Guard posts fan out in front of the base, towards the attackers.
	ai.post = _open_cell(arena.core_cell + Vector2i(int(side) * (3 + row * 2), -3 + row))
	t.add_child(ai)
	add_child(t)
	t.died.connect(func(_tank, _by: bool) -> void:
		if not is_over:
			_ally_wait[i] = Cfg.ALLY_RESPAWN
			hud.show_banner("ALLY DOWN", Cfg.COL_WARN))
	view.add_tank(t)
	Fx.dust(self, t.position, 14)


func _spawn_enemy(kind: String) -> bool:
	var count: int = arena.enemy_spawns.size()
	for i in count:
		var cell: Vector2i = arena.enemy_spawns[(_spawn_index + i) % count]
		var pos: Vector2 = arena.cell_center(cell)
		if not _spot_free(pos):
			continue
		_spawn_index += i + 1
		var d: Dictionary = Cfg.ENEMY_TYPES[kind]
		var t = Tank.new()
		t.team = Cfg.TEAM_ENEMY
		t.max_hp = roundi(float(d["hp"]) * Cfg.wave_hull(GameState.wave))
		t.hp = t.max_hp
		# Every enemy tank gets its own paint job.
		var look: Array = Cfg.next_skin()
		t.skin = look[0]
		t.wear = look[1]
		t.speed = float(d["speed"]) * float(Cfg.diff()["speed"])
		t.fire_cooldown = float(d["fire_cd"]) * float(Cfg.diff()["fire"])
		t.shell_speed = Cfg.ENEMY_SHELL_SPEED
		t.color = look[2]
		t.model = randi() % Cfg.TANKS.size()
		t.size_scale = d["scale"]
		t.reward = d["gold"]
		t.turret_turn_speed = Cfg.ENEMY_TURRET_SPEED
		t.hull_angle = PI * 0.5
		t.turret_angle = PI * 0.5
		t.aim_angle = PI * 0.5
		t.position = pos
		var ai = EnemyAI.new()
		ai.setup(arena, pathfinder, core, self, randf() < float(d["hunts"]))
		t.add_child(ai)
		add_child(t)
		t.died.connect(_on_enemy_died)
		_alive_enemies += 1
		view.add_tank(t)
		Fx.dust(self, pos, 14)
		return true
	return false


func _on_enemy_died(tank, by_player: bool) -> void:
	_alive_enemies -= 1
	# Only the player's own kills pay out.
	if by_player:
		GameState.add_kill(tank.reward)
	if randf() < float(Cfg.diff()["drop"]):
		_drop_pickup(tank.global_position)


## A destroyed enemy sometimes leaves a power-up by its wreck.
func _drop_pickup(at: Vector2) -> void:
	var item = Pickup.new()
	item.kind = Pickup.KINDS[randi() % Pickup.KINDS.size()]
	item.mode = self
	item.position = at
	item.taken.connect(func(text: String) -> void: hud.show_banner(text, Cfg.COL_GOOD))
	add_child.call_deferred(item)
	view.add_pickup(item)


func _on_player_died(_tank, _by_player: bool) -> void:
	shake(16.0)
	GameState.lives -= 1
	if GameState.lives <= 0:
		_finish(false)
	else:
		_respawn_timer = 1.5


func _on_core_destroyed() -> void:
	shake(22.0)
	_finish(false)


func _finish(victory: bool) -> void:
	if is_over:
		return
	is_over = true
	_close_shop()
	finished.emit(victory)
