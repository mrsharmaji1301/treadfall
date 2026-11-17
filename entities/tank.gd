extends CharacterBody2D
## One tank: movement, health and firing. Its 3D model is view/tank_model.gd. A controller child node
## (player_controller.gd or enemy_ai.gd) sets move_dir and aim_angle.

signal died(tank, by_player: bool)

const Shell := preload("res://entities/shell.gd")
const Fx := preload("res://fx/fx.gd")
const Sfx := preload("res://fx/sfx.gd")
const Mine := preload("res://entities/mine.gd")

var team: int = 0
var is_player := false
var max_hp: int = 3
var hp: int = 3
var speed := 170.0
var fire_cooldown := 0.45
var shell_speed := 520.0
var shell_damage: int = 1
## How far this tank's shells fly before they drop, in pixels.
var shell_range := Cfg.ENEMY_RANGE
var color := Color.WHITE
## Paint job: which base paint ("" lets the colour choose) and which dirt
## over it ("", "mud" or "rust"). Only the look; see Cfg.next_skin().
var skin := ""
## Which tank design it is: a number into Cfg.TANKS.
var model: int = 0
## A tank on show in a menu: no sound, no dust.
var display := false
var wear := ""
var size_scale := 1.0
var reward: int = 0
var turret_turn_speed := 2.2

var hull_angle := 0.0
var turret_angle := 0.0
var move_dir := Vector2.ZERO
var aim_angle := 0.0
var shield_time := 0.0
var alive := true
var in_water := false
## In the deep channel: the hull is under water, only the gun shows.
var submerged := false
## A parked target: defences leave it alone.
var dummy := false
## Seconds until the tank can hide again after giving itself away by firing.
var exposed := 0.0
## Timed power-ups: name -> seconds left. "boost", "rapid", "cannon".
var buffs: Dictionary = {}
## How many of each power-up this tank has collected.
var picked: Dictionary = {}
## Power-ups the player carries and sets off with the number keys:
## name -> how many. See ITEMS for the key order.
var stock: Dictionary = {}
const ITEMS := ["repair", "boost", "rapid", "cannon", "shield"]
const STOCK_MAX := 9
const BUFF_TIME := 16.0
const SHIELD_TIME := 6.0
## Right-button weapon: "heavy", "missile" or "mine", and rounds left (-1 = endless).
var special := "heavy"
var special_ammo: int = -1
var _cd2 := 0.0
## Workshop upgrade: the special weapon reloads in this share of the time.
var special_cd_mul := 1.0

var _cd := 0.0
var recoil := 0.0


func _ready() -> void:
	collision_layer = Cfg.LAYER_TANK
	collision_mask = Cfg.LAYER_WALL | Cfg.LAYER_TANK | Cfg.LAYER_CORE
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var circle := CircleShape2D.new()
	circle.radius = 17.0 * size_scale
	var cs := CollisionShape2D.new()
	cs.shape = circle
	add_child(cs)
	add_to_group("tanks")


func _physics_process(delta: float) -> void:
	_cd = maxf(_cd - delta, 0.0)
	_cd2 = maxf(_cd2 - delta, 0.0)
	recoil = maxf(recoil - delta * 6.0, 0.0)
	shield_time = maxf(shield_time - delta, 0.0)
	exposed = maxf(exposed - delta, 0.0)
	var mode = get_parent()
	var pace := 1.0
	if mode != null and mode.get("arena") != null:
		pace = mode.arena.pace_at(global_position)
		in_water = mode.arena.is_water(global_position)
		submerged = mode.arena.is_deep(global_position)
	for key in buffs.keys():
		buffs[key] = float(buffs[key]) - delta
		if float(buffs[key]) <= 0.0:
			buffs.erase(key)
	if buffs.has("boost"):
		pace *= 1.35
	if move_dir.length_squared() > 0.01:
		velocity = move_dir.limit_length(1.0) * speed * pace
		hull_angle = rotate_toward(hull_angle, move_dir.angle(), 9.0 * delta)
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	turret_angle = rotate_toward(turret_angle, aim_angle, turret_turn_speed * delta)


## Camouflage: a player tank in water is hard to spot until it fires.
func concealed() -> bool:
	return alive and team == Cfg.TEAM_PLAYER and in_water and exposed <= 0.0


func try_fire() -> bool:
	if not alive or _cd > 0.0:
		return false
	_cd = fire_cooldown * (0.55 if buffs.has("rapid") else 1.0)
	# The player's left-button gun is a light quick-firer with a small kick.
	recoil = 0.45 if is_player else 1.0
	var dir := Vector2.RIGHT.rotated(turret_angle)
	var shell = Shell.new()
	# Starts at the tank centre so it can never begin inside a wall.
	shell.setup(self, global_position, dir)
	if buffs.has("cannon"):
		shell.damage *= 2
	exposed = Cfg.CAMO_BREAK
	if is_player:
		# The gun is loud: enemies in earshot learn where the shot came from.
		get_tree().call_group("enemy_ai", "hear", global_position)
	get_parent().add_child(shell)
	get_tree().call_group("world_view", "add_shell", shell)
	Fx.muzzle(get_parent(), global_position + dir * 44.0 * size_scale, dir, not is_player)
	return true


## Right button: the special weapon. One heavy shot by default; a power-up
## swaps in seeking missiles or mines until their rounds run out.
func try_special() -> bool:
	if not alive or _cd2 > 0.0:
		return false
	var spec: Dictionary = Cfg.SPECIALS[special]
	_cd2 = float(spec["cd"]) * special_cd_mul
	var dir := Vector2.RIGHT.rotated(turret_angle)
	var view = get_tree().get_first_node_in_group("world_view")
	if special == "mine":
		var mine = Mine.new()
		mine.team = team
		mine.by_player = is_player
		mine.position = global_position - Vector2.RIGHT.rotated(hull_angle) * 34.0 * size_scale
		get_parent().add_child(mine)
		if view != null:
			view.add_mine(mine)
			Sfx.at(view, "mine_drop", view.spot(mine.position), -4.0)
	else:
		var shell = Shell.new()
		shell.setup(self, global_position, dir)
		shell.heavy = true
		shell.damage = int(spec["damage"]) * (2 if buffs.has("cannon") else 1)
		if special == "missile":
			shell.homing = true
			shell.velocity = dir * 330.0
			shell.life = 4.5
			shell.reach = Cfg.MISSILE_RANGE
			recoil = 0.45
			if view != null:
				Sfx.at(view, "missile_launch", view.spot(global_position), -2.0)
		else:
			shell.velocity = dir * shell_speed * 0.9
			shell.reach = shell_range * Cfg.HEAVY_RANGE_MUL
			recoil = 1.0
			Fx.muzzle(get_parent(), global_position + dir * 44.0 * size_scale, dir, true)
		get_parent().add_child(shell)
		get_tree().call_group("world_view", "add_shell", shell)
	# A mine goes down quietly; anything fired gives the tank away.
	if special != "mine":
		exposed = Cfg.CAMO_BREAK
	if is_player and special != "mine":
		get_tree().call_group("enemy_ai", "hear", global_position)
	if special_ammo > 0:
		special_ammo -= 1
		if special_ammo == 0:
			special = "heavy"
			special_ammo = -1
	return true


## Loads a special weapon picked up in the field.
func give_special(kind: String) -> void:
	special = kind
	special_ammo = int(Cfg.SPECIALS[kind]["ammo"])
	_cd2 = minf(_cd2, 0.4)


func special_fraction() -> float:
	return clampf(_cd2 / (float(Cfg.SPECIALS[special]["cd"]) * special_cd_mul), 0.0, 1.0)


func add_buff(kind: String, seconds: float) -> void:
	buffs[kind] = maxf(float(buffs.get(kind, 0.0)), seconds)


## Puts a collected power-up to work at once. Returns false when it would
## be wasted (a repair on a whole hull).
func apply_item(kind: String) -> bool:
	match kind:
		"repair":
			if hp >= max_hp:
				return false
			hp = mini(hp + 2, max_hp)
			Fx.heal(get_parent(), global_position)
		"shield":
			shield_time = maxf(shield_time, 0.0) + SHIELD_TIME
		"boost", "rapid", "cannon":
			buffs[kind] = float(buffs.get(kind, 0.0)) + BUFF_TIME
		_:
			return false
	return true


## Number keys: sets off one stored power-up.
func use_item(kind: String) -> bool:
	if not alive or int(stock.get(kind, 0)) <= 0:
		return false
	if not apply_item(kind):
		return false
	stock[kind] = int(stock[kind]) - 1
	return true


func buff_left(kind: String) -> float:
	return float(buffs.get(kind, 0.0))


func cooldown_fraction() -> float:
	return clampf(_cd / fire_cooldown, 0.0, 1.0)


func take_damage(amount: int, by_player: bool) -> void:
	if not alive or shield_time > 0.0:
		return
	hp -= amount
	if hp <= 0:
		alive = false
		Fx.explosion(get_parent(), global_position)
		died.emit(self, by_player)
		queue_free()
