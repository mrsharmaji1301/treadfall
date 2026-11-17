extends Node2D
## A shell. Moves by raycast each physics frame so it cannot tunnel through
## walls. It passes through tanks and structures on its own team.

const Fx := preload("res://fx/fx.gd")

var team: int = 0
var by_player := false
var damage: int = 1
var velocity := Vector2.ZERO
var life := 2.5
## How far it flies before it drops and bursts, in pixels.
var reach := 470.0
var _flown := 0.0
## Heavy rounds blow up where they land. Homing rounds steer at enemy tanks.
var heavy := false
var homing := false
var _exclude: Array[RID] = []


func setup(shooter, pos: Vector2, dir: Vector2) -> void:
	team = shooter.team
	by_player = shooter.is_player
	damage = shooter.shell_damage
	velocity = dir * float(shooter.shell_speed)
	reach = float(shooter.shell_range)
	position = pos
	rotation = dir.angle()
	_exclude = [shooter.get_rid()]


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if homing:
		_seek(delta)
	var from: Vector2 = global_position
	var to: Vector2 = from + velocity * delta
	var space := get_world_2d().direct_space_state
	# Tanks are hit on their whole body: a box the size of the hull, turned
	# with it. Walls and the base are found by raycast. Whichever the shell
	# reaches first along this frame's path is what it hits.
	var mask: int = Cfg.LAYER_WALL | Cfg.LAYER_CORE
	var struck = null
	var struck_at := 2.0
	for t in get_tree().get_nodes_in_group("tanks"):
		if not t.alive or t.team == team:
			continue
		var f: float = _box_entry(t, from, to)
		if f < struck_at:
			struck_at = f
			struck = t
	if struck != null:
		var stop: Vector2 = from.lerp(to, struck_at)
		var wall := PhysicsRayQueryParameters2D.create(from, stop, Cfg.LAYER_WALL, _exclude)
		if from.is_equal_approx(stop) or space.intersect_ray(wall).is_empty():
			struck.take_damage(damage, by_player)
			Fx.hit(get_parent(), stop, "armour")
			if heavy:
				Fx.explosion(get_parent(), stop, false, 0.5)
			queue_free()
			return
	for i in 4:
		var query := PhysicsRayQueryParameters2D.create(from, to, mask, _exclude)
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			break
		var target = hit["collider"]
		var point: Vector2 = hit["position"]
		var normal: Vector2 = hit["normal"]
		var what := "sand"
		if target.has_method("take_damage"):
			if target.team == team:
				_exclude.append(hit["rid"])
				continue
			target.take_damage(damage, by_player)
			what = "armour"
		elif target.has_method("damage_at"):
			target.damage_at(point - normal * 4.0, damage)
			what = "wall"
		Fx.hit(get_parent(), point, what)
		if heavy:
			Fx.explosion(get_parent(), point, false, 0.5)
		queue_free()
		return
	global_position = to
	_flown += from.distance_to(to)
	if _flown >= reach:
		# Spent: it drops short and bursts on the ground.
		Fx.hit(get_parent(), to, "sand")
		if heavy:
			Fx.explosion(get_parent(), to, false, 0.5)
		queue_free()


## Where along from..to (0..1) the shell enters a tank's body, or 2 if it
## misses. The body is the hull footprint plus the shell's own thickness.
func _box_entry(t, from: Vector2, to: Vector2) -> float:
	var grow: float = 6.0 if heavy or homing else 4.0
	var half := Vector2(25.0, 15.0) * float(t.size_scale) + Vector2(grow, grow)
	var a: Vector2 = (from - t.global_position).rotated(-t.hull_angle)
	var d: Vector2 = (to - t.global_position).rotated(-t.hull_angle) - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		if absf(d[axis]) < 0.0001:
			if absf(a[axis]) > half[axis]:
				return 2.0
			continue
		var n: float = (-half[axis] - a[axis]) / d[axis]
		var m: float = (half[axis] - a[axis]) / d[axis]
		t0 = maxf(t0, minf(n, m))
		t1 = minf(t1, maxf(n, m))
		if t0 > t1:
			return 2.0
	return t0


## Turns towards the nearest enemy tank ahead, a little each frame.
func _seek(delta: float) -> void:
	var best = null
	var best_score := 1e9
	for t in get_tree().get_nodes_in_group("tanks"):
		if not t.alive or t.team == team:
			continue
		var to: Vector2 = t.global_position - global_position
		var off: float = absf(velocity.angle_to(to))
		if to.length() > 700.0 or off > 1.4:
			continue
		var score: float = to.length() * (1.0 + off)
		if score < best_score:
			best_score = score
			best = t
	if best != null:
		var want: float = (best.global_position - global_position).angle()
		velocity = Vector2.RIGHT.rotated(rotate_toward(velocity.angle(), want, 3.4 * delta)) \
			* velocity.length()
		rotation = velocity.angle()
