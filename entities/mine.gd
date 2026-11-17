extends Node2D
## A mine dropped behind a tank. It arms after a moment, then goes off when
## an enemy tank drives close, hurting every enemy in the blast.

const Fx := preload("res://fx/fx.gd")

const TRIGGER := 36.0
const BLAST := 84.0

var team: int = 0
var by_player := false
var arm := 1.0
var life := 75.0


func _physics_process(delta: float) -> void:
	arm -= delta
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if arm > 0.0:
		return
	for t in get_tree().get_nodes_in_group("tanks"):
		if t.alive and t.team != team and t.global_position.distance_to(global_position) < TRIGGER:
			_explode()
			return


func _explode() -> void:
	Fx.explosion(get_parent(), global_position)
	for t in get_tree().get_nodes_in_group("tanks"):
		if t.alive and t.team != team and t.global_position.distance_to(global_position) < BLAST:
			t.take_damage(Cfg.MINE_DAMAGE, by_player)
	queue_free()
