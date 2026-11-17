# TREADFALL

An original desert tank battle game, made in Godot 4.7 with the Forward+ desktop renderer (soft sun shadows, ambient occlusion, haze, glow). Models are built by code from shaped parts. Ground, plants, rocks, walls, tank paint, effects, icons, HUD and menu pictures come from SharmaJi's own art in `TANK assets`, converted by `tools/import_assets.py`. Sources and licences are listed in `CREDITS.md`.

## Run it
1. Open Godot 4.7, choose **Import**, and select `project.godot` in this folder.
2. Press **F5** to play. The first start takes a minute or two while Godot imports the textures.

## Updating the art
Put new or changed pictures in `TANK assets` (same folders and names), then from this folder run `python tools/import_assets.py "..\TANK assets"`. It never changes the source folder. It removes the generator's corner mark, resizes, makes black or white backgrounds transparent, and cuts sheets of four into even strips. Needs Python with Pillow and numpy.

## In this build
Both modes play on **Oasis Crossing**, a 48x32 desert map: three lanes split by dune ridges and rock, a central oasis, smaller pools, palm groves, grass and reeds along the water. Tanks wade through water (slower, with wakes, splashes and ripples). Track ruts fade with time and wrecks burn for a while.

**Free Roam**: the map with three parked enemy tanks, for judging the look.

**Base Defense**: protect the command post at the bottom of the map through 5 waves. You have 3 lives. You lose if the base is destroyed or you run out of lives.

**Weapons**: left button is a rapid light gun. Right button is the special weapon: one heavy shot with a cooldown by default. Missile and mine power-ups replace it for a few rounds (seeking missiles, mines dropped behind the tank), then it returns to the heavy shot. Your rounds glow cyan, enemy rounds red.

**Sound**: every sound is a file in `assets/audio/` (NAME.ogg or NAME.wav). To replace or add sounds, run `python tools/import_sounds.py FOLDER` on a folder of WAV files with the same names: it mixes them to mono, levels them and makes the loops seamless. `tools/make_sounds.py` can regenerate plain synthesised stand-ins.

**Power-ups**: destroyed enemies sometimes leave a spinning coin with a circle around it. Drive into the circle to take it. Nothing pauses: repair (+2 hull), armour (+1 maximum hull), speed boost, rapid fire and heavy shells (16 seconds each) apply at once and show in the bottom bar.

**Enemies** only know where you are when they can see you or hear your gun, and they forget after a few seconds. DIFFICULTY in the main menu changes their speed, sight, reaction time and numbers, your hull, and how often power-ups drop.

**Minimap and radar** (top right): the map is always shown, with a white outline of the part you can see on screen. Every enemy inside that on-screen area is a red blip, in either camera view; zoom out to cover more. The turning sweep is only an animation. Your tank and the base are green, power-ups yellow. Each tank blip has a pointer showing its heading.

Mouse wheel zooms. C switches between the camera behind the tank and the whole map. GRAPHICS in the main menu sets the quality level.

## Controls
| Action | Keyboard / mouse | Controller |
|---|---|---|
| Move | WASD or arrow keys | Left stick / D-pad |
| Aim | Mouse (or I J K L keys) | Right stick |
| Rapid fire | Left mouse or Space | Right trigger / RB / A |
| Special weapon | Right mouse, E or Shift | Left trigger / LB |
| Camera | C | |
| Pause | Esc | Start |

## Project layout
- `autoload/` settings (`config.gd`) and run state (`game_state.gd`)
- `entities/` tank, shell, command post, player controller, enemy AI (game logic, runs on a hidden 2D grid)
- `world/` arena tiles, level layouts, pathfinding
- `modes/` game modes (Base Defense so far)
- `ui/` menu, HUD, pause and end screens
- `view/` the 3D scene: tank model with moving parts, terrain with water and dunes, palms, rocks, walls, materials
- `fx/` dust, smoke and fire particles

## Credits
Made by SharmaJi.

## Twin Banks (the big river map)

Free Roam now runs on a 128 x 84 map. A river crosses the middle: the shallows can be waded (slower), the deep channel cannot be crossed except at the fords. Three roads (a little faster to drive on) join your Command Centre in the south to the enemy's in the north. Jungle fills the ground between the roads, and loot is hidden inside it behind narrow gaps. The enemy bank is drier and rockier.

**Defence lines**, the same on both banks, from the river back to the base:
1. Watch towers on the river bank. Yours show enemies inside their circle on the minimap. The enemy's call nearby crews when they see you.
2. First line: gun turrets, slow but hard hitting.
3. Second line: artillery. A red ring shows where each shell will land about 2.4 seconds later, so keep moving.
4. Last line: two twin guns in front of the Command Centre.

The second line and everything behind it cannot be damaged (grey-blue health bar) until at least one defence of the line in front has been destroyed.

**Health bars:** your own tank dark green, friends bright green, enemies red.

**Camouflage:** your tank in shallow water is seen from only about a third of the normal distance, by tanks, towers and guns. Firing breaks it for 3 seconds. The line above the slot bar says CAMOUFLAGED or SPOTTED.

Base Defense (solo) is unchanged and still plays on the Oasis map.
