class_name PieMenu
extends Control
## Popup interaction menu (grouped list). Full-rect click catcher closes it.
signal chosen(def_id: String, target_id: int)

var panel: PanelContainer
var box: VBoxContainer
var folk = null
var target_kind := ""
var target_id := -1
var entry_buttons: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
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
	var title := UIU.make_label("Interact", 13, UITheme.MUTED)
	box.add_child(title)
	if entries.is_empty():
		box.add_child(UIU.make_label("Nothing to do here.", 14))
	var last_cat := ""
	for e in entries:
		if e["category"] != last_cat:
			last_cat = e["category"]
			var h := UIU.make_label(last_cat.to_upper(), 11, UITheme.ACCENT)
			box.add_child(h)
		var b := Button.new()
		b.text = e["label"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(190, 28)
		b.disabled = not e["enabled"]
		if not e["enabled"]:
			b.tooltip_text = e["reason"]
			b.mouse_filter = Control.MOUSE_FILTER_STOP   # keep tooltips on disabled buttons
		var did: String = e["id"]
		b.pressed.connect(func(): _choose(did))
		box.add_child(b)
		entry_buttons.append(b)
	visible = true
	panel.reset_size()
	await get_tree().process_frame
	var vp := get_viewport_rect().size
	panel.position = Vector2(clampf(screen_pos.x - 20, 0, vp.x - panel.size.x), clampf(screen_pos.y - 20, 0, vp.y - panel.size.y))

func _choose(def_id: String) -> void:
	UIU.enqueue(folk, def_id, target_id)
	chosen.emit(def_id, target_id)
	close()

func close() -> void:
	visible = false
