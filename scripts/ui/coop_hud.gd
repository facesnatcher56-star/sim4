class_name CoopHud
extends PanelContainer
## Co-op widgets on the HUD (stages 2 + 3), shown only while a co-op session is running:
##  - the fixed pace, and a banner that says WHY time is skipping (or that it is paused / who asked to pause) with Pause / Resume / Accept / No
##  - a big-moment alert for YOUR household with a "Show me" button (camera offer; no sound)
##  - coloured name tags (player colour + player name) on every household's folk; your own folk are marked "(you)"
## It reads the host's CoopTime directly (host) or the last TIME message (client); every action goes through CoopSession.

var hud: Node
var _pace: Label
var _banner: Label
var _pause_btn: Button
var _accept_btn: Button
var _decline_btn: Button
var _alert_box: HBoxContainer
var _alert_label: Label
var _look_btn: Button
var _alert_tile := Vector2i(-1, -1)
var _alert_until := 0.0
var _poll := 0.0
var _wired := 0
var _was_active := false
var _tag_i := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	position.y = 64.0
	mouse_filter = Control.MOUSE_FILTER_PASS
	var v := VBoxContainer.new()
	add_child(v)
	var row := HBoxContainer.new()
	v.add_child(row)
	_pace = UIU.make_label("", 14, UITheme.ACCENT)
	row.add_child(_pace)
	_banner = UIU.make_label("", 14)
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.custom_minimum_size = Vector2(360, 0)
	row.add_child(_banner)
	_pause_btn = _btn("Pause...", row, _on_pause)
	_accept_btn = _btn("Accept", row, func(): _vote("pause", true))
	_decline_btn = _btn("No", row, func(): _vote("pause", false))
	_alert_box = HBoxContainer.new()
	v.add_child(_alert_box)
	_alert_label = UIU.make_label("", 15, Color("#f2c94c"))
	_alert_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_alert_label.custom_minimum_size = Vector2(360, 0)
	_alert_box.add_child(_alert_label)
	_look_btn = _btn("Show me", _alert_box, _look)
	_btn("Dismiss", _alert_box, func(): _alert_until = 0.0)
	visible = false

func _btn(text: String, parent: Control, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _process(delta: float) -> void:
	_poll += delta
	if _poll < 0.25:
		return
	_poll = 0.0
	var ses := CoopSession.instance
	var on: bool = ses != null and is_instance_valid(ses) and ses.is_active() and CoopTime.active
	if on != _was_active:
		_was_active = on
		_set_solo_ui(not on)
	visible = on
	if not on:
		return
	_wire(ses)
	_refresh(ses)
	_tags()

func _state(ses: CoopSession) -> Dictionary:
	if ses.role == "host" and ses.time != null:
		return ses.time.state()
	if ses.role == "client" and ses.client != null:
		return ses.client.time_state
	return {}

func _refresh(ses: CoopSession) -> void:
	var st := _state(ses)
	var me := Players.local_id
	_pace.text = "%s pace" % str(st.get("label", "Normal"))
	var text := str(st.get("reason", ""))
	var voting := int(st.get("vote", 0)) > 0
	if voting:
		text = "%s asks everyone to pause." % str(st.get("who", "Someone"))
	elif str(st.get("note", "")) != "" and text == "":
		text = str(st["note"])
	_banner.text = text
	_banner.add_theme_color_override("font_color", Color("#7ed6a5") if bool(st.get("skip", false)) else UITheme.TEXT)
	_banner.visible = text != ""
	var paused := bool(st.get("paused", false))
	var i_voted: bool = (st.get("yes", []) as Array).has(me)
	_pause_btn.text = "Resume" if paused else "Pause..."
	_pause_btn.visible = paused or not voting
	_accept_btn.visible = voting and not i_voted
	_decline_btn.visible = voting and not i_voted
	_alert_box.visible = Time.get_ticks_msec() / 1000.0 < _alert_until

func _on_pause() -> void:
	var ses := CoopSession.instance
	if bool(_state(ses).get("paused", false)):
		if ses.role == "host":
			ses.time.resume(Players.LOCAL)
		else:
			ses.client.send_vote("resume", true)
	else:
		_vote("pause", true)

func _vote(kind: String, yes: bool) -> void:
	var ses := CoopSession.instance
	if ses.role == "host" and ses.time != null:
		if kind == "pause" and yes and ses.time.vote.is_empty():
			ses.time.call_vote(Players.LOCAL, ses._t)
		else:
			ses.time.answer_vote(Players.LOCAL, yes)
	elif ses.client != null:
		ses.client.send_vote(kind, yes)

func _wire(ses: CoopSession) -> void:
	var key: int = ses.host.get_instance_id() if ses.role == "host" and ses.host != null else (ses.client.get_instance_id() if ses.client != null else 0)
	if key == _wired or key == 0:
		return
	_wired = key
	if ses.role == "host":
		ses.host.local_alert.connect(func(text, _f, data): _show_alert(text, data))
	else:
		ses.client.alert_received.connect(func(text, data): _show_alert(text, data))

func _show_alert(text: String, data: Dictionary) -> void:
	_alert_label.text = text
	_alert_tile = Vector2i(int(data.get("x", -1)), int(data.get("y", -1)))
	_look_btn.visible = _alert_tile.x >= 0
	_alert_until = Time.get_ticks_msec() / 1000.0 + 25.0
	UIU.notify(text, "bad")

func _look() -> void:
	var lv = hud.get("lot_view") if hud != null else null
	if lv != null and _alert_tile.x >= 0 and lv.has_method("focus_tile"):
		lv.call("focus_tile", _alert_tile)

## Solo UI comes back when the session ends; in co-op the speed buttons are hidden (the host's pace is fixed).
func _set_solo_ui(solo: bool) -> void:
	if hud == null:
		return
	for k in hud.get("speed_buttons"):
		(hud.speed_buttons[k] as Control).visible = solo
	if hud.has_method("rebuild_folk_row"):
		hud.call("rebuild_folk_row")

## Name tags: a few folk per poll so it stays cheap.
func _tags() -> void:
	var lv = hud.get("lot_view") if hud != null else null
	if lv == null or not lv.has_method("get_folk_view"):
		return
	var folk: Array = WorldIface.all_folk()
	for k in mini(6, folk.size()):
		_tag_i = (_tag_i + 1) % folk.size()
		var f = folk[_tag_i]
		if int(f.household_id) <= 0:
			continue
		var pid := Players.player_of(int(f.household_id))
		var fv = lv.call("get_folk_view", int(f.id))
		if pid <= 0 or fv == null or fv._name_label == null or not Players.table.has(pid):
			continue
		var mine := CoopVisibility.is_mine(f)
		fv._name_label.text = "%s (you)" % f.name if mine else "%s - %s" % [f.name, Players.name_of(pid)]
		fv._name_label.modulate = Players.color_of(pid)
