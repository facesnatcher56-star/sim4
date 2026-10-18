class_name SettingsDialog
extends UIDialog
## Settings window (title screen "Settings", pause menu "Settings"). Rows are generated from GameSettings.DEFS;
## the Controls tab lists SettingsKeys.ACTIONS with click-to-rebind. Changes apply and save immediately.
signal closed
const REVERT_SECONDS := 15.0
const LABEL_W := 230.0

var tab := "display"
var capturing := ""                     # action waiting for a key press
var confirm: ConfirmDialog = null
var note: Label = null
var _tab_buttons: Dictionary = {}

func _ready() -> void:
	dialog_width = 640.0
	super._ready()
	add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.PANEL, 1.0), 10, Color(1, 1, 1, 0.12), 1, 10))      # opaque: on the title screen it would show the menu behind

func build() -> void:
	title_label.text = "Settings"
	capturing = ""
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	body.add_child(tabs)
	_tab_buttons.clear()
	for t in GameSettings.TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.button_pressed = (t[0] == tab)
		b.tooltip_text = "%s settings" % t[1]
		b.pressed.connect(show_tab.bind(t[0]))
		tabs.add_child(b)
		_tab_buttons[t[0]] = b
	if tab == "controls":
		_build_controls()
	else:
		for d in GameSettings.defs_for(tab):
			_add_row(d)
		_build_extras()
	note = line("", 13, UITheme.MUTED)
	var reset := Button.new()
	reset.name = "ResetBtn"
	reset.text = "Reset this tab to defaults"
	reset.tooltip_text = "Puts every setting on this tab back to how the game ships"
	reset.pressed.connect(func():
		GameSettings.reset_tab(tab)
		refresh())
	body.add_child(reset)
	if tab == "audio":
		line("There is no music or sound in the game yet. These sliders already control the audio buses, so sound added later just works.", 12, UITheme.MUTED)

func show_tab(t: String) -> void:
	tab = t
	refresh()
	call_deferred("_center")

func _center() -> void:
	# fixed height so switching tabs does not make the window jump
	var max_h := clampf(get_viewport_rect().size.y - 150.0, 160.0, 560.0)
	_scroll.custom_minimum_size = Vector2(0, max_h)
	reset_size()
	var vp := get_viewport_rect().size
	position = ((vp - size) / 2.0).floor()
	position.y = maxf(position.y, 56.0)

func hide_dialog() -> void:
	if not visible:
		return
	GameSettings.flush()
	capturing = ""
	super.hide_dialog()
	closed.emit()

# ------------------------------------------------------------ rows
func _row(label: String, tip: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.tooltip_text = tip
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var l := UIU.make_label(label, 14)
	l.custom_minimum_size = Vector2(LABEL_W, 0)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(l)
	body.add_child(row)
	return row

func _add_row(d: Dictionary) -> void:
	var row := _row(str(d["label"]), str(d["tip"]))
	var key: String = d["k"]
	var ctl: Control
	match str(d["t"]):
		"bool":
			var cb := CheckButton.new()
			cb.name = key
			cb.button_pressed = GameSettings.get_bool(key)
			cb.text = "On" if cb.button_pressed else "Off"
			cb.toggled.connect(func(on):
				cb.text = "On" if on else "Off"
				GameSettings.set_value(key, on))
			ctl = cb
		"range":
			ctl = _slider(d)
		_:
			ctl = _option(d)
	ctl.tooltip_text = str(d["tip"])
	row.add_child(ctl)

func _slider(d: Dictionary) -> Control:
	var key: String = d["k"]
	var box := HBoxContainer.new()
	box.name = key
	var s := HSlider.new()
	s.min_value = float(d["min"])
	s.max_value = float(d["max"])
	s.step = float(d["step"])
	s.value = GameSettings.get_float(key)
	s.custom_minimum_size = Vector2(190, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.tooltip_text = str(d["tip"])
	var val := UIU.make_label("", 14, UITheme.ACCENT)
	val.custom_minimum_size = Vector2(80, 0)
	var fmt := func(v: float): val.text = (("%.1f" % v) if d["def"] is float else ("%d" % int(v))) + str(d["unit"])
	fmt.call(s.value)
	s.value_changed.connect(func(v: float):
		fmt.call(v)
		GameSettings.set_value(key, v, false))
	s.drag_ended.connect(func(_c): GameSettings.flush())
	box.add_child(s)
	box.add_child(val)
	return box

func _option(d: Dictionary) -> Control:
	var key: String = d["k"]
	var ob := OptionButton.new()
	ob.name = key
	ob.custom_minimum_size = Vector2(210, 0)
	var opts: Array = SettingsApply.resolution_options() if key == "resolution" else d["opts"]
	var cur = GameSettings.get_value(key)
	for o in opts:
		ob.add_item(str(o[1]))
		ob.set_item_metadata(ob.item_count - 1, o[0])
		if o[0] == cur:
			ob.select(ob.item_count - 1)
	ob.item_selected.connect(func(i: int): _picked(key, ob.get_item_metadata(i)))
	return ob

## Window mode / size changes ask "keep these settings?" and go back on No or after 15 s.
func _picked(key: String, v) -> void:
	if key != "window_mode" and key != "resolution":
		GameSettings.set_value(key, v)
		return
	var old_mode := GameSettings.get_int("window_mode")
	var old_res := GameSettings.get_str("resolution")
	GameSettings.set_value(key, v)
	if SettingsApply.headless():
		return
	if confirm == null:
		confirm = ConfirmDialog.new()
		get_parent().add_child(confirm)
	confirm.ask("Keep these display settings?", "The screen changed. If you cannot see this or do not want it, pick No (it reverts by itself).",
		"Keep", Callable(), "Revert", func():
			GameSettings.set_value("window_mode", old_mode)
			GameSettings.set_value("resolution", old_res)
			if visible:
				refresh(), REVERT_SECONDS)

func _build_extras() -> void:
	if tab == "gameplay":
		var b := Button.new()
		b.text = "Show the welcome tips again"
		b.tooltip_text = "The short first-run tips will appear the next time you start or load a game"
		b.pressed.connect(func():
			UIPrefs.set_flag("tips_seen", false)
			note.text = "Welcome tips will show when you next start or load a game.")
		body.add_child(b)

# ------------------------------------------------------------ controls
func _build_controls() -> void:
	line("Click a key to change it. Esc cancels. A key that is already used moves to the new action. Fixed keys: Esc (menu / close), ? (help).", 12, UITheme.MUTED)
	var group := ""
	for a in SettingsKeys.ACTIONS:
		if a[2] != group:
			group = a[2]
			heading(group)
		var row := _row(str(a[1]), "Click, then press the new key")
		var b := Button.new()
		b.name = a[0]
		b.text = SettingsKeys.binding_text(a[0])
		b.custom_minimum_size = Vector2(190, 0)
		b.tooltip_text = "Click, then press the new key (Esc cancels)"
		b.pressed.connect(_start_capture.bind(a[0], b))
		row.add_child(b)

func _start_capture(action: String, b: Button) -> void:
	capturing = action
	b.text = "Press a key..."

func _input(ev: InputEvent) -> void:
	if capturing == "" or not visible:
		return
	var bound := false
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_ESCAPE:
			capturing = ""
			refresh()
			get_viewport().set_input_as_handled()
			return
		if ev.keycode in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META]:
			return
		bound = true
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index > MOUSE_BUTTON_RIGHT:
		bound = true
	if not bound:
		return
	get_viewport().set_input_as_handled()
	var act := capturing
	capturing = ""
	var other := SettingsKeys.rebind(act, ev)
	GameSettings.flush()
	refresh()
	if other != "" and note != null:
		note.text = "%s was using that key and is now unbound." % other.trim_prefix("sim_").replace("_", " ").capitalize()

func _unhandled_input(ev: InputEvent) -> void:
	if visible and ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		hide_dialog()
