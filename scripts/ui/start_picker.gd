class_name StartPicker
extends Control
## New-game screen: scenario cards (Solo Start pre-selected), difficulty, Customise and a big Start button.
## Emits chosen(config) with {scenario, difficulty, start_id, funds, household} or cancelled.
signal chosen(config: Dictionary)
signal cancelled

var selected_id := ""
var difficulty := "normal"
var household: Dictionary = {}
var start_id := "classic"
var world_seed := 0                # drawn per picker opening; the whole map follows from it
var homes: Dictionary = {}         # scenario id -> home template shown on its card
var home_state := "empty"           # task 32d: empty (furnish it yourself, default) or furnished
var home_buttons: Dictionary = {}
var home_desc: Label
var funds_base := -1               # Free Play funds option (-1 = the scenario's own funds)
var storyteller := "classic"       # task 29: the storyteller personality (Calm / Classic / Chaotic / Custom)
var st_custom: Dictionary = {}     # the four Custom sliders, 0..1
var st_buttons: Dictionary = {}
var st_desc: Label
var st_sliders: HBoxContainer
var cards: Dictionary = {}
var diff_buttons: Dictionary = {}
var diff_desc: Label
var funds_row: HBoxContainer
var funds_opt: OptionButton
var summary: Label
var start_btn: Button
var custom_btn: Button
var creator: HouseholdCreator

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
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.custom_minimum_size = Vector2(1180, 0)
	center.add_child(root)
	root.add_child(UIU.make_label("New Game", 32, UITheme.ACCENT))
	root.add_child(UIU.make_label("How do you want to begin? New to the game? Solo Start is the gentlest way in.", 14, UITheme.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	root.add_child(row)
	for s in Scenario.scenarios():
		var card := ScenarioCard.new()
		row.add_child(card)
		card.setup(s, Scenario.funds_for(str(s["id"]), Scenario.default_difficulty()))
		card.picked.connect(select)
		card.rerolled.connect(reroll_home)
		cards[str(s["id"])] = card
	_build_options(root)
	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func(): cancelled.emit())
	bottom.add_child(back)
	summary = UIU.make_label("", 14, UITheme.MUTED)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(summary)
	custom_btn = Button.new()
	custom_btn.text = "Customise..."
	custom_btn.tooltip_text = "Edit names, traits, looks and relations of the starting household"
	custom_btn.custom_minimum_size = Vector2(150, 44)
	custom_btn.pressed.connect(_open_creator.bind(false))
	bottom.add_child(custom_btn)
	start_btn = Button.new()
	start_btn.custom_minimum_size = Vector2(240, 54)
	start_btn.add_theme_font_size_override("font_size", 20)
	start_btn.pressed.connect(_on_start)
	bottom.add_child(start_btn)
	creator = HouseholdCreator.new()
	creator.visible = false
	add_child(creator)
	creator.cancelled.connect(func(): creator.visible = false)
	creator.done.connect(_on_creator_done)
	open()

func _build_options(root: VBoxContainer) -> void:
	var dr := HBoxContainer.new()
	root.add_child(dr)
	dr.add_child(UIU.make_label("Difficulty", 15))
	var grp := ButtonGroup.new()
	for d in Scenario.difficulty_ids():
		var b := Button.new()
		b.text = str(Scenario.difficulty_def(d).get("label", d))
		b.toggle_mode = true
		b.button_group = grp
		b.custom_minimum_size = Vector2(110, 34)
		b.pressed.connect(set_difficulty.bind(d))
		dr.add_child(b)
		diff_buttons[d] = b
	diff_desc = UIU.make_label("", 13, UITheme.MUTED)
	diff_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dr.add_child(diff_desc)
	_build_home_state(root)
	_build_storyteller(root)
	funds_row = HBoxContainer.new()
	root.add_child(funds_row)
	funds_row.add_child(UIU.make_label("Starting funds", 15))
	funds_opt = OptionButton.new()
	funds_opt.item_selected.connect(func(i):
		funds_base = int(funds_opt.get_item_metadata(i))
		_refresh())
	funds_row.add_child(funds_opt)

## Home row (task 32d): an empty home (the default) or a furnished one.
func _build_home_state(root: VBoxContainer) -> void:
	var hr := HBoxContainer.new()
	root.add_child(hr)
	var hl := UIU.make_label("Home", 15)
	hl.tooltip_text = "Start with bare walls and extra coins to furnish it yourself, or move into a furnished home. In co-op the host's choice applies."
	hr.add_child(hl)
	var grp := ButtonGroup.new()
	for hid in StartHome.ids():
		var b := Button.new()
		b.text = str(StartHome.option(hid).get("label", hid))
		b.toggle_mode = true
		b.button_group = grp
		b.custom_minimum_size = Vector2(110, 34)
		b.pressed.connect(set_home_state.bind(str(hid)))
		hr.add_child(b)
		home_buttons[str(hid)] = b
	home_desc = UIU.make_label("", 13, UITheme.MUTED)
	home_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(home_desc)

func set_home_state(s: String) -> void:
	home_state = StartHome.normalize(s)
	if home_buttons.has(home_state):
		(home_buttons[home_state] as Button).button_pressed = true
	if home_desc != null:
		home_desc.text = str(StartHome.option(home_state).get("desc", ""))
		_refresh()

## Storyteller row (task 29): pick how the unexpected plays out; Custom shows four sliders. The choice is saved as the default for the next game.
func _build_storyteller(root: VBoxContainer) -> void:
	var sr := HBoxContainer.new()
	root.add_child(sr)
	var tl := UIU.make_label("Storyteller", 15)
	tl.tooltip_text = "How the unexpected plays out. You can change it later in Settings. In co-op the host's choice applies."
	sr.add_child(tl)
	var grp := ButtonGroup.new()
	for pid in Storyteller.personality_ids():
		var b := Button.new()
		b.text = Storyteller.label(str(pid))
		b.toggle_mode = true
		b.button_group = grp
		b.custom_minimum_size = Vector2(110, 34)
		b.pressed.connect(set_storyteller.bind(str(pid)))
		sr.add_child(b)
		st_buttons[str(pid)] = b
	st_desc = UIU.make_label("", 13, UITheme.MUTED)
	st_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sr.add_child(st_desc)
	st_sliders = HBoxContainer.new()
	root.add_child(st_sliders)
	for k in [["frequency", "How often"], ["severity", "How big"], ["balance", "Good luck"], ["mercy", "Mercy"]]:
		st_sliders.add_child(UIU.make_label(str(k[1]), 13))
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.custom_minimum_size = Vector2(120, 24)
		s.value = float(st_custom.get(k[0], 0.5))
		s.value_changed.connect(func(v): st_custom[k[0]] = v)
		st_sliders.add_child(s)

func set_storyteller(p: String) -> void:
	storyteller = p
	if st_buttons.has(p):
		(st_buttons[p] as Button).button_pressed = true
	if st_desc != null:
		st_desc.text = Storyteller.blurb(p)
	if st_sliders != null:
		st_sliders.visible = p == "custom"

## Reset to the defaults: Solo Start, Normal.
func open() -> void:
	if creator != null:
		creator.visible = false
	difficulty = Scenario.default_difficulty()
	var sa: Dictionary = StorytellerCmd.settings_args()
	st_custom = (sa["custom"] as Dictionary).duplicate()
	set_storyteller(str(sa["personality"]))
	set_home_state(StartHome.default_id())
	var keys: Array = ["frequency", "severity", "balance", "mercy"]
	var i := 0
	for ch in st_sliders.get_children():
		if ch is HSlider:
			(ch as HSlider).set_value_no_signal(float(st_custom.get(keys[i], 0.5)))
			i += 1
	world_seed = randi() & 0x7fffffff
	homes.clear()
	for k in cards:
		var sid := str(Scenario.def(k).get("start_id", "classic"))
		_set_home(k, LotPicker.home_for(sid, world_seed + hash(k)), sid)
	select(Scenario.default_id())
	set_difficulty(difficulty)
	visible = true

func select(scenario_id: String) -> void:
	if Scenario.def(scenario_id).is_empty():
		return
	selected_id = scenario_id
	var def := Scenario.def(scenario_id)
	household = HouseholdSetup.make_household(scenario_id)
	start_id = str(def.get("start_id", "classic"))
	if not LotPicker.home_pool(start_id).has(homes.get(scenario_id, "")):
		_set_home(scenario_id, LotPicker.home_for(start_id, world_seed), start_id)
	funds_base = -1
	funds_opt.clear()
	for o in def.get("funds_options", []):
		funds_opt.add_item("%s (%s)" % [o["label"], ScenarioCard.coins_text(int(o["funds"]))])
		funds_opt.set_item_metadata(funds_opt.item_count - 1, int(o["funds"]))
	funds_row.visible = funds_opt.item_count > 0
	if funds_opt.item_count > 0:
		funds_base = int(funds_opt.get_item_metadata(0))
	for k in cards:
		(cards[k] as ScenarioCard).set_selected(k == scenario_id)
	_refresh()

func _set_home(scenario_id: String, tid: String, sid: String) -> void:
	homes[scenario_id] = tid
	(cards[scenario_id] as ScenarioCard).set_home(tid, LotPicker.home_pool(sid).size() > 1)

## Another floor plan of the same start (never the one shown now).
func reroll_home(scenario_id: String) -> void:
	if scenario_id != selected_id:
		select(scenario_id)
	_set_home(scenario_id, LotPicker.home_for(start_id, randi(), str(homes.get(scenario_id, ""))), start_id)

func set_difficulty(d: String) -> void:
	difficulty = d
	(diff_buttons[d] as Button).button_pressed = true
	_refresh()

func funds() -> int:
	return Scenario.funds_for(selected_id, difficulty, funds_base)

func _refresh() -> void:
	diff_desc.text = Scenario.difficulty_text(difficulty)
	for k in cards:
		var base := -1
		if k == selected_id and funds_base >= 0:
			base = funds_base
		(cards[k] as ScenarioCard).set_funds(Scenario.funds_for(str(k), difficulty, base))
	var def := Scenario.def(selected_id)
	var custom: bool = bool(def.get("custom", false))
	start_btn.text = "Create Household" if custom else "Start: %s" % str(def.get("label", ""))
	custom_btn.visible = not custom
	var names: Array = []
	for fd in household.get("folk", []):
		names.append(str(fd["name"]))
	var extra: String = ("  +  %s to furnish" % ScenarioCard.coins_text(StartHome.bonus(start_id))) if home_state == "empty" else ""
	summary.text = "" if custom else "%s  -  %s" % [", ".join(names), ScenarioCard.coins_text(funds())] + extra

func _open_creator(with_home: bool) -> void:
	var custom: bool = bool(Scenario.def(selected_id).get("custom", false))
	creator.open(household, start_id, with_home, "Start Playing" if custom else "Use this household")
	creator.visible = true

func _on_start() -> void:
	if bool(Scenario.def(selected_id).get("custom", false)):
		_open_creator(true)
		return
	_emit_chosen()

func _on_creator_done(h: Dictionary, sid: String) -> void:
	household = h
	if sid != start_id:          # another kind of home chosen in Free Play: its own pool
		_set_home(selected_id, LotPicker.home_for(sid, world_seed), sid)
	start_id = sid
	creator.visible = false
	_refresh()
	if bool(Scenario.def(selected_id).get("custom", false)):
		_emit_chosen()

func _emit_chosen() -> void:
	var st: Dictionary = StorytellerCmd.settings_args()
	st["personality"] = storyteller
	st["custom"] = st_custom.duplicate()
	GameSettings.set_value("storyteller", storyteller)         # the next new game starts from this choice
	GameSettings.set_value("storyteller_freq", int(round(float(st_custom.get("frequency", 0.5)) * 100.0)))
	GameSettings.set_value("storyteller_sev", int(round(float(st_custom.get("severity", 0.5)) * 100.0)))
	GameSettings.set_value("storyteller_good", int(round(float(st_custom.get("balance", 0.5)) * 100.0)))
	GameSettings.set_value("storyteller_mercy", int(round(float(st_custom.get("mercy", 0.5)) * 100.0)))
	chosen.emit({"storyteller": st, "scenario": selected_id, "difficulty": difficulty, "start_id": start_id, "funds": funds(), "household": household,
		"home_template": str(homes.get(selected_id, "")), "world_seed": world_seed, "home_state": home_state})
