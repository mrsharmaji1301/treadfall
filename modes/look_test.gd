extends Node2D
## Free roam: the Twin Banks river map with no enemies attacking, to judge the
## map, models, water and effects. Three parked enemy tanks can be shot.

signal finished(victory: bool)

const Arena := preload("res://world/arena.gd")
const Levels := preload("res://world/levels.gd")
const Tank := preload("res://entities/tank.gd")
const PlayerController := preload("res://entities/player_controller.gd")
const CoreBase := preload("res://entities/core_base.gd")
const WorldView := preload("res://view/world_view.gd")
const Ui := preload("res://ui/ui_kit.gd")
const SlotBar := preload("res://ui/slot_bar.gd")
const Minimap := preload("res://ui/minimap.gd")
const Pickup := preload("res://entities/pickup.gd")
const Structure := preload("res://entities/structure.gd")
const Shift := preload("res://modes/shift.gd")

var arena
var view
var player
var core
var enemy_core
var is_over := false
var _close := true
var _respawn := -1.0


func _ready() -> void:
	add_to_group("shaker")
	visible = false
	GameState.reset(0)
	Structure.reset()

	arena = Arena.new()
	add_child(arena)
	arena.build(Levels.RIVER)

	core = CoreBase.new()
	core.position = arena.cell_center(arena.core_cell)
	add_child(core)

	view = WorldView.new()
	add_child(view)
	view.build(arena)
	view.add_core(core)

	# The enemy's Command Centre on the far bank.
	if arena.enemy_core_cell.x >= 0:
		enemy_core = CoreBase.new()
		enemy_core.team = Cfg.TEAM_ENEMY
		enemy_core.hp = 30
		enemy_core.max_hp = 30
		enemy_core.position = arena.cell_center(arena.enemy_core_cell)
		add_child(enemy_core)
		view.add_core(enemy_core)

	# Towers and guns on both banks. The river decides whose they are.
	for spot in arena.defence_spots:
		var b = Structure.new()
		b.kind = spot[1]
		b.position = arena.cell_center(spot[0])
		b.team = Cfg.TEAM_ENEMY if arena.is_north(b.position) else Cfg.TEAM_PLAYER
		add_child(b)
		view.add_structure(b)

	# Loot hidden in the jungle.
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for cell in arena.loot_cells:
		var item = Pickup.new()
		item.kind = Pickup.KINDS[rng.randi() % Pickup.KINDS.size()]
		item.cache = true
		item.mode = self
		item.position = arena.cell_center(cell)
		add_child(item)
		view.add_pickup(item)

	# THE SHIFT: day and night, and the portal gates.
	Shift.setup(self)
	_spawn_player()

	# One parked tank of each enemy type near the base. They can be shot,
	# and our own guns leave them alone.
	var x: int = arena.player_spawn.x - 3
	for kind in ["scout", "gunner", "bruiser"]:
		var d: Dictionary = Cfg.ENEMY_TYPES[kind]
		var parked = _add_tank(Vector2i(x, arena.player_spawn.y - 4), d["color"], d["scale"],
			Cfg.TEAM_ENEMY, d["hp"])
		parked.dummy = true
		parked.died.connect(_on_parked_died)
		x += 3

	var slots = SlotBar.new()
	slots.mode = self
	add_child(slots)
	var radar = Minimap.new()
	radar.mode = self
	add_child(radar)
	var layer := CanvasLayer.new()
	add_child(layer)
	var strip := ColorRect.new()
	strip.color = Color(0, 0, 0, 0.5)
	strip.size = Vector2(1280, 44)
	layer.add_child(strip)
	layer.add_child(Ui.centered(
		"FREE ROAM     Drive: WASD     Aim: mouse     Rapid fire: left click     Heavy shot: right click     Zoom: mouse wheel     Camera: C     Menu: Esc",
		18, Cfg.COL_UI, 4.0))


func _spawn_player() -> void:
	player = _add_tank(arena.player_spawn, Cfg.PAINT_PLAYER, 1.0, Cfg.TEAM_PLAYER, Cfg.player_hull())
	player.is_player = true
	player.speed = Cfg.PLAYER_SPEED
	player.fire_cooldown = Cfg.PLAYER_FIRE_CD
	player.shell_speed = Cfg.PLAYER_SHELL_SPEED
	player.shell_range = Cfg.PLAYER_RANGE
	player.turret_turn_speed = Cfg.PLAYER_TURRET_SPEED
	player.shield_time = 2.0
	player.add_child(PlayerController.new())
	player.died.connect(_on_player_died)
	view.set_tank(player)
	view.set_follow(player if _close else null)


func _on_player_died(_tank, _by_player: bool) -> void:
	shake(14.0)
	_respawn = 2.0


func _process(delta: float) -> void:
	if _respawn > 0.0:
		_respawn -= delta
		if _respawn <= 0.0:
			_spawn_player()


func _add_tank(cell: Vector2i, paint: Color, size: float, team: int, hp: int):
	var t = Tank.new()
	t.team = team
	t.max_hp = hp
	t.hp = hp
	t.color = paint
	if team == Cfg.TEAM_ENEMY:
		# Every enemy tank gets its own paint job.
		var look: Array = Cfg.next_skin()
		t.skin = look[0]
		t.wear = look[1]
		t.color = look[2]
		t.model = randi() % Cfg.TANKS.size()
	else:
		t.model = Cfg.my_tank
		t.skin = Cfg.SKINS[Cfg.my_skin]
		t.wear = Cfg.WEARS[Cfg.my_wear]
		t.color = Cfg.TINTS[Cfg.my_tint][1]
	t.size_scale = size
	t.hull_angle = -PI * 0.5
	t.turret_angle = -PI * 0.5
	t.aim_angle = -PI * 0.5
	t.position = arena.cell_center(cell)
	if team == Cfg.TEAM_PLAYER:
		t.is_player = true
	add_child(t)
	view.add_tank(t)
	return t


## Every parked tank leaves a power-up here, so they can be tried out.
func _on_parked_died(tank, _by_player: bool) -> void:
	var item = Pickup.new()
	item.kind = Pickup.KINDS[randi() % Pickup.KINDS.size()]
	item.mode = self
	item.position = tank.global_position
	add_child.call_deferred(item)
	view.add_pickup(item)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera"):
		_close = not _close
		view.set_follow(player if _close else null)


func shake(amount: float) -> void:
	view.shake(amount)
