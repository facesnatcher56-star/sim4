class_name FolkPanel
extends PanelContainer
signal goals_requested(folk_id: int)
signal career_requested(folk_id: int)
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
var status_box: HFlowContainer          # injured / unwell / in hospital chips (Hospital.status_chips)
var needs_box: VBoxContainer
var skills_box: VBoxContainer
var rel_box: VBoxContainer
var rel_scroll: ScrollContainer
var _rel_pending := false
var record_box: VBoxContainer          # "Record" tab: criminal record, sentences and orders in force (RecordView)
var family_box: VBoxContainer          # "Family" tab: partner / parents / children / siblings + action buttons
var family_buttons: Dictionary = {}    # action id -> Button
var goal_label: Label
var goals_button: Button
var career_button: Button
var home_button: CheckButton
var why_label: Label
var why_toggle: CheckButton
var tabs: TabContainer
var mood_area: Control
var _why_timer: Timer
var expanded := false                  # compact by default (task 32d): the portrait, mood and need pips; click the header or Details to open everything
var mini_box: HFlowContainer              # compact view: one thin bar per need
var mini_icons: Dictionary = {}           # need id -> NeedIcon over its mini bar
var mini_bars: Dictionary = {}
var details_btn: Button
var goal_row: HBoxContainer

func _ready() -> void:
	custom_minimum_size = Vector2(320, 0)
	var root := VBoxContainer.new()
	add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	portrait = FaceIcon.new()
	portrait.custom_minimum_size = Vector2(48, 48)
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
	details_btn = Button.new()
	details_btn.flat = true
	details_btn.tooltip_text = "Show or hide needs, skills, people and goals"
	details_btn.pressed.connect(func(): set_expanded(not expanded))
	head.add_child(details_btn)
	mini_box = HFlowContainer.new()
	mini_box.add_theme_constant_override("h_separation", 4)
	mini_box.add_theme_constant_override("v_separation", 3)
	root.add_child(mini_box)
	trait_box = HFlowContainer.new()
	root.add_child(trait_box)
	status_box = HFlowContainer.new()
	status_box.name = "StatusChips"
	root.add_child(status_box)
	goal_row = HBoxContainer.new()
	root.add_child(goal_row)
	goal_label = UIU.make_label("", 13, UITheme.MUTED)
	goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goal_label.custom_minimum_size = Vector2(150, 0)
	goal_row.add_child(goal_label)
	goals_button = Button.new()
	goals_button.text = "Goals"
	goals_button.tooltip_text = "Aspiration, whims, satisfaction points and perks"
	goals_button.pressed.connect(func(): goals_requested.emit(folk_id))
	goal_row.add_child(goals_button)
	career_button = Button.new()
	career_button.text = "Work"
	career_button.tooltip_text = "Job, performance, shifts and job offers"
	career_button.pressed.connect(func(): career_requested.emit(folk_id))
	goal_row.add_child(career_button)
	home_button = CheckButton.new()
	home_button.text = "Stay at home"
	home_button.tooltip_text = "A homemaker role instead of a career: no job offers, looks after the house, the cooking and the little ones"
	home_button.toggled.connect(func(on): if folk_id >= 0 and on != Careers.homemakers.has(folk_id): Commands.run({"folk_id": folk_id, "action": "set_homemaker", "args": {"on": on}}))
	goal_row.add_child(home_button)
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 250)
	root.add_child(tabs)
	needs_box = VBoxContainer.new()
	needs_box.name = "Needs"
	tabs.add_child(needs_box)
	skills_box = VBoxContainer.new()
	skills_box.name = "Skills"
	tabs.add_child(skills_box)
	rel_scroll = ScrollContainer.new()
	rel_scroll.name = "People"
	rel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(rel_scroll)
	rel_box = VBoxContainer.new()
	rel_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rel_box.add_theme_constant_override("separation", 5)
	rel_scroll.add_child(rel_box)
	var fam_scroll := ScrollContainer.new()
	fam_scroll.name = "Family"
	fam_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(fam_scroll)
	family_box = VBoxContainer.new()
	family_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fam_scroll.add_child(family_box)
	var rec_scroll := ScrollContainer.new()
	rec_scroll.name = "Record"
	rec_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(rec_scroll)
	record_box = VBoxContainer.new()
	record_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rec_scroll.add_child(record_box)
	tabs.tab_changed.connect(func(_i): _refresh_record())
	var why_box := VBoxContainer.new()
	why_box.name = "Thinking"
	tabs.add_child(why_box)
	why_toggle = CheckButton.new()
	why_toggle.text = "Explain their decisions"
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
	expanded = UIPrefs.get_flag("folk_panel_expanded", false)
	set_expanded(expanded)
	UIU.connect_ev("need_changed", _on_need_changed)
	UIU.connect_ev("mood_changed", _on_mood_changed)
	UIU.connect_ev("buff_added", _on_buff_event)
	UIU.connect_ev("buff_removed", _on_buff_event)
	UIU.connect_ev("skill_changed", _on_skill_changed)
	UIU.connect_ev("relationship_changed", _on_rel_changed)
	UIU.connect_ev("game_event", _on_family_event)

func show_folk(f) -> void:
	folk = f
	if f == null:
		folk_id = -1
		name_label.text = "No one selected"
		return
	folk_id = int(UIU.prop(f, "id", -1))
	name_label.text = str(UIU.prop(f, "name", "?"))
	portrait.color = portrait_color(f)
	var pc: Color = Genetics.ui_color(f)          # the person's own colour (their shirt) frames the panel: a coloured left edge and a tinted plate
	var sb := UITheme.box(Color(UITheme.PANEL.lerp(pc, 0.10), 0.95), 12, Color(pc, 0.4), 1, 10)
	sb.border_color = pc
	sb.border_width_left = 6
	add_theme_stylebox_override("panel", sb)
	_build_mini()
	_build_needs()      # (fills the mini bars too)
	_build_traits()
	_build_status()
	_build_skills()
	_build_relationships()
	_build_family()
	_refresh_record()
	_refresh_mood()
	_refresh_goal()
	_refresh_why()

func _refresh_record() -> void:
	if record_box != null and tabs != null and tabs.get_current_tab_control() != null and tabs.get_current_tab_control().name == "Record":
		RecordView.fill(record_box, folk_id)

## Portrait colour: the registry colour picked on the title screen when there is one, else the folk's shirt (Genetics).
static func portrait_color(f) -> Color:
	var id := int(UIU.prop(f, "id", -1))
	if UIU.folk_colors.has(id):
		return UIU.folk_colors[id]
	return Genetics.ui_color(f)

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
		var lab := UIU.make_label(str(def.get("label", UIU.sentence(str(nid)))), 14)
		lab.custom_minimum_size = Vector2(80, 0)
		row.add_child(lab)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.step = 0.001
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(170, 16)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bar)
		var num := UIU.make_label("", 13)
		num.custom_minimum_size = Vector2(44, 0)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		num.name = "num"
		row.add_child(num)
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
	if mini_bars.has(nid):
		(mini_bars[nid] as ProgressBar).value = r
		(mini_bars[nid] as ProgressBar).add_theme_stylebox_override("fill", UITheme.box(UIU.level_color(r), 3, Color(0, 0, 0, 0), 0, 0))
		if mini_icons.has(nid):
			(mini_icons[nid] as NeedIcon).set_ratio(r)
	var num: Label = need_rows[nid].get_node_or_null("num")
	if num != null:
		num.visible = GameSettings.get_bool("need_numbers")
		num.text = ("! %d%%" if r < 0.2 else "%d%%") % int(r * 100.0)    # number + "!" so low needs never rely on colour alone
		num.add_theme_color_override("font_color", UITheme.sem("low_text") if r < 0.2 else UITheme.TEXT)
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

func _active_buff_ids(include_hidden: bool = false) -> Array:
	var out: Array = []
	var defs := UIU.tbl("buffs")
	for b in UIU.prop(folk, "buffs", []):
		var bid := UIU.buff_id(b)
		if not include_hidden and bool(defs.get(bid, {}).get("hidden", false)):
			continue
		out.append(bid)
	return out

func _buff_label(id: String) -> String:
	var bd: Dictionary = UIU.tbl("buffs").get(id, {})
	var lab := str(bd.get("label", UIU.sentence(id)))
	var m = bd.get("mood", {})
	if m is Dictionary and m.size() > 0:
		var parts: Array = []
		for k in m:
			parts.append("%s %+d" % [mood_name(str(k)), int(m[k])])
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

func mood_color(mood: String) -> Color:
	if UIU.MOOD_COLORS.has(mood):
		return UIU.mood_color(mood)
	if Emotions.mood_defs().has(mood):
		return UITheme.tone(Emotions.color(mood))
	return UIU.MOOD_COLORS["neutral"]

## Display name of a mood id. "neutral" reads as "Calm" (nothing pulls the mood either way).
static func mood_name(mood: String) -> String:
	if mood == "neutral":
		return "Calm"
	return Emotions.label(mood) if Emotions.mood_defs().has(mood) else UIU.sentence(mood)

const INTENSITY_WORDS := ["", "mild", "strong", "intense"]

func _apply_mood(mood: String, inten: int) -> void:
	mood_icon.mood = mood
	mood_icon.color = mood_color(mood)
	portrait.mood = mood
	mood_label.text = "%s %s" % [mood_name(mood), "●".repeat(clampi(inten, 0, 3))] if mood != "neutral" else mood_name(mood)
	mood_area.tooltip_text = mood_tooltip(mood, inten)

## What drives the mood: strongest contributing buffs first, then what the mood does (data/emotions.json).
func mood_tooltip(mood: String, inten: int) -> String:
	var lines: Array = ["Mood: %s" % mood_name(mood) if mood == "neutral" else "Mood: %s (%s)" % [mood_name(mood), INTENSITY_WORDS[clampi(inten, 1, 3)]]]
	var blurb := Emotions.blurb(mood) if mood != "neutral" else "Nothing is pulling their mood either way."

	if blurb != "":
		lines.append(blurb)
	var rows: Array = []
	if folk is Folk:
		rows = Mood.breakdown(folk)["rows"]
	else:
		for id in _active_buff_ids():
			rows.append({"id": id, "label": _buff_label(id), "toward": 0.0, "hidden": false, "weights": {}})
	lines.append("Driven by:")
	var any := false
	for r in rows:
		if bool(r.get("hidden", false)):
			continue
		any = true
		if folk is Folk:
			var parts: Array = []
			for k in r["weights"]:
				parts.append("%s %+d" % [mood_name(str(k)), int(r["weights"][k])])
			var mark := "▶ " if float(r["toward"]) > 0.0 else "   "
			lines.append("  %s%s  (%s)" % [mark, str(r["label"]), ", ".join(parts)])
		else:
			lines.append("  • " + str(r["label"]))
	if not any:
		lines.append("  (nothing in particular)")
	var fx: Array = Emotions.describe_effects(mood, inten)
	if not fx.is_empty():
		lines.append("Effects:")
		for l in fx:
			lines.append("  " + str(l))
	var others: Array = []
	for id2 in _active_buff_ids():
		if not rows.any(func(r): return str(r["id"]) == id2):
			others.append(_buff_label(id2))
	if not others.is_empty():
		lines.append("Other buffs: " + ", ".join(others))
	return "\n".join(lines)

func _on_mood_changed(fid: int, mood: String, intensity: int) -> void:
	if fid == folk_id:
		_apply_mood(mood, intensity)

func _on_buff_event(fid: int, _buff: String) -> void:
	if fid != folk_id:
		return
	_build_status()
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
		var l := UIU.make_label(str(defs.get(t, {}).get("label", UIU.sentence(str(t)))), 12)
		chip.add_child(l)
		chip.tooltip_text = str(defs.get(t, {}).get("description", ""))
		trait_box.add_child(chip)

## Status chips: Injured / Unwell / In hospital (hidden `in_hospital` buff, so this is where the player sees it).
func _build_status() -> void:
	for c in status_box.get_children():
		c.queue_free()
	if folk == null or not (folk is Folk):
		return
	for chip in Hospital.status_chips(folk):
		status_box.add_child(_chip(str(chip["text"]), chip["color"], str(chip["tip"])))
	for chip2 in JusticePlayer.status_chips(folk):
		status_box.add_child(_chip(str(chip2["text"]), chip2["color"], str(chip2["tip"])))

func _refresh_goal() -> void:
	var info: Dictionary = Goals.active_for(folk_id) if folk_id >= 0 else {}
	if info.is_empty():
		goal_label.text = "No aspiration yet"
		goal_label.tooltip_text = ""
	else:
		var ms: Dictionary = info["milestone"]
		goal_label.text = "Dream: %s" % str(info["aspiration_label"])
		goal_label.tooltip_text = ("Next: %s" % str(ms["label"])) if not ms.is_empty() else "Aspiration complete"
		goal_label.mouse_filter = Control.MOUSE_FILTER_STOP
	var young: bool = str(UIU.prop(folk, "age_stage", "adult")) in ["baby", "toddler"]
	goals_button.disabled = info.is_empty() or young
	career_button.disabled = young
	var grown: bool = str(UIU.prop(folk, "age_stage", "adult")) in ["adult", "elder"]
	home_button.visible = grown
	home_button.set_pressed_no_signal(Careers.homemakers.has(folk_id))

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
		var lab := UIU.make_label("%s  Lv %d" % [ContentRules.skill_label(str(s)), lv], 14)
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
static func _track_color(k: String) -> Color:
	return UITheme.sem({"friendship": "good", "romance": "romance", "trust": "trust"}[k])

func _known_ids() -> Array:
	var ids: Array = []
	var rels = UIU.prop(folk, "relationships", {})
	if rels is Dictionary:
		for k in rels:
			if int(k) != folk_id and not ids.has(int(k)):
				ids.append(int(k))
	for k2 in RelationshipService.all_known(folk_id):
		if int(k2) != folk_id and not ids.has(int(k2)):
			ids.append(int(k2))
	return ids

func _track_value(oid: int, track: String) -> float:
	var rels = UIU.prop(folk, "relationships", {})
	if rels is Dictionary and rels.has(oid) and rels[oid] is Dictionary and (rels[oid] as Dictionary).has(track):
		return float(rels[oid][track])
	return RelationshipService.value(folk_id, oid, track)

func _build_relationships() -> void:
	_rel_pending = false
	for c in rel_box.get_children():
		rel_box.remove_child(c)
		c.queue_free()
	if folk == null or folk_id < 0:
		return
	var ids := _known_ids()
	var goal := SocialDynamics.goal_text(folk_id)
	if goal != "":
		var gl := UIU.make_label("Social goal: " + goal, 12, UITheme.ACCENT)
		gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rel_box.add_child(gl)
	if ids.is_empty():
		rel_box.add_child(UIU.make_label("Hasn't met anyone yet.", 13, UITheme.MUTED))
		return
	ids.sort_custom(func(a, b):
		return _track_value(a, "friendship") + _track_value(a, "romance") > _track_value(b, "friendship") + _track_value(b, "romance"))
	for oid in ids:
		rel_box.add_child(_rel_card(int(oid)))

func _chip(text: String, col: Color, tip: String = "") -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UITheme.box(col.darkened(0.45), 10, col, 1, 6))
	chip.add_child(UIU.make_label(text, 11))
	chip.tooltip_text = tip
	return chip

func _meter(title: String, value: float, col: Color) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UIU.make_label("%s %d" % [title, int(round(value))], 10, UITheme.MUTED))
	var bar := ProgressBar.new()
	bar.min_value = -100.0
	bar.max_value = 100.0
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(60, 8)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("fill", UITheme.box(col if value >= 0.0 else UITheme.sem("bad"), 3, Color(0, 0, 0, 0), 0, 0))
	v.add_child(bar)
	return v

func _rel_card(oid: int) -> PanelContainer:
	var other = UIU.get_folk(oid)
	var nm := str(UIU.prop(other, "name", SysUtil.folk_name(oid) if other == null else "Folk #%d" % oid))
	var card := PanelContainer.new()
	card.name = "rel_%d" % oid
	card.add_theme_stylebox_override("panel", UITheme.box(UITheme.PANEL_HI.darkened(0.2), 8, Color(1, 1, 1, 0.06), 1, 8))
	card.tooltip_text = RelationshipService.describe(folk_id, oid)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	card.add_child(col)
	# --- head: name, relationship bit, romance stage, tension, their mood
	var head := HFlowContainer.new()
	head.add_theme_constant_override("h_separation", 5)
	col.add_child(head)
	head.add_child(UIU.make_label(nm, 14))
	var bit := RelationshipService.bit_for(folk_id, oid)
	if bit != "stranger":
		head.add_child(_chip(RelationshipService.bit_label(bit), UITheme.tone(Color(RelationshipService.bit_color(bit))), "How %s sees %s" % [str(UIU.prop(folk, "name", "they")), nm]))
	var stage := RelationshipService.romance_stage(folk_id, oid)
	if stage in ["crush", "flirting"]:
		head.add_child(_chip(RelationshipService.stage_label(stage), UITheme.sem("romance"), "Romance stage"))
	var ten := _track_value(oid, "tension")
	if ten >= 10.0:
		head.add_child(_chip("Tense %d" % int(ten), UITheme.sem("bad"), "Unresolved tension - make up, forgive or apologize. It fades slowly over days."))
	if other != null and other.has_method("get_mood"):
		var om: Dictionary = other.get_mood()
		var mn := str(om.get("mood", "neutral"))
		if mn != "neutral":
			var ml := UIU.make_label("● " + (Emotions.label(mn) if Emotions.mood_defs().has(mn) else UIU.sentence(mn)), 11, mood_color(mn))
			ml.tooltip_text = mood_tooltip_for(other)
			ml.mouse_filter = Control.MOUSE_FILTER_STOP
			head.add_child(ml)
	# --- tracks
	var meters := HBoxContainer.new()
	meters.add_theme_constant_override("separation", 8)
	col.add_child(meters)
	meters.add_child(_meter("Friendship", _track_value(oid, "friendship"), _track_color("friendship")))
	meters.add_child(_meter("Romance", _track_value(oid, "romance"), _track_color("romance")))
	meters.add_child(_meter("Trust", _track_value(oid, "trust"), _track_color("trust")))
	# --- what is known about them ('?' until discovered)
	var ks := RelationshipService.known_summary(folk_id, oid)
	var tparts: Array = []
	for t in ks["traits"]:
		tparts.append(str(t["label"]))
	var known_txt := "Traits: %s\nJob: %s   Dream: %s" % [" · ".join(tparts) if not tparts.is_empty() else "-", str(ks["career"]), str(ks["aspiration"])]
	if not (ks["interests"] as Array).is_empty():
		known_txt += "\nInterests: " + ", ".join(ks["interests"])
	var kl := UIU.make_label(known_txt, 11, UITheme.TEXT.darkened(0.15))
	kl.name = "known"
	kl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(kl)
	# --- chemistry + shared history
	var extra: Array = []
	if _track_value(oid, "romance") > 5.0 or stage != "none":
		extra.append("Spark %s" % RelationshipService.spark_hearts(folk_id, oid))
	extra.append("Together: %s" % RelationshipService.compat_label(RelationshipService.compatibility(folk_id, oid)))
	var hl := UIU.make_label("  ·  ".join(extra), 11, UITheme.MUTED)
	col.add_child(hl)
	var snippets := RelationshipService.history_snippets(folk_id, oid, 2)
	if not snippets.is_empty():
		var sl := UIU.make_label("\n".join(snippets), 10, UITheme.MUTED)
		sl.name = "history"
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(sl)
	return card

func mood_tooltip_for(other) -> String:
	var om: Dictionary = other.get_mood()
	var mn := str(om.get("mood", "neutral"))
	var lines: Array = ["%s is feeling %s" % [str(UIU.prop(other, "name", "They")), mood_name(mn).to_lower()]]
	lines.append_array(Emotions.describe_effects(mn, int(om.get("intensity", 1))))
	return "\n".join(lines)

func _on_rel_changed(a: int, b: int, _track: String = "", _v: float = 0.0) -> void:
	if (a == folk_id or b == folk_id) and not _rel_pending:
		_rel_pending = true
		call_deferred("_build_relationships")

# ---------------- family ----------------
const SOCIAL_EVENTS := ["knowledge_revealed", "breakup", "argument", "argument_resolved", "date_accepted", "gossip_spread", "secret_shared", "cheating_discovered"]
const FAMILY_EVENTS := ["married", "divorced", "engaged", "baby_born", "adopted", "moved_in", "moved_out", "child_removed", "engagement_broken"]

func _on_family_event(ev: String, _payload: Dictionary = {}) -> void:
	if ev in FAMILY_EVENTS and folk != null:
		_build_family()
	if ev in SOCIAL_EVENTS and folk != null and not _rel_pending:
		_rel_pending = true
		call_deferred("_build_relationships")

## One person in the Family tab: the name, then one muted line of plain facts (45: "Mother · Adult · elsewhere", no brackets).
func _family_line(n: Dictionary, extra: String = "") -> Array:
	var bits: Array = []
	if extra != "":
		bits.append(extra)
	bits.append(UIU.sentence(str(n.get("stage_text", n.get("stage", "")))))
	if not bool(n.get("alive", true)):
		bits.append("passed away")
	elif not bool(n.get("on_lot", false)):
		bits.append("elsewhere")
	return [str(n.get("name", "?")), " · ".join(bits)]

var _family_shown: int = 0

func _family_section(title: String, lines: Array) -> void:
	if lines.is_empty():          # empty sections stay out: a newcomer with no family sees one line, not five dashes
		return
	_family_shown += 1
	family_box.add_child(UIU.make_label(title, 12, UITheme.ACCENT))
	for l in lines:
		family_box.add_child(UIU.make_label("  " + str(l[0]), 13))
		var sub := UIU.make_label("    " + str(l[1]), 11, UITheme.MUTED)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		family_box.add_child(sub)

func _build_family() -> void:
	if family_box == null:
		return
	for c in family_box.get_children():
		c.queue_free()
	family_buttons.clear()
	if folk == null or folk_id < 0:
		return
	var t: Dictionary = Family.tree_for(folk_id, 1, 1)
	_family_shown = 0
	var partner: Dictionary = t["partner"]
	var plines: Array = []
	if not partner.is_empty():
		plines.append(_family_line(partner, Sexes.label("spouse", Sexes.of(int(partner["id"]))) if str(partner.get("status", "")) == "spouse" else {"fiance": "Engaged", "partner": "Partner", "sweetheart": "Sweetheart"}.get(str(partner.get("status", "")), "")))
	_family_section("PARTNER", plines)
	var par: Array = []
	for p in t["parents"]:
		par.append(_family_line(p, Family.relation_label(folk_id, int(p["id"]))))
	_family_section("PARENTS", par)
	var kids: Array = []
	for c in t["children"]:
		kids.append(_family_line(c, Family.relation_label(folk_id, int(c["id"]))))
	_family_section("CHILDREN", kids)
	var sibs: Array = []
	for s in t["siblings"]:
		sibs.append(_family_line(s, Family.relation_label(folk_id, int(s["id"]))))
	_family_section("SIBLINGS", sibs)
	if not (t["exes"] as Array).is_empty():
		var ex: Array = []
		for e in t["exes"]:
			ex.append(_family_line(e))
		_family_section("EXES", ex)
	if _family_shown == 0:
		family_box.add_child(UIU.make_label("No family in town yet.", 13, UITheme.MUTED))
	# actions go through the same interaction ids as the pie menu
	var stage := str(UIU.prop(folk, "age_stage", "adult"))
	var grown := stage == "adult" or stage == "elder"
	var pid := int(partner.get("id", -1))
	var pst := str(partner.get("status", ""))
	var here := not partner.is_empty() and bool(partner.get("on_lot", false))
	var row := HFlowContainer.new()
	family_box.add_child(row)
	if not partner.is_empty():          # the partner shortcuts only when there is a partner (anyone else is asked from their own menu)
		if pst in ["sweetheart", "partner"]:
			_family_button(row, "propose", "Propose", grown and here, pid, "%s isn't here." % str(partner.get("name", "")))
		var baby_why: String = Conception.why_not(folk_id, pid) if here else ""
		_family_button(row, "try_for_baby", "Try for Baby", grown and here and baby_why == "", pid, baby_why if baby_why != "" else "%s isn't here." % str(partner.get("name", "")))
		if pst == "fiance":
			_family_button(row, "have_wedding", "Hold Wedding", grown and here, pid, "%s isn't here." % str(partner.get("name", "")))
	_family_button(row, "adopt_child", "Adopt a Child", grown, -1, "Adults only.")
	_heir_row()

## Task 15: who plays on when the head of the family dies, and a button to pick the heir.
func _heir_row() -> void:
	var pid: int = Players.local_id
	if not Players.owns(pid, int(UIU.prop(folk, "household_id", 0))):
		return
	var head: int = Succession.head_of(pid)
	var line: Array = HeirLine.candidates(head, Players.household_of(pid), pid)
	if line.is_empty() and folk_id == head:          # living alone: nobody to name, so no heir row (it would only be a greyed button)
		return
	family_box.add_child(UIU.make_label("HEAD OF THE FAMILY: %s" % Family.name_of(head), 12, UITheme.ACCENT))
	var heir_txt := "Next in line: %s" % str(line[0]["label"]) if not line.is_empty() else "Nobody is next in line. You would choose who to play."
	var lab := UIU.make_label("  " + heir_txt, 13)
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	family_box.add_child(lab)
	var b := Button.new()
	var is_heir: bool = Succession.heir_of(pid) == folk_id
	b.text = "Heir: yes (click to clear)" if is_heir else "Make Heir"
	b.disabled = folk_id == head
	b.tooltip_text = "The head of the family cannot be their own heir." if folk_id == head else "This person plays on when the head of the family dies."
	b.pressed.connect(func():
		Commands.run({"player_id": pid, "folk_id": folk_id, "action": "set_heir", "args": {"heir_id": -1 if is_heir else folk_id}})
		_build_family())
	family_box.add_child(b)

func _family_button(row: Control, iid: String, text: String, enabled: bool, target: int, why_not: String) -> void:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	if not enabled:
		b.tooltip_text = why_not
		b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.pressed.connect(func(): UIU.enqueue(folk, iid, target))
	row.add_child(b)
	family_buttons[iid] = b

# ---------------- why? ----------------
func _refresh_why() -> void:
	if why_label == null:
		return
	if not why_toggle.button_pressed:
		why_label.text = "Switch this on to see why they chose what they are doing."
		return
	var ac = UIU.cls("Autonomy")
	var all_dbg = ac.get("last_debug") if ac != null else null
	var dbg = all_dbg.get(folk_id) if all_dbg is Dictionary else null
	if not (dbg is Dictionary):
		why_label.text = "Nothing decided yet. Folk think for themselves when they have nothing queued."
		return
	var lines: Array = ["Last decision (%s):" % str(dbg.get("time", "")), "  " + str(dbg.get("reason", "nothing to do"))]
	var top: Array = dbg.get("top", [])
	if top.size() > 1:
		lines.append("Other options it weighed:")
		for r in top:
			lines.append("  %s  (score %.1f)" % [str(r.get("label", "?")), float(r.get("score", 0.0))])
	why_label.text = "
".join(lines)

# ---------------- compact / expanded (task 32d) ----------------
## The panel starts compact so it does not cover the home: face, mood and a pip per need. Expanded = every tab as before.
signal expanded_changed(on: bool)

func set_expanded(on: bool) -> void:
	expanded = on
	expanded_changed.emit(on)
	UIPrefs.set_flag("folk_panel_expanded", on)
	if details_btn != null:
		details_btn.text = "Less" if on else "Details"
	for n in [trait_box, goal_row, tabs]:
		if n != null:
			(n as Control).visible = on
	if mini_box != null:
		mini_box.visible = not on
	custom_minimum_size = Vector2(360 if on else 320, 0)
	size = Vector2(custom_minimum_size.x, 0)

## One thin bar per need for the compact view; kept in step by _update_need.
func _build_mini() -> void:
	for c in mini_box.get_children():
		c.queue_free()
	mini_bars.clear()
	mini_icons.clear()
	var defs := UIU.tbl("needs")
	for nid in UIU.prop(folk, "needs", {}):
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		cell.tooltip_text = str((defs.get(nid, {}) as Dictionary).get("label", UIU.sentence(str(nid))))
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.step = 0.001
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(36, 8)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(bar)
		var ic := NeedIcon.new(str(nid), str((defs.get(nid, {}) as Dictionary).get("label", UIU.sentence(str(nid)))))          # task 59: a glyph, the full name on hover
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(ic)
		cell.move_child(ic, 0)
		mini_icons[nid] = ic
		mini_box.add_child(cell)
		mini_bars[nid] = bar
