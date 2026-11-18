extends Node
## Online play. Autoloaded as "Net".
## One connection to the lobby server (server/lobby_server.js). The server
## lists lobbies and passes data between the players of a lobby. The battle
## itself runs on the lobby host's PC: the other players send their controls
## and get back where everything is (see net/replicator.gd, modes/net_client.gd).

signal status_changed
signal lobbies_listed(list: Array)
signal lobby_changed
signal problem(text: String)
signal game_starting
signal left_lobby(reason: String)
signal game_message(from: int, msg: Array)
signal peer_left(peer: int)
## After a battle: the lobby screen should come back.
signal back_in_lobby

const VERSION := "1"
const DEFAULT_SERVER := "wss://treadfall-lobby.onrender.com"
const HOST := 1
const ALL := 255
## Seats in a lobby, the host's included. A new lobby opens four of them.
const SLOTS := 10

enum { OFFLINE, CONNECTING, ONLINE, IN_LOBBY }

## Message kinds. Lobby ones are handled here, the rest by the game mode.
enum {
	L_HELLO = 1, L_STATE, L_START, L_BACK,
	S_SPAWN = 10, S_STATE, S_GONE, S_FX, S_TILE, S_BANNER, S_OVER, S_SHOP, S_SOUND,
	C_INPUT = 30, C_BUY, C_SKIP,
}

var status: int = OFFLINE
var server_url := DEFAULT_SERVER
var player_name := "Tanker"
var my_id: int = 0
var room: Dictionary = {}
## The lobby as the host set it up. Every player holds a copy.
var lobby: Dictionary = {}
## True from START until the battle is left.
var in_game := false
## Game messages that arrived before the battle scene was ready.
var pending: Array = []

var _ws: WebSocketPeer
var _was_open := false
var _want_private := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()


func _path() -> String:
	return Cfg.settings_path().get_base_dir().path_join("net.cfg")


func _load() -> void:
	var f := ConfigFile.new()
	if f.load(_path()) == OK:
		server_url = str(f.get_value("net", "server", DEFAULT_SERVER))
		player_name = str(f.get_value("net", "name", player_name))


func save() -> void:
	var f := ConfigFile.new()
	f.set_value("net", "server", server_url)
	f.set_value("net", "name", player_name)
	f.save(_path())


func is_host() -> bool:
	return status == IN_LOBBY and my_id == HOST


## True while a battle is being played online, on either side.
func playing() -> bool:
	return in_game and status == IN_LOBBY


## True on the PC that runs the battle for everyone.
func hosting() -> bool:
	return playing() and my_id == HOST


func my_slot() -> int:
	return slot_of(my_id)


func slot_of(peer: int) -> int:
	var slots: Array = lobby.get("slots", [])
	for i in slots.size():
		if slots[i]["kind"] == "human" and int(slots[i]["peer"]) == peer:
			return i
	return -1


func my_look() -> Array:
	return [Cfg.my_tank, Cfg.my_skin, Cfg.my_wear, Cfg.my_tint]


# --- connection ------------------------------------------------------------

func connect_server() -> void:
	close()
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	_ws.max_queued_packets = 4096
	if _ws.connect_to_url(server_url) != OK:
		_ws = null
		problem.emit("Bad server address")
		return
	_set_status(CONNECTING)


func close() -> void:
	if _ws != null:
		_ws.close()
	_ws = null
	_was_open = false
	room = {}
	lobby = {}
	my_id = 0
	in_game = false
	pending.clear()
	_set_status(OFFLINE)


func _set_status(s: int) -> void:
	if status != s:
		status = s
		status_changed.emit()


func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var state: int = _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			_control({"t": "hello", "name": player_name, "ver": VERSION})
		while _ws != null and _ws.get_available_packet_count() > 0:
			var data: PackedByteArray = _ws.get_packet()
			if _ws.was_string_packet():
				var msg = JSON.parse_string(data.get_string_from_utf8())
				if msg is Dictionary:
					_on_control(msg)
			elif data.size() > 1:
				var from: int = data[0]
				var body = bytes_to_var(data.slice(1))
				if body is Array and not body.is_empty():
					_on_message(from, body)
	elif state == WebSocketPeer.STATE_CLOSED:
		var was_in: bool = status == IN_LOBBY
		var could: bool = _was_open
		close()
		if was_in:
			left_lobby.emit("Connection to the server was lost")
		else:
			problem.emit("Connection lost" if could else "Could not reach the lobby server")


func _control(msg: Dictionary) -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))


func _on_control(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"welcome":
			_set_status(ONLINE)
			request_list()
		"lobbies":
			lobbies_listed.emit(msg.get("list", []))
		"joined":
			room = msg["room"]
			my_id = int(msg["you"])
			in_game = false
			pending.clear()
			status = IN_LOBBY
			if my_id == HOST:
				lobby = {"mode": "defense", "difficulty": Cfg.difficulty, "endless": Cfg.endless,
					"private": _want_private, "slots": []}
				lobby["slots"].append({"kind": "human", "peer": HOST, "name": player_name, "look": my_look()})
				for i in SLOTS - 1:
					lobby["slots"].append({"kind": "open" if i < 1 else ("cpu" if i < 3 else "closed"), "peer": 0, "name": "", "look": []})
				_publish()
			else:
				lobby = {}
				send_host([L_HELLO, player_name, my_look()])
			status_changed.emit()
			lobby_changed.emit()
		"peer_left":
			var peer := int(msg["peer"])
			if my_id == HOST:
				var i: int = slot_of(peer)
				if i >= 0:
					# In a battle a computer takes over the tank.
					lobby["slots"][i] = {"kind": "cpu" if in_game else "open", "peer": 0, "name": "",
						"look": [], "was_open": true}
				_publish()
			peer_left.emit(peer)
		"left":
			var why := str(msg.get("reason", ""))
			room = {}
			lobby = {}
			my_id = 0
			in_game = false
			pending.clear()
			_set_status(ONLINE)
			left_lobby.emit(why)
		"error":
			problem.emit(str(msg.get("msg", "Error")))


# --- lobby list --------------------------------------------------------------

func request_list() -> void:
	_control({"t": "list"})


func create_lobby(private: bool) -> void:
	_control({"t": "hello", "name": player_name, "ver": VERSION})
	_want_private = private
	_control({"t": "create", "name": player_name + "'s lobby", "private": private,
		"info": {"mode": "BASE DEFENSE", "map": "OASIS", "max": SLOTS}})


func join_lobby(id: int) -> void:
	_control({"t": "hello", "name": player_name, "ver": VERSION})
	_control({"t": "join", "id": id})


func join_code(code: String) -> void:
	_control({"t": "hello", "name": player_name, "ver": VERSION})
	_control({"t": "join", "code": code})


func leave_lobby() -> void:
	in_game = false
	_control({"t": "leave"})


# --- lobby set-up (host) -----------------------------------------------------

## Sends the lobby to the players in it and its summary to the list.
func _publish() -> void:
	if my_id != HOST:
		return
	var humans := 0
	var open := 0
	var seats := 0
	for s in lobby["slots"]:
		if s["kind"] == "human":
			humans += 1
		if s["kind"] == "open":
			open += 1
		if s["kind"] != "closed":
			seats += 1
	_control({"t": "info", "private": bool(lobby["private"]), "started": in_game, "open": open,
		"info": {"mode": "BASE DEFENSE", "map": "OASIS", "max": seats, "humans": humans,
			"level": Cfg.DIFFICULTY_NAMES[int(lobby["difficulty"])]}})
	send_all([L_STATE, lobby])
	lobby_changed.emit()


## Host: an empty seat goes Open -> CPU -> Closed. A seat with a player in
## it removes that player.
func cycle_slot(i: int) -> void:
	if my_id != HOST or i <= 0 or i >= SLOTS or in_game:
		return
	var s: Dictionary = lobby["slots"][i]
	if s["kind"] == "human":
		_control({"t": "kick", "peer": int(s["peer"])})
		return
	var order := ["open", "cpu", "closed"]
	s["kind"] = order[(order.find(s["kind"]) + 1) % order.size()]
	_publish()


func set_option(key: String, value) -> void:
	if my_id != HOST or in_game:
		return
	lobby[key] = value
	_publish()


func start_game() -> void:
	if my_id != HOST or in_game:
		return
	# Whoever has not taken an open seat by now is replaced by the computer.
	for s in lobby["slots"]:
		if s["kind"] == "open":
			s["kind"] = "cpu"
			s["was_open"] = true
	lobby["slots"][0]["look"] = my_look()
	in_game = true
	pending.clear()
	_publish()
	send_all([L_START])
	game_starting.emit()


## Host, after a battle: everyone returns to the lobby screen.
func back_to_lobby() -> void:
	if my_id != HOST:
		return
	in_game = false
	for s in lobby["slots"]:
		if s["kind"] == "cpu" and s.get("was_open", false):
			s["kind"] = "open"
		s.erase("was_open")
	_publish()
	send_all([L_BACK])
	back_in_lobby.emit()


# --- messages ----------------------------------------------------------------

func _send(target: int, msg: Array) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN or status != IN_LOBBY:
		return
	var data := PackedByteArray([target])
	data.append_array(var_to_bytes(msg))
	_ws.send(data)


func send_all(msg: Array) -> void:
	if my_id == HOST:
		_send(ALL, msg)


func send_to(peer: int, msg: Array) -> void:
	if my_id == HOST:
		_send(peer, msg)


func send_host(msg: Array) -> void:
	_send(HOST, msg)


func _on_message(from: int, msg: Array) -> void:
	var kind: int = int(msg[0])
	match kind:
		L_HELLO:
			if my_id != HOST or msg.size() < 3:
				return
			for s in lobby["slots"]:
				if s["kind"] == "open" and not in_game:
					s["kind"] = "human"
					s["peer"] = from
					s["name"] = str(msg[1]).substr(0, 20)
					s["look"] = msg[2] if msg[2] is Array else []
					_publish()
					return
			_control({"t": "kick", "peer": from, "reason": "Lobby is full"})
		L_STATE:
			if from == HOST and msg.size() > 1 and msg[1] is Dictionary:
				lobby = msg[1]
				lobby_changed.emit()
		L_START:
			if from == HOST and not in_game:
				in_game = true
				pending.clear()
				game_starting.emit()
		L_BACK:
			if from == HOST:
				in_game = false
				pending.clear()
				back_in_lobby.emit()
		_:
			if not in_game:
				return
			if my_id != HOST and from != HOST:
				return
			if game_message.get_connections().is_empty():
				pending.append([from, msg])
			else:
				game_message.emit(from, msg)


## The battle scene calls this once it can take messages.
func drain() -> void:
	var held: Array = pending.duplicate()
	pending.clear()
	for p in held:
		game_message.emit(p[0], p[1])


# --- hooks called by the game code -------------------------------------------

## fx/fx.gd reports every effect here; the host passes it to the others.
func fx(parent: Node, name: String, args: Array) -> void:
	# Effects the 3D view makes for itself are made on every PC anyway.
	if in_game and my_id == HOST and status == IN_LOBBY and not parent is Node3D:
		_send(ALL, [S_FX, name, args])


## ui/hud.gd reports every banner here.
func banner(text: String, color: Color) -> void:
	if in_game and my_id == HOST and status == IN_LOBBY:
		_send(ALL, [S_BANNER, text, color])
