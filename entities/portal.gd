extends Node2D
## A portal gate. Its pair stands across the map. While it is night
## (GameState.is_night) any tank that drives into it comes out of the other
## one; by day it is shut. Its 3D look is view/portal_view.gd.

signal used(tank, from: Vector2, to: Vector2)

const RADIUS := 26.0

var partner
## Which way a tank leaves the far gate: towards the middle of the map.
var exit_dir := Vector2.RIGHT


func _ready() -> void:
	add_to_group("portals")


func is_open() -> bool:
	return GameState.is_night


func _physics_process(_delta: float) -> void:
	if not is_open() or partner == null or not is_instance_valid(partner):
		return
	var now: int = Time.get_ticks_msec()
	for t in get_tree().get_nodes_in_group("tanks"):
		if not t.alive or t.global_position.distance_to(global_position) > RADIUS:
			continue
		if int(t.get_meta("portal_ready", 0)) > now:
			continue
		var to: Vector2 = partner.global_position + partner.exit_dir * 40.0
		var from: Vector2 = t.global_position
		t.set_meta("portal_ready", now + int(Cfg.PORTAL_REST * 1000.0))
		t.global_position = to
		t.hull_angle = partner.exit_dir.angle()
		used.emit(t, from, to)
