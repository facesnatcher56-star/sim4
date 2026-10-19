class_name FolkLookTabs
extends TabContainer
## The appearance pickers of the character creator in four compact tabs: Face / Hair / Body / Clothes. Pure view: it shows
## an appearance dictionary and emits `look_changed(key, value)` for every pick (the editor writes it and updates the preview).

signal look_changed(key: String, value)

const SWATCH := Vector2(24, 24)
const HAIR_NAMES := ["Short crop", "Buzz cut", "Long", "Ponytail", "Spiky", "Afro", "Curly", "Bun", "Braids", "Bald", "Mohawk",
	"Long straight", "Bob", "Quiff", "Pigtails", "Shaggy"]
const LABELS := {
	"body_type": ["Slim", "Average", "Broad"], "frame": ["Neutral", "Soft", "Angular"],
	"mouth": ["Mouth 1", "Mouth 2", "Mouth 3", "Mouth 4"], "brows": ["Brows 1", "Brows 2", "Brows 3", "Brows 4"],
	"ears": ["Ears 1", "Ears 2", "Ears 3"], "facial_hair": ["None", "Moustache", "Goatee", "Beard"],
	"mark": ["None", "Freckles", "Beauty mark"], "glasses": ["None", "Round", "Square"], "hat": ["None", "Cap", "Beanie"],
	"scarf": ["None", "Scarf"], "bag": ["None", "Backpack", "Satchel"],
	"top": ["T-shirt", "Hoodie", "Sweater", "Shirt", "Dress", "Apron", "Uniform"], "bottom": ["Trousers", "Shorts", "Skirt"],
	"shoes": ["Shoes", "Boots", "Barefoot", "Sneakers"],
}

var ap: Dictionary = {}
var _rows: Dictionary = {}          # key -> HFlowContainer of swatches
var _opts: Dictionary = {}          # key -> OptionButton
var _sliders: Dictionary = {}       # key -> HSlider
var _loading := false


func _init() -> void:
	custom_minimum_size = Vector2(340, 0)
	var gen: Dictionary = Genetics.cfg()
	var face := _tab("Face")
	_swatch_group(face, "Skin tone", "skin", gen.get("skin_tones", []))
	_swatch_group(face, "Eye colour", "eye_color", _hexes(gen.get("eye_colors", [])))
	_face_picker(face)
	for k in ["mouth", "brows", "ears", "facial_hair", "mark", "glasses"]:
		_choice(face, _title(k), k, LABELS[k])
	var hair := _tab("Hair")
	_choice(hair, "Hair style", "hair_style", HAIR_NAMES)
	_swatch_group(hair, "Hair colour", "hair_color", _hexes(gen.get("hair_colors", [])))
	var body := _tab("Body")
	_choice(body, "Body shape", "body_type", LABELS["body_type"])
	_choice(body, "Frame", "frame", LABELS["frame"])
	_slider(body, "Height", "height")
	_slider(body, "Build", "build")
	var cl := _tab("Clothes")
	_choice(cl, "Top", "top", LABELS["top"])
	_swatch_group(cl, "Top colour", "shirt", gen.get("shirt_colors", []))
	_choice(cl, "Bottom", "bottom", LABELS["bottom"])
	_swatch_group(cl, "Bottom colour", "pants", gen.get("pants_colors", []))
	_choice(cl, "Shoes", "shoes", LABELS["shoes"])
	_swatch_group(cl, "Accent colour (apron, cap, scarf, bag)", "accent", gen.get("accent_colors", []))
	for k in ["hat", "scarf", "bag"]:
		_choice(cl, _title(k), k, LABELS[k])


func _title(k: String) -> String:
	return UIU.sentence(k.replace("_", " "))


func _tab(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(330, 300)
	add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 3)
	sc.add_child(vb)
	return vb


func _hexes(arr: Array) -> Array:
	var out: Array = []
	for e in arr:
		out.append(str(e["hex"]) if e is Dictionary else str(e))
	return out


func _swatch_group(parent: Control, title: String, key: String, hexes: Array) -> void:
	parent.add_child(UIU.make_label(title, 13, UITheme.MUTED))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	parent.add_child(row)
	_rows[key] = row
	for hx in hexes:
		var b := Button.new()
		b.custom_minimum_size = SWATCH
		b.set_meta("hex", str(hx))
		b.tooltip_text = title
		b.pressed.connect(func(): _pick(key, str(hx)))
		row.add_child(b)


func _choice(parent: Control, title: String, key: String, labels: Array) -> void:
	var hb := HBoxContainer.new()
	parent.add_child(hb)
	var l := UIU.make_label(title, 13, UITheme.MUTED)
	l.custom_minimum_size = Vector2(96, 0)
	hb.add_child(l)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in labels:
		ob.add_item(str(s))
	ob.item_selected.connect(func(i): _pick(key, i))
	hb.add_child(ob)
	_opts[key] = ob


## Face shape = eyes (4) x nose (4); shown as one list of 16.
func _face_picker(parent: Control) -> void:
	var labels: Array = []
	for i in 16:
		labels.append("Face %d" % (i + 1))
	_choice(parent, "Face shape", "face", labels)


func _slider(parent: Control, title: String, key: String) -> void:
	var hb := HBoxContainer.new()
	parent.add_child(hb)
	var l := UIU.make_label(title, 13, UITheme.MUTED)
	l.custom_minimum_size = Vector2(96, 0)
	hb.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.9
	s.max_value = 1.1
	s.step = 0.01
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(160, 20)
	s.value_changed.connect(func(v): _pick(key, snappedf(v, 0.001)))
	hb.add_child(s)
	_sliders[key] = s


func _pick(key: String, v) -> void:
	if _loading:
		return
	ap[key] = v
	if key == "shirt":
		ap["color"] = v
	look_changed.emit(key, v)
	_refresh()


## Show this appearance (edited in place by the picks).
func load_ap(appearance: Dictionary) -> void:
	ap = appearance
	_refresh()


func _refresh() -> void:
	_loading = true
	for key in _rows:
		for b in (_rows[key] as Control).get_children():
			var hx: String = str(b.get_meta("hex"))
			var on: bool = hx.to_lower() == str(ap.get(key, "")).to_lower()
			b.add_theme_stylebox_override("normal", UITheme.box(Color.html(hx), 5, Color.WHITE if on else Color(0, 0, 0, 0.35), 3 if on else 1, 0))
			b.add_theme_stylebox_override("hover", UITheme.box(Color.html(hx).lightened(0.15), 5, UITheme.ACCENT, 2, 0))
			b.add_theme_stylebox_override("pressed", UITheme.box(Color.html(hx), 5, Color.WHITE, 3, 0))
	for key in _opts:
		(_opts[key] as OptionButton).select(clampi(int(ap.get(key, 0)), 0, (_opts[key] as OptionButton).item_count - 1))
	for key in _sliders:
		(_sliders[key] as HSlider).value = float(ap.get(key, 1.0))
	_loading = false
