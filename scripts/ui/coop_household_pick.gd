class_name CoopHouseholdPick
extends Control
## A joining co-op player chooses their household: a ready-made one (scenario presets) or their own (the normal household creator).
## The host then gives them a free home (a neighbour's house) and the folk move in. Emits `chosen(household)`; the lobby sends it.
signal chosen(household: Dictionary)
signal cancelled

var presets: Array = []
var picked: int = 0
var household: Dictionary = {}
var _list: VBoxContainer
var _summary: Label
var _creator: HouseholdCreator
var _error: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(UITheme.BG, 0.98)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	center.add_child(box)
	box.add_child(UIU.make_label("Choose your household", 28, UITheme.ACCENT))
	var intro := UIU.make_label("You will have your own home and money in this shared town. Pick a ready-made household or build your own.", 13, UITheme.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)
	_list = VBoxContainer.new()
	box.add_child(_list)
	_summary = UIU.make_label("", 14)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_summary)
	var row := HBoxContainer.new()
	box.add_child(row)
	_button("Customise...", _customise, row)
	_button("Move in", func(): chosen.emit(household), row)
	_button("Back", func(): cancelled.emit(), row)
	_error = UIU.make_label("", 14, UITheme.sem("bad"))
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_error)
	_creator = HouseholdCreator.new()
	_creator.visible = false
	add_child(_creator)
	_creator.done.connect(func(h, _sid):
		household = h
		_creator.visible = false
		_refresh())
	_creator.cancelled.connect(func(): _creator.visible = false)
	reroll()

func _button(text: String, cb: Callable, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 36)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func reroll() -> void:
	presets = CoopHouseholds.presets(3)
	for c in _list.get_children():
		c.queue_free()
	for i in presets.size():
		var idx := i
		var b := _button(str(presets[i]["label"]), func(): pick(idx), _list)
		b.toggle_mode = true
	pick(0)

func pick(i: int) -> void:
	picked = clampi(i, 0, presets.size() - 1)
	household = (presets[picked]["household"] as Dictionary).duplicate(true)
	for k in _list.get_child_count():
		(_list.get_child(k) as Button).button_pressed = (k == picked)
	_refresh()

func _refresh() -> void:
	var names: Array = []
	for fd in household.get("folk", []):
		names.append("%s (%s)" % [fd["name"], HouseholdSetup.STAGE_LABELS.get(str(fd["stage"]), "")])
	_summary.text = "%s: %s" % [household.get("name", ""), ", ".join(names)]

func _customise() -> void:
	_creator.open(household, "classic", false, "Use this character" if (household.get("folk", []) as Array).size() <= 1 else "Use this household")
	_creator.visible = true

func show_error(msg: String) -> void:
	_error.text = msg
