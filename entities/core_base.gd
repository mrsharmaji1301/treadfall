extends StaticBody2D
## The command post the player defends. Its 3D model is view/core_view.gd.

signal destroyed

const Fx := preload("res://fx/fx.gd")
const Structure := preload("res://entities/structure.gd")

var team: int = Cfg.TEAM_PLAYER
var hp: int = Cfg.CORE_HP
var max_hp: int = Cfg.CORE_HP
var alive := true


func _ready() -> void:
	collision_layer = Cfg.LAYER_CORE
	collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(40, 40)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)
	if team == Cfg.TEAM_PLAYER:
		GameState.core_hp = hp


## The Command Centre cannot be hurt while both of its last-line guns stand.
func shielded() -> bool:
	return alive and Structure.line_shielded(team, Structure.CORE_LINE)


func take_damage(amount: int, _by_player: bool) -> void:
	if not alive:
		return
	if shielded():
		Fx.hit(get_parent(), global_position, "armour")
		return
	hp = maxi(hp - amount, 0)
	if team == Cfg.TEAM_PLAYER:
		GameState.core_hp = hp
		get_tree().call_group("shaker", "shake", 5.0)
	if hp <= 0:
		alive = false
		Fx.explosion(get_parent(), global_position, true)
		destroyed.emit()
