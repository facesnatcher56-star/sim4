class_name PieMenu
extends Control
## Popup interaction menu (grouped list). Full-rect click catcher closes it.
## Objects get a flat grouped list. Folk targets (social menu) get collapsible category sections - Friendly / Funny / Romantic /
## Deep / Group / Mean / ... - inside a scroll area, with a specific reason on every disabled entry (SocialDynamics.reason_unavailable).
signal chosen(def_id: String, target_id: int)

const SOCIAL_ORDER := ["Friendly", "Funny", "Romantic", "Deep", "Group", "Mean"]
const CAT_COLORS := {"Friendly": Color("#4cc78a"), "Funny": Color("#f2c94c"), "Romantic": Color("#ee86a6"), "Deep": Color("#35a7b0"),
	"Group": Color("#8f6bf0"), "Mean": Color("#e5534b")}
## Which social sections stay expanded between openings (player's choice persists).
static var open_cats: Dictionary = {"Friendly": true}

var panel: PanelContainer
var box: VBoxContainer
var folk = null
var target_kind := ""
var target_id := -1
var entry_buttons: Array = []
var category_headers: Dictionary = {}    # category -> header Button (folk menu)
var category_boxes: Dictionary = {}      # category -> VBoxContainer holding that section's buttons
var scroll: ScrollContainer = null

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

func open_for(f, kind: String, id: int, screen_pos: Vector2) -> void:
	open_with_entries(f, kind, id, InteractionQuery.entries_for(f, kind, id), screen_pos)

func open_with_entries(f, kind: String, id: int, entries: Array, screen_pos: Vector2) -> void:
	folk = f
	target_kind = kind
	target_id = id
	for c in box.get_children():
		c.queue_free()
	entry_buttons.clear()
	category_headers.clear()
	category_boxes.clear()
	scroll = null
	var target = UIU.get_folk(id) if kind == "folk" else null
	entries = PieEntries.prepare(entries)
	var title_text := PieEntries.object_title(id) if kind == "object" else "Interact"
	if target != null:
		title_text = "Interact with %s" % str(UIU.prop(target, "name", "them"))
		var bit := RelationshipService.bit_for(int(UIU.prop(f, "id", -1)), id)
		if bit != "stranger":
			title_text += "  (%s)" % RelationshipService.bit_label(bit)
	var title := UIU.make_label(title_text, 13, UITheme.MUTED)
	box.add_child(title)
	if entries.is_empty():
		box.add_child(UIU.make_label("Nothing they can do here right now.", 14))
	if kind == "folk" and target != null and not entries.is_empty():
		_fill_social(f, target, entries)
	else:
		_fill_flat(entries)
	visible = true
	panel.reset_size()
	await get_tree().process_frame
	var vp := get_viewport_rect().size
	panel.position = Vector2(clampf(screen_pos.x - 20, 0, vp.x - panel.size.x), clampf(screen_pos.y - 20, 0, vp.y - panel.size.y))

func _make_button(e: Dictionary, reason: String) -> Button:
	var b := Button.new()
	b.text = e["label"]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(190, 28)
	b.disabled = not e["enabled"]
	if not e["enabled"]:
		if reason != "":
			var short := reason if reason.length() <= 30 else reason.substr(0, 28) + "..."
			b.text = "%s  (%s)" % [e["label"], short.substr(0, 1).to_lower() + short.substr(1)]
		b.tooltip_text = reason
		b.mouse_filter = Control.MOUSE_FILTER_STOP   # keep tooltips on disabled buttons
	var did: String = e["id"]
	b.name = "btn_" + did
	b.pressed.connect(func(): _choose(did))
	entry_buttons.append(b)
	return b

func _fill_flat(entries: Array) -> void:
	var last_cat := ""
	var headers := entries.size() > 7     # short menus need no group titles
	var recent_n := 0
	for e in entries:
		if e["enabled"] and PieEntries.recent.has(str(e["id"])):
			recent_n += 1
	if recent_n > 0 and headers:
		box.add_child(UIU.make_label("RECENT", 11, UITheme.ACCENT))
	for e in entries:
		var is_recent: bool = recent_n > 0 and e["enabled"] and PieEntries.recent.has(str(e["id"]))
		if headers and not is_recent and e["category"] != last_cat:
			last_cat = e["category"]
			var h := UIU.make_label(last_cat.to_upper(), 11, UITheme.ACCENT)
			box.add_child(h)
		box.add_child(_make_button(e, str(e["reason"])))

func _fill_social(f, target, entries: Array) -> void:
	var cats: Dictionary = {}
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
		if not e["enabled"] and PieEntries.is_never(reason):
			continue
		var c: String = str(e["category"])
		if not cats.has(c):
			cats[c] = []
		(cats[c] as Array).append({"e": e, "reason": reason})
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
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vp_h: float = get_viewport_rect().size.y if is_inside_tree() else 720.0
	scroll.custom_minimum_size = Vector2(230, minf(vp_h * 0.68, 520.0))
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	var shown_recent := 0
	for rid in PieEntries.recent:
		for c4 in order:
			for it4 in cats[c4]:
				if str(it4["e"]["id"]) == str(rid) and it4["e"]["enabled"] and shown_recent < 3:
					if shown_recent == 0:
						list.add_child(UIU.make_label("RECENT", 11, UITheme.ACCENT))
					var rb := _make_button(it4["e"], "")
					rb.name = "recent_" + str(rid)
					entry_buttons.pop_back()    # shortcuts, not extra entries
					list.add_child(rb)
					shown_recent += 1
	for c3 in order:
		var items: Array = cats[c3]
		var enabled_n := 0
		for it in items:
			if it["e"]["enabled"]:
				enabled_n += 1
		var is_open: bool = bool(open_cats.get(c3, false))
		var header := Button.new()
		header.flat = true
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.name = "cat_" + str(c3)
		var col: Color = CAT_COLORS.get(c3, UITheme.ACCENT)
		header.add_theme_color_override("font_color", col)
		header.add_theme_color_override("font_hover_color", col.lightened(0.3))
		list.add_child(header)
		category_headers[c3] = header
		var sect := VBoxContainer.new()
		sect.add_theme_constant_override("separation", 2)
		sect.visible = is_open
		list.add_child(sect)
		category_boxes[c3] = sect
		for it2 in items:
			sect.add_child(_make_button(it2["e"], str(it2["reason"])))
		_set_header_text(header, str(c3), enabled_n, items.size(), is_open)
		header.pressed.connect(func(): _toggle_category(str(c3), header, sect, enabled_n, items.size()))

func _set_header_text(header: Button, cat: String, enabled_n: int, total: int, is_open: bool) -> void:
	header.text = "%s %s   %d/%d" % ["▾" if is_open else "▸", cat.to_upper(), enabled_n, total]

func _toggle_category(cat: String, header: Button, sect: Control, enabled_n: int, total: int) -> void:
	var now_open := not sect.visible
	sect.visible = now_open
	open_cats[cat] = now_open
	_set_header_text(header, cat, enabled_n, total, now_open)
	panel.reset_size()

func set_category_open(cat: String, is_open: bool) -> void:
	if category_boxes.has(cat):
		(category_boxes[cat] as Control).visible = is_open
		open_cats[cat] = is_open
		var header: Button = category_headers[cat]
		var txt := header.text
		header.text = ("▾" if is_open else "▸") + txt.substr(1)
		panel.reset_size()

func _choose(def_id: String) -> void:
	PieEntries.remember(def_id)
	UIU.enqueue(folk, def_id, target_id)
	chosen.emit(def_id, target_id)
	close()

func close() -> void:
	visible = false
