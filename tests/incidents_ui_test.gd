extends RefCounted
## Incident UI: Surprises setting (settings file default for new games, per-save value, applied live), the F9 debug panel (rows, force
## buttons, quick switch, action registered) and the folk panel status chips.

const K = preload("res://tests/systems_kit.gd")
const TMP := "user://incidents_ui_settings.cfg"

func run() -> Array:
	var f: Array = []
	_setting(f)
	_debug_panel(f)
	_chips(f)
	return f

func _root() -> Window:
	return Engine.get_main_loop().root

func _setting(f: Array) -> void:
	var old_path: String = GameSettings.path
	var old_vals: Dictionary = GameSettings.values.duplicate()
	GameSettings.path = TMP
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	GameSettings.load_settings()
	K.setup()
	Incidents.reset()
	K.expect(f, GameSettings.get_str("surprises") == "rare" and Incidents.level_id() == "rare", "default is Rare")
	GameSettings.set_value("surprises", "chaotic")
	K.expect(f, Incidents.level_id() == "chaotic" and Incidents.surprise_mult() == 10.0, "changing the setting applies to the running game")
	GameSettings.values = {}
	GameSettings.load_settings()
	K.expect(f, GameSettings.get_str("surprises") == "chaotic", "stored in the settings file")
	Incidents.reset()
	K.expect(f, Incidents.level_id() == "chaotic", "a new game starts from the settings value")
	Incidents.set_level("off")
	var snap: Dictionary = JSON.parse_string(JSON.stringify(Incidents.to_dict()))
	GameSettings.set_value("surprises", "normal")
	Incidents.from_dict(snap)
	K.expect(f, Incidents.level_id() == "off", "a loaded game keeps ITS level (per-save), not the settings file's")
	GameSettings.path = old_path
	GameSettings.values = old_vals
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	K.teardown()
	Incidents.reset()

func _debug_panel(f: Array) -> void:
	var w := K.setup()
	Incidents.reset()
	Incidents.set_level("rare")
	var a := K.make_folk(w, "Ada", [], 1)
	IncidentDebug.ensure_action()
	K.expect(f, InputMap.has_action("sim_debug_incidents"), "F9 action registered")
	var found := false
	for e in InputMap.action_get_events("sim_debug_incidents"):
		if e is InputEventKey and e.keycode == KEY_F9:
			found = true
	K.expect(f, found, "bound to F9")
	var dlg := IncidentDebug.new()
	_root().add_child(dlg)
	dlg.show_for(a.id)
	var n_buttons: int = 0
	for ch in dlg.find_children("Force_*", "Button", true, false):
		n_buttons += 1
	K.expect(f, n_buttons == Incidents.list().size() and n_buttons >= 4, "a Force button for every incident (%d)" % n_buttons)
	var sw: OptionButton = dlg.find_child("Surprises", true, false)
	K.expect(f, sw != null and sw.item_count == 4, "Surprises quick switch")
	(dlg.find_child("Force_found_money", true, false) as Button).pressed.emit()
	K.expect(f, int(Incidents.stat("found_money")["forced"]) == 1, "Force button triggers the incident for the selected target")
	if sw != null:
		sw.item_selected.emit(3)
	K.expect(f, Incidents.level_id() == "chaotic", "quick switch changes the level")
	dlg.queue_free()
	GameSettings.set_value("surprises", "rare")
	K.teardown()

func _chips(f: Array) -> void:
	var w := K.setup()
	Incidents.reset()
	var a := K.make_folk(w, "Ada", [], 1)
	var panel := FolkPanel.new()
	_root().add_child(panel)
	panel.show_folk(a)
	K.expect(f, panel.status_box.get_child_count() == 0, "healthy: no status chips")
	Hospital.injure(a, 1, "x")
	panel._build_status()          # the panel rebuilds on buff events; the standalone test Events bus is not the one it listens to
	K.expect(f, panel.status_box.get_child_count() >= 1, "injured chip appears when the buff is added")
	Hospital.fall_ill(a, 2, "y")
	panel._build_status()
	var texts: Array = []
	for c in panel.status_box.get_children():
		if not c.is_queued_for_deletion():
			texts.append(c.get_child(0).text)
	K.expect(f, texts.has("In hospital") and texts.has("Injured") and texts.has("Unwell"), "In hospital / Injured / Unwell chips: %s" % str(texts))
	panel.queue_free()
	K.teardown()
