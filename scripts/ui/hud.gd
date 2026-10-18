class_name Hud
extends Control
## Root of the in-game HUD. Everything is built in code so the scene stays trivial.
signal save_requested(slot: int)
signal load_requested(slot: int)
signal quit_to_title

var lot_view = null
var theme_res: Theme
var top_bar: PanelContainer
var time_label: Label
var day_label: Label
var coins_label: Label
var speed_buttons: Dictionary = {}     # speed int -> Button
var build_button: Button
var save_button: Button
var folk_panel: FolkPanel
var queue_bar: QueueBar
var pie: PieMenu
var thoughts: ThoughtLayer
var toasts: ToastFeed
var build_panel: BuildPanel
var folk_row: HBoxContainer
var save_menu: PanelContainer
var selected_folk_id := -1
var selected_object_id := -1
var coins := 0
var household_name := "Household"
var prev_speed := 1
var folk_resolver: Callable = Callable()
var _ctx_handled := false
var _pending_tile := Vector2i(-1, -1)

func _ready() -> void:
	theme_res = UITheme.build()
	theme = theme_res
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_left()
	thoughts = ThoughtLayer.new()
	add_child(thoughts)
	toasts = ToastFeed.new()
	toasts.anchor_left = 1.0
	toasts.anchor_right = 1.0
	toasts.offset_left = -300
	toasts.offset_right = -12
	toasts.offset_top = 64
	add_child(toasts)
	build_panel = BuildPanel.new()
	build_panel.anchor_left = 1.0
	build_panel.anchor_right = 1.0
	build_panel.anchor_top = 0.0
	build_panel.anchor_bottom = 1.0
	build_panel.offset_left = -324
	build_panel.offset_right = -12
	build_panel.offset_top = 64
	build_panel.offset_bottom = -12
	build_panel.mode_changed.connect(_on_build_mode)
	add_child(build_panel)
	pie = PieMenu.new()
	add_child(pie)
	_build_save_menu()
	UIU.connect_ev("selection_changed", _on_selection_changed)
	UIU.connect_ev("coins_changed", _on_coins_changed)
	UIU.connect_ev("folk_added", func(_i): rebuild_folk_row())
	UIU.connect_ev("folk_removed", func(_i): rebuild_folk_row())
	UIU.connect_ev("game_event", func(n, _p): if n in ["left_for_work", "returned_from_work", "left_for_school", "returned_from_school", "left_lot", "returned_to_lot", "moved_in", "moved_out", "adopted", "married", "divorced"]: rebuild_folk_row())
	if Clock.has_signal("minute_passed"):
		Clock.connect("minute_passed", _update_clock)
	_update_clock()
	_update_speed_buttons()

func _process(_d: float) -> void:
	# Cheap poll keeps speed highlight right even if something else changes Clock.speed.
	if not build_panel.active:
		_update_speed_buttons()

# ------------------------------------------------------------ construction
func _build_top_bar() -> void:
	top_bar = PanelContainer.new()
	top_bar.anchor_right = 1.0
	top_bar.offset_left = 8
	top_bar.offset_right = -8
	top_bar.offset_top = 8
	add_child(top_bar)
	var h := HBoxContainer.new()
	top_bar.add_child(h)
	day_label = UIU.make_label("Day 1", 18)
	h.add_child(day_label)
	time_label = UIU.make_label("--:--", 18, UITheme.ACCENT)
	time_label.custom_minimum_size = Vector2(70, 0)
	h.add_child(time_label)
	h.add_child(VSeparator.new())
	for s in [[0, "||"], [1, ">"], [2, ">>"], [3, ">>>"]]:
		var b := Button.new()
		b.text = s[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(44, 0)
		b.tooltip_text = "Pause (Space)" if s[0] == 0 else "Speed %dx (%d)" % [s[0], s[0]]
		b.pressed.connect(set_speed.bind(s[0]))
		h.add_child(b)
		speed_buttons[s[0]] = b
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	coins_label = UIU.make_label("0 Coins", 18, Color("#f2c94c"))
	h.add_child(coins_label)
	build_button = Button.new()
	build_button.text = "Build/Buy"
	build_button.toggle_mode = true
	build_button.tooltip_text = "Toggle Build/Buy mode (B)"
	build_button.pressed.connect(func(): build_panel.set_active(build_button.button_pressed))
	h.add_child(build_button)
	save_button = Button.new()
	save_button.text = "Save/Load"
	save_button.pressed.connect(func(): save_menu.visible = not save_menu.visible)
	h.add_child(save_button)

func _build_left() -> void:
	var left := VBoxContainer.new()
	left.anchor_top = 1.0
	left.anchor_bottom = 1.0
	left.offset_left = 12
	left.offset_bottom = -12
	left.grow_vertical = Control.GROW_DIRECTION_BEGIN
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	folk_row = HBoxContainer.new()
	left.add_child(folk_row)
	queue_bar = QueueBar.new()
	left.add_child(queue_bar)
	folk_panel = FolkPanel.new()
	left.add_child(folk_panel)

func _build_save_menu() -> void:
	save_menu = PanelContainer.new()
	save_menu.visible = false
	save_menu.anchor_left = 0.5
	save_menu.anchor_right = 0.5
	save_menu.anchor_top = 0.5
	save_menu.anchor_bottom = 0.5
	save_menu.offset_left = -200
	save_menu.offset_right = 200
	save_menu.offset_top = -140
	save_menu.offset_bottom = 140
	add_child(save_menu)
	var v := VBoxContainer.new()
	save_menu.add_child(v)
	v.add_child(UIU.make_label("Save / Load", 20))
	for i in range(1, SaveSlots.SLOTS + 1):
		var row := HBoxContainer.new()
		v.add_child(row)
		var lab := UIU.make_label("Slot %d: %s" % [i, SaveSlots.slot_summary(i)], 14)
		lab.name = "SlotLabel%d" % i
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lab)
		var sb := Button.new()
		sb.text = "Save"
		sb.pressed.connect(func(): do_save(i, lab))
		row.add_child(sb)
		var lb := Button.new()
		lb.text = "Load"
		lb.pressed.connect(func():
			save_menu.visible = false
			load_requested.emit(i))
		row.add_child(lb)
	var hb := HBoxContainer.new()
	v.add_child(hb)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): save_menu.visible = false)
	hb.add_child(close)
	var qt := Button.new()
	qt.text = "Quit to Title"
	qt.pressed.connect(func():
		save_menu.visible = false
		quit_to_title.emit())
	hb.add_child(qt)

func do_save(slot: int, lab: Label = null) -> bool:
	var ok := SaveSlots.save(slot, household_name)
	if lab:
		lab.text = "Slot %d: %s" % [slot, SaveSlots.slot_summary(slot)]
	UIU.notify("Game saved (slot %d)" % slot if ok else "Save failed", "good" if ok else "bad")
	save_requested.emit(slot)
	return ok

# ------------------------------------------------------------ wiring
func set_lot_view(lv) -> void:
	lot_view = lv
	thoughts.lot_view = lv
	build_panel.lot_view = lv
	if lv != null and lv.has_signal("tile_clicked"):
		lv.tile_clicked.connect(_on_tile_clicked)
		lv.context_requested.connect(_on_context_requested)

func _resolve(id: int):
	if folk_resolver.is_valid():
		return folk_resolver.call(id)
	return UIU.get_folk(id)

func select_folk(id: int) -> void:
	selected_folk_id = id
	var f = _resolve(id)
	folk_panel.show_folk(f)
	queue_bar.set_folk(f)
	rebuild_folk_row()

func rebuild_folk_row() -> void:
	for c in folk_row.get_children():
		c.queue_free()
	if not World.has_method("all_folk"):
		return
	for f in World.all_folk():
		if f.has_meta("visitor") or f.has_meta("away"):
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(46, 46)
		b.tooltip_text = str(f.name)
		b.toggle_mode = true
		b.button_pressed = (f.id == selected_folk_id)
		var fi := FaceIcon.new()
		fi.color = FolkPanel.portrait_color(f)
		fi.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.add_child(fi)
		var fid: int = f.id
		b.pressed.connect(func(): select_folk(fid))
		folk_row.add_child(b)

func _on_selection_changed(kind: String, id: int) -> void:
	if build_panel.active:
		return
	match kind:
		"folk":
			var cur = _resolve(selected_folk_id)
			var other = _resolve(id)
			var same_house: bool = cur == null or other == null or id == selected_folk_id \
				or UIU.prop(cur, "household_id", 0) == UIU.prop(other, "household_id", 0)
			if same_house:
				select_folk(id)
			else:
				pie.open_for(cur, "folk", id, get_viewport().get_mouse_position())
		"object":
			selected_object_id = id
			var f = _resolve(selected_folk_id)
			if f != null:
				pie.open_for(f, "object", id, get_viewport().get_mouse_position())
		_:
			selected_object_id = -1
			pie.close()

func _on_coins_changed(_hh: int, amount: int) -> void:
	coins = amount
	coins_label.text = "%d Coins" % amount

# ------------------------------------------------------------ time
func _update_clock(_t = 0) -> void:
	time_label.text = UIU.clock_text()
	day_label.text = "Day %d" % UIU.day_number()

func set_speed(s: int) -> void:
	if build_panel.active:
		return
	UIU.set_speed(s)
	_update_speed_buttons()

func _update_speed_buttons() -> void:
	var cur := UIU.get_speed()
	for k in speed_buttons:
		speed_buttons[k].button_pressed = (k == cur)
		speed_buttons[k].disabled = build_panel != null and build_panel.active

func _on_build_mode(on: bool) -> void:
	build_button.set_pressed_no_signal(on)
	pie.close()
	if on:
		prev_speed = maxi(UIU.get_speed(), 1)
		UIU.set_speed(0)
	else:
		UIU.set_speed(prev_speed)
	folk_panel.visible = not on
	queue_bar.visible = not on
	_update_speed_buttons()

# ------------------------------------------------------------ input
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_SPACE:
				if not build_panel.active:
					set_speed(0 if UIU.get_speed() != 0 else maxi(prev_speed, 1))
			KEY_1: set_speed(1)
			KEY_2: set_speed(2)
			KEY_3: set_speed(3)
			KEY_B: build_panel.set_active(not build_panel.active)
			KEY_TAB: if lot_view: lot_view.call("cycle_wall_mode")
			KEY_ESCAPE:
				if pie.visible: pie.close()
		if UIU.get_speed() != 0:
			prev_speed = UIU.get_speed()

func _on_tile_clicked(tile: Vector2i, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT and not build_panel.active:
		_ctx_handled = false
		_pending_tile = tile
		call_deferred("_maybe_go_here")

func _on_context_requested(_kind: String, _id: int, _tile: Vector2i) -> void:
	_ctx_handled = true

func _maybe_go_here() -> void:
	if not _ctx_handled:
		go_here(_pending_tile)

## Right-click on bare ground: send the selected folk there.
func go_here(tile: Vector2i) -> bool:
	var f = _resolve(selected_folk_id)
	if f == null or tile.x < 0:
		return false
	return UIU.enqueue(f, "go_here", -1, {"tile": tile})
