# Online play (MULTIPLAYER)

## How it works
- MULTIPLAYER in the main menu opens the lobby list. CREATE LOBBY makes a public lobby, CREATE PRIVATE one that only shows its CODE, JOIN BY CODE joins with that code.
- In a lobby the host sets difficulty, waves and public or private, and each seat: OPEN (a player can take it), CPU or CLOSED. Open seats nobody took become CPU at START BATTLE.
- The battle runs on the host's PC. The others send their controls and see what the host sends. If a player leaves, a CPU takes over that tank. If the host leaves, the lobby closes for everyone.
- Lives and gold are the team's. Each player buys their own workshop upgrades from the team gold.
- Esc online opens a menu but does not pause the battle.

## Testing on one PC
1. Double-click `START_LOBBY_SERVER.bat` (needs Node.js) and keep its window open.
2. Run the game twice (F5 in Godot, and the exported .exe or a second Godot window).
3. Both: MULTIPLAYER. The first: CREATE LOBBY. The second: JOIN in the list. Host: START BATTLE.

## Two PCs at home (same WiFi)
Run the server on one PC. On the other PC, in MULTIPLAYER (when it says NOT CONNECTED), set the address to `ws://<that PC's IP>:8765`, for example `ws://192.168.1.5:8765`. Windows Firewall will ask once to allow Node.js: allow it.

## Over the internet
The server must run somewhere public. Not set up yet.

## Files
`net/net.gd` (Net autoload: server connection, lobby), `net/replicator.gd` (host sends the battle), `net/remote_controller.gd`, `net/net_input.gd`, `modes/net_base_defense.gd` (host), `modes/net_client.gd` (other players), `ui/lobby.gd`, `server/lobby_server.js`. Test: start the server, then `godot --headless res://tools/net_smoke.tscn -- host 20` and `-- join 20` (extra cases: night, shop, over, quit, hostquit).
