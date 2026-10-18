class_name HouseholdCreator
extends Control
## Full-screen household editor: 1-6 Folk (name, age group, traits, aspiration, looks, relations) and, for Free Play,
## the home. Used by 'Customise' on any start and by Free Play. Emits done(household, start_id) / cancelled.
signal done(household: Dictionary, start_id: String)
signal cancelled

var household: Dictionary = {}
var start_id := "classic"
var selected := 0
var allow_home := false
var name_edit: LineEdit
var home_row: HBoxContainer
var home_cards: Dictionary = {}
var member_row: HBoxContainer
var add_btn: Button
var remove_btn: Button
var editor: FolkEditor
var error_label: Label
var go_btn: Button
var intro: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var wrap := HBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(wrap)
	for part in 3:
		if part == 1:
			wrap.add_child(_column())
		else:
			var sp := Control.new()
			sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			wrap.add_child(sp)

func _column() -> VBoxContainer:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.custom_minimum_size = Vector2(980, 0)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 14)
	root.add_child(pad)
	root.add_child(UIU.make_label("Create your household", 30, UITheme.ACCENT))
	intro = UIU.make_label("", 14, UITheme.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(intro)
	var top := HBoxContainer.new()
	root.add_child(top)
	top.add_child(UIU.make_label("Household name", 14))
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size = Vector2(220, 0)
	name_edit.max_length = 20
	name_edit.text_changed.connect(func(t): household["name"] = t.strip_edges())
	top.add_child(name_edit)
	home_row = HBoxContainer.new()
	home_row.add_theme_constant_override("separation", 10)
	root.add_child(home_row)
	member_row = HBoxContainer.new()
	root.add_child(member_row)
	editor = FolkEditor.new()
	editor.changed.connect(_on_edited)
	root.add_child(editor)
	error_label = UIU.make_label("", 14, Color("#e5534b"))
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(error_label)
	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func(): cancelled.emit())
	bottom.add_child(back)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp2)
	go_btn = Button.new()
	go_btn.custom_minimum_size = Vector2(200, 44)
	go_btn.pressed.connect(submit)
	bottom.add_child(go_btn)
	return root

## Edit `h` (a HouseholdSetup dictionary; it is copied). `with_home` shows the home chooser (Free Play).
func open(h: Dictionary, p_start_id: String, with_home: bool, go_text: String) -> void:
	household = h.duplicate(true)
	start_id = p_start_id
	allow_home = with_home
	selected = 0
	name_edit.text = str(household.get("name", "Fernwood"))
	go_btn.text = go_text
	intro.text = "Choose 1 to %d Folk. Pick an age group, three traits (they change what a Folk enjoys and how they behave), a life aspiration and a look. Hover for details." % HouseholdSetup.MAX_FOLK
	home_row.visible = with_home
	if with_home:
		_build_home_cards()
	error_label.text = ""
	_rebuild_members()
	visible = true

# ------------------------------------------------------------------ home chooser
func _build_home_cards() -> void:
	for c in home_row.get_children():
		home_row.remove_child(c)
		c.queue_free()
	home_cards.clear()
	home_row.add_child(UIU.make_label("Home", 14))
	for s in Neighborhood.starts():
		var sid := str(s["id"])
		var pc := PanelContainer.new()
		var v := VBoxContainer.new()
		pc.add_child(v)
		var th := LotThumb.new()
		th.template_id = str(s.get("template", "classic"))
		th.custom_minimum_size = Vector2(128, 80)
		v.add_child(th)
		v.add_child(UIU.make_label(str(s["label"]), 14))
		v.add_child(UIU.make_label("%s  |  bills: %s" % [s.get("size", ""), str(s.get("running_costs", "")).to_lower()], 11, UITheme.MUTED))
		pc.tooltip_text = str(s.get("description", ""))
		pc.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_pick_home(sid))
		home_row.add_child(pc)
		home_cards[sid] = pc
	_pick_home(start_id)

func _pick_home(sid: String) -> void:
	start_id = sid
	for k in home_cards:
		var on: bool = (k == sid)
		(home_cards[k] as PanelContainer).add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.PANEL_HI if on else UITheme.PANEL, 0.97), 8, UITheme.ACCENT if on else Color(1, 1, 1, 0.08), 2 if on else 1, 8))

# ------------------------------------------------------------------ members
func _members() -> Array:
	return household["folk"]

func _rebuild_members() -> void:
	for c in member_row.get_children():
		member_row.remove_child(c)
		c.queue_free()
	var folk := _members()
	for i in folk.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = (i == selected)
		b.text = "%s (%s)" % [str(folk[i]["name"]), HouseholdSetup.STAGE_LABELS.get(str(folk[i]["stage"]), "")]
		b.custom_minimum_size = Vector2(130, 34)
		var idx := i
		b.pressed.connect(func(): _select(idx))
		member_row.add_child(b)
	add_btn = Button.new()
	add_btn.text = "+ Add Folk"
	add_btn.disabled = folk.size() >= HouseholdSetup.MAX_FOLK
	add_btn.tooltip_text = "Up to %d Folk per household" % HouseholdSetup.MAX_FOLK
	add_btn.pressed.connect(_add_member)
	member_row.add_child(add_btn)
	remove_btn = Button.new()
	remove_btn.text = "Remove"
	remove_btn.disabled = folk.size() <= 1
	remove_btn.tooltip_text = "Remove the selected Folk"
	remove_btn.pressed.connect(_remove_member)
	member_row.add_child(remove_btn)
	_load_selected()

func _select(i: int) -> void:
	selected = i
	_rebuild_members()

func _load_selected() -> void:
	var folk := _members()
	selected = clampi(selected, 0, folk.size() - 1)
	editor.load_folk(folk[selected], selected == 0, str(folk[0]["name"]) if folk.size() > 0 else "")

func _add_member() -> void:
	var folk := _members()
	if folk.size() >= HouseholdSetup.MAX_FOLK:
		return
	var used: Array = []
	for fd in folk:
		used.append(fd["name"])
	folk.append(HouseholdSetup.random_folk("adult", "none", used))
	selected = folk.size() - 1
	_rebuild_members()

func _remove_member() -> void:
	var folk := _members()
	if folk.size() <= 1:
		return
	folk.remove_at(selected)
	for fd in folk:
		if selected == 0:
			fd["rel"] = "none"      # relations are relative to the first member
	selected = maxi(selected - 1, 0)
	_rebuild_members()

func _on_edited() -> void:
	error_label.text = ""
	var folk := _members()
	for i in member_row.get_child_count():
		if i < folk.size():
			(member_row.get_child(i) as Button).text = "%s (%s)" % [str(folk[i]["name"]), HouseholdSetup.STAGE_LABELS.get(str(folk[i]["stage"]), "")]

## Validate and hand the household back.
func submit() -> void:
	household["name"] = name_edit.text.strip_edges()
	if household["name"] == "":
		error_label.text = "Give your household a name."
		return
	var err := HouseholdSetup.validate(household)
	error_label.text = err
	if err == "":
		done.emit(household, start_id)
