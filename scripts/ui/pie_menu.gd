class_name PieMenu
extends Control
## The action menu of the game: what the player can do with the thing they clicked (an object, a person, themselves, or bare ground).
## It lists only what can be done NOW, a handful of actions at a time: the main ones on top (recent first), the rest in a few named groups that open on a click.
## What cannot be done is not listed; at most a short "not right now" note under the list says why the most likely ones are out (and the whole list when nothing can be done).
## Objects use the curated menus in data/menus.json (PieEntries.curate). People get the social categories (Friendly / Funny / Romantic / Deep / Group / Mean) as
## groups. Bare ground offers "Go here" and the things you can do anywhere. A click outside closes it; so does Esc.
signal chosen(def_id: String, target_id: int)

const SOCIAL_ORDER := ["Friendly", "Funny", "Romantic", "Deep", "Group", "Mean"]
const CAT_COLORS := {"Friendly": Color("#4cc78a"), "Funny": Color("#f2c94c"), "Romantic": Color("#ee86a6"), "Deep": Color("#35a7b0"),
	"Group": Color("#8f6bf0"), "Mean": Color("#e5534b")}
const KIND_ACCENT := {"object": "#f2a33c", "folk": "#ee86a6", "self": "#3fb8af", "ground": "#5bb8ff", "door": "#c98f5b"}
## Which groups stay open between openings (the player's choice persists).
static var open_cats: Dictionary = {"Friendly": true}

var panel: PanelContainer
var box: VBoxContainer
var folk = null
var target_kind := ""
var target_id := -1
var entry_buttons: Array = []
var category_headers: Dictionary = {}    # group -> header Button
var category_boxes: Dictionary = {}      # group -> VBoxContainer holding that group's buttons
var scroll: ScrollContainer = null
var _list: VBoxContainer = null           # where the entries go (inside `scroll`)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	panel = PanelContainer.new()
	add_child(panel)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		close()
		accept_event()

func _unhandled_key_input(ev: InputEvent) -> void:
	if visible and ev is InputEventKey and ev.pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func open_for(f, kind: String, id: int, screen_pos: Vector2) -> void:
	open_with_entries(f, kind, id, InteractionQuery.entries_for(f, kind, id), screen_pos)

## `entries`: [{id, label, category, enabled, reason}] and optionally {action: Callable} (run instead of queueing an interaction).
func open_with_entries(f, kind: String, id: int, entries: Array, screen_pos: Vector2) -> void:
	folk = f
	target_kind = kind
	target_id = id
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	entry_buttons.clear()
	category_headers.clear()
	category_boxes.clear()
	scroll = null
	_list = null
	UIIdentity.skin(panel, str(KIND_ACCENT.get(kind, "#f2a33c")), "band", 10)
	var target = UIU.get_folk(id) if kind == "folk" else null
	var title_text := "What now?"
	var object_def := ""
	match kind:
		"object":
			title_text = PieEntries.object_title(id)
			var o = WorldIface.get_object(id)
			object_def = str(UIU.prop(o, "def_id", "")) if o != null else ""
		"folk":
			title_text = "Interact"
			if target != null:
				title_text = str(UIU.prop(target, "name", "them"))          # the menu shows the person, never how well you know them
		"self":
			title_text = "Myself"
		"ground":
			title_text = "Here"
		"door":
			title_text = "The front door"
	box.add_child(UIU.make_label(title_text, 16, Color(str(KIND_ACCENT.get(kind, "#f2a33c"))).lightened(0.3)))
	if kind == "folk" and target != null:
		_fill_social(f, target, entries)
	else:
		_fill_compact(PieEntries.curate(entries, object_def if kind == "object" else kind))
	visible = true
	if get_parent() != null:
		get_parent().move_child(self, -1)          # on top of the tips, the checklist and every other panel
	panel.reset_size()
	await get_tree().process_frame
	_place(screen_pos)

func _place(screen_pos: Vector2) -> void:
	panel.reset_size()
	var vp := get_viewport_rect().size
	panel.position = Vector2(clampf(screen_pos.x + 8, 8, maxf(vp.x - panel.size.x - 8, 8)), clampf(screen_pos.y - 12, 62, maxf(vp.y - panel.size.y - 8, 62)))

func _scroll_list() -> VBoxContainer:
	if _list != null:
		return _list
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(240, 0)
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_list)
	return _list

func _fit_scroll() -> void:
	if scroll == null:
		return
	var vp_h: float = get_viewport_rect().size.y
	scroll.custom_minimum_size = Vector2(240, minf(_list.get_combined_minimum_size().y + 4.0, minf(vp_h * 0.62, 520.0)))

func _make_button(e: Dictionary, reason: String = "") -> Button:
	var b := Button.new()
	b.text = e["label"]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(230, 30)
	b.disabled = not e["enabled"]
	if not e["enabled"]:
		b.tooltip_text = reason
		b.mouse_filter = Control.MOUSE_FILTER_STOP   # keep tooltips on disabled buttons
	var did: String = e["id"]
	b.name = "btn_" + did
	if e.has("action") and (e["action"] as Callable).is_valid():
		var act: Callable = e["action"]
		b.pressed.connect(func():
			close()
			act.call())
	else:
		b.pressed.connect(func(): _choose(did))
	entry_buttons.append(b)
	return b

func _group_button(parent: Control, name: String, entries: Array, col: Color) -> void:
	var header := Button.new()
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.name = "cat_" + name
	header.add_theme_color_override("font_color", col)
	header.add_theme_color_override("font_hover_color", col.lightened(0.3))
	parent.add_child(header)
	category_headers[name] = header
	var sect := VBoxContainer.new()
	sect.add_theme_constant_override("separation", 2)
	sect.visible = bool(open_cats.get(name, false))
	parent.add_child(sect)
	category_boxes[name] = sect
	for e in entries:
		sect.add_child(_make_button(e))
	_set_header_text(header, name, entries.size(), sect.visible)
	header.pressed.connect(func(): _toggle_category(name, header, sect, entries.size()))

## The curated list: main actions, then the groups, then (only when there is little to do) a short note on what is out of reach.
func _fill_compact(cur: Dictionary) -> void:
	var main: Array = cur["main"]
	var groups: Array = cur["groups"]
	if main.is_empty() and groups.is_empty():
		box.add_child(UIU.make_label("Nothing to do here right now.", 14))
		for b in cur["blocked"]:
			box.add_child(UIU.make_label("%s: %s" % [b["label"], str(b["reason"]).to_lower()], 12, UITheme.MUTED))
		return
	var list := _scroll_list()
	for e in main:
		list.add_child(_make_button(e))
	for g in groups:
		_group_button(list, str(g["name"]), g["entries"], Color(str(KIND_ACCENT.get(target_kind, "#f2a33c"))).lightened(0.2))
	_fit_scroll()

func _fill_social(f, target, entries: Array) -> void:
	var cats: Dictionary = {}
	var blocked: Array = []
	for e0 in entries:
		var e: Dictionary = (e0 as Dictionary).duplicate()
		var reason: String = str(e["reason"])
		# the social engine knows more than the plain tests (knowledge, relationship stage...): always ask it
		var specific: String = SocialDynamics.reason_unavailable(f, target, str(e["id"]), false)
		if specific != "":
			e["enabled"] = false
			reason = PieEntries.polish_reason(specific)
		elif not e["enabled"] and str(e["reason"]) == "":
			reason = "Unavailable right now"
		else:
			reason = PieEntries.polish_reason(reason)
		if not e["enabled"]:
			if not PieEntries.is_never(reason) and blocked.size() < 4:
				blocked.append({"label": str(e["label"]), "reason": reason})
			continue
		var c: String = str(e["category"])
		if not cats.has(c):
			cats[c] = []
		if str(e["id"]) == "talk_interests":          # "Talk about fishing": one entry per interest you have learned, nothing until you know one
			for topic in RelationshipKnowledge.known_interests(int(UIU.prop(f, "id", -1)), int(UIU.prop(target, "id", -1))):
				var te: Dictionary = e.duplicate()
				te["label"] = "Talk about %s" % UIU.sentence(str(topic)).to_lower()
				var tp: String = str(topic)
				var fid0: int = int(UIU.prop(f, "id", -1))
				var tgt0: int = int(UIU.prop(target, "id", -1))
				te["action"] = func():
					Conversation.active_topic[fid0] = tp
					UIU.enqueue(f, "talk_interests", tgt0)
				te["id"] = "talk_interests_" + tp
				(cats[c] as Array).append(te)
			continue
		(cats[c] as Array).append(e)
	if cats.is_empty():
		box.add_child(UIU.make_label("Nothing to do with them right now.", 14))
		for b in blocked:
			box.add_child(UIU.make_label("%s: %s" % [b["label"], str(b["reason"]).to_lower()], 12, UITheme.MUTED))
		return
	var order: Array = []
	for c in SOCIAL_ORDER:
		if cats.has(c):
			order.append(c)
	var rest: Array = []
	for c2 in cats:
		if not order.has(c2):
			rest.append(c2)
	rest.sort()
	order.append_array(rest)
	var list := _scroll_list()
	var shown_recent := 0
	for rid in PieEntries.recent:
		for c4 in order:
			for e4 in cats[c4]:
				if str(e4["id"]) == str(rid) and shown_recent < 3:
					var rb := _make_button(e4)
					rb.name = "recent_" + str(rid)
					entry_buttons.pop_back()    # shortcuts, not extra entries
					list.add_child(rb)
					shown_recent += 1
	for c3 in order:
		_group_button(list, str(c3), cats[c3], CAT_COLORS.get(c3, UITheme.ACCENT))
	_fit_scroll()

func _set_header_text(header: Button, cat: String, n: int, is_open: bool) -> void:
	header.text = "%s %s  (%d)" % ["▾" if is_open else "▸", cat, n]

func _toggle_category(cat: String, header: Button, sect: Control, n: int) -> void:
	var now_open := not sect.visible
	sect.visible = now_open
	open_cats[cat] = now_open
	_set_header_text(header, cat, n, now_open)
	_fit_scroll()
	panel.reset_size()

func set_category_open(cat: String, is_open: bool) -> void:
	if category_boxes.has(cat):
		(category_boxes[cat] as Control).visible = is_open
		open_cats[cat] = is_open
		var header: Button = category_headers[cat]
		var txt := header.text
		header.text = ("▾" if is_open else "▸") + txt.substr(1)
		_fit_scroll()
		panel.reset_size()

func _choose(def_id: String) -> void:
	PieEntries.remember(def_id)
	UIU.enqueue(folk, def_id, target_id)
	chosen.emit(def_id, target_id)
	close()

func close() -> void:
	visible = false
