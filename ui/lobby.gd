extends Control
## MULTIPLAYER page of the main menu: the list of open lobbies, and the
## lobby itself with its seats (a player, Open, CPU or Closed) and options.
## All the work is done by the Net autoload; this page only shows it.

signal closed

const Ui := preload("res://ui/ui_kit.gd")
const ROW := 40.0
## Height of one seat row: ten seats must fit.
const SEAT := 38.0
const SEAT_WORDS := {"open": "OPEN  (waiting for a player)", "cpu": "CPU", "closed": "CLOSED"}

## Words to show first, for example why the last lobby was left.
var note := ""
var _page: Control
var _status: Label
var _list: VBoxContainer
var _poll := 0.0
var _shown: int = -1


func _ready() -> void:
	var back := ColorRect.new()
	back.color = Color(0.035, 0.035, 0.03, 1.0)
	back.position = Vector2(150, 30)
	back.size = Vector2(980, 670)
	add_child(back)
	var edge := ReferenceRect.new()
	edge.border_color = Cfg.COL_ACCENT
	edge.border_width = 2.0
	edge.editor_only = false
	edge.position = back.position
	edge.size = back.size
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(edge)
	var head := Ui.label("MULTIPLAYER", 30, Cfg.COL_ACCENT)
	head.position = Vector2(180, 40)
	add_child(head)
	_status = Ui.label(note, 18, Cfg.COL_WARN)
	_status.position = Vector2(430, 48)
	_status.size = Vector2(680, 26)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_status)
	var done := _small("BACK", 200.0)
	done.position = Vector2(900, 642)
	done.pressed.connect(_back)
	add_child(done)

	Net.status_changed.connect(_show)
	Net.lobby_changed.connect(_show)
	Net.lobbies_listed.connect(_fill_list)
	Net.problem.connect(_say)
	Net.left_lobby.connect(_say)
	if Net.status == Net.OFFLINE:
		Net.connect_server()
	_show()


func _say(text: String) -> void:
	_status.text = text


func _back() -> void:
	if Net.status == Net.IN_LOBBY:
		Net.leave_lobby()
	Net.close()
	closed.emit()


func _process(delta: float) -> void:
	if Net.status != Net.ONLINE:
		return
	_poll -= delta
	if _poll <= 0.0:
		_poll = 2.0
		Net.request_list()


func _small(text: String, wide: float) -> Button:
	var b := Ui.button(text, Cfg.COL_UI)
	b.custom_minimum_size = Vector2(wide, ROW - 2.0)
	b.size = Vector2(wide, ROW - 2.0)
	b.add_theme_font_size_override("font_size", 17)
	return b


func _text(words: String, at: Vector2, size: int = 20, color: Color = Cfg.COL_UI) -> Label:
	var l := Ui.label(words, size, color)
	l.position = at
	_page.add_child(l)
	return l


func _field(text: String, at: Vector2, wide: float, hint: String, most: int) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = hint
	e.max_length = most
	e.position = at
	e.size = Vector2(wide, ROW - 4.0)
	e.add_theme_font_size_override("font_size", 18)
	_page.add_child(e)
	return e


func _show() -> void:
	# The lobby page redraws on every change; the others only when entered,
	# so that typing in a box is not interrupted.
	if Net.status == _shown and Net.status != Net.IN_LOBBY:
		return
	_shown = Net.status
	if is_instance_valid(_page):
		_page.queue_free()
	_page = Control.new()
	add_child(_page)
	_list = null
	match Net.status:
		Net.OFFLINE:
			_show_offline()
		Net.CONNECTING:
			_text("CONNECTING TO THE LOBBY SERVER ...", Vector2(190, 300), 24)
		Net.ONLINE:
			_show_browser()
		Net.IN_LOBBY:
			_show_lobby()


func _show_offline() -> void:
	_text("NOT CONNECTED", Vector2(190, 110), 24, Cfg.COL_WARN)
	_text("LOBBY SERVER ADDRESS", Vector2(190, 170), 18)
	var addr := _field(Net.server_url, Vector2(190, 200), 520.0, "ws://address:port", 120)
	var go := _small("CONNECT", 200.0)
	go.position = Vector2(730, 199)
	go.pressed.connect(func() -> void:
		Net.server_url = addr.text.strip_edges()
		Net.save()
		_say("")
		Net.connect_server())
	_page.add_child(go)
	go.grab_focus()


func _show_browser() -> void:
	_text("YOUR NAME", Vector2(190, 96), 18)
	var name := _field(Net.player_name, Vector2(300, 90), 240.0, "name", 20)
	name.text_changed.connect(func(t: String) -> void:
		Net.player_name = t.strip_edges() if t.strip_edges() != "" else "Tanker")
	name.focus_exited.connect(Net.save)
	var make := _small("CREATE LOBBY", 200.0)
	make.position = Vector2(190, 140)
	make.pressed.connect(func() -> void:
		Net.save()
		Net.create_lobby(false))
	_page.add_child(make)
	var hidden := _small("CREATE PRIVATE", 200.0)
	hidden.position = Vector2(400, 140)
	hidden.pressed.connect(func() -> void:
		Net.save()
		Net.create_lobby(true))
	_page.add_child(hidden)
	var code := _field("", Vector2(700, 141), 170.0, "LOBBY CODE", 8)
	var join := _small("JOIN BY CODE", 200.0)
	join.position = Vector2(880, 140)
	var enter := func() -> void:
		if code.text.strip_edges() != "":
			Net.save()
			Net.join_code(code.text.strip_edges().to_upper())
	join.pressed.connect(enter)
	code.text_submitted.connect(func(_t: String) -> void: enter.call())
	_page.add_child(join)

	_text("OPEN LOBBIES", Vector2(190, 200), 22, Cfg.COL_ACCENT)
	var x := [190.0, 500.0, 700.0, 820.0]
	var heads := ["LOBBY", "MODE", "MAP", "PLAYERS"]
	for i in 4:
		_text(heads[i], Vector2(x[i], 236), 15, Color(Cfg.COL_UI, 0.6))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(180, 262)
	scroll.size = Vector2(930, 370)
	_page.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	_poll = 0.0
	make.grab_focus()


func _fill_list(list: Array) -> void:
	if not is_instance_valid(_list):
		return
	for c in _list.get_children():
		c.queue_free()
	if list.is_empty():
		var none := Ui.label("No open lobbies right now. Create one.", 18, Color(Cfg.COL_UI, 0.7))
		none.custom_minimum_size = Vector2(900, 40)
		_list.add_child(none)
		return
	for entry in list:
		var info: Dictionary = entry.get("info", {})
		var row := Control.new()
		row.custom_minimum_size = Vector2(900, ROW)
		var words := [str(entry.get("name", "?")), str(info.get("mode", "")), str(info.get("map", "")),
			"%d / %d" % [int(info.get("humans", entry.get("players", 1))), int(info.get("max", 4))]]
		var x := [10.0, 320.0, 520.0, 640.0]
		for i in 4:
			var l := Ui.label(words[i], 18, Cfg.COL_UI)
			l.position = Vector2(x[i], 6)
			l.size = Vector2(300.0 if i == 0 else 190.0, 28)
			l.clip_text = true
			row.add_child(l)
		var b := _small("JOIN", 150.0)
		b.position = Vector2(740, 1)
		b.pressed.connect(func() -> void:
			Net.save()
			Net.join_lobby(int(entry["id"])))
		row.add_child(b)
		_list.add_child(row)


func _show_lobby() -> void:
	var lobby: Dictionary = Net.lobby
	_text(str(Net.room.get("name", "LOBBY")).to_upper(), Vector2(190, 92), 26, Cfg.COL_ACCENT)
	_text("CODE  " + str(Net.room.get("code", "")), Vector2(820, 96), 22, Color(1.0, 0.85, 0.3))
	if lobby.is_empty():
		_text("JOINING ...", Vector2(190, 300), 24)
		return
	var host: bool = Net.is_host()
	var slots: Array = lobby["slots"]

	# Options on the left.
	var rows := [
		["MODE: BASE DEFENSE", Callable()],
		["MAP: OASIS", Callable()],
		["DIFFICULTY: " + Cfg.DIFFICULTY_NAMES[int(lobby["difficulty"])],
			func() -> void: Net.set_option("difficulty", (int(lobby["difficulty"]) + 1) % 3)],
		["WAVES: ENDLESS (SURVIVAL)" if lobby["endless"] else "WAVES: 5 (SHORT BATTLE)",
			func() -> void: Net.set_option("endless", not bool(lobby["endless"]))],
		["PRIVATE (JOIN BY CODE ONLY)" if lobby["private"] else "PUBLIC (SHOWN IN THE LIST)",
			func() -> void: Net.set_option("private", not bool(lobby["private"]))],
	]
	for i in rows.size():
		var b := _small(rows[i][0], 380.0)
		b.position = Vector2(190, 150 + i * (ROW + 6))
		if host and rows[i][1].is_valid():
			b.pressed.connect(rows[i][1])
		else:
			b.disabled = true
			b.modulate = Color(0.75, 0.75, 0.75)
		_page.add_child(b)

	# Seats on the right.
	var count := 0
	for s in slots:
		if s["kind"] != "closed":
			count += 1
	_text("YOUR TEAM  (%d / %d)" % [count, slots.size()], Vector2(620, 150), 20, Cfg.COL_ACCENT)
	for i in slots.size():
		var s: Dictionary = slots[i]
		var words: String = SEAT_WORDS.get(s["kind"], "")
		var tone: Color = Color(Cfg.COL_UI, 0.75)
		if s["kind"] == "human":
			words = str(s["name"]) + ("  (HOST)" if i == 0 else "")
			tone = Cfg.COL_GOOD if int(s["peer"]) == Net.my_id else Cfg.COL_UI
		_text("%d" % (i + 1), Vector2(620, 192 + i * SEAT), 19, Color(Cfg.COL_UI, 0.5))
		_text(words, Vector2(655, 192 + i * SEAT), 19, tone)
		if host and i > 0:
			var b := _small("REMOVE" if s["kind"] == "human" else "CHANGE", 130.0)
			b.position = Vector2(960, 189 + i * SEAT)
			b.custom_minimum_size.y = SEAT - 4.0
			b.size.y = SEAT - 4.0
			b.pressed.connect(Net.cycle_slot.bind(i))
			_page.add_child(b)
	_text("Empty OPEN seats are filled by the computer when the battle starts.",
		Vector2(620, 192 + slots.size() * SEAT + 6), 15, Color(Cfg.COL_UI, 0.6))

	var leave := _small("LEAVE LOBBY", 200.0)
	leave.position = Vector2(190, 642)
	leave.pressed.connect(Net.leave_lobby)
	_page.add_child(leave)
	if host:
		var go := Ui.button("START BATTLE", Cfg.COL_ACCENT)
		go.position = Vector2(210, 430)
		go.pressed.connect(Net.start_game)
		_page.add_child(go)
		go.grab_focus()
	else:
		_text("WAITING FOR THE HOST TO START", Vector2(190, 440), 24, Cfg.COL_ACCENT)
