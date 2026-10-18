class_name TitleMenu
extends Control
## Title screen + simple household creation.
signal new_game(household: Dictionary)      # {name, folk:[{name, traits:[..], color:Color}]}
signal continue_game(slot: int)
signal quit_game

var main_box: VBoxContainer
var create_box: VBoxContainer
var household_name: LineEdit
var rows: Array = []     # {name: LineEdit, traits:[OptionButton x3], color: ColorPickerButton}
var continue_btn: Button
var error_label: Label

const DEFAULT_NAMES := ["Mira", "Tobin", "Wren"]
const DEFAULT_COLORS := [Color("#e07a5f"), Color("#3d85c6"), Color("#81b29a")]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(UITheme.BG, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var root := VBoxContainer.new()
	panel.add_child(root)
	main_box = VBoxContainer.new()
	main_box.custom_minimum_size = Vector2(320, 0)
	root.add_child(main_box)
	main_box.add_child(UIU.make_label("sim-4", 44, UITheme.ACCENT))
	main_box.add_child(UIU.make_label("a tiny life simulation", 14, UITheme.MUTED))
	var nb := Button.new()
	nb.text = "New Household"
	nb.custom_minimum_size = Vector2(0, 40)
	nb.pressed.connect(show_create)
	main_box.add_child(nb)
	continue_btn = Button.new()
	continue_btn.text = "Continue / Load"
	continue_btn.custom_minimum_size = Vector2(0, 40)
	continue_btn.pressed.connect(_continue)
	main_box.add_child(continue_btn)
	var qb := Button.new()
	qb.text = "Quit"
	qb.custom_minimum_size = Vector2(0, 40)
	qb.pressed.connect(func(): quit_game.emit())
	main_box.add_child(qb)
	_build_create(root)
	refresh()

func refresh() -> void:
	continue_btn.disabled = not SaveSlots.has_any()

func _build_create(root: VBoxContainer) -> void:
	create_box = VBoxContainer.new()
	create_box.visible = false
	root.add_child(create_box)
	create_box.add_child(UIU.make_label("Create your household", 22))
	var hr := HBoxContainer.new()
	create_box.add_child(hr)
	hr.add_child(UIU.make_label("Household name", 14))
	household_name = LineEdit.new()
	household_name.text = "Fernwood"
	household_name.custom_minimum_size = Vector2(220, 0)
	hr.add_child(household_name)
	var traits := UIU.tbl("traits")
	var tids: Array = traits.keys()
	tids.sort()
	for i in 3:
		var card := VBoxContainer.new()
		create_box.add_child(card)
		var top := HBoxContainer.new()
		card.add_child(top)
		var cp := ColorPickerButton.new()
		cp.color = DEFAULT_COLORS[i]
		cp.custom_minimum_size = Vector2(44, 28)
		cp.edit_alpha = false
		top.add_child(cp)
		var ne := LineEdit.new()
		ne.text = DEFAULT_NAMES[i]
		ne.custom_minimum_size = Vector2(150, 0)
		top.add_child(ne)
		var tr := HBoxContainer.new()
		card.add_child(tr)
		var opts: Array = []
		for k in 3:
			var ob := OptionButton.new()
			ob.custom_minimum_size = Vector2(120, 0)
			for t in tids:
				ob.add_item(str(traits[t].get("label", t)))
				ob.set_item_metadata(ob.item_count - 1, t)
			if tids.size() > 0:
				ob.select((i * 3 + k) % tids.size())
			tr.add_child(ob)
			opts.append(ob)
		rows.append({"name": ne, "traits": opts, "color": cp})
	error_label = UIU.make_label("", 13, Color("#e5534b"))
	create_box.add_child(error_label)
	var hb := HBoxContainer.new()
	create_box.add_child(hb)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func():
		create_box.visible = false
		main_box.visible = true)
	hb.add_child(back)
	var go := Button.new()
	go.text = "Start Playing"
	go.pressed.connect(submit)
	hb.add_child(go)

func show_create() -> void:
	main_box.visible = false
	create_box.visible = true

func collect() -> Dictionary:
	var folk: Array = []
	for r in rows:
		var ts: Array = []
		for ob in r["traits"]:
			if ob.selected >= 0:
				var t = ob.get_item_metadata(ob.selected)
				if not (t in ts):
					ts.append(t)
		folk.append({"name": r["name"].text.strip_edges(), "traits": ts, "color": r["color"].color})
	return {"name": household_name.text.strip_edges(), "folk": folk}

func validate(h: Dictionary) -> String:
	if h["name"] == "":
		return "Give your household a name."
	var seen := {}
	for f in h["folk"]:
		if f["name"] == "":
			return "Every folk needs a name."
		if seen.has(f["name"]):
			return "Names must be distinct."
		seen[f["name"]] = true
		if f["traits"].size() < 3 and UIU.tbl("traits").size() >= 3:
			return "%s needs 3 different traits." % f["name"]
	return ""

func submit() -> void:
	var h := collect()
	var err := validate(h)
	error_label.text = err
	if err == "":
		new_game.emit(h)

func _continue() -> void:
	for i in range(SaveSlots.SLOTS, 0, -1):
		if SaveSlots.has_slot(i):
			continue_game.emit(i)
			return
