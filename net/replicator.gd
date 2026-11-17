extends Node
## Host side of an online battle. Watches everything the game mode adds
## (tanks, shells, mines, power-ups), tells the other players when each one
## appears and goes, and sends where they all are 20 times a second.

const Tank := preload("res://entities/tank.gd")
const Shell := preload("res://entities/shell.gd")
const Mine := preload("res://entities/mine.gd")
const Pickup := preload("res://entities/pickup.gd")

const TICK := 0.05

var mode
var _next: int = 1
var _tanks: Dictionary = {}
var _shells: Dictionary = {}
var _clock := 0.0
var _count: int = 0


func on_child(n: Node) -> void:
	var s = n.get_script()
	var kind := ""
	var p: Dictionary = {}
	if s == Tank:
		kind = "tank"
		var owner_id: int = int(n.get_meta("owner", Net.HOST if n.is_player else 0))
		p = {"team": n.team, "color": n.color, "skin": n.skin, "wear": n.wear, "model": n.model,
			"scale": n.size_scale, "hp": n.hp, "max": n.max_hp, "pos": n.position,
			"hull": n.hull_angle, "turret": n.turret_angle, "range": n.shell_range,
			"owner": owner_id, "dummy": n.dummy}
	elif s == Shell:
		kind = "shell"
		p = {"team": n.team, "heavy": n.heavy, "homing": n.homing, "pos": n.position,
			"vel": n.velocity}
	elif s == Mine:
		kind = "mine"
		p = {"team": n.team, "pos": n.position}
	elif s == Pickup:
		kind = "pickup"
		p = {"kind": n.kind, "pos": n.position, "cache": n.cache, "life": n.life}
	else:
		return
	var nid: int = _next
	_next += 1
	n.set_meta("nid", nid)
	if kind == "tank":
		_tanks[nid] = n
	elif kind == "shell":
		_shells[nid] = n
	n.tree_exiting.connect(_on_gone.bind(nid, n, kind))
	Net.send_all([Net.S_SPAWN, nid, kind, p])


func _on_gone(nid: int, n: Node, kind: String) -> void:
	_tanks.erase(nid)
	_shells.erase(nid)
	if not is_instance_valid(mode) or mode.is_queued_for_deletion() or not mode.is_inside_tree():
		return
	var dead: bool = kind == "tank" and not n.alive
	Net.send_all([Net.S_GONE, nid, dead, n.position])


func _physics_process(delta: float) -> void:
	_clock += delta
	if _clock < TICK:
		return
	_clock = 0.0
	_count += 1
	var tanks := PackedFloat32Array()
	for nid in _tanks:
		var t = _tanks[nid]
		if not is_instance_valid(t):
			continue
		var flags: int = (1 if t.in_water else 0) | (2 if t.submerged else 0) | (4 if t.alive else 0)
		tanks.append_array([nid, t.position.x, t.position.y, t.hull_angle, t.turret_angle,
			t.hp, t.max_hp, flags, t.shield_time, t.recoil])
	var shells := PackedFloat32Array()
	for nid in _shells:
		var s = _shells[nid]
		if is_instance_valid(s):
			shells.append_array([nid, s.position.x, s.position.y, s.velocity.x, s.velocity.y])
	var core_hp: int = GameState.core_hp
	var core_max: int = GameState.core_max
	var gs := [GameState.score, GameState.gold, GameState.wave, GameState.total_waves,
		GameState.lives, GameState.incoming, core_hp, core_max, mode.break_left(), Cfg.shop_open,
		GameState.day_no, "", 0.0]
	var cycle = mode.get_meta("cycle", null)
	if is_instance_valid(cycle):
		gs[11] = cycle.phase
		gs[12] = cycle._left
	# The slower details of each human's tank, every other tick.
	var extra: Dictionary = {}
	if _count % 2 == 0:
		_add_extra(extra, mode.player, mode.upgrades)
		for i in mode.humans:
			_add_extra(extra, mode.humans[i]["tank"], mode.humans[i]["upgrades"])
	Net.send_all([Net.S_STATE, tanks, shells, gs, extra])


func _add_extra(extra: Dictionary, t, upgrades: Dictionary) -> void:
	if not is_instance_valid(t) or not t.alive or not t.has_meta("nid"):
		return
	extra[int(t.get_meta("nid"))] = [t.stock, t.buffs, t.picked, t.special, t.special_ammo,
		t._cd, t.fire_cooldown, t._cd2, t.special_cd_mul, t.exposed, upgrades]
