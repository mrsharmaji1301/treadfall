extends Node
## Reads input and drives the parent tank. Aim follows the mouse, or the
## right stick / IJKL keys once those are used.

var tank
var _use_mouse := true


func _ready() -> void:
	tank = get_parent()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_use_mouse = true


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(tank) or not tank.alive:
		return
	tank.move_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var stick: Vector2 = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick.length() > 0.35:
		_use_mouse = false
		tank.aim_angle = stick.angle()
	elif _use_mouse:
		var view = get_tree().get_first_node_in_group("world_view")
		if view == null:
			return
		var mouse: Vector2 = view.mouse_ground()
		var here: Vector2 = tank.global_position
		if mouse.distance_to(here) > 6.0:
			tank.aim_angle = (mouse - here).angle()
	# Workshop open between waves: the mouse is busy buying.
	if Cfg.shop_open:
		return
	if Input.is_action_pressed("fire"):
		tank.try_fire()
	if Input.is_action_pressed("fire_alt"):
		tank.try_special()
	for i in tank.ITEMS.size():
		if Input.is_action_just_pressed("item_%d" % (i + 1)):
			tank.use_item(tank.ITEMS[i])
