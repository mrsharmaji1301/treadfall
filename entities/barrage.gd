extends Node2D
## One artillery shell in the air. It is aimed at a spot on the ground, not
## at a tank: a marker shows where it will land, and it lands FLIGHT seconds
## later, so a tank that keeps moving can get clear. Its 3D side is
## view/barrage_view.gd.

const Fx := preload("res://fx/fx.gd")

const FLIGHT := 2.4
const BLAST := 86.0

var team: int = 0
var damage: int = 3
var origin := Vector2.ZERO
var time := 0.0


func _physics_process(delta: float) -> void:
	time += delta
	if time < FLIGHT:
		return
	Fx.explosion(get_parent(), global_position, true)
	get_tree().call_group("shaker", "shake", 7.0)
	for t in get_tree().get_nodes_in_group("tanks"):
		if not t.alive or t.team == team:
			continue
		var d: float = t.global_position.distance_to(global_position)
		if d < BLAST:
			# Full damage near the middle, less at the edge.
			t.take_damage(damage if d < BLAST * 0.55 else maxi(damage - 2, 1), false)
	queue_free()
