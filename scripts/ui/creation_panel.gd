class_name CreationPanel
extends VBoxContainer
## Task 55: the Points column of the character creator (data/creation.json via Creation). A running total, the background, starting skills
## (- / +, the cost rises per level), perks and flaws as small cards (cost, one plain line), and Random. Edits write spec into the member
## dictionary (fd["creation"]) and emit `changed`. Telling the player what a perk does here is choosing a character, not a hint in play.
signal changed

const BAD := Color("#e8806a")
const TABS := ["Background", "Skills", "Perks and flaws"]
## Skill groups on the Skills tab (presentation only); a skill not listed goes under "Other".
const GROUPS := [["People", ["charisma", "manipulation", "intimidation", "perception"]], ["Hands", ["sleight", "lockpicking", "mechanics", "handiness"]],
	["Body", ["fitness", "fighting", "driving", "shooting"]], ["Mind", ["logic", "first_aid", "writing", "cooking"]]]

var spec: Dictionary = {}
var difficulty: String = "normal"
var _total: Label
var _bg_opt: OptionButton
var _bg_line: Label
var _body: VBoxContainer
var _tab: int = 0
var _tabs: TabBar
var _bg_box: VBoxContainer

func _ready() -> void:
	custom_minimum_size = Vector2(300, 0)
	add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	add_child(top)
	_total = UIU.make_label("", 15)
	_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_total)
	var rnd := Button.new()
	rnd.text = "Random"
	rnd.tooltip_text = "Roll a background, skills, perks and flaws within the points"
	rnd.pressed.connect(func():
		var r := RandomNumberGenerator.new()
		r.randomize()
		set_spec(Creation.random_spec(difficulty, r))
		changed.emit())
	top.add_child(rnd)
	_tabs = TabBar.new()
	for t in TABS:
		_tabs.add_tab(t)
	_tabs.tab_changed.connect(func(i):
		_tab = i
		_refresh())
	add_child(_tabs)
	_bg_box = VBoxContainer.new()
	add_child(_bg_box)
	_bg_opt = OptionButton.new()
	for id in (Creation.cfg().get("backgrounds", {}) as Dictionary):
		_bg_opt.add_item(str(Creation.background(str(id)).get("label", id)))
		_bg_opt.set_item_metadata(_bg_opt.item_count - 1, str(id))
	_bg_opt.item_selected.connect(func(i):
		spec["background"] = str(_bg_opt.get_item_metadata(i))
		_fit_skills()
		_refresh()
		changed.emit())
	_bg_box.add_child(_bg_opt)
	_bg_line = UIU.make_label("", 12, UITheme.MUTED)
	_bg_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bg_box.add_child(_bg_line)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(300, 430)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_body)
	if spec.is_empty():
		spec = Creation.empty_spec()
	_refresh()

func set_spec(s: Dictionary) -> void:
	spec = s
	if not spec.has("skills"):
		spec = Creation.empty_spec()
	if is_inside_tree():
		_refresh()

## A background change can push a bought skill over the cap: trim it.
func _fit_skills() -> void:
	var cap: int = int(Creation.cfg().get("skill_cap", 3))
	for sk in (spec["skills"] as Dictionary).keys():
		var room: int = cap - Creation.start_level(spec, str(sk))
		if int(spec["skills"][sk]) > room:
			spec["skills"][sk] = maxi(room, 0)
	for fl in (spec["flaws"] as Array).duplicate():
		if not Creation.allowed(_without(str(fl)), str(fl)):
			spec["flaws"].erase(fl)

func _without(id: String) -> Dictionary:
	var s: Dictionary = spec.duplicate(true)
	s["perks"].erase(id)
	s["flaws"].erase(id)
	return s

func _refresh() -> void:
	var left: int = Creation.left(spec, difficulty)
	_total.text = "Points left: %d" % left
	_total.add_theme_color_override("font_color", UITheme.ACCENT if left >= 0 else BAD)
	for i in _bg_opt.item_count:
		if str(_bg_opt.get_item_metadata(i)) == str(spec.get("background", "")):
			_bg_opt.select(i)
	var bg: Dictionary = Creation.background(str(spec.get("background", "")))
	var free: Array = []
	for sk in (bg.get("skills", {}) as Dictionary):
		free.append("%s %d" % [ContentRules.skill_label(str(sk)), int(bg["skills"][sk])])
	_bg_line.text = str(bg.get("text", "")) + ("\nStarts with: " + ", ".join(free) if not free.is_empty() else "")
	if str(bg.get("up", "")) != "":          # task 62: the trade, in words
		_bg_line.text += "\n+ " + str(bg["up"]) + "\n- " + str(bg.get("cost", ""))
	for c in _body.get_children():
		c.queue_free()
	_bg_box.visible = _tab == 0
	_body.get_parent().visible = _tab != 0
	if _tab == 1:
		var shown: Array = []
		for g in GROUPS:
			_body.add_child(UIU.make_label(str(g[0]), 13, UITheme.MUTED))
			for sk in g[1]:
				if Creation.skill_ids().has(sk):
					_body.add_child(_skill_row(str(sk)))
					shown.append(sk)
		var rest: Array = Creation.skill_ids().filter(func(s): return not shown.has(s))
		if not rest.is_empty():
			_body.add_child(UIU.make_label("Other", 13, UITheme.MUTED))
			for sk2 in rest:
				_body.add_child(_skill_row(str(sk2)))
	elif _tab == 2:
		_body.add_child(UIU.make_label("Perks (cost points)", 13, UITheme.MUTED))
		for id in (Creation.cfg().get("perks", {}) as Dictionary):
			_body.add_child(_card(str(id), true))
		_body.add_child(UIU.make_label("Flaws (give points)", 13, UITheme.MUTED))
		for id2 in (Creation.cfg().get("flaws", {}) as Dictionary):
			_body.add_child(_card(str(id2), false))

func _skill_row(sk: String) -> Control:
	var row := HBoxContainer.new()
	var start: int = Creation.start_level(spec, sk)
	var bought: int = int((spec["skills"] as Dictionary).get(sk, 0))
	var lv: int = start + bought
	var lab := UIU.make_label("%s  Lv %d" % [ContentRules.skill_label(sk), lv], 13, UITheme.TEXT if lv > 0 else UITheme.MUTED)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lab)
	var minus := Button.new()
	minus.text = "-"
	minus.disabled = bought <= 0
	minus.pressed.connect(func():
		spec["skills"][sk] = bought - 1
		if int(spec["skills"][sk]) <= 0:
			spec["skills"].erase(sk)
		_refresh()
		changed.emit())
	row.add_child(minus)
	var plus := Button.new()
	var cost: int = Creation.skill_price(lv, 1)
	plus.text = "+%d" % cost if Creation.can_buy_level(spec, sk) else "max"
	plus.disabled = not Creation.can_buy_level(spec, sk)
	plus.tooltip_text = "Raise to level %d for %d points" % [lv + 1, cost]
	plus.pressed.connect(func():
		spec["skills"][sk] = bought + 1
		_refresh()
		changed.emit())
	row.add_child(plus)
	return row

func _card(id: String, is_perk: bool) -> Control:
	var d: Dictionary = Creation.perk(id) if is_perk else Creation.flaw(id)
	var key: String = "perks" if is_perk else "flaws"
	var on: bool = (spec[key] as Array).has(id)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(UITheme.PANEL_HI if on else UITheme.PANEL, 6, UITheme.ACCENT if on else Color(0, 0, 0, 0), 1 if on else 0, 6))
	var v := VBoxContainer.new()
	p.add_child(v)
	var cb := CheckBox.new()
	cb.text = "%s  (%s%d)" % [str(d.get("label", id)), "-" if is_perk else "+", int(d.get("cost" if is_perk else "points", 0))]
	cb.button_pressed = on
	cb.disabled = not on and not Creation.allowed(spec, id)
	cb.toggled.connect(func(t):
		if t:
			spec[key].append(id)
		else:
			spec[key].erase(id)
		_refresh()
		changed.emit())
	v.add_child(cb)
	var line := UIU.make_label(str(d.get("text", "")), 12, UITheme.MUTED)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(line)
	return p
