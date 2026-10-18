extends RefCounted
## Settings: defaults, save/load roundtrip, clamping, dialog controls, headless apply, reset, key rebinding. Convention: run() -> Array of failures.

const TMP := "user://settings_test.cfg"

func run() -> Array:
	var fails: Array = []
	var old_path := GameSettings.path
	var old_vals: Dictionary = GameSettings.values.duplicate()
	GameSettings.path = TMP
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	GameSettings.load_settings()

	# defaults
	for d in GameSettings.DEFS:
		if GameSettings.get_value(d["k"]) != d["def"]:
			fails.append("default differs for %s" % d["k"])
	if GameSettings.get_int("ui_scale") != 100 or not GameSettings.get_bool("pause_on_dialog") or not GameSettings.get_bool("autosave"):
		fails.append("unexpected core defaults")

	# clamping / validation
	if GameSettings.sanitize("ui_scale", 500) != 150: fails.append("ui_scale not clamped high")
	if GameSettings.sanitize("ui_scale", 3) != 80: fails.append("ui_scale not clamped low")
	if GameSettings.sanitize("ui_scale", 103) != 105: fails.append("ui_scale not snapped to step")
	if GameSettings.sanitize("ui_scale", "big") != 100: fails.append("bad type should fall back to default")
	if GameSettings.sanitize("aa", 99) != 1: fails.append("bad enum should fall back")
	if GameSettings.sanitize("mute", 1) != false: fails.append("non-bool should fall back")
	if GameSettings.sanitize("resolution", "garbage") != "auto": fails.append("bad resolution should fall back to default")
	if GameSettings.sanitize("resolution", "1600x900") != "1600x900": fails.append("good resolution rejected")
	if not (GameSettings.sanitize("tooltip_delay", 9.0) is float): fails.append("float setting lost its type")

	# roundtrip
	GameSettings.set_value("ui_scale", 125)
	GameSettings.set_value("shadows", 0)
	GameSettings.set_value("notif_bills", false)
	GameSettings.set_value("tooltip_delay", 0.9)
	var act: String = SettingsKeys.ACTIONS[0][0]
	var ev := InputEventKey.new()
	ev.keycode = KEY_I
	SettingsKeys.rebind(act, ev)
	GameSettings.flush()
	GameSettings.values = {}
	GameSettings.load_settings()
	if GameSettings.get_int("ui_scale") != 125 or GameSettings.get_int("shadows") != 0 or GameSettings.get_bool("notif_bills"):
		fails.append("roundtrip lost values")
	if absf(GameSettings.get_float("tooltip_delay") - 0.9) > 0.001: fails.append("float roundtrip")
	if SettingsKeys.binding_text(act) != "I": fails.append("rebind did not persist (got %s)" % SettingsKeys.binding_text(act))
	if not InputMap.has_action(act): fails.append("action missing from InputMap")

	# a corrupt file must not crash and must fall back
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("[settings]\nui_scale=\"wide\"\naa=77\n[keys]\nsim_pause=[\"nonsense\"]\n")
	f.close()
	GameSettings.load_settings()
	if GameSettings.get_int("ui_scale") != 100 or GameSettings.get_int("aa") != 1: fails.append("corrupt file did not fall back")
	if SettingsKeys.binding_text("sim_pause") != "Unbound" and SettingsKeys.binding_text("sim_pause") != "Space":
		fails.append("corrupt key binding gave %s" % SettingsKeys.binding_text("sim_pause"))
	if not InputMap.has_action("sim_pause"): fails.append("sim_pause missing")

	# rebinding swaps instead of double-binding
	GameSettings.load_settings()
	var e2 := InputEventKey.new()
	e2.keycode = KEY_B           # B is "sim_build"
	var displaced := SettingsKeys.rebind("sim_map", e2)
	if displaced != "sim_build": fails.append("rebind should displace sim_build, got '%s'" % displaced)

	# apply is safe (headless skips window calls) and notifies
	var seen := []
	var cb := func(k, _v): seen.append(k)
	GameSettings.bus.changed.connect(cb)
	SettingsApply.apply_all()
	GameSettings.set_value("master_vol", 40)
	GameSettings.set_value("mute", true)
	GameSettings.bus.changed.disconnect(cb)
	if not ("master_vol" in seen): fails.append("changed signal not emitted")
	if AudioServer.get_bus_index("Music") < 0 or AudioServer.get_bus_index("SFX") < 0: fails.append("Music / SFX buses missing")
	if not AudioServer.is_bus_mute(0): fails.append("mute not applied")
	GameSettings.set_value("mute", false)
	if GameSettings.notification_allowed("Bill due", "bill") == false and GameSettings.get_bool("notif_bills"): fails.append("bill notification blocked while on")
	GameSettings.set_value("notif_whims", false)
	if GameSettings.notification_allowed("Mira fulfilled a whim", "goal"): fails.append("whim notification not filtered")
	if not GameSettings.notification_allowed("Mira got a promotion", "goal"): fails.append("non-whim goal notification filtered")

	# dialog builds every control
	var root: Window = Engine.get_main_loop().root
	var dlg := SettingsDialog.new()
	dlg.theme = UITheme.build()
	root.add_child(dlg)
	for t in GameSettings.TABS:
		dlg.tab = t[0]
		dlg.show_for(-1)
		if t[0] == "controls":
			for a in SettingsKeys.ACTIONS:
				if dlg.find_child(a[0], true, false) == null: fails.append("controls: no row for %s" % a[0])
		else:
			for d in GameSettings.defs_for(t[0]):
				if dlg.find_child(d["k"], true, false) == null: fails.append("tab %s: no control for %s" % [t[0], d["k"]])
		if dlg.find_child("ResetBtn", true, false) == null: fails.append("tab %s: no reset button" % t[0])
	# tooltips everywhere
	for d in GameSettings.DEFS:
		if str(d.get("tip", "")) == "": fails.append("no tooltip for %s" % d["k"])

	# reset to defaults
	GameSettings.set_value("ui_scale", 140)
	GameSettings.set_value("aa", 3)
	GameSettings.reset_tab("display")
	if GameSettings.get_int("ui_scale") != 100 or GameSettings.get_int("aa") != 1: fails.append("reset_tab(display) failed")
	GameSettings.reset_tab("controls")
	if SettingsKeys.binding_text(act) != "W": fails.append("controls reset failed: %s" % SettingsKeys.binding_text(act))

	# pause-on-dialog restores the speed
	dlg.hide_dialog()
	UIDialog._open.clear()      # other tests may leave dialogs open in leaked scenes
	UIDialog._resume_speed = 0
	UIU.set_speed(2)
	dlg.show_for(-1)
	if UIU.get_speed() != 0: fails.append("dialog did not pause (open=%s resume=%d vis=%s)" % [str(UIDialog._open), UIDialog._resume_speed, str(dlg.is_visible_in_tree())])
	dlg.hide_dialog()
	if UIU.get_speed() != 2: fails.append("speed not restored after dialog (got %d)" % UIU.get_speed())
	GameSettings.set_value("pause_on_dialog", false)
	dlg.show_for(-1)
	if UIU.get_speed() != 2: fails.append("paused although the setting is off")
	dlg.hide_dialog()
	UIU.set_speed(0)

	dlg.queue_free()
	GameSettings.reset_all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	GameSettings.path = old_path
	GameSettings.values = old_vals
	SettingsKeys.load_from(null)
	SettingsApply.apply_all()
	return fails
