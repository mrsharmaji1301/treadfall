extends Node
## Host side: drives a tank from the controls another player sent.

var tank
## Filled in by the game mode whenever that player's controls arrive.
var input: Dictionary = {}


func _ready() -> void:
	tank = get_parent()


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(tank) or not tank.alive:
		return
	var move: Vector2 = input.get("move", Vector2.ZERO)
	tank.move_dir = move.limit_length(1.0)
	tank.aim_angle = float(input.get("aim", tank.aim_angle))
	if Cfg.shop_open:
		return
	if input.get("fire", false):
		tank.try_fire()
	if input.get("alt", false):
		tank.try_special()
