extends Node
## State of the current run. Autoloaded as "GameState". The HUD reads it.

var score := 0
var gold := 0
var wave := 0
var total_waves := 0
var lives := 0
var incoming := 0
var player_hp := 0
var player_max := 0
var core_hp := 0
var core_max := 0
## THE SHIFT (world/day_cycle.gd keeps these): 0 is full day, 1 full
## night, in between while it changes. is_night turns on once the dark has
## fallen and off at dawn; portals follow it. phase_left: seconds until the
## next change starts. day_no counts the days, from 1.
var night := 0.0
var is_night := false
var phase_left := 0.0
var day_no: int = 1
## The 6 HUD slots. Each is null (empty) or {"icon": name, "cd": 0..1, "count": n}.
## Slot 0 is the main cannon. Power-ups and extra weapons fill the rest later.
var slots: Array = [null, null, null, null, null, null]


func reset(waves: int) -> void:
	score = 0
	gold = 0
	wave = 0
	total_waves = waves
	lives = Cfg.PLAYER_LIVES
	incoming = 0
	player_hp = Cfg.player_hull()
	player_max = player_hp
	core_hp = Cfg.CORE_HP
	core_max = Cfg.CORE_HP
	night = 0.0
	is_night = false
	phase_left = Cfg.DAY_TIME
	day_no = 1
	slots = [{"icon": "cannon", "cd": 0.0, "count": -1}, null, null, null, null, null]


func add_kill(reward: int) -> void:
	gold += reward
	score += reward * 2
