class_name FolkEditor
extends HBoxContainer
## Edits ONE member dictionary of a household (see HouseholdSetup): name, age group, relation, traits, aspiration and looks,
## with a live FolkPreview. Edits write straight into the dictionary and emit `changed`.
signal changed

const SWATCH := Vector2(26, 26)

var fd: Dictionary = {}
var is_first := true
var first_name := ""
var _loading := false
var name_edit: LineEdit
var stage_opt: OptionButton
var rel_row: HBoxContainer
var rel_opt: OptionButton
var trait_opts: Array = []
var trait_info: Label
var asp_opt: OptionButton
var home_check: CheckBox
var preview: FolkPreview
var tabs: FolkLookTabs
var others_provider: Callable = Callable()   # -> Array of the other members' appearances (set by the household creator)
var sex_opt: OptionButton
var _prev_traits: Array = [-1, -1, -1]

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	add_child(left)
	var nr := HBoxContainer.new()
	left.add_child(nr)
	name_edit = LineEdit.new()
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.max_length = 14
	name_edit.text_changed.connect(func(t): _edit("name", t.strip_edges()))
	nr.add_child(name_edit)
	var dice := Button.new()
	dice.text = "Random"
	dice.tooltip_text = "Pick a random name"
	dice.pressed.connect(_random_name)
	nr.add_child(dice)
	left.add_child(UIU.make_label("Sex", 13, UITheme.MUTED))
	sex_opt = OptionButton.new()
	sex_opt.add_item("Female")
	sex_opt.add_item("Male")
	sex_opt.tooltip_text = "Female or male. Only a woman can be pregnant; relationships between any two adults are open. Looks and names follow."
	sex_opt.item_selected.connect(func(i): _set_sex(Sexes.BOTH[i]))
	left.add_child(sex_opt)
	left.add_child(UIU.make_label("Age group", 13, UITheme.MUTED))
	stage_opt = OptionButton.new()
	for s in HouseholdSetup.STAGES:
		stage_opt.add_item(HouseholdSetup.STAGE_LABELS[s])
	stage_opt.item_selected.connect(func(i): _set_stage(HouseholdSetup.STAGES[i]))
	left.add_child(stage_opt)
	rel_row = HBoxContainer.new()
	left.add_child(rel_row)
	rel_opt = OptionButton.new()
	rel_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rel_opt.tooltip_text = "How this Folk is related to the first member of the household"
	rel_opt.item_selected.connect(func(i): _edit("rel", HouseholdSetup.REL_ORDER[i]))
	rel_row.add_child(rel_opt)
	var th := HBoxContainer.new()
	left.add_child(th)
	var tl := UIU.make_label("Traits", 13, UITheme.MUTED)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(tl)
	var sur := Button.new()
	sur.text = "Surprise me"
	sur.tooltip_text = "Pick random traits"
	sur.pressed.connect(_random_traits)
	th.add_child(sur)
	_build_trait_opts(left)
	trait_info = UIU.make_label("", 12, UITheme.MUTED)
	trait_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trait_info.custom_minimum_size = Vector2(290, 84)
	left.add_child(trait_info)
	left.add_child(UIU.make_label("Life aspiration", 13, UITheme.MUTED))
	asp_opt = OptionButton.new()
	asp_opt.tooltip_text = "A long-term dream with milestones. Leave on 'Fits their traits' to let the game choose."
	asp_opt.add_item("Fits their traits")
	asp_opt.set_item_metadata(0, "")
	var defs: Dictionary = Goals.cfg().get("aspirations", {})
	for aid in Goals.aspiration_ids():
		asp_opt.add_item(str(defs[aid].get("label", aid)))
		asp_opt.set_item_metadata(asp_opt.item_count - 1, aid)
		asp_opt.set_item_tooltip(asp_opt.item_count - 1, str(defs[aid].get("description", "")))
	asp_opt.item_selected.connect(func(i): _edit("aspiration", str(asp_opt.get_item_metadata(i))))
	left.add_child(asp_opt)
	home_check = CheckBox.new()
	home_check.text = "Stays at home"
	home_check.tooltip_text = "No career: looks after the house, the cooking and the little ones. No job offers."
	home_check.toggled.connect(func(on): _edit("homemaker", on))
	left.add_child(home_check)
	var mid := VBoxContainer.new()
	mid.custom_minimum_size = Vector2(330, 0)
	add_child(mid)
	tabs = FolkLookTabs.new()
	tabs.look_changed.connect(_on_look)
	mid.add_child(tabs)
	var look := Button.new()
	look.text = "Random look"
	look.tooltip_text = "Roll a new random appearance that does not look like anyone else in the household or town"
	look.pressed.connect(func():
		fd["appearance"] = Genetics.unique_appearance(_others(), null, str(fd.get("sex", "")))
		load_folk(fd, is_first, first_name)
		changed.emit())
	mid.add_child(look)
	preview = FolkPreview.new()
	add_child(preview)

func _build_trait_opts(parent: Control) -> void:
	var traits: Dictionary = SimEnv.data().traits()
	var ids: Array = traits.keys()
	ids.sort()
	for k in 3:
		var ob := OptionButton.new()
		for t in ids:
			ob.add_item(str(traits[t].get("label", t)))
			ob.set_item_metadata(ob.item_count - 1, t)
			ob.set_item_tooltip(ob.item_count - 1, HouseholdSetup.trait_blurb(str(t)))
		var slot := k
		ob.item_selected.connect(func(i): _trait_picked(slot, i))
		parent.add_child(ob)
		trait_opts.append(ob)


# ------------------------------------------------------------------ data in
## Show member `data` (the dictionary is edited in place).
func load_folk(data: Dictionary, first: bool, first_member_name: String) -> void:
	_loading = true
	fd = data
	is_first = first
	first_name = first_member_name
	name_edit.text = str(fd.get("name", ""))
	if not Sexes.valid(fd.get("sex", "")):
		fd["sex"] = Sexes.guess(str(fd.get("name", "")), 0)
	sex_opt.select(Sexes.BOTH.find(str(fd["sex"])))
	stage_opt.select(maxi(HouseholdSetup.stage_rank(str(fd.get("stage", "adult"))), 0))
	rel_row.visible = not first
	rel_opt.clear()
	for r in HouseholdSetup.REL_ORDER:
		rel_opt.add_item(_rel_label(r))
	rel_opt.select(maxi(HouseholdSetup.REL_ORDER.find(str(fd.get("rel", "none"))), 0))
	_show_traits()
	home_check.button_pressed = bool(fd.get("homemaker", false)) and str(fd.get("stage", "adult")) in ["adult", "elder"]
	home_check.disabled = not (str(fd.get("stage", "adult")) in ["adult", "elder"])
	var asp: String = str(fd.get("aspiration", ""))
	for i in asp_opt.item_count:
		if str(asp_opt.get_item_metadata(i)) == asp:
			asp_opt.select(i)
	fd["appearance"] = Genetics.normalize(fd["appearance"])
	tabs.load_ap(fd["appearance"])
	_loading = false
	preview.show_folk(str(fd.get("stage", "adult")), fd["appearance"])

func _rel_label(r: String) -> String:
	if first_name == "":
		return str(HouseholdSetup.REL_LABELS[r])
	return {"none": "Unrelated to %s", "partner": "Partner of %s", "spouse": "Spouse of %s", "child": "Child of %s",
		"parent": "Parent of %s", "sibling": "Sibling of %s"}[r] % first_name

func _show_traits() -> void:
	var want: int = HouseholdSetup.trait_count(str(fd.get("stage", "adult")))
	var have: Array = fd.get("traits", [])
	while have.size() > want:
		have.pop_back()
	if have.size() < want:
		have = HouseholdSetup.random_traits(want)
	fd["traits"] = have
	for k in 3:
		var ob: OptionButton = trait_opts[k]
		ob.visible = k < want
		if k < have.size():
			for i in ob.item_count:
				if str(ob.get_item_metadata(i)) == str(have[k]):
					ob.select(i)
		_prev_traits[k] = ob.selected
	var lines: Array = []
	for t in have:
		var td: Dictionary = SimEnv.data().trait_def(str(t))
		lines.append("%s: %s" % [td.get("label", t), HouseholdSetup.trait_blurb(str(t))])
	trait_info.text = "\n".join(lines)


# ------------------------------------------------------------------ edits
func _edit(key: String, v) -> void:
	if _loading:
		return
	fd[key] = v
	changed.emit()

func _on_look(_key: String, _v) -> void:
	var ap: Dictionary = fd["appearance"]
	fd["color"] = Color.html(str(ap["shirt"]))
	preview.show_folk(str(fd.get("stage", "adult")), ap)
	changed.emit()

func _set_stage(s: String) -> void:
	if _loading:
		return
	fd["stage"] = s
	_show_traits()
	preview.show_folk(s, fd["appearance"])
	changed.emit()

func _set_sex(s: String) -> void:
	if _loading:
		return
	fd["sex"] = s
	GeneticsSex.fit(fd["appearance"], s)
	_loading = true
	tabs.load_ap(fd["appearance"])
	_loading = false
	preview.show_folk(str(fd.get("stage", "adult")), fd["appearance"])
	changed.emit()

func _random_name() -> void:
	fd["name"] = HouseholdSetup.random_name([], null, str(fd.get("sex", "")))
	name_edit.text = str(fd["name"])
	changed.emit()

func _random_traits() -> void:
	fd["traits"] = HouseholdSetup.random_traits(HouseholdSetup.trait_count(str(fd.get("stage", "adult"))))
	_show_traits()
	changed.emit()

func _trait_picked(slot: int, idx: int) -> void:
	if _loading:
		return
	# picking a trait another slot already has swaps the two, so the three stay different
	for k in trait_opts.size():
		var other: OptionButton = trait_opts[k]
		if k != slot and other.visible and other.selected == idx:
			other.select(int(_prev_traits[slot]))
	var ts: Array = []
	for k2 in trait_opts.size():
		var ob: OptionButton = trait_opts[k2]
		_prev_traits[k2] = ob.selected
		if ob.visible:
			ts.append(ob.get_item_metadata(ob.selected))
	fd["traits"] = ts
	_show_traits()
	changed.emit()

## Appearances this member must not clone: the other household members + everyone already in town.
func _others() -> Array:
	var out: Array = others_provider.call() if others_provider.is_valid() else []
	return out + GeneticsUnique.registry()
