extends RefCounted
## The co-op screen builds, validates input with plain messages, shows the host's code and the joined players, and can remove one.

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _texts(n: Node, out: Array) -> void:
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		_texts(c, out)

func run() -> Array:
	fails = []
	CoopProto.build_override = "test-build"
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var lobby := CoopLobby.new()
	lobby.theme = UITheme.build()
	root.add_child(lobby)
	_check(lobby.open_btn != null and lobby.join_btn != null, "screen built")
	# join input errors are plain language
	lobby.code_edit.text = "nonsense"
	lobby._join()
	_check(lobby.status.text != "" and not lobby.ses.is_active(), "a bad code shows a message and starts nothing (%s)" % lobby.status.text)
	lobby.code_edit.text = ""
	lobby._join()
	_check("first" in lobby.status.text, "empty code asks for it (%s)" % lobby.status.text)
	# host (the "game I am playing" entry: no Main in this test, so nothing is loaded)
	lobby.slot_opt.clear()
	lobby.slot_opt.add_item("The game I am playing now", 0)
	lobby.slot_opt.select(0)
	lobby._open_lobby()
	var ses := lobby.ses
	_check(ses.role == "host", "lobby opened")
	if ses.role == "host":
		ses.host.snapshot_fn = Callable()          # no world needed here
		var texts: Array = []
		_texts(lobby, texts)
		var all := " ".join(PackedStringArray(texts))
		_check("UDP port" in all, "NAT note is shown")
		_check(lobby.open_btn.disabled and lobby.name_edit.editable == false, "controls lock while hosting")
		# a client joins over a real socket
		var other := CoopSession.new()
		_check(other.join("127.0.0.1:%d" % ses.port, "Guest") == "", "guest starts joining")
		var t0 := Time.get_ticks_msec()
		while ses.host.player_count() < 2 and Time.get_ticks_msec() - t0 < 8000:
			ses.pump(0.02)
			other.pump(0.02)
			OS.delay_msec(5)
		ses.pump(0.02)
		_check(ses.host.player_count() == 2, "the guest is in the lobby")
		texts = []
		_texts(lobby.peers_box, texts)
		_check(" ".join(PackedStringArray(texts)).contains("Guest"), "the host screen lists Guest (%s)" % str(texts))
		var removed := false
		for b in lobby.peers_box.find_children("*", "Button", true, false):
			if (b as Button).text == "Remove":
				(b as Button).pressed.emit()
				removed = true
		_check(removed, "there is a Remove button")
		t0 = Time.get_ticks_msec()
		while other.client.state != "ended" and Time.get_ticks_msec() - t0 < 5000:
			ses.pump(0.02)
			other.pump(0.02)
			OS.delay_msec(5)
		_check(other.client.state == "ended" and "removed" in other.client.status, "the removed guest is told why (%s)" % other.client.status)
		other.stop()
		other.free()
	lobby._leave()
	_check(not lobby.ses.is_active(), "leaving closes the lobby")
	if CoopSession.instance != null:
		CoopSession.instance.free()
		CoopSession.instance = null
	CoopProto.build_override = ""
	return fails
