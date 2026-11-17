extends StaticBody2D
## A fixed defence. Four kinds, in lines from the river back to the base:
##   tower      watches the river bank and reports what it sees
##   turret     first line: one slow gun that hits very hard
##   artillery  second line: lobs shells a long way, they land after a delay
##   guard      last line: two fast guns in front of the Command Centre
## Its 3D model is view/structure_view.gd.
##
## Lines fall in order. The second line and everything behind it cannot be
## damaged until at least one defence of the line in front has been destroyed.

signal destroyed(structure)

const Fx := preload("res://fx/fx.gd")
const Sfx := preload("res://fx/sfx.gd")
const Shell := preload("res://entities/shell.gd")
const Barrage := preload("res://entities/barrage.gd")

const SPECS := {
	"tower": {"hp": 8, "line": 0, "sight": 620.0},
	"turret": {"hp": 16, "line": 1, "range": 440.0, "cd": 2.4, "damage": 2, "speed": 540.0},
	"artillery": {"hp": 14, "line": 2, "range": 900.0, "near": 220.0, "cd": 5.5, "damage": 3},
	"guard": {"hp": 24, "line": 3, "range": 410.0, "cd": 0.55, "damage": 1, "speed": 600.0},
}
## The Command Centre counts as the line behind the last guns.
const CORE_LINE := 4

## How many defences each team has built and lost, per line: key team * 10 + line.
static var built: Dictionary = {}
static var fallen: Dictionary = {}

var team: int = Cfg.TEAM_PLAYER
var kind := "turret"
var hp: int = 1
var max_hp: int = 1
var alive := true
var line: int = 0
var aim_angle := 0.0
## True for a moment after firing; the model reads it for its recoil.
var kick := 0.0
## Towers: true while something hostile is in view.
var spotting := false
## Read by shells fired from here.
var is_player := false
var shell_damage: int = 1
var shell_speed := 500.0
## Shells from a gun fly a little past the distance it opens fire at.
var shell_range := 470.0
var _cd := 1.0
var _scan := 0.0
var _target = null
var _barrel: int = 0


static func reset() -> void:
	built = {}
	fallen = {}


## True if a team's line cannot be hurt yet: the line in front still stands whole.
static func line_shielded(for_team: int, for_line: int) -> bool:
	if for_line < 2:
		return false
	var key: int = for_team * 10 + for_line - 1
	return int(built.get(key, 0)) > 0 and int(fallen.get(key, 0)) == 0


func _ready() -> void:
	var spec: Dictionary = SPECS[kind]
	max_hp = int(spec["hp"])
	hp = max_hp
	line = int(spec["line"])
	shell_damage = int(spec.get("damage", 1))
	shell_speed = float(spec.get("speed", 500.0))
	shell_range = float(spec.get("range", 420.0)) * 1.12
	collision_layer = Cfg.LAYER_CORE
	collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(42, 42)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)
	add_to_group("structures")
	built[team * 10 + line] = int(built.get(team * 10 + line, 0)) + 1
	aim_angle = PI * 0.5 if team == Cfg.TEAM_ENEMY else -PI * 0.5
	_scan = randf() * 0.3
	_cd = randf_range(0.5, 1.5)


func shielded() -> bool:
	return alive and line_shielded(team, line)


func take_damage(amount: int, _by_player: bool) -> void:
	if not alive:
		return
	if shielded():
		Fx.hit(get_parent(), global_position, "armour")
		return
	hp = maxi(hp - amount, 0)
	if hp <= 0:
		alive = false
		spotting = false
		fallen[team * 10 + line] = int(fallen.get(team * 10 + line, 0)) + 1
		Fx.explosion(get_parent(), global_position, true)
		get_tree().call_group("shaker", "shake", 6.0)
		destroyed.emit(self)


func sight() -> float:
	return float(SPECS[kind].get("sight", SPECS[kind].get("range", 0.0)))


## How far away this defence can pick out a given tank.
func _reach(tank) -> float:
	# Towers keep searchlights: night costs them less than tank crews.
	var r: float = sight() * lerpf(1.0, 0.75, GameState.night)
	if tank.has_method("concealed") and tank.concealed():
		r *= Cfg.CAMO_DEEP if tank.submerged else Cfg.CAMO_SIGHT
	return r


func _physics_process(delta: float) -> void:
	if not alive:
		return
	_cd = maxf(_cd - delta, 0.0)
	kick = maxf(kick - delta * 4.0, 0.0)
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.3
		_target = _find_target()
		if kind == "tower":
			var was: bool = spotting
			spotting = _target != null
			if spotting and team == Cfg.TEAM_ENEMY:
				# The tower radios what it sees to every crew in earshot.
				get_tree().call_group("enemy_ai", "hear", _target.global_position)
			if spotting and not was:
				var view = get_tree().get_first_node_in_group("world_view")
				if view != null:
					Sfx.at(view, "tower_alert", view.spot(global_position), -8.0)
	if kind == "tower" or _target == null or not is_instance_valid(_target) or not _target.alive:
		return
	var to: Vector2 = _target.global_position - global_position
	aim_angle = rotate_toward(aim_angle, to.angle(), (1.2 if kind == "artillery" else 2.6) * delta)
	if _cd > 0.0 or absf(angle_difference(aim_angle, to.angle())) > 0.1:
		return
	_cd = float(SPECS[kind]["cd"])
	kick = 1.0
	if kind == "artillery":
		_lob(_target)
	else:
		_shoot()


func _find_target():
	var best = null
	var best_d := 1e9
	var space := get_world_2d().direct_space_state
	for t in get_tree().get_nodes_in_group("tanks"):
		if not t.alive or t.team == team or t.get("dummy") == true:
			continue
		var d: float = t.global_position.distance_to(global_position)
		if d > _reach(t) or d >= best_d:
			continue
		if kind == "artillery":
			if d < float(SPECS[kind]["near"]):
				continue
		else:
			# Guns and towers need a clear line; artillery fires over everything.
			var q := PhysicsRayQueryParameters2D.create(global_position, t.global_position,
				Cfg.LAYER_WALL)
			if not space.intersect_ray(q).is_empty():
				continue
		best = t
		best_d = d
	return best


func _shoot() -> void:
	var dir := Vector2.RIGHT.rotated(aim_angle)
	var from: Vector2 = global_position
	if kind == "guard":
		# Two barrels, fired in turn.
		_barrel = 1 - _barrel
		from += dir.orthogonal() * (8.0 if _barrel == 0 else -8.0)
	var shell = Shell.new()
	shell.setup(self, from, dir)
	shell.heavy = kind == "turret"
	get_parent().add_child(shell)
	get_tree().call_group("world_view", "add_shell", shell)
	Fx.muzzle(get_parent(), from + dir * 52.0, dir, kind == "turret")


func _lob(target) -> void:
	var shot = Barrage.new()
	shot.team = team
	shot.damage = shell_damage
	shot.origin = global_position
	# Aimed a little ahead of a moving tank, and never dead on.
	var lead: Vector2 = target.velocity * shot.FLIGHT * 0.6
	shot.position = target.global_position + lead \
		+ Vector2.RIGHT.rotated(randf() * TAU) * randf_range(0.0, 40.0)
	get_parent().add_child(shot)
	get_tree().call_group("world_view", "add_barrage", shot)
	Fx.muzzle(get_parent(), global_position + Vector2.RIGHT.rotated(aim_angle) * 56.0,
		Vector2.RIGHT.rotated(aim_angle), true)
