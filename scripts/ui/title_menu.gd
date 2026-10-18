class_name TitleMenu
extends Control
## Title screen: New Game (opens the StartPicker), Continue, Load, Settings, Quit.
signal new_game_requested
signal continue_game(slot: int)
signal quit_game

var main_box: VBoxContainer
var continue_btn: Button
var load_btn: Button
var load_box: VBoxContainer
var settings_dialog: SettingsDialog

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(UITheme.BG, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var root := VBoxContainer.new()
	panel.add_child(root)
	main_box = VBoxContainer.new()
	main_box.custom_minimum_size = Vector2(320, 0)
	root.add_child(main_box)
	main_box.add_child(UIU.make_label("sim-4", 44, UITheme.ACCENT))
	main_box.add_child(UIU.make_label("a tiny life simulation", 14, UITheme.MUTED))
	var nb := Button.new()
	nb.text = "New Game"
	nb.custom_minimum_size = Vector2(0, 40)
	nb.pressed.connect(func(): new_game_requested.emit())
	main_box.add_child(nb)
	continue_btn = Button.new()
	continue_btn.text = "Continue"
	continue_btn.tooltip_text = "Jump back into your most recent save"
	continue_btn.custom_minimum_size = Vector2(0, 40)
	continue_btn.pressed.connect(_continue)
	main_box.add_child(continue_btn)
	load_btn = Button.new()
	load_btn.text = "Load Game..."
	load_btn.tooltip_text = "Pick one of your save slots"
	load_btn.custom_minimum_size = Vector2(0, 40)
	load_btn.pressed.connect(show_load)
	main_box.add_child(load_btn)
	var sb := Button.new()
	sb.text = "Settings"
	sb.tooltip_text = "Display, gameplay, accessibility, audio and controls"
	sb.custom_minimum_size = Vector2(0, 40)
	sb.pressed.connect(func(): settings_dialog.show_for(-1))
	main_box.add_child(sb)
	var qb := Button.new()
	qb.text = "Quit"
	qb.custom_minimum_size = Vector2(0, 40)
	qb.pressed.connect(func(): quit_game.emit())
	main_box.add_child(qb)
	_build_load(root)
	settings_dialog = SettingsDialog.new()
	add_child(settings_dialog)
	refresh()

func refresh() -> void:
	continue_btn.disabled = not SaveSlots.has_any()
	load_btn.disabled = not SaveSlots.has_any()
	if load_box != null:
		_fill_load()

func show_main() -> void:
	load_box.visible = false
	main_box.visible = true

func _build_load(root: VBoxContainer) -> void:
	load_box = VBoxContainer.new()
	load_box.visible = false
	load_box.custom_minimum_size = Vector2(430, 0)
	root.add_child(load_box)

func _fill_load() -> void:
	for c in load_box.get_children():
		load_box.remove_child(c)
		c.queue_free()
	load_box.add_child(UIU.make_label("Load a game", 22))
	for i in range(1, SaveSlots.SLOTS + 1):
		var row := HBoxContainer.new()
		load_box.add_child(row)
		var lab := UIU.make_label("Slot %d: %s" % [i, SaveSlots.slot_summary(i)], 14)
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lab)
		var b := Button.new()
		b.text = "Load"
		b.disabled = not SaveSlots.can_load(i)
		var slot := i
		b.pressed.connect(func(): continue_game.emit(slot))
		row.add_child(b)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(show_main)
	load_box.add_child(back)

func show_load() -> void:
	_fill_load()
	main_box.visible = false
	load_box.visible = true

## Most recently written slot.
func newest_slot() -> int:
	var best := -1
	var best_t := -1
	for i in range(1, SaveSlots.SLOTS + 1):
		if SaveSlots.has_slot(i):
			var t := int(FileAccess.get_modified_time(SaveSlots.path(i)))
			if t > best_t:
				best_t = t
				best = i
	return best

func _continue() -> void:
	var slot := newest_slot()
	if slot > 0:
		continue_game.emit(slot)
