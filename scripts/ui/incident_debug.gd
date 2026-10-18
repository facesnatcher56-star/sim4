class_name IncidentDebug
extends UIDialog
## Hidden debug panel (F9, InputMap action `sim_debug_incidents`, not listed in Settings): every incident with its effective yearly rate for
## the selected Folk / their household, how often and when it last happened, a Force button, the Surprises quick switch and the recent history.
const ACTION := "sim_debug_incidents"

## Make sure the F9 action exists (idempotent; the HUD calls it).
static func ensure_action() -> void:
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var e := InputEventKey.new()
		e.keycode = KEY_F9
		InputMap.action_add_event(ACTION, e)

func _ready() -> void:
	dialog_width = 660.0
	super._ready()

func build() -> void:
	title_label.text = "Incidents (debug)"
	var f = folk_obj()
	var hid: int = int(f.household_id) if f != null else Economy.primary_household()
	var sw := HBoxContainer.new()
	body.add_child(sw)
	sw.add_child(UIU.make_label("Surprises:", 14))
	var ob := OptionButton.new()
	ob.name = "Surprises"
	var levels: Array = (IncidentDefs.cfg("levels", {}) as Dictionary).keys()
	for lv in levels:
		ob.add_item("%s (x%s)" % [str(lv).capitalize(), str((IncidentDefs.cfg("levels", {}) as Dictionary)[lv])])
		ob.set_item_metadata(ob.item_count - 1, lv)
		if lv == Incidents.level_id():
			ob.select(ob.item_count - 1)
	ob.item_selected.connect(func(i: int):
		var id: String = str(ob.get_item_metadata(i))
		Incidents.set_level(id)
		GameSettings.set_value("surprises", id)
		refresh())
	sw.add_child(ob)
	line("Target: %s   |   household %d   |   rates are events per year with the current setting" % [str(f.name) if f != null else "nobody selected", hid], 12, UITheme.MUTED)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 12)
	body.add_child(grid)
	for h in ["Incident", "Scope", "Rate / yr", "Last day", "Count", ""]:
		grid.add_child(UIU.make_label(h, 12, UITheme.MUTED))
	for row in Incidents.list():
		var id2: String = row["id"]
		var def: Dictionary = IncidentDefs.get_def(id2)
		var rate_txt: String = "-"
		var subj = _subject_for(def, f, hid)
		if subj != null:
			rate_txt = "%.3f" % IncidentRisk.effective_rate(def, subj)
		var st: Dictionary = row["stat"]
		var name_l := UIU.make_label(str(row["label"]), 13)
		name_l.tooltip_text = _tooltip(def, subj)
		grid.add_child(name_l)
		grid.add_child(UIU.make_label("%s/%s" % [row["scope"], row["check"]], 12, UITheme.MUTED))
		grid.add_child(UIU.make_label(rate_txt, 13, UITheme.ACCENT))
		grid.add_child(UIU.make_label(str(int(st["last_day"])) if int(st["last_day"]) >= 0 else "-", 13))
		grid.add_child(UIU.make_label("%d" % (int(st["triggered"]) + int(st["forced"])), 13))
		var b := Button.new()
		b.name = "Force_" + id2
		b.text = "Force"
		b.pressed.connect(func():
			var r: Dictionary = Incidents.force(id2, {"folk_id": folk_id, "lot": hid})
			refresh()
			call_deferred("_center")
			if not bool(r.get("ok", false)):
				SysUtil.notify("Could not force %s: %s" % [id2, str(r.get("text", "no target"))], "warn"))
		grid.add_child(b)
	heading("Recent")
	var hist: Array = Incidents.history(6)
	if hist.is_empty():
		line("Nothing yet.", 12, UITheme.MUTED)
	for h2 in hist:
		line("Day %d %s  [%s]  %s" % [int(h2["day"]), str(h2["time"]), str(h2.get("mode", "")), str(h2["text"]) if str(h2["text"]) != "" else str(h2["label"])], 12)
	if not Incidents.active().is_empty():
		heading("Waiting (warned)")
		for p in Incidents.active():
			line("%s - due in %d min" % [str(p["id"]), int(p["due_min"]) - SysUtil.now()], 12)

func _subject_for(def: Dictionary, f, hid: int):
	match str(def.get("scope", "")):
		"folk":
			return IncidentSubject.of_folk(f) if f != null else null
		"lot", "town":
			return IncidentSubject.of_household(hid)
		"townie":
			var ts: Array = IncidentChecks.townie_subjects()
			return ts[0] if not ts.is_empty() else null
	return null

func _tooltip(def: Dictionary, subj) -> String:
	if subj == null:
		return ""
	var lines: Array = []
	for e in IncidentRisk.breakdown(def, subj):
		lines.append("%s %s x%s" % ["+" if e["kind"] == "risk" else "-", str(e["label"]), str(e["mult"])])
	return "Base %.3f per year\n%s" % [float(def.get("base_rate_per_year", 0.0)), "\n".join(lines) if not lines.is_empty() else "(no active modifiers)"]
