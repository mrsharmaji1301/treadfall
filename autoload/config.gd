extends Node
## Tunable constants and input setup. Autoloaded as "Cfg".

const CELL := 48
## Map size in cells. Set by the arena when it builds a layout.
var cols: int = 25
var rows: int = 14
## Tanks wading through water move at this fraction of their speed.
const WATER_SLOW := 0.62
## Tanks crawling along the bed of the deep channel, hull under water.
const DEEP_SLOW := 0.4
const ROAD_FAST := 1.12
## Tanks climbing a dune move at this fraction of their speed.
const DUNE_SLOW := 0.68

const TEAM_PLAYER := 0
const TEAM_ENEMY := 1

const LAYER_WALL := 1
const LAYER_TANK := 2
const LAYER_CORE := 4
## Deep water. Tanks can drive through it submerged; bots plan round it.
const LAYER_DEEP := 8
## A player tank sitting in water is harder to spot: enemy sight shrinks to
## this share. Firing gives the tank away for CAMO_BREAK seconds.
const CAMO_SIGHT := 0.35
## The same for a tank fully under water in the deep channel.
const CAMO_DEEP := 0.2
const CAMO_BREAK := 3.0

## Tank paint tint over the camouflage texture. White keeps it as painted.
const PAINT_PLAYER := Color(1.0, 1.0, 1.0)

## UI colours.
const COL_UI := Color(0.9, 0.85, 0.72)
const COL_ACCENT := Color(0.78, 0.66, 0.4)
const COL_GOOD := Color(0.45, 0.7, 0.3)
const COL_WARN := Color(0.85, 0.3, 0.22)
const COL_PANEL := Color(0.09, 0.095, 0.085, 0.93)

const QUALITY_NAMES := ["LOW", "MEDIUM", "HIGH", "ULTRA", "CUSTOM"]
## Graphics preset. 0..3 fill in every option of `gfx` below; 4 means the
## player changed single options by hand. HIGH suits a GTX 1660 class card.
var quality: int = 2
## The single graphics options. scale: 3D resolution in percent of the
## screen. shadows: 0 off .. 4 ultra. aa: 0 off, 1 FXAA, 2 MSAA 2x, 3 MSAA 4x.
## foliage: 0 sparse, 1 medium, 2 full (used when a map is built).
const PRESETS := [
	{"scale": 60, "shadows": 1, "ssao": false, "glow": false, "fog": false, "gi": false, "aa": 0, "foliage": 0},
	{"scale": 80, "shadows": 2, "ssao": true, "glow": true, "fog": false, "gi": false, "aa": 1, "foliage": 1},
	{"scale": 100, "shadows": 3, "ssao": true, "glow": true, "fog": true, "gi": false, "aa": 2, "foliage": 2},
	{"scale": 100, "shadows": 4, "ssao": true, "glow": true, "fog": true, "gi": true, "aa": 3, "foliage": 2},
]
const SHADOW_NAMES := ["OFF", "LOW", "MEDIUM", "HIGH", "ULTRA"]
const AA_NAMES := ["OFF", "FXAA", "MSAA 2X", "MSAA 4X"]
const FOLIAGE_NAMES := ["SPARSE", "MEDIUM", "FULL"]
const FPS_CAPS := [0, 30, 60, 90, 120, 144]
var gfx: Dictionary = PRESETS[2].duplicate()
var vsync := true
## Frames per second limit; 0 is no limit.
var fps_cap: int = 0
var show_fps := false
## True once the game has picked a graphics level for this computer.
var gfx_auto_done := false
## True while the first battle still measures the frame rate, to step the
## level down once more if the first pick was too hopeful.
var gfx_probe := false
## What the first-start check found, for the settings page.
var gfx_found := ""

## Where the power-up bar sits on screen (its top left corner, in the
## 1280 x 720 layout). The player drags it while the game is paused.
const BAR_HOME := Vector2(346, 632)
var bar_pos := BAR_HOME
## True while the pause screen is up: the power-up bar can be dragged.
var hud_edit := false

## THE SHIFT: the battlefield turns from day to night and back. Seconds
## of full day, of full night, of the change between them, and how long
## before a change the warning shows. At night sight shrinks to NIGHT_SIGHT
## of the day's, a tank sees round itself only NIGHT_VISION far (pixels),
## and the portals open.
const DAY_TIME := 110.0
const NIGHT_TIME := 70.0
const TWILIGHT := 6.0
const SHIFT_WARN := 10.0
const NIGHT_SIGHT := 0.55
const NIGHT_VISION := 300.0
## Seconds a tank must wait before a portal takes it again.
const PORTAL_REST := 3.0


## How far eyes reach now, as a share of the daytime distance.
func sight_now() -> float:
	return lerpf(1.0, NIGHT_SIGHT, GameState.night)


## Seconds between waves, with the workshop open to spend gold.
const SHOP_TIME := 10.0
## True while the workshop is up: the mouse is a pointer and the guns rest.
var shop_open := false
## What gold buys between waves. cost: first price. grow: how much dearer
## each further level is (share of the first price). max: levels, 0 = no end.
const UPGRADES := {
	"hull": {"name": "HULL ARMOUR", "icon": "armour", "cost": 120, "grow": 0.5, "max": 6,
		"says": "+1 hull and a full repair"},
	"fire": {"name": "FIRE RATE", "icon": "rapid", "cost": 150, "grow": 0.5, "max": 5,
		"says": "Quick gun fires 8% faster"},
	"heavy": {"name": "HEAVY LOADER", "icon": "heavy", "cost": 150, "grow": 0.5, "max": 4,
		"says": "Heavy shot loads 12% faster"},
	"engine": {"name": "ENGINE", "icon": "boost", "cost": 120, "grow": 0.5, "max": 4,
		"says": "Tank drives 6% faster"},
	"shield": {"name": "SHIELD", "icon": "shield", "cost": 80, "grow": 0.0, "max": 0,
		"says": "One shield in the bar (key 5)"},
	"base_fix": {"name": "BASE REPAIR", "icon": "repair", "cost": 100, "grow": 0.0, "max": 0,
		"says": "Base gets 5 strength back"},
	"base_up": {"name": "BASE PROTECTION", "icon": "command", "cost": 200, "grow": 0.5, "max": 5,
		"says": "Base strength +4 for good"},
	"life": {"name": "SPARE TANK", "icon": "heart", "cost": 300, "grow": 0.25, "max": 0,
		"says": "One more life"},
}

## Base Defense: true = waves never end (Survival), false = five waves.
var endless := true

## The tank designs, built in code (view/tank_designs.gd), each in the
## manner of one country's modern tank. The names are our own codenames;
## no real tank names are used, so nothing needs a licence when the game
## is sold. hull: hit
## points more or less than the difficulty gives. speed, turret, reach:
## multipliers. fire and heavy: multipliers on the time between shots, so
## smaller is quicker.
const TANKS := [
	{"name": "NOMAD", "style": "All-round desert tank", "hull": 0, "speed": 1.0,
		"fire": 1.0, "heavy": 1.0, "turret": 1.0, "reach": 1.0},
	{"name": "TITAN", "style": "United States: slab armour, steady gun", "hull": 2, "speed": 0.9,
		"fire": 1.0, "heavy": 1.0, "turret": 0.9, "reach": 1.05},
	{"name": "WRAITH", "style": "Russia: low, fast, autoloader", "hull": -1, "speed": 1.12,
		"fire": 0.95, "heavy": 0.82, "turret": 1.0, "reach": 0.95},
	{"name": "PANZER", "style": "Germany: very long gun, long reach", "hull": 1, "speed": 1.0,
		"fire": 1.08, "heavy": 0.95, "turret": 1.0, "reach": 1.2},
	{"name": "BULWARK", "style": "Israel: engine in front, toughest hull", "hull": 3, "speed": 0.82,
		"fire": 1.1, "heavy": 1.05, "turret": 0.85, "reach": 1.0},
	{"name": "WARHAMMER", "style": "India: thick turret, heavy hitter", "hull": 2, "speed": 0.88,
		"fire": 1.05, "heavy": 0.88, "turret": 0.95, "reach": 1.08},
	{"name": "PHANTOM", "style": "South Korea: quick loader, quick turret", "hull": 0, "speed": 1.06,
		"fire": 0.86, "heavy": 0.9, "turret": 1.3, "reach": 1.0},
	{"name": "SOVEREIGN", "style": "United Kingdom: heaviest armour, far-reaching gun", "hull": 3, "speed": 0.84,
		"fire": 1.05, "heavy": 0.95, "turret": 0.9, "reach": 1.18},
	{"name": "RONIN", "style": "Japan: small, light and very quick", "hull": -1, "speed": 1.15,
		"fire": 0.9, "heavy": 0.9, "turret": 1.25, "reach": 0.95},
	{"name": "DEADSHOT", "style": "France: fires fast on the move", "hull": 0, "speed": 1.14,
		"fire": 0.84, "heavy": 0.92, "turret": 1.15, "reach": 1.0},
	{"name": "ABYSS", "style": "China: strong engine, long strike", "hull": 1, "speed": 1.04,
		"fire": 1.0, "heavy": 0.9, "turret": 1.0, "reach": 1.12},
	{"name": "SCIMITAR", "style": "Turkey: big, well armoured all-rounder", "hull": 2, "speed": 0.94,
		"fire": 0.98, "heavy": 0.96, "turret": 1.0, "reach": 1.08},
	{"name": "GLADIATOR", "style": "Italy: light on its tracks, nimble", "hull": 0, "speed": 1.08,
		"fire": 0.96, "heavy": 1.0, "turret": 1.1, "reach": 1.0},
	{"name": "REVENANT", "style": "Ukraine: tile armour, quick loader", "hull": 1, "speed": 1.05,
		"fire": 0.98, "heavy": 0.85, "turret": 1.0, "reach": 0.98},
	{"name": "VIPER", "style": "Pakistan: compact, built for the heat", "hull": 0, "speed": 1.08,
		"fire": 0.95, "heavy": 0.86, "turret": 1.05, "reach": 1.0},
	{"name": "SPECTRE", "style": "Poland: light, cheap and lively", "hull": -1, "speed": 1.1,
		"fire": 0.92, "heavy": 0.9, "turret": 1.05, "reach": 0.92},
]
## Paint colours the player can choose. They shade the chosen pattern.
const TINTS := [["FACTORY", Color(1, 1, 1)], ["SAND", Color(1.0, 0.9, 0.7)],
	["OLIVE", Color(0.68, 0.8, 0.5)], ["STEEL", Color(0.72, 0.8, 0.92)],
	["RUST", Color(1.0, 0.62, 0.48)], ["GOLD", Color(1.0, 0.84, 0.42)],
	["BLUE", Color(0.5, 0.68, 1.0)], ["NIGHT", Color(0.42, 0.42, 0.48)]]
const SKIN_NAMES := ["DESERT CAMO", "GREY", "OLIVE", "RED", "TAN", "FIELD CAMO"]
const WEAR_NAMES := ["CLEAN", "MUDDY", "RUSTY"]
## The player's own tank, chosen on the Customize page.
var my_tank: int = 0
var my_skin: int = 0
var my_wear: int = 0
var my_tint: int = 0


## Dresses and tunes a tank as the player's chosen design. `hull` is the
## hit points before the design's own bonus.
func fit_player(t, hull: int) -> void:
	var d: Dictionary = TANKS[my_tank]
	t.model = my_tank
	t.skin = SKINS[my_skin]
	t.wear = WEARS[my_wear]
	t.color = TINTS[my_tint][1]
	t.max_hp = maxi(hull + int(d["hull"]), 1)
	t.hp = t.max_hp
	t.speed *= float(d["speed"])
	t.fire_cooldown *= float(d["fire"])
	t.special_cd_mul *= float(d["heavy"])
	t.turret_turn_speed *= float(d["turret"])
	t.shell_range *= float(d["reach"])


## Paint jobs for enemy tanks: every base paint with every kind of dirt.
const SKINS := ["camo_desert", "paint_grey", "paint_olive", "paint_red", "paint_tan", "camo"]
const WEARS := ["", "mud", "rust"]
var _skin_bag: Array = []


## The next enemy paint job: [skin, wear, tint]. Works through every
## combination before any repeats, so tanks on the map differ.
func next_skin() -> Array:
	if _skin_bag.is_empty():
		for s in SKINS:
			for w in WEARS:
				_skin_bag.append([s, w])
		_skin_bag.shuffle()
	var pick: Array = _skin_bag.pop_back()
	var shade: float = randf_range(0.82, 1.0)
	var tint := Color(shade, shade * randf_range(0.94, 1.0), shade * randf_range(0.88, 1.0))
	return [pick[0], pick[1], tint]


## The enemy tanks of wave `n` (1 is the first). Waves after the written
## ones are worked out, bigger and heavier each time, and never end.
func wave_list(n: int) -> Array:
	if n <= WAVES.size():
		return WAVES[n - 1].duplicate()
	var extra: int = n - WAVES.size()
	var size: int = mini(10 + extra * 2, 28)
	var heavy: int = mini(2 + extra / 2, 6)
	var out: Array = []
	for i in size:
		var r: int = (i * 7 + n * 3) % 10
		out.append("bruiser" if r < heavy else ("gunner" if r < heavy + 4 else "scout"))
	return out


## How much tougher enemy hulls are in wave `n` of an endless battle.
func wave_hull(n: int) -> float:
	return 1.0 + 0.12 * maxi(n - WAVES.size(), 0)


## Fills every graphics option from a preset 0..3.
func set_preset(level: int) -> void:
	quality = clampi(level, 0, 3)
	gfx = PRESETS[quality].duplicate()


## Looks at this computer and returns the graphics preset that suits it.
## Laptop chips built into the processor get LOW; real graphics cards get
## MEDIUM to ULTRA by how strong the model is; little memory or few
## processor cores hold the level down.
func detect_quality() -> int:
	var kind: int = RenderingServer.get_video_adapter_type()
	var card: String = RenderingServer.get_video_adapter_name()
	var low: String = card.to_lower()
	var cores: int = OS.get_processor_count()
	var ram: float = float(OS.get_memory_info().get("physical", 0)) / 1073741824.0
	var level: int = 1
	var built_in: bool = kind == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU
	for word in ["uhd", "hd graphics", "iris", "radeon(tm) graphics", "radeon graphics", "vega", "adreno", "mali"]:
		if low.contains(word):
			built_in = true
	var software: bool = kind == RenderingDevice.DEVICE_TYPE_CPU
	for word in ["llvmpipe", "swiftshader", "basic render", "software"]:
		if low.contains(word):
			software = true
	if built_in or software or card == "":
		level = 0
	else:
		var strong := RegEx.new()
		strong.compile("rtx|rx ?(5[6-9]|6[0-9]|7[0-9]|9[0-9])\\d\\d|gtx ?(16[56]0|10[678]0|9[78]0)|arc.*[ab][57]\\d\\d|titan")
		var top := RegEx.new()
		top.compile("rtx ?[3-9]0[6-9]0|rx ?(6[89]|7[7-9]|9[0-9])\\d\\d")
		if top.search(low) != null:
			level = 3
		elif strong.search(low) != null:
			level = 2
	if ram > 0.0 and ram < 3.5:
		level = 0
	elif cores <= 2 or (ram > 0.0 and ram < 7.0):
		level = mini(level, 1)
	gfx_found = "%s  |  %s  |  %d cores  |  %d GB" % [card if card != "" else "unknown graphics",
		"built-in" if built_in else ("software" if software else "graphics card"), cores, roundi(ram)]
	return level


## First start on this computer: pick a graphics level by itself.
func auto_graphics() -> void:
	set_preset(detect_quality())
	gfx_auto_done = true
	gfx_probe = true
	save_settings()


## Applies the options that belong to the window and the screen; the map's
## own lights and effects follow through world_view.apply_quality().
func apply_graphics() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_cap
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = clampf(float(gfx["scale"]) / 100.0, 0.4, 1.0)
		var aa: int = int(gfx["aa"])
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][aa]
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH][int(gfx["shadows"])])
	get_tree().call_group("world_view", "apply_quality")

const DIFFICULTY_NAMES := ["EASY", "NORMAL", "HARD"]
## Chosen in the main menu.
var difficulty: int = 1
## What each difficulty changes. speed, sight: enemy multipliers.
## fire: multiplier on the enemy's time between shots. react: seconds an
## enemy needs to see a target before its first shot. active: extra enemy
## tanks allowed on the map at once. hull: player hit points. drop: chance
## that a destroyed enemy leaves a power-up.
const DIFFICULTY := [
	{"speed": 0.85, "fire": 1.35, "sight": 0.85, "react": 1.0, "active": -1, "hull": 6, "drop": 0.7},
	{"speed": 1.0, "fire": 1.0, "sight": 1.0, "react": 0.7, "active": 0, "hull": 4, "drop": 0.5},
	{"speed": 1.15, "fire": 0.8, "sight": 1.2, "react": 0.4, "active": 1, "hull": 3, "drop": 0.35},
]

const PLAYER_SPEED := 190.0
const PLAYER_LIVES := 3
## Left button: quick light rounds. Right button: the special weapon.
const PLAYER_FIRE_CD := 0.2
## Right-button weapons. "heavy" is the standing one; the others come from
## power-ups, carry limited rounds, and hand back to "heavy" when spent.
const SPECIALS := {
	"heavy": {"cd": 2.6, "ammo": -1, "damage": 3},
	"missile": {"cd": 1.3, "ammo": 4, "damage": 3},
	"mine": {"cd": 0.9, "ammo": 3, "damage": 4},
}
const MINE_DAMAGE := 4
const PLAYER_SHELL_SPEED := 560.0
## How far a shell flies before it drops and bursts, in pixels (48 = one
## map cell). The heavy shot reaches further, missiles furthest.
const PLAYER_RANGE := 480.0
const HEAVY_RANGE_MUL := 1.3
const MISSILE_RANGE := 770.0
## Enemy tank guns: a little beyond what their crews can see.
const ENEMY_RANGE := 470.0
const SPAWN_SHIELD := 2.5
## Turret traverse in radians per second. Lower is heavier.
const PLAYER_TURRET_SPEED := 6.5
const ENEMY_TURRET_SPEED := 1.4

const CORE_HP := 14
const ENEMY_SHELL_SPEED := 380.0
## Enemies only know about the player when they see the tank (in range,
## nothing in the way) or hear its gun. They remember for a few seconds.
const ENEMY_SIGHT := 430.0
const ENEMY_HEARING := 620.0
const ENEMY_MEMORY := 6.0
const SPAWN_INTERVAL := 3.5
const WAVE_BREAK := 4.0
## Enemy tanks allowed on the map at once, per wave.
const WAVE_ACTIVE := [2, 3, 3, 4, 4]

## hunts = chance that this enemy goes looking for the player, not the base.
const ENEMY_TYPES := {
	"scout": {"speed": 120.0, "hp": 2, "fire_cd": 1.9, "gold": 40, "scale": 0.85,
		"hunts": 1.0, "color": Color(1.0, 0.88, 0.7)},
	"gunner": {"speed": 85.0, "hp": 4, "fire_cd": 1.5, "gold": 60, "scale": 1.0,
		"hunts": 0.5, "color": Color(0.7, 0.68, 0.68)},
	"bruiser": {"speed": 58.0, "hp": 9, "fire_cd": 2.3, "gold": 100, "scale": 1.2,
		"hunts": 0.0, "color": Color(0.46, 0.44, 0.46)},
}

const WAVES := [
	["scout", "scout", "gunner"],
	["scout", "gunner", "scout", "gunner"],
	["gunner", "scout", "bruiser", "scout", "gunner", "scout"],
	["gunner", "scout", "bruiser", "scout", "gunner", "bruiser", "scout", "gunner"],
	["bruiser", "scout", "gunner", "scout", "bruiser", "gunner", "gunner", "scout",
		"bruiser", "scout"],
]


## --- Player settings, kept in settings.cfg beside the game ---------------
const CROSS_STYLES := ["RINGS + DOT", "RING + TICKS", "CROSS", "DOT"]
const CROSS_COLORS := [
	["RED", Color(1.0, 0.1, 0.06)], ["WHITE", Color(1, 1, 1)],
	["GREEN", Color(0.2, 1.0, 0.25)], ["YELLOW", Color(1.0, 0.9, 0.1)],
	["CYAN", Color(0.2, 0.95, 1.0)], ["ORANGE", Color(1.0, 0.55, 0.1)],
	["MAGENTA", Color(1.0, 0.25, 0.9)]]
const CROSS_MIN := 15
const CROSS_MAX := 96
const AIM_MIN := 0.3
const AIM_MAX := 3.0
var cross_style: int = 0
var cross_color: int = 0
## Width of the whole mark on screen, in pixels at 1280 x 720.
var cross_size: int = 40
## Mouse speed for aiming: 1 is the normal Windows pointer speed.
var aim_speed: float = 1.0
## Where the aiming mark is on screen. The reticle keeps it up to date.
var aim_pos := Vector2(640, 360)
const DISPLAY_NAMES := ["FULLSCREEN", "BORDERLESS", "WINDOWED"]
## 0 true fullscreen at the monitor's own resolution, 1 borderless window
## over the whole screen, 2 an ordinary window.
var display_mode: int = 0
## Master volume, 0 to 100.
var volume: int = 80


func apply_volume() -> void:
	AudioServer.set_bus_mute(0, volume <= 0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 1) / 100.0))

## Computer allies in Base Defense: 0 is solo, 1 to 4 is co-op.
var allies: int = 0
const ALLY_RESPAWN := 8.0
const ALLY_PAINT := Color(0.8, 0.9, 0.62)


## Puts the game window in the chosen display mode.
func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Browser: full screen only after a click or key, and never exclusive.
	if OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if display_mode == 2
			else DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	var want: int = [DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN, DisplayServer.WINDOW_MODE_FULLSCREEN,
		DisplayServer.WINDOW_MODE_WINDOWED][display_mode]
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)
	if display_mode == 2:
		# A window of sensible size in the middle of the screen.
		var screen: Vector2i = DisplayServer.screen_get_size()
		var size := Vector2i(1280, 720)
		if screen.x >= 2200:
			size = Vector2i(1920, 1080)
		elif screen.x >= 1800:
			size = Vector2i(1600, 900)
		DisplayServer.window_set_size(size)
		DisplayServer.window_set_position(DisplayServer.screen_get_position() + (screen - size) / 2)


## The settings file sits in the game's own folder, never in the Windows
## user profile: the project folder when run from the editor, the folder
## of the .exe once exported.
func settings_path() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://settings.cfg")
	# In a browser there is no game folder: the browser keeps the file.
	if OS.has_feature("web"):
		return "user://settings.cfg"
	return OS.get_executable_path().get_base_dir().path_join("settings.cfg")


func load_settings() -> void:
	var f := ConfigFile.new()
	if f.load(settings_path()) != OK:
		return
	cross_style = clampi(int(f.get_value("crosshair", "style", cross_style)), 0, CROSS_STYLES.size() - 1)
	cross_color = clampi(int(f.get_value("crosshair", "color", cross_color)), 0, CROSS_COLORS.size() - 1)
	cross_size = clampi(int(f.get_value("crosshair", "size", cross_size)), CROSS_MIN, CROSS_MAX)
	aim_speed = clampf(float(f.get_value("aim", "sensitivity", aim_speed)), AIM_MIN, AIM_MAX)
	quality = clampi(int(f.get_value("game", "graphics", quality)), 0, 4)
	gfx = PRESETS[mini(quality, 3)].duplicate()
	gfx_auto_done = bool(f.get_value("graphics", "auto_done", false))
	gfx_probe = bool(f.get_value("graphics", "probe", false))
	gfx_found = str(f.get_value("graphics", "found", ""))
	if quality == 4:
		gfx["scale"] = clampi(int(f.get_value("graphics", "scale", 100)), 50, 100)
		gfx["shadows"] = clampi(int(f.get_value("graphics", "shadows", 3)), 0, 4)
		gfx["aa"] = clampi(int(f.get_value("graphics", "aa", 2)), 0, 3)
		gfx["foliage"] = clampi(int(f.get_value("graphics", "foliage", 2)), 0, 2)
		for key in ["ssao", "glow", "fog", "gi"]:
			gfx[key] = bool(f.get_value("graphics", key, gfx[key]))
	vsync = bool(f.get_value("graphics", "vsync", vsync))
	fps_cap = int(f.get_value("graphics", "fps_cap", fps_cap))
	if not FPS_CAPS.has(fps_cap):
		fps_cap = 0
	show_fps = bool(f.get_value("graphics", "show_fps", show_fps))
	endless = bool(f.get_value("game", "endless", endless))
	my_tank = clampi(int(f.get_value("tank", "model", 0)), 0, TANKS.size() - 1)
	my_skin = clampi(int(f.get_value("tank", "skin", 0)), 0, SKINS.size() - 1)
	my_wear = clampi(int(f.get_value("tank", "wear", 0)), 0, WEARS.size() - 1)
	my_tint = clampi(int(f.get_value("tank", "tint", 0)), 0, TINTS.size() - 1)
	var at: Vector2 = f.get_value("hud", "bar_pos", bar_pos)
	bar_pos = Vector2(clampf(at.x, 0.0, 1280.0 - 588.0), clampf(at.y, 30.0, 720.0 - 80.0))
	difficulty = clampi(int(f.get_value("game", "difficulty", difficulty)), 0, 2)
	display_mode = clampi(int(f.get_value("game", "display", display_mode)), 0, 2)
	allies = clampi(int(f.get_value("game", "allies", allies)), 0, 4)
	volume = clampi(int(f.get_value("game", "volume", volume)), 0, 100)


func save_settings() -> void:
	var f := ConfigFile.new()
	f.set_value("crosshair", "style", cross_style)
	f.set_value("crosshair", "color", cross_color)
	f.set_value("crosshair", "size", cross_size)
	f.set_value("aim", "sensitivity", aim_speed)
	f.set_value("game", "graphics", quality)
	f.set_value("game", "endless", endless)
	f.set_value("tank", "model", my_tank)
	f.set_value("tank", "skin", my_skin)
	f.set_value("tank", "wear", my_wear)
	f.set_value("tank", "tint", my_tint)
	for key in gfx:
		f.set_value("graphics", key, gfx[key])
	f.set_value("graphics", "vsync", vsync)
	f.set_value("graphics", "fps_cap", fps_cap)
	f.set_value("graphics", "show_fps", show_fps)
	f.set_value("graphics", "auto_done", gfx_auto_done)
	f.set_value("graphics", "probe", gfx_probe)
	f.set_value("graphics", "found", gfx_found)
	f.set_value("hud", "bar_pos", bar_pos)
	f.set_value("game", "difficulty", difficulty)
	f.set_value("game", "display", display_mode)
	f.set_value("game", "allies", allies)
	f.set_value("game", "volume", volume)
	f.save(settings_path())


func diff() -> Dictionary:
	return DIFFICULTY[difficulty]


func player_hull() -> int:
	return int(diff()["hull"])


func _ready() -> void:
	load_settings()
	# Many guns and engines at once must not overdrive the output: a limiter
	# on the master bus holds the loudest moments just under full level.
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -1.0
	limiter.pre_gain_db = -3.0
	AudioServer.add_bus_effect(0, limiter)
	apply_volume()
	# First start on this computer: choose the graphics level by itself.
	if not gfx_auto_done and not OS.get_cmdline_user_args().has("noauto"):
		auto_graphics()
	apply_graphics.call_deferred()
	# Browser: the game starts inside the page; F11 or Settings go full screen.
	if OS.has_feature("web"):
		display_mode = 2
	elif not has_meta("aim_test") and not OS.get_cmdline_user_args().has("windowed"):
		apply_display()
	_keys("move_up", [KEY_W, KEY_UP])
	_keys("move_down", [KEY_S, KEY_DOWN])
	_keys("move_left", [KEY_A, KEY_LEFT])
	_keys("move_right", [KEY_D, KEY_RIGHT])
	_keys("aim_up", [KEY_I])
	_keys("aim_down", [KEY_K])
	_keys("aim_left", [KEY_J])
	_keys("aim_right", [KEY_L])
	_keys("fire", [KEY_SPACE])
	_keys("fire_alt", [KEY_E, KEY_SHIFT])
	_keys("pause", [KEY_ESCAPE])
	_keys("camera", [KEY_C])
	# Stored power-ups: 1 repair, 2 speed, 3 rapid fire, 4 double damage, 5 shield.
	for i in 5:
		_keys("item_%d" % (i + 1), [KEY_1 + i, KEY_KP_1 + i])

	_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)
	_axis("aim_left", JOY_AXIS_RIGHT_X, -1.0)
	_axis("aim_right", JOY_AXIS_RIGHT_X, 1.0)
	_axis("aim_up", JOY_AXIS_RIGHT_Y, -1.0)
	_axis("aim_down", JOY_AXIS_RIGHT_Y, 1.0)
	_axis("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_axis("fire_alt", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_pad("fire_alt", JOY_BUTTON_LEFT_SHOULDER)

	_pad("move_up", JOY_BUTTON_DPAD_UP)
	_pad("move_down", JOY_BUTTON_DPAD_DOWN)
	_pad("move_left", JOY_BUTTON_DPAD_LEFT)
	_pad("move_right", JOY_BUTTON_DPAD_RIGHT)
	_pad("fire", JOY_BUTTON_RIGHT_SHOULDER)
	_pad("fire", JOY_BUTTON_A)
	_pad("pause", JOY_BUTTON_START)

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	_add("fire", click)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	_add("fire_alt", right)


func _add(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.3)
	InputMap.action_add_event(action, event)


func _keys(action: String, keys: Array) -> void:
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		_add(action, ev)


func _axis(action: String, axis: int, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	_add(action, ev)


func _pad(action: String, button: int) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	_add(action, ev)
