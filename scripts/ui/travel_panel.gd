class_name TravelPanel
extends Control
## "Go to..." dialog (opened from the HUD "Map" button or M). Lots are tiles laid out on the map grid from
## data/neighborhood.json: name, open/closed state, walking time from the selected folk's tile, who is there. Pick a lot (the
## camera moves to it), tick the folk to bring, press Go: they WALK there. "Fast travel" hides them for a short trip instead
## (a fade + toast covers it). Townie homes list their residents; venue lots can invite a friend.

signal travelled(result: Dictionary)

const TILE := Vector2(150, 84)
const GAP := 10

var dialog: PanelContainer
var map_box: Control
var detail: VBoxContainer
var folk_box: VBoxContainer
var where_label: Label
var status_label: Label
var title_label: Label
var blurb_label: Label
var info_label: Label
var people_label: Label
var travel_button: Button
var fast_check: CheckBox
var home_button: Button
var invite_pick: OptionButton
var invite_button: Button
var fade: ColorRect
var fade_label: Label
var selected_lot: String = ""
var checked: Dictionary = {}          # folk id -> bool
var tiles: Dictionary = {}            # lot id -> Button
var _folk_checks: Dictionary = {}     # folk id -> CheckBox
var _tween: Tween = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	UIU.connect_ev("game_event", _on_game_event)
	SimEnv.clock().hour_passed.connect(func(_h): if visible and dialog.visible: refresh())
	dialog.visible = false

func _build() -> void:
	dialog = PanelContainer.new()
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.anchor_left = 0.5
	dialog.anchor_right = 0.5
	dialog.anchor_top = 0.5
	dialog.anchor_bottom = 0.5
	dialog.offset_left = -520
	dialog.offset_right = 520
	dialog.offset_top = -310
	dialog.offset_bottom = 310
	add_child(dialog)
	var root := VBoxContainer.new()
	dialog.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	head.add_child(UIU.make_label("Go to...", 24, UITheme.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	where_label = UIU.make_label("", 15, UITheme.MUTED)
	head.add_child(where_label)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(close_panel)
	head.add_child(close)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	# ---- map
	var map_panel := PanelContainer.new()
	map_panel.add_theme_stylebox_override("panel", UITheme.box(Color("#17202a"), 8, Color(1, 1, 1, 0.06), 1, 8))
	body.add_child(map_panel)
	var g: Array = Neighborhood.cfg().get("grid", [5, 4])
	map_box = Control.new()
	map_box.custom_minimum_size = Vector2(g[0] * (TILE.x + GAP) + GAP, g[1] * (TILE.y + GAP) + GAP)
	map_panel.add_child(map_box)
	for l in Neighborhood.lots():
		var lid: String = str(l["id"])
		var b := Button.new()
		b.toggle_mode = false
		b.custom_minimum_size = TILE
		b.size = TILE
		var p: Array = l.get("pos", [0, 0])
		b.position = Vector2(GAP + p[0] * (TILE.x + GAP), GAP + p[1] * (TILE.y + GAP))
		b.clip_text = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(select_lot.bind(lid))
		map_box.add_child(b)
		tiles[lid] = b
	# ---- detail
	var dp := PanelContainer.new()
	dp.custom_minimum_size = Vector2(280, 0)
	dp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(dp)
	detail = VBoxContainer.new()
	dp.add_child(detail)
	title_label = UIU.make_label("", 20)
	detail.add_child(title_label)
	status_label = UIU.make_label("", 14)
	detail.add_child(status_label)
	blurb_label = UIU.make_label("", 13, UITheme.MUTED)
	blurb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(blurb_label)
	info_label = UIU.make_label("", 13)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(info_label)
	people_label = UIU.make_label("", 13, UITheme.MUTED)
	people_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(people_label)
	detail.add_child(HSeparator.new())
	detail.add_child(UIU.make_label("Bring along:", 14))
	folk_box = VBoxContainer.new()
	detail.add_child(folk_box)
	var ir := HBoxContainer.new()
	detail.add_child(ir)
	invite_pick = OptionButton.new()
	invite_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ir.add_child(invite_pick)
	invite_button = Button.new()
	invite_button.text = "Invite friend"
	invite_button.tooltip_text = "Ask this townie to meet you here in about 40 minutes."
	invite_button.pressed.connect(_on_invite)
	ir.add_child(invite_button)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(spacer)
	var br := HBoxContainer.new()
	detail.add_child(br)
	home_button = Button.new()
	home_button.text = "Go Home"
	home_button.tooltip_text = "Everyone heads home"
	home_button.pressed.connect(_on_home)
	br.add_child(home_button)
	fast_check = CheckBox.new()
	fast_check.text = "Fast travel"
	fast_check.tooltip_text = "Skip the walk: the folk are out of sight for a short trip and arrive at the door."
	fast_check.toggled.connect(func(_on: bool): refresh())
	br.add_child(fast_check)
	travel_button = Button.new()
	travel_button.text = "Go"
	travel_button.custom_minimum_size = Vector2(130, 36)
	travel_button.pressed.connect(_on_travel)
	br.add_child(travel_button)
	# ---- fade overlay (loading toast)
	fade = ColorRect.new()
	fade.color = Color(0.05, 0.08, 0.11, 0.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.visible = false
	add_child(fade)
	fade_label = UIU.make_label("", 30, UITheme.TEXT)
	fade_label.set_anchors_preset(Control.PRESET_CENTER)
	fade_label.anchor_left = 0.5
	fade_label.anchor_right = 0.5
	fade_label.anchor_top = 0.5
	fade_label.anchor_bottom = 0.5
	fade_label.offset_left = -300
	fade_label.offset_right = 300
	fade_label.offset_top = -20
	fade_label.offset_bottom = 20
	fade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fade.add_child(fade_label)

# ------------------------------------------------------------------ open / close
func open_panel() -> void:
	dialog.visible = true
	if selected_lot == "":
		selected_lot = _default_selection()
	refresh()

func close_panel() -> void:
	dialog.visible = false

func toggle() -> void:
	if dialog.visible:
		close_panel()
	else:
		open_panel()

func is_open() -> bool:
	return dialog.visible

func _default_selection() -> String:
	if Neighborhood.lot_of_selected() != Neighborhood.HOME:
		return Neighborhood.HOME
	return "park"

# ------------------------------------------------------------------ content
func refresh() -> void:
	var cur: String = Neighborhood.lot_of_selected()
	where_label.text = "%s is at: %s" % [_sel_name(), Neighborhood.label_of(cur)]
	for l in Neighborhood.lots():
		_style_tile(l)
	_refresh_detail()

func _style_tile(l: Dictionary) -> void:
	var lid: String = str(l["id"])
	var b: Button = tiles[lid]
	var cur: String = Neighborhood.lot_of_selected()
	var open: bool = Neighborhood.is_open(lid)
	var here: Array = Neighborhood.folk_at(lid)
	var status: String = "You are here" if lid == cur else "~%d min walk" % _estimate(lid)
	var open_txt: String = "Open" if open else "Closed"
	var line3: String = ""
	var parts: Array = []
	if not here.is_empty():
		parts.append("%d of yours" % here.size())
	if Crowd.count(lid) > 0:
		parts.append("%d locals" % Crowd.count(lid))
	if str(l.get("type", "")) == "townie_home":
		var rc: int = Neighborhood.residents_of(lid).size()
		if rc > 0:
			parts.append("%d resident%s" % [rc, "" if rc == 1 else "s"])
	line3 = ", ".join(parts)
	b.text = "%s
%s  -  %s%s" % [str(l["label"]), open_txt, status, ("
" + line3) if line3 != "" else ""]
	var base := Color(str(l.get("color", "#556070")))
	var bg: Color = base.darkened(0.55)
	if not open:
		bg = bg.lerp(Color("#2a2a2e"), 0.6)
	var sel: bool = (lid == selected_lot)
	var border: Color = UITheme.ACCENT if sel else (Color("#f2c94c") if lid == cur else Color(1, 1, 1, 0.1))
	var bw: int = 3 if sel else (2 if lid == cur else 1)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := UITheme.box(bg.lightened(0.12) if st == "hover" else bg, 8, border, bw, 8)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color.WHITE if open else Color(1, 1, 1, 0.55))

func select_lot(lot_id: String) -> void:
	selected_lot = lot_id
	Neighborhood.focus_lot(lot_id)
	refresh()

func _sel_name() -> String:
	var f = SysUtil.folk(Neighborhood.selected)
	if f == null and not SysUtil.residents().is_empty():
		f = SysUtil.residents()[0]
	return "You" if f == null else str(f.name)

## Rough walking minutes from the selected folk to a lot (octile distance, no path search: used for the whole list).
func _estimate(lid: String) -> int:
	var f = SysUtil.folk(Neighborhood.selected)
	if f == null and not SysUtil.residents().is_empty():
		f = SysUtil.residents()[0]
	var spot: Vector2i = Neighborhood.entry_tile(lid)
	if f == null or spot.x < 0:
		return Neighborhood.travel_minutes(Neighborhood.lot_of_selected(), lid)
	var dx := absf(f.tile.x - spot.x)
	var dy := absf(f.tile.y - spot.y)
	return int(ceil((maxf(dx, dy) + 0.41 * minf(dx, dy)) * Interaction.WALK_MIN_PER_TILE * 1.15))

## Exact walking minutes (path search) for the selected lot.
func _walk_minutes(lid: String) -> int:
	var m: int = Neighborhood.walk_minutes(Neighborhood.selected, lid) if SysUtil.folk(Neighborhood.selected) != null else -1
	return m if m >= 0 else _estimate(lid)

func _refresh_detail() -> void:
	var lid: String = selected_lot
	var l: Dictionary = Neighborhood.lot(lid)
	if l.is_empty():
		return
	var cur: String = Neighborhood.lot_of_selected()
	title_label.text = str(l["label"])
	var open: bool = Neighborhood.is_open(lid)
	status_label.text = Venues.status_text(lid)
	status_label.add_theme_color_override("font_color", Color("#4cc78a") if open else Color("#e5534b"))
	blurb_label.text = str(l.get("blurb", ""))
	var fee: int = Venues.fee(str(l.get("type", "")))
	var fast: bool = fast_check.button_pressed
	var mins: int = Neighborhood.travel_minutes(cur, lid) if fast else _walk_minutes(lid)
	var info: String = "%s: %s" % ["Fast travel" if fast else "Walking time", "here" if lid == cur else "%d min" % mins]
	if fee > 0:
		info += "   |   Entry: %d coins each" % fee
	info_label.text = info
	# who is there
	var lines: Array = []
	var here: Array = Neighborhood.folk_at(lid)
	if not here.is_empty():
		var names: Array = []
		for id in here:
			names.append(SysUtil.folk_name(int(id)))
		lines.append("Your household here: %s" % ", ".join(names))
	if Crowd.count(lid) > 0:
		var nn: Array = []
		for f in Crowd.crowd_folk(lid):
			nn.append(str(f.name))
		lines.append("Also here: %s" % ", ".join(nn))
	if str(l.get("type", "")) == "townie_home":
		var rn: Array = []
		for t in Neighborhood.residents_of(lid):
			rn.append(str(t["name"]))
		lines.append("Residents: %s" % (", ".join(rn) if not rn.is_empty() else "none right now"))
	people_label.text = "\n".join(lines)
	_rebuild_folk_list()
	_rebuild_invites()
	var res: Dictionary = Neighborhood.can_travel(_selected_folk(), lid)
	travel_button.disabled = not bool(res["ok"])
	travel_button.text = "Go (%d min)" % mins if lid != cur else "Go"
	travel_button.tooltip_text = str(res["reason"])
	var all_home: bool = Neighborhood.folk_at(Neighborhood.HOME).size() == SysUtil.residents().size()
	home_button.visible = not all_home
	home_button.disabled = all_home

func _rebuild_folk_list() -> void:
	for c in folk_box.get_children():
		c.queue_free()
	_folk_checks.clear()
	for f in SysUtil.residents():
		var fid: int = int(f.id)
		var rs: String = str(Away.info(fid).get("reason", ""))
		var held: bool = rs in Neighborhood.HELD_REASONS
		var cb := CheckBox.new()
		var at: String = Neighborhood.label_of(Neighborhood.where(fid))
		var tag: String = "" if not held else "  (%s)" % rs
		if Neighborhood.heading_to(fid) != "":
			tag = "  (walking to %s)" % Neighborhood.label_of(Neighborhood.heading_to(fid))
		cb.text = "%s - at %s%s" % [f.name, at, tag]
		cb.add_theme_font_size_override("font_size", 13)
		cb.disabled = held
		if not checked.has(fid):
			checked[fid] = not held
		cb.button_pressed = bool(checked[fid]) and not held
		cb.toggled.connect(func(on: bool): checked[fid] = on; _refresh_travel_button())
		folk_box.add_child(cb)
		_folk_checks[fid] = cb

func _refresh_travel_button() -> void:
	var res: Dictionary = Neighborhood.can_travel(_selected_folk(), selected_lot)
	travel_button.disabled = not bool(res["ok"])
	travel_button.tooltip_text = str(res["reason"])

func _selected_folk() -> Array:
	var out: Array = []
	for id in checked:
		if bool(checked[id]) and SysUtil.folk(int(id)) != null:
			out.append(int(id))
	return out

func _rebuild_invites() -> void:
	invite_pick.clear()
	var lid: String = selected_lot
	var venue: bool = lid != Neighborhood.HOME and str(Neighborhood.lot(lid).get("type", "")) != "townie_home"
	invite_pick.visible = venue
	invite_button.visible = venue
	if not venue:
		return
	var res: Array = SysUtil.residents()
	var rows: Array = []
	for t in Story.alive_townies():
		if Story.stage_of(t) in ["baby", "toddler", "child"]:
			continue
		var best: float = 0.0
		for r in res:
			best = maxf(best, RelationshipService.value(int(r.id), int(t["id"]), "friendship"))
		rows.append([best, t])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for i in mini(rows.size(), 12):
		var t2: Dictionary = rows[i][1]
		invite_pick.add_item("%s (%d)" % [t2["name"], int(rows[i][0])])
		invite_pick.set_item_metadata(invite_pick.item_count - 1, int(t2["id"]))
	invite_button.disabled = invite_pick.item_count == 0

func _on_invite() -> void:
	if invite_pick.item_count == 0 or invite_pick.selected < 0:
		return
	var tid: int = int(invite_pick.get_item_metadata(invite_pick.selected))
	var sel: Array = _selected_folk()
	var host: int = int(sel[0]) if not sel.is_empty() else (int(SysUtil.residents()[0].id) if not SysUtil.residents().is_empty() else -1)
	if host < 0:
		return
	var inv: Dictionary = Commands.run({"folk_id": host, "action": "invite_to_venue", "args": {"townie_id": tid, "lot_id": selected_lot}})
	if not bool(inv.get("ok", false)):
		return
	refresh()

func _on_travel() -> void:
	var res: Dictionary = do_travel(selected_lot)
	if bool(res.get("ok", false)):
		close_panel()

## Programmatic entry used by the button and tests.
func do_travel(lot_id: String) -> Dictionary:
	var ids: Array = _selected_folk()
	var res: Dictionary = Commands.run({"action": "travel", "args": {"folk_ids": ids, "lot_id": lot_id, "opts": {"fast": fast_check.button_pressed}}})
	if bool(res.get("ok", false)):
		travelled.emit(res)
	refresh()
	return res

func _on_home() -> void:
	var ids: Array = []
	for f in SysUtil.residents():
		ids.append(int(f.id))
	var res: Dictionary = Commands.run({"action": "go_home", "args": {"folk_ids": ids, "opts": {"fast": fast_check.button_pressed}}})
	if bool(res.get("ok", false)):
		close_panel()
	refresh()

func _on_game_event(ev_name: String, p: Dictionary) -> void:
	if ev_name == "lot_changed" and not bool(p.get("walk", false)):
		var to_id: String = str(p.get("to", ""))
		_play_fade(Neighborhood.label_of(to_id) if to_id != Neighborhood.HOME else "Home", "", int(p.get("minutes", 0)))
	if ev_name in ["lot_changed", "returned_to_lot", "left_lot", "met_townie"] and dialog.visible:
		refresh()

# ------------------------------------------------------------------ loading toast
func _play_fade(to_label: String, _from_label: String, minutes: int) -> void:
	if not is_inside_tree():
		return
	fade_label.text = "Heading to %s...  (%d min)" % [to_label, minutes] if to_label != "Home" else "Heading home...  (%d min)" % minutes
	fade.visible = true
	fade.color.a = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	fade_label.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(fade, "color:a", 0.78, 0.14)
	_tween.parallel().tween_property(fade_label, "modulate:a", 1.0, 0.14)
	_tween.tween_interval(float(Neighborhood.cfg().get("travel", {}).get("toast_seconds", 1.6)) * 0.45)
	_tween.tween_property(fade, "color:a", 0.0, 0.5)
	_tween.parallel().tween_property(fade_label, "modulate:a", 0.0, 0.5)
	_tween.tween_callback(func(): fade.visible = false)
