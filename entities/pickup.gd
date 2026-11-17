extends Node2D
## A power-up left behind by a destroyed tank. The player or a computer
## ally collects it by driving into its circle. Collection is instant and
## never pauses the game. For the player, repair, speed, rapid fire, double
## damage and shield go into the bar and wait for their number key; armour
## and the special weapons work at once. Allies use everything at once.

signal taken(text: String)

const Fx := preload("res://fx/fx.gd")

const Sfx := preload("res://fx/sfx.gd")

## Repair is listed twice, so it drops twice as often as the others.
const KINDS := ["repair", "repair", "armour", "boost", "rapid", "cannon", "missile", "mine", "shield"]
const COLORS := {
	"repair": Color(0.35, 0.9, 0.35), "armour": Color(0.45, 0.7, 1.0),
	"boost": Color(1.0, 0.6, 0.2), "rapid": Color(1.0, 0.9, 0.3),
	"cannon": Color(1.0, 0.35, 0.3), "missile": Color(0.9, 0.5, 1.0),
	"mine": Color(1.0, 0.25, 0.55), "shield": Color(0.3, 0.9, 1.0),
}
const NAMES := {"repair": "REPAIR KIT", "boost": "SPEED BOOST", "rapid": "RAPID FIRE",
	"cannon": "DOUBLE DAMAGE", "shield": "SHIELD"}
const RADIUS := 44.0
const LIFE := 24.0

var kind := "repair"
var life := LIFE
## Loot hidden in the jungle: waits for ever and does not show on the minimap.
var cache := false
var mode


func _ready() -> void:
	add_to_group("pickups")


func _physics_process(delta: float) -> void:
	if not cache:
		life -= delta
	if life <= 0.0:
		queue_free()
		return
	if mode == null:
		return
	for p in get_tree().get_nodes_in_group("tanks"):
		if not p.alive or p.team != Cfg.TEAM_PLAYER or p.dummy:
			continue
		if p.global_position.distance_to(global_position) >= RADIUS:
			continue
		if not p.is_player and not useful_to(kind, p):
			continue
		var words: String = apply(kind, p)
		taken.emit(words if p.is_player else "ALLY: " + words)
		if kind == "armour":
			Fx.heal(mode, p.global_position)
		Sfx.flat(mode, "loot_open" if cache and Sfx.stream("loot_open") != null else "pickup", -4.0)
		queue_free()
		return


## Would a computer ally gain anything from this one? It leaves a repair
## kit alone while its own hull is whole, so the player can have it.
static func useful_to(what: String, tank) -> bool:
	return what != "repair" or tank.hp < tank.max_hp


## Applies a power-up to a tank and returns the words to flash on screen.
static func apply(what: String, tank) -> String:
	tank.picked[what] = int(tank.picked.get(what, 0)) + 1
	if tank.is_player and tank.ITEMS.has(what):
		tank.stock[what] = mini(int(tank.stock.get(what, 0)) + 1, tank.STOCK_MAX)
		return "%s STORED  -  KEY %d" % [NAMES[what], tank.ITEMS.find(what) + 1]
	match what:
		"armour":
			tank.max_hp += 1
			tank.hp += 1
			return "EXTRA ARMOUR"
		"missile":
			tank.give_special("missile")
			return "SEEKING MISSILES"
		"mine":
			tank.give_special("mine")
			return "MINES"
	tank.apply_item(what)
	return NAMES.get(what, "")
