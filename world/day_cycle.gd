extends Node
## THE SHIFT: day turns to night and back, over and over. This node keeps
## the clock and writes the result into GameState (night, is_night,
## phase_left, day_no). Everything else only reads GameState, so on a
## network game only the host runs this node and the rest follow.

signal warned(to_night: bool)
signal shifted(to_night: bool)

## "day", "dusk" (getting dark), "night", "dawn" (getting light).
var phase := "day"
var _left := Cfg.DAY_TIME
var _warned := false


func _ready() -> void:
	GameState.night = 0.0
	GameState.is_night = false
	GameState.phase_left = _left


func _process(delta: float) -> void:
	_left -= delta
	if not _warned and _left <= Cfg.SHIFT_WARN and (phase == "day" or phase == "night"):
		_warned = true
		warned.emit(phase == "day")
	if _left <= 0.0:
		match phase:
			"day":
				_go("dusk", Cfg.TWILIGHT)
			"dusk":
				_go("night", Cfg.NIGHT_TIME)
				GameState.is_night = true
				shifted.emit(true)
			"night":
				_go("dawn", Cfg.TWILIGHT)
				GameState.is_night = false
				shifted.emit(false)
			"dawn":
				_go("day", Cfg.DAY_TIME)
				GameState.day_no += 1
	match phase:
		"day":
			GameState.night = 0.0
		"night":
			GameState.night = 1.0
		"dusk":
			GameState.night = smoothstep(0.0, 1.0, 1.0 - _left / Cfg.TWILIGHT)
		"dawn":
			GameState.night = smoothstep(0.0, 1.0, _left / Cfg.TWILIGHT)
	# Seconds until the next change starts; 0 while it is changing.
	GameState.phase_left = _left if phase == "day" or phase == "night" else 0.0


func _go(next: String, seconds: float) -> void:
	phase = next
	_left = seconds
	_warned = false


## Jumps straight to full night or full day (tests, and a host catching up).
func force(to_night: bool) -> void:
	_go("night" if to_night else "day", Cfg.NIGHT_TIME if to_night else Cfg.DAY_TIME)
	GameState.is_night = to_night
	GameState.night = 1.0 if to_night else 0.0
	shifted.emit(to_night)
