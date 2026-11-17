extends Node
## Player side of an online battle: reads the controls and sends them to
## the host 30 times a second.

var mode
var _use_mouse := true
var _items: int = 0
var _aim := -PI * 0.5
var _flip := false


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_use_mouse = true


func _physics_process(_delta: float) -> void:
	for i in 5:
		if Input.is_action_just_pressed("item_%d" % (i + 1)):
			_items |= 1 << i
	_flip = not _flip
	if _flip:
		return
	var move: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var fire: bool = Input.is_action_pressed("fire")
	var alt: bool = Input.is_action_pressed("fire_alt")
	var tank = mode.player
	if is_instance_valid(tank) and tank.alive:
		var stick: Vector2 = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
		if stick.length() > 0.35:
			_use_mouse = false
			_aim = stick.angle()
		elif _use_mouse and is_instance_valid(mode.view):
			var mouse: Vector2 = mode.view.mouse_ground()
			var here: Vector2 = tank.global_position
			if mouse.distance_to(here) > 6.0:
				_aim = (mouse - here).angle()
	# Automatic test: controls come from the test script.
	if Cfg.has_meta("net_test_input"):
		var fake: Dictionary = Cfg.get_meta("net_test_input")
		move = fake.get("move", Vector2.ZERO)
		_aim = float(fake.get("aim", _aim))
		fire = fake.get("fire", false)
		alt = fake.get("alt", false)
	# A visible pointer means a menu is up: clicks belong to its buttons.
	if Cfg.shop_open or mode.is_over or (Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
			and not Cfg.has_meta("net_test_input")):
		fire = false
		alt = false
	var bits: int = (1 if fire else 0) | (2 if alt else 0) | (_items << 2)
	_items = 0
	Net.send_host([Net.C_INPUT, move, _aim, bits])
