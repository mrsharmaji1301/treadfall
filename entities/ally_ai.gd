extends "res://entities/enemy_ai.gd"
## Computer ally brain (Base Defense co-op). It guards a post near the base,
## drives out to meet the nearest attacker, and fires only with a clear line.
## It never shoots through the base's own walls.

## Where it waits when no enemy is about.
var post := Vector2i.ZERO
## Which attacker it prefers, so allies spread over several enemies.
var slot: int = 0


func _ready() -> void:
	tank = get_parent()
	_repath = randf_range(0.0, 0.4)
	_last_pos = tank.position


func hear(_from: Vector2) -> void:
	pass


func _physics_process(delta: float) -> void:
	if not tank.alive:
		return
	var pos: Vector2 = tank.global_position
	var my_cell: Vector2i = arena.world_to_cell(pos)
	var home: Vector2 = core.global_position if is_instance_valid(core) else pos

	# Every attacker on the map, nearest to the base first (the allies are
	# on the radio net, so they know where the enemy is).
	var foes: Array = []
	for t in tank.get_tree().get_nodes_in_group("tanks"):
		if t.alive and t.team != tank.team and not t.dummy:
			foes.append(t)
	foes.sort_custom(func(a, b) -> bool:
		return a.global_position.distance_squared_to(home) < b.global_position.distance_squared_to(home))

	# Shoot the nearest one it can actually see.
	var sight: float = Cfg.ENEMY_SIGHT * Cfg.sight_now()
	var prey = null
	var prey_d := INF
	for t in foes:
		var d: float = pos.distance_to(t.global_position)
		if d < sight and d < prey_d and _clear_line(pos, t.global_position):
			prey = t
			prey_d = d

	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.5
		var goal: Vector2i = post
		if not foes.is_empty():
			goal = arena.world_to_cell(foes[slot % foes.size()].global_position)
		# A power-up close by is worth a detour when nobody is in its sights.
		if prey == null:
			for item in tank.get_tree().get_nodes_in_group("pickups"):
				if not item.cache and item.useful_to(item.kind, tank) \
						and pos.distance_to(item.global_position) < 330.0:
					goal = arena.world_to_cell(item.global_position)
					break
		_path = pathfinder.path(my_cell, goal)

	var move := Vector2.ZERO
	var hold: bool = prey != null and prey_d < 230.0
	var next_cell: Vector2i = _next_cell(my_cell)
	if next_cell != my_cell and not hold and arena.tile_at(next_cell) == arena.EMPTY:
		move = _steer(pos, my_cell, next_cell)
	move = _unstick(delta, pos, move)
	tank.move_dir = move

	if prey != null:
		_watch += delta
		tank.aim_angle = (prey.global_position - pos).angle() + _aim_error
		if _watch >= 0.35 and absf(angle_difference(tank.turret_angle, tank.aim_angle)) < 0.12:
			if tank.try_fire():
				_aim_error = randf_range(-0.07, 0.07)
			# Missiles or mines it has picked up go out as well.
			if tank.special != "heavy":
				tank.try_special()
	else:
		_watch = 0.0
		if move != Vector2.ZERO:
			tank.aim_angle = move.angle()
