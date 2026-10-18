class_name ScenarioCard
extends PanelContainer
## One start option on the new-game screen: floor-plan thumbnail, title, short description and chips (who / where / money / tone).
signal picked(scenario_id: String)
signal rerolled(scenario_id: String)

var scenario_id := ""
var money_label: Label
var thumb: LotThumb
var reroll_btn: Button
var _selected := false

static func coins_text(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out + " coins"

func setup(def: Dictionary, funds: int) -> void:
	scenario_id = str(def["id"])
	custom_minimum_size = Vector2(228, 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	thumb = LotThumb.new()
	thumb.template_id = str(Neighborhood.start_def(str(def.get("start_id", "classic"))).get("template", "classic"))
	thumb.custom_minimum_size = Vector2(0, 156)
	v.add_child(thumb)
	reroll_btn = Button.new()
	reroll_btn.text = "Reroll home"
	reroll_btn.tooltip_text = "Show another floor plan for this start"
	reroll_btn.pressed.connect(func(): rerolled.emit(scenario_id))
	v.add_child(reroll_btn)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := UIU.make_label(str(def["label"]), 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if str(def.get("badge", "")) != "":
		head.add_child(_chip(str(def["badge"]), UITheme.ACCENT.darkened(0.45), Color.WHITE))
	var d := UIU.make_label(str(def.get("blurb", "")), 13, UITheme.TEXT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(0, 42)
	v.add_child(d)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 4)
	chips.add_theme_constant_override("v_separation", 4)
	v.add_child(chips)
	chips.add_child(_chip(str(def.get("who", "")), UITheme.PANEL_HI, UITheme.TEXT, "Who lives here"))
	chips.add_child(_chip(str(def.get("where", "")), UITheme.PANEL_HI, UITheme.TEXT, "The home"))
	var m := _chip(coins_text(funds), Color("#4a3d12"), Color("#f2c94c"), "Starting funds at the chosen difficulty")
	money_label = m.get_child(0)
	chips.add_child(m)
	chips.add_child(_chip(str(def.get("tone", "")), UITheme.PANEL_HI, UITheme.MUTED, "How the start feels"))
	gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			picked.emit(scenario_id))
	set_selected(false)

## Show this home layout (and the Reroll button only when the start has more than one to offer).
func set_home(template_id: String, can_reroll: bool) -> void:
	thumb.template_id = template_id
	reroll_btn.visible = can_reroll
	thumb.tooltip_text = str(LotLoader.template(template_id).get("label", ""))

func set_funds(funds: int) -> void:
	money_label.text = coins_text(funds)

func set_selected(on: bool) -> void:
	_selected = on
	add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.PANEL_HI if on else UITheme.PANEL, 0.97), 10, UITheme.ACCENT if on else Color(1, 1, 1, 0.08), 3 if on else 1, 10))

static func _chip(text: String, bg: Color, fg: Color, tip: String = "") -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.box(bg, 9, Color(0, 0, 0, 0), 0, 7))
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	pc.tooltip_text = tip
	pc.add_child(UIU.make_label(text, 12, fg))
	return pc
