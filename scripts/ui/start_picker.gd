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
var funds_base := -1               # Free Play funds option (-1 = the scenario's own funds)
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
	funds_row = HBoxContainer.new()
	root.add_child(funds_row)
	funds_row.add_child(UIU.make_label("Starting funds", 15))
	funds_opt = OptionButton.new()
	funds_opt.item_selected.connect(func(i):
		funds_base = int(funds_opt.get_item_metadata(i))
		_refresh())
	funds_row.add_child(funds_opt)

## Reset to the defaults: Solo Start, Normal.
func open() -> void:
	if creator != null:
		creator.visible = false
	difficulty = Scenario.default_difficulty()
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
	summary.text = "" if custom else "%s  -  %s" % [", ".join(names), ScenarioCard.coins_text(funds())]

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
	start_id = sid
	creator.visible = false
	_refresh()
	if bool(Scenario.def(selected_id).get("custom", false)):
		_emit_chosen()

func _emit_chosen() -> void:
	chosen.emit({"scenario": selected_id, "difficulty": difficulty, "start_id": start_id, "funds": funds(), "household": household})
