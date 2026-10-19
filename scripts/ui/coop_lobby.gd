class_name CoopLobby
extends Control
## Co-op screen (task 24C stage 1), opened from the title menu's "Co-op" button.
##   Host: pick a saved game, open the lobby, share the code; see who joined (ready state), kick.
##   Join: type the host's code or address, press Join; a progress bar shows the town download.
## All networking lives in CoopSession / CoopHost / CoopClient; this file is only the screen. A joined client enters the game
## through Main's own `_clear_world` / `_enter_game`, and the town is then frozen (speed 0): in this stage the client has no
## authority of its own and refreshes from the host on request ("Refresh town").
signal closed

var ses: CoopSession
var main_node: Node
var name_edit: LineEdit
var slot_opt: OptionButton
var code_edit: LineEdit
var host_box: VBoxContainer
var join_box: VBoxContainer
var status: Label
var bar: ProgressBar
var peers_box: VBoxContainer
var info: Label
var open_btn: Button
var join_btn: Button
var refresh_btn: Button
var tab_host: Button
var tab_join: Button
var hide_btn: Button
var chip: Button
var panel: PanelContainer

func _ready() -> void:
	ses = CoopSession.ensure(get_tree())
	main_node = get_tree().current_scene
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(UITheme.BG, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	var root := VBoxContainer.new()
	panel.add_child(root)
	root.add_child(UIU.make_label("Play together", 28, UITheme.ACCENT))
	root.add_child(UIU.make_label("One of you hosts the town, the others join it.", 13, UITheme.MUTED))
	var tabs := HBoxContainer.new()
	root.add_child(tabs)
	tab_host = _button("Host a game", func(): _show_tab(true), tabs)
	tab_join = _button("Join a game", func(): _show_tab(false), tabs)
	var nrow := HBoxContainer.new()
	root.add_child(nrow)
	nrow.add_child(UIU.make_label("Your name", 14))
	name_edit = LineEdit.new()
	name_edit.text = _default_name()
	name_edit.max_length = 24
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(name_edit)
	host_box = VBoxContainer.new()
	root.add_child(host_box)
	slot_opt = OptionButton.new()
	host_box.add_child(UIU.make_label("Town to play", 14))
	host_box.add_child(slot_opt)
	open_btn = _button("Open the lobby", _open_lobby, host_box)
	peers_box = VBoxContainer.new()
	host_box.add_child(peers_box)
	join_box = VBoxContainer.new()
	root.add_child(join_box)
	join_box.add_child(UIU.make_label("Host's code or address", 14))
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "ABCD-EFGH-IJKL   or   192.168.1.20:%d" % CoopProto.DEFAULT_PORT
	code_edit.text_submitted.connect(func(_t): _join())
	join_box.add_child(code_edit)
	join_btn = _button("Join", _join, join_box)
	refresh_btn = _button("Refresh town from the host", func(): if ses.client != null: ses.client.request_snapshot(), join_box)
	refresh_btn.visible = false
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 14)
	bar.show_percentage = false
	bar.visible = false
	root.add_child(bar)
	info = UIU.make_label("", 12, UITheme.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(info)
	status = UIU.make_label("", 14)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status)
	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	hide_btn = _button("Hide", _hide_panel, bottom)
	hide_btn.tooltip_text = "Keep playing; the co-op button in the corner brings this back"
	hide_btn.visible = false
	_button("Leave / Back", _leave, bottom)
	chip = Button.new()
	chip.visible = false
	chip.pressed.connect(func():
		chip.visible = false
		visible = true)
	chip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	chip.position = Vector2(-150, 8)
	ses.changed.connect(_refresh)
	_fill_slots()
	_show_tab(true)
	_refresh()

func _exit_tree() -> void:
	if chip != null and is_instance_valid(chip) and chip.get_parent() == null:
		chip.free()

func _button(text: String, cb: Callable, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 36)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _default_name() -> String:
	var n := OS.get_environment("USERNAME")
	return n.left(24) if n != "" else "Player"

func _fill_slots() -> void:
	slot_opt.clear()
	var playing: bool = main_node != null and bool(main_node.get("playing"))
	if playing:
		slot_opt.add_item("The game I am playing now", 0)
	for i in range(1, SaveSlots.SLOTS + 1):
		if SaveSlots.can_load(i):
			slot_opt.add_item("Slot %d: %s" % [i, SaveSlots.slot_summary(i)], i)
	if slot_opt.item_count == 0:
		slot_opt.add_item("(no saved game yet: start one first)", -1)
		open_btn.disabled = true

func _show_tab(host: bool) -> void:
	var live := ses.is_active()
	host_box.visible = host
	join_box.visible = not host
	tab_host.disabled = host or (live and ses.role == "client")
	tab_join.disabled = (not host) or (live and ses.role == "host")
	info.text = ""
	_refresh()

# ------------------------------------------------------------------ host
func _open_lobby() -> void:
	var id := slot_opt.get_selected_id()
	if id < 0:
		return
	if id > 0 and main_node != null and main_node.has_method("load_game"):
		main_node.call("load_game", id)           # the same path as the Load button
	var err := ses.start_host(CoopProto.DEFAULT_PORT, name_edit.text)
	if err != "":
		err = ses.start_host(CoopProto.DEFAULT_PORT + 1 + randi() % 50, name_edit.text)      # the usual port is taken: try a nearby one
	if err != "":
		status.text = err
		return
	ses.host.peer_joined.connect(func(_p, n): UIU.notify("%s joined the game." % n, "good"))
	ses.host.peer_left.connect(func(_p, _r): _refresh())
	_refresh()

func _host_info() -> String:
	var ip := CoopAddress.local_ip()
	var code := CoopAddress.encode(ip, ses.port) if ip != "" else ""
	var s := ""
	if code != "":
		s += "Code for players on your network: %s\nor type: %s:%d\n\n" % [code, ip, ses.port]
	s += "Playing over the internet? Your router must forward UDP port %d to this computer (or you can both use a VPN such as Tailscale), and then they type your public address:%d. There is no relay service yet." % [ses.port, ses.port]
	return s

func _rebuild_peers() -> void:
	for c in peers_box.get_children():
		peers_box.remove_child(c)
		c.queue_free()
	if ses.role != "host" or ses.host == null:
		return
	var lob := ses.host.lobby_dict()
	peers_box.add_child(UIU.make_label("Players (%d of %d)" % [ses.host.player_count(), ses.host.max_players], 14))
	peers_box.add_child(UIU.make_label("%s (you, host)" % ses.host.host_name, 14))
	for p in lob["peers"]:
		var row := HBoxContainer.new()
		peers_box.add_child(row)
		var state := "away, can rejoin" if p["away"] else ("ready" if p["ready"] else "joining...")
		var lab := UIU.make_label("%s - %s" % [p["name"], state], 14)
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lab)
		if not p["away"]:
			var pid := int(p["id"])
			_button("Remove", func(): ses.host.kick(pid), row)

# ------------------------------------------------------------------ client
func _join() -> void:
	var err := ses.join(code_edit.text, name_edit.text)
	if err != "":
		status.text = err
		return
	var c := ses.client
	c.load_fn = _load_into_game
	c.snapshot_loaded.connect(func(_h): _refresh())
	_refresh()

## The client's snapshot loader: clear the old game, restore in memory (no save slot is touched), enter the game, freeze time.
func _load_into_game(text: String) -> String:
	if main_node != null and main_node.has_method("_clear_world"):
		main_node.call("_clear_world")
	var err := CoopSnapshot.load_text(text)
	if err != "":
		return err
	if main_node != null and main_node.has_method("_enter_game"):
		main_node.call("_enter_game")
	UIU.set_speed(0)
	return ""

func _refresh() -> void:
	if not is_inside_tree():
		return
	var c := ses.client
	var hosting := ses.role == "host"
	var joined := ses.role == "client" and c != null
	open_btn.disabled = hosting or slot_opt.get_selected_id() < 0
	open_btn.text = "Lobby is open" if hosting else "Open the lobby"
	join_btn.disabled = joined and c.state not in ["refused", "ended", "failed", "idle"]
	name_edit.editable = not ses.is_active()
	hide_btn.visible = (hosting or (joined and c.state == "synced"))
	refresh_btn.visible = joined and c.state in ["synced", "desync"]
	bar.visible = joined and c.state == "loading"
	if bar.visible:
		bar.value = c.ras.progress() * 100.0
	if hosting:
		info.text = _host_info()
		status.text = ses.status_text()
		_rebuild_peers()
	elif joined:
		info.text = ""
		status.text = c.status
		if c.state == "synced":
			status.text = "%s\nYou are in %s's town. It is paused for you until you refresh; orders you give are carried out by the host." % [c.status, c.host_name]
		for p in c.lobby.get("peers", []):
			status.text += "\n%s - %s" % [p["name"], "ready" if p["ready"] else "joining..."]
	else:
		info.text = ""
	if chip != null:
		chip.text = "Co-op (%d)" % (ses.host.player_count() if hosting and ses.host != null else 2 if joined else 0)

func _hide_panel() -> void:
	visible = false
	if chip.get_parent() == null:
		get_parent().add_child(chip)
	chip.visible = true

func _leave() -> void:
	ses.stop()
	if chip != null and chip.get_parent() != null:
		chip.queue_free()
	closed.emit()
	queue_free()
