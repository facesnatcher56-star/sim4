class_name CoopWaiting
extends PanelContainer
## What a PASSIVE co-op player can do while time cannot skip because another player is busy (stage 4):
##  - read the town stories (news log + public chronicle, via CoopStories)
##  - watch the active player's household: a read-only camera that follows one of their folk, and a feed of what each of them is doing
## Nothing here sends a command. Every folk shown goes through CoopVisibility.visible_to(local player, folk), so tier rules apply later without change.
## Shown by CoopHud when `CoopWaiting.waiting(state, me)` is true; the player can hide it.

const ROW_LIMIT := 8

var hud: Node
var _title: Label
var _body: VBoxContainer
var _tabs: HBoxContainer
var _mode := "stories"            # "stories" or "watch:<player id>"
var _hidden := false
var _last_sig := ""
var _watching := -1               # folk id the camera follows

# ------------------------------------------------------------------ rules (static: tests call them)
## Waiting = my household is asleep / away (nothing for me to do), time is NOT skipping (someone else is busy) and nobody paused.
static func waiting(state: Dictionary, me: int) -> bool:
	if bool(state.get("skip", false)) or bool(state.get("paused", false)):
		return false
	return CoopTime.household_passive(Players.household_of(me)) and not active_players(me).is_empty()

## Other players whose household has something to do right now.
static func active_players(me: int) -> Array:
	var out: Array = []
	for pid in Players.ids():
		if int(pid) != me and not CoopTime.household_passive(Players.household_of(int(pid))):
			out.append(int(pid))
	return out

## [{id, text}] for the folk of `pid`'s household the viewer may see: "Name: doing X (mood)".
static func folk_lines(pid: int, viewer: int) -> Array:
	var out: Array = []
	var hid := Players.household_of(pid)
	for f in WorldIface.all_folk():
		if int(f.household_id) != hid or f.has_meta("visitor") or not CoopVisibility.visible_to(viewer, f):
			continue
		var what: String = "away" if (f.has_meta("away") or Away.is_away(int(f.id))) else (str(f.current.label()) if f.current != null else "idle")
		out.append({"id": int(f.id), "text": "%s: %s (%s)" % [f.name, what, str(f.mood_name)]})
		if out.size() >= ROW_LIMIT:
			break
	return out

# ------------------------------------------------------------------ view
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(12, 150)
	custom_minimum_size = Vector2(340, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.PANEL, 0.96), 8, UITheme.ACCENT, 1, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	_title = UIU.make_label("While you wait", 15, UITheme.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var hide_btn := Button.new()
	hide_btn.text = "Hide"
	hide_btn.pressed.connect(func(): _hidden = true; visible = false)
	head.add_child(hide_btn)
	_tabs = HBoxContainer.new()
	v.add_child(_tabs)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 3)
	v.add_child(_body)
	visible = false

## CoopHud calls this a few times a second with the TIME state.
func update_state(state: Dictionary) -> void:
	var me := Players.local_id
	var on := waiting(state, me)
	if not on:
		_hidden = false          # shown again the next time we wait
		visible = false
		_watching = -1
		return
	visible = not _hidden
	if not visible:
		return
	var sig := _sig(me)
	if sig != _last_sig:           # rebuild only when something changed, so a click is never swallowed by a refresh
		_last_sig = sig
		_rebuild(me)

func _rebuild(me: int) -> void:
	var act := active_players(me)
	if _mode.begins_with("watch:") and not act.has(int(_mode.substr(6))):
		_mode = "stories"
		_watching = -1
	_title.text = "%s is playing. Time can't skip yet." % Players.name_of(int(act[0]))
	for c in _tabs.get_children():
		c.queue_free()
	_tab("Town stories", "stories")
	for pid in act:
		_tab("Watch %s" % Players.name_of(int(pid)), "watch:%d" % int(pid))
	for c2 in _body.get_children():
		c2.queue_free()
	if _mode == "stories":
		_stories()
	else:
		_watch(int(_mode.substr(6)), me)

func _tab(text: String, mode: String) -> void:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = _mode == mode
	b.pressed.connect(func(): _set_mode(mode))
	_tabs.add_child(b)

func _set_mode(mode: String) -> void:
	_mode = mode
	if mode == "stories":
		_watching = -1
	_rebuild(Players.local_id)

func _stories() -> void:
	var lines := CoopStories.local_lines()
	if lines.is_empty():
		_body.add_child(UIU.make_label("Nothing to report yet.", 13, UITheme.MUTED))
	for i in range(lines.size() - 1, -1, -1):
		var l := UIU.make_label(CoopStories.text_of(lines[i]), 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(316, 0)
		_body.add_child(l)

func _watch(pid: int, me: int) -> void:
	_body.add_child(UIU.make_label("Watching only: you can't give orders here.", 12, UITheme.MUTED))
	var rows := folk_lines(pid, me)
	if rows.is_empty():
		_body.add_child(UIU.make_label("There is nothing you can see of them right now.", 13, UITheme.MUTED))
	if _watching < 0 and not rows.is_empty():
		_follow(int(rows[0]["id"]))
	for r in rows:
		var b := Button.new()
		b.text = ("> " if int(r["id"]) == _watching else "") + str(r["text"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.flat = true
		b.pressed.connect(func(): _follow(int(r["id"])))
		_body.add_child(b)
	var stop := Button.new()
	stop.text = "Back to my household"
	stop.pressed.connect(_stop_watching)
	_body.add_child(stop)

func _follow(folk_id: int) -> void:
	_watching = folk_id
	var wf = WorldIface.get_folk(folk_id)
	if wf != null:
		CameraFocus.look("cam", wf.tile)          # the spectate camera: what the watched folk are near is simulated in full at once (the camera glide catches up later)
	var lv = hud.get("lot_view") if hud != null else null
	if lv != null and lv.has_method("focus_on"):
		lv.call("focus_on", "folk", folk_id)

func _stop_watching() -> void:
	_watching = -1
	_mode = "stories"
	var mine := Players.household_of(Players.local_id)
	for f in WorldIface.all_folk():
		if int(f.household_id) == mine:
			_follow(int(f.id))
			_watching = -1
			break
	_rebuild(Players.local_id)

func _sig(me: int) -> String:
	var act := active_players(me)
	var body: Array = CoopStories.local_lines() if _mode == "stories" else (folk_lines(int(_mode.substr(6)), me) if _mode.begins_with("watch:") else [])
	return JSON.stringify([_mode, _watching, act, body])
