extends Node
## Enemy brain. Follows an A* path lane by lane, shoots plating or the core
## when they are the next step, and fires at the player or core only with a
## clear line of sight. Detects being stuck and sidesteps.

var tank
var arena
var pathfinder
var core
var mode
var hunts_player := false

var _path: Array[Vector2i] = []
var _repath := 0.0
var _stuck_time := 0.0
var _last_pos := Vector2.ZERO
var _sidestep := 0.0
var _sidestep_dir := Vector2.ZERO
## Where this crew last saw or heard the player, and how long they will
## remember it. They know nothing else about where the player is.
var _known := Vector2.ZERO
var _memory := 0.0
## How long the current target has been in view, and this shot's aim error.
var _watch := 0.0
var _aim_error := 0.0


func setup(p_arena, p_pathfinder, p_core, p_mode, p_hunts: bool) -> void:
	arena = p_arena
	pathfinder = p_pathfinder
	core = p_core
	mode = p_mode
	hunts_player = p_hunts


func _ready() -> void:
	tank = get_parent()
	add_to_group("enemy_ai")
	_repath = randf_range(0.0, 0.4)
	_last_pos = tank.position


## Called when the player's gun fires somewhere on the map.
func hear(from: Vector2) -> void:
	if tank != null and tank.global_position.distance_to(from) < Cfg.ENEMY_HEARING:
		_known = from
		_memory = Cfg.ENEMY_MEMORY


func _physics_process(delta: float) -> void:
	if not tank.alive:
		return
	# The nearest tank of the player's side: the player or a computer ally.
	var player = mode.player
	var near := INF
	for t in tank.get_tree().get_nodes_in_group("tanks"):
		if t.alive and t.team != tank.team and not t.dummy:
			var d: float = tank.global_position.distance_squared_to(t.global_position)
			if d < near:
				near = d
				player = t
	var has_player: bool = is_instance_valid(player) and player.alive
	var core_ok: bool = is_instance_valid(core) and core.alive
	if not has_player and not core_ok:
		tank.move_dir = Vector2.ZERO
		return
	var pos: Vector2 = tank.global_position
	var my_cell: Vector2i = arena.world_to_cell(pos)

	# Eyes: the player is seen only in range and with nothing in the way.
	# THE SHIFT: at night the crews see much less (Cfg.sight_now).
	var sight: float = Cfg.ENEMY_SIGHT * float(Cfg.diff()["sight"]) * Cfg.sight_now()
	var sees: bool = false
	if has_player:
		var to_player: Vector2 = player.global_position
		# A tank lying low in the water has to be nearly run into.
		if player.concealed():
			sight *= Cfg.CAMO_DEEP if player.submerged else Cfg.CAMO_SIGHT
		sees = pos.distance_to(to_player) < sight and _clear_line(pos, to_player)
		if sees:
			_known = to_player
			_memory = Cfg.ENEMY_MEMORY
	_memory = maxf(_memory - delta, 0.0)
	# Reached the last known spot and found nothing: give up the search.
	if _memory > 0.0 and not sees and pos.distance_to(_known) < 60.0:
		_memory = 0.0

	var chase_player: bool = _memory > 0.0 and (hunts_player or not core_ok)
	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.5
		var goal: Vector2i = arena.core_cell
		if chase_player:
			goal = arena.world_to_cell(_known)
		_path = pathfinder.path(my_cell, goal)

	# What to shoot at, and whether to hold position while doing it.
	var has_shot := false
	var shoot_pos := Vector2.ZERO
	var hold := false
	if sees:
		var p_pos: Vector2 = player.global_position
		has_shot = true
		shoot_pos = p_pos
		hold = chase_player and pos.distance_to(p_pos) < 170.0
	if not has_shot and core_ok:
		var c_pos: Vector2 = core.global_position
		var c_dist: float = pos.distance_to(c_pos)
		if c_dist < sight and _clear_line(pos, c_pos):
			has_shot = true
			shoot_pos = c_pos
			hold = c_dist < 260.0

	var move := Vector2.ZERO
	var next_cell: Vector2i = _next_cell(my_cell)
	if next_cell != my_cell:
		var blocked: bool = arena.tile_at(next_cell) == arena.PLATING
		if core_ok and next_cell == arena.core_cell:
			blocked = true
		if blocked:
			if not has_shot:
				has_shot = true
				shoot_pos = arena.cell_center(next_cell)
			var centre: Vector2 = arena.cell_center(my_cell)
			if pos.distance_to(centre) > 4.0:
				move = (centre - pos).normalized()
		elif not hold:
			move = _steer(pos, my_cell, next_cell)

	move = _unstick(delta, pos, move)
	tank.move_dir = move

	if has_shot:
		# The crew needs a moment to react, and no shot is perfectly laid.
		_watch += delta
		tank.aim_angle = (shoot_pos - pos).angle() + _aim_error
		if _watch >= float(Cfg.diff()["react"]) \
				and absf(angle_difference(tank.turret_angle, tank.aim_angle)) < 0.12:
			if tank.try_fire():
				_aim_error = randf_range(-0.09, 0.09)
	else:
		_watch = 0.0
		if move != Vector2.ZERO:
			tank.aim_angle = move.angle()


func _next_cell(my_cell: Vector2i) -> Vector2i:
	var i: int = _path.find(my_cell)
	if i == -1:
		_repath = minf(_repath, 0.1)
		return my_cell
	if i + 1 >= _path.size():
		return my_cell
	return _path[i + 1]


## Moves along the lane to the next cell, first re-centring on the lane so the
## tank does not clip wall corners.
func _steer(pos: Vector2, my_cell: Vector2i, next_cell: Vector2i) -> Vector2:
	var cur: Vector2 = arena.cell_center(my_cell)
	var nxt: Vector2 = arena.cell_center(next_cell)
	var axis: Vector2 = (nxt - cur).normalized()
	var rel: Vector2 = pos - cur
	var off: Vector2 = rel - axis * rel.dot(axis)
	if off.length() > 5.0:
		return (-off).normalized()
	return (nxt - pos).normalized()


func _unstick(delta: float, pos: Vector2, move: Vector2) -> Vector2:
	if _sidestep > 0.0:
		_sidestep -= delta
		return _sidestep_dir
	if move == Vector2.ZERO:
		_stuck_time = 0.0
		_last_pos = pos
		return move
	_stuck_time += delta
	if _stuck_time >= 1.0:
		if pos.distance_to(_last_pos) < 10.0:
			_sidestep = 0.45
			_sidestep_dir = Vector2.RIGHT.rotated(randi_range(0, 3) * PI * 0.5)
			_repath = 0.0
		_stuck_time = 0.0
		_last_pos = pos
	return move


func _clear_line(from: Vector2, to: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = tank.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to, Cfg.LAYER_WALL)
	return space.intersect_ray(query).is_empty()
