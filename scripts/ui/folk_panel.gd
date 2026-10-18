class_name FolkPanel
extends PanelContainer
## Selected-folk panel: portrait, mood, need bars, traits, skills, relationships, aspiration, "Why?" debug.

var folk = null                      # current folk (Folk or duck-typed fake)
var folk_id := -1
var need_bars: Dictionary = {}       # need id -> ProgressBar
var need_rows: Dictionary = {}       # need id -> HBoxContainer
var portrait: FaceIcon
var mood_icon: FaceIcon
var name_label: Label
var mood_label: Label
var trait_box: HFlowContainer
var needs_box: VBoxContainer
var skills_box: VBoxContainer
var rel_box: VBoxContainer
var goal_label: Label
var why_label: Label
var why_toggle: CheckButton
var tabs: TabContainer
var mood_area: Control
var _why_timer: Timer

func _ready() -> void:
	custom_minimum_size = Vector2(360, 0)
	var root := VBoxContainer.new()
	add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	portrait = FaceIcon.new()
	portrait.custom_minimum_size = Vector2(64, 64)
	head.add_child(portrait)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	name_label = UIU.make_label("No one selected", 20)
	hv.add_child(name_label)
	mood_area = HBoxContainer.new()
	mood_area.mouse_filter = Control.MOUSE_FILTER_PASS
	hv.add_child(mood_area)
	mood_icon = FaceIcon.new()
	mood_icon.custom_minimum_size = Vector2(24, 24)
	mood_area.add_child(mood_icon)
	mood_label = UIU.make_label("", 14, UITheme.MUTED)
	mood_label.mouse_filter = Control.MOUSE_FILTER_PASS
	mood_area.add_child(mood_label)
	mood_area.mouse_filter = Control.MOUSE_FILTER_STOP
	trait_box = HFlowContainer.new()
	root.add_child(trait_box)
	goal_label = UIU.make_label("", 13, UITheme.MUTED)
	goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(goal_label)
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 250)
	root.add_child(tabs)
	needs_box = VBoxContainer.new()
	needs_box.name = "Needs"
	tabs.add_child(needs_box)
	skills_box = VBoxContainer.new()
	skills_box.name = "Skills"
	tabs.add_child(skills_box)
	rel_box = VBoxContainer.new()
	rel_box.name = "People"
	tabs.add_child(rel_box)
	var why_box := VBoxContainer.new()
	why_box.name = "Why?"
	tabs.add_child(why_box)
	why_toggle = CheckButton.new()
	why_toggle.text = "Show autonomy scoring"
	why_toggle.toggled.connect(func(_on): _refresh_why())
	why_box.add_child(why_toggle)
	why_label = UIU.make_label("", 12, UITheme.MUTED)
	why_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	why_box.add_child(why_label)
	_why_timer = Timer.new()
	_why_timer.wait_time = 1.0
	_why_timer.autostart = true
	_why_timer.timeout.connect(_refresh_why)
	add_child(_why_timer)
	UIU.connect_ev("need_changed", _on_need_changed)
	UIU.connect_ev("mood_changed", _on_mood_changed)
	UIU.connect_ev("buff_added", _on_buff_event)
	UIU.connect_ev("buff_removed", _on_buff_event)
	UIU.connect_ev("skill_changed", _on_skill_changed)
	UIU.connect_ev("relationship_changed", _on_rel_changed)

func show_folk(f) -> void:
	folk = f
	if f == null:
		folk_id = -1
		name_label.text = "No one selected"
		return
	folk_id = int(UIU.prop(f, "id", -1))
	name_label.text = str(UIU.prop(f, "name", "?"))
	portrait.color = UIU.folk_color(f)
	_build_needs()
	_build_traits()
	_build_skills()
	_build_relationships()
	_refresh_mood()
	_refresh_goal()
	_refresh_why()

# ---------------- needs ----------------
func _build_needs() -> void:
	for c in needs_box.get_children():
		c.queue_free()
	need_bars.clear()
	need_rows.clear()
	var defs := UIU.tbl("needs")
	var needs = UIU.prop(folk, "needs", {})
	for nid in needs:
		var def: Dictionary = defs.get(nid, {})
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var lab := UIU.make_label(str(def.get("label", str(nid).capitalize())), 14)
		lab.custom_minimum_size = Vector2(80, 0)
		row.add_child(lab)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.step = 0.001
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(200, 16)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bar)
		needs_box.add_child(row)
		need_bars[nid] = bar
		need_rows[nid] = row
		_update_need(nid, needs[nid])

func _update_need(nid: String, stat, raw_value = null) -> void:
	if not need_bars.has(nid):
		return
	var bar: ProgressBar = need_bars[nid]
	var r := UIU.stat_ratio(stat)
	if raw_value != null and stat != null:
		var lo := float(UIU.prop(stat, "min", 0.0))
		var hi := float(UIU.prop(stat, "max", 100.0))
		r = clampf((float(raw_value) - lo) / maxf(hi - lo, 0.001), 0.0, 1.0)
	bar.value = r
	var sb := UITheme.box(UIU.level_color(r), 4, Color(0, 0, 0, 0), 0, 0)
	bar.add_theme_stylebox_override("fill", sb)
	need_rows[nid].tooltip_text = _need_tooltip(nid, r)

func _need_tooltip(nid: String, r: float) -> String:
	var defs := UIU.tbl("needs")
	var def: Dictionary = defs.get(nid, {})
	var t := "%s: %d%%" % [def.get("label", nid), int(r * 100.0)]
	var causing: Array = []
	var active := _active_buff_ids()
	for th in def.get("thresholds", []):
		var b := str(th.get("buff", ""))
		if b in active:
			causing.append(_buff_label(b))
	if causing.size() > 0:
		t += "\nCausing: " + ", ".join(causing)
	else:
		t += "\nNo mood effect right now."
	return t

func _active_buff_ids() -> Array:
	var out: Array = []
	for b in UIU.prop(folk, "buffs", []):
		out.append(UIU.buff_id(b))
	return out

func _buff_label(id: String) -> String:
	var bd: Dictionary = UIU.tbl("buffs").get(id, {})
	var lab := str(bd.get("label", id.capitalize()))
	var m = bd.get("mood", {})
	if m is Dictionary and m.size() > 0:
		var parts: Array = []
		for k in m:
			parts.append("%s %+d" % [k, int(m[k])])
		lab += " (" + ", ".join(parts) + ")"
	return lab

func _on_need_changed(fid: int, need: String, value: float) -> void:
	if fid != folk_id or folk == null:
		return
	var needs = UIU.prop(folk, "needs", {})
	_update_need(need, needs.get(need), value)

# ---------------- mood ----------------
func _refresh_mood() -> void:
	var mood := "neutral"
	var inten := 0
	if folk != null and folk.has_method("get_mood"):
		var m = folk.call("get_mood")
		if m is Dictionary:
			mood = str(m.get("mood", "neutral"))
			inten = int(m.get("intensity", 0))
		elif m != null:
			mood = str(m)
	_apply_mood(mood, inten)

func _apply_mood(mood: String, inten: int) -> void:
	mood_icon.mood = mood
	mood_icon.color = UIU.MOOD_COLORS.get(mood, UIU.MOOD_COLORS["neutral"])
	portrait.mood = mood
	mood_label.text = "%s %s" % [mood.capitalize(), "●".repeat(clampi(inten, 0, 3))]
	var lines := ["Mood: %s (intensity %d)" % [mood, inten], "Buffs:"]
	var any := false
	for id in _active_buff_ids():
		lines.append("  • " + _buff_label(id))
		any = true
	if not any:
		lines.append("  (none)")
	mood_area.tooltip_text = "\n".join(lines)

func _on_mood_changed(fid: int, mood: String, intensity: int) -> void:
	if fid == folk_id:
		_apply_mood(mood, intensity)

func _on_buff_event(fid: int, _buff: String) -> void:
	if fid != folk_id:
		return
	_refresh_mood()
	for nid in need_bars:
		_update_need(nid, UIU.prop(folk, "needs", {}).get(nid))

# ---------------- traits / goals ----------------
func _build_traits() -> void:
	for c in trait_box.get_children():
		c.queue_free()
	var defs := UIU.tbl("traits")
	for t in UIU.prop(folk, "traits", []):
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UITheme.box(UITheme.ACCENT.darkened(0.45), 12, UITheme.ACCENT, 1, 8))
		var l := UIU.make_label(str(defs.get(t, {}).get("label", str(t).capitalize())), 12)
		chip.add_child(l)
		chip.tooltip_text = str(defs.get(t, {}).get("description", ""))
		trait_box.add_child(chip)

func _refresh_goal() -> void:
	var g = UIU.prop(folk, "aspiration", null)
	if g == null:
		g = UIU.prop(folk, "goal", null)
	goal_label.text = ("Aspiration: " + str(g)) if g != null and str(g) != "" else "Aspiration: (none yet)"

# ---------------- skills ----------------
func _build_skills() -> void:
	for c in skills_box.get_children():
		c.queue_free()
	var skills = UIU.prop(folk, "skills", {})
	if skills.size() == 0:
		skills_box.add_child(UIU.make_label("No skills yet - practice something!", 13, UITheme.MUTED))
	for s in skills:
		var st = skills[s]
		var row := HBoxContainer.new()
		row.name = "skill_" + str(s)
		var lv := _skill_level(st)
		var lab := UIU.make_label("%s  Lv %d" % [str(s).capitalize(), lv], 14)
		lab.custom_minimum_size = Vector2(130, 0)
		row.add_child(lab)
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.show_percentage = false
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.custom_minimum_size = Vector2(120, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.value = _skill_progress(st)
		row.add_child(bar)
		skills_box.add_child(row)

func _skill_level(st) -> int:
	if st is Dictionary:
		return int(st.get("level", int(st.get("value", 0))))
	if st is int or st is float:
		return int(st)
	var lv = st.get("level")
	return int(lv) if lv != null else int(UIU.prop(st, "value", 0))

func _skill_progress(st) -> float:
	if st is int or st is float:
		return fmod(float(st), 1.0)
	if st is Dictionary and st.has("xp"):
		var lv := int(st.get("level", 0))
		var lo := 50.0 * lv * (lv + 1)
		var hi := 50.0 * (lv + 1) * (lv + 2)
		return clampf((float(st["xp"]) - lo) / maxf(hi - lo, 1.0), 0.0, 1.0)
	return UIU.stat_ratio(st) if UIU.prop(st, "max", null) != null else 0.0

func _on_skill_changed(fid: int, _skill: String, _level: int) -> void:
	if fid == folk_id:
		_build_skills()

# ---------------- relationships ----------------
func _build_relationships() -> void:
	for c in rel_box.get_children():
		c.queue_free()
	var rels = UIU.prop(folk, "relationships", {})
	if not (rels is Dictionary) or rels.size() == 0:
		rel_box.add_child(UIU.make_label("Hasn't met anyone yet.", 13, UITheme.MUTED))
		return
	for other_id in rels:
		var other = UIU.get_folk(int(other_id))
		var nm := str(UIU.prop(other, "name", "Folk #%s" % other_id))
		var tracks = rels[other_id]
		var txt := nm
		if tracks is Dictionary:
			var parts: Array = []
			for tr in tracks:
				parts.append("%s %d" % [tr, int(tracks[tr])])
			txt += ":  " + ", ".join(parts)
		rel_box.add_child(UIU.make_label(txt, 13))

func _on_rel_changed(a: int, b: int, _track: String = "", _v: float = 0.0) -> void:
	if a == folk_id or b == folk_id:
		_build_relationships()

# ---------------- why? ----------------
func _refresh_why() -> void:
	if why_label == null:
		return
	if not why_toggle.button_pressed:
		why_label.text = "(toggle to inspect decisions)"
		return
	var ac = UIU.cls("Autonomy")
	var dbg = ac.get("last_debug") if ac != null else null
	if dbg == null:
		why_label.text = "No autonomy data yet."
	elif dbg is Dictionary or dbg is Array:
		why_label.text = JSON.stringify(dbg, "  ")
	else:
		why_label.text = str(dbg)
