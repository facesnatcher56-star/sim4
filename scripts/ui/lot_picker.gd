class_name LotPicker
extends Control
## New-game home chooser: cards for the starting lots in data/neighborhood.json ("starts"), each with a floor-plan
## thumbnail, description and starting funds. Emits picked(start_id) / cancelled.
signal picked(start_id: String)
signal cancelled

const THUMB := Vector2(224, 168)

# Hand-drawn plan of the classic starter house (floors + walls) for its thumbnail.
const CLASSIC_FLOORS := [[4, 4, 9, 9, "carpet"], [10, 4, 13, 9, "tile"], [14, 4, 19, 9, "carpet"], [4, 10, 10, 15, "tile"],
	[11, 10, 19, 15, "wood"], [15, 16, 15, 20, "stone"]]
const CLASSIC_WALLS := [[4, 4, 20, 4], [4, 16, 20, 16], [4, 4, 4, 16], [20, 4, 20, 16], [4, 10, 20, 10], [10, 4, 10, 10], [14, 4, 14, 10], [11, 10, 11, 16]]

var start_id_selected: String = ""
var cards: Dictionary = {}       # start id -> PanelContainer
var title_label: Label
var confirm_button: Button
var household_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(UITheme.BG, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	center.add_child(root)
	title_label = UIU.make_label("Choose your home", 30, UITheme.ACCENT)
	root.add_child(title_label)
	household_label = UIU.make_label("Bigger homes mean bigger bills - and a leaner starting wallet.", 14, UITheme.MUTED)
	root.add_child(household_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	root.add_child(row)
	for s in Neighborhood.starts():
		var card := _make_card(s)
		row.add_child(card)
		cards[str(s["id"])] = card
	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func(): cancelled.emit())
	bottom.add_child(back)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp)
	confirm_button = Button.new()
	confirm_button.text = "Move In"
	confirm_button.custom_minimum_size = Vector2(160, 40)
	confirm_button.pressed.connect(func(): if start_id_selected != "": picked.emit(start_id_selected))
	bottom.add_child(confirm_button)
	var starts: Array = Neighborhood.starts()
	if not starts.is_empty():
		select(str(starts[0]["id"]))

func select(start_id: String) -> void:
	start_id_selected = start_id
	for k in cards:
		var pc: PanelContainer = cards[k]
		var on: bool = (k == start_id)
		pc.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.PANEL_HI if on else UITheme.PANEL, 0.97), 10, UITheme.ACCENT if on else Color(1, 1, 1, 0.08), 2 if on else 1, 10))
	if confirm_button != null:
		confirm_button.text = "Move In: %s" % str(Neighborhood.start_def(start_id).get("label", start_id))

func _make_card(s: Dictionary) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(250, 0)
	var v := VBoxContainer.new()
	pc.add_child(v)
	var thumb := LotThumb.new()
	thumb.template_id = str(s.get("template", "classic"))
	thumb.custom_minimum_size = THUMB
	v.add_child(thumb)
	v.add_child(UIU.make_label(str(s.get("label", s["id"])), 20))
	var tid: String = str(s.get("template", "classic"))
	var info: Dictionary = LotLoader.template(tid)
	var objs: int = (info.get("objects", []) as Array).size() if tid != "classic" else 51
	var sz: String = {"classic": "2 bedrooms", "small": "Studio", "medium": "2-3 bedrooms", "large": "3 bedrooms + extras"}.get(str(s["id"]), "")
	v.add_child(UIU.make_label("%s  -  %d objects" % [sz, objs], 13, UITheme.MUTED))
	var d := UIU.make_label(str(s.get("description", "")), 13, UITheme.TEXT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(230, 78)
	v.add_child(d)
	v.add_child(UIU.make_label("Starting funds: %d coins" % int(s.get("funds", 5000)), 16, Color("#f2c94c")))
	var b := Button.new()
	b.text = "Choose"
	b.pressed.connect(select.bind(str(s["id"])))
	v.add_child(b)
	pc.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			select(str(s["id"])))
	return pc


## Floor-plan thumbnail of a lot template.
class LotThumb extends Control:
	var template_id: String = "classic"
	const FLOOR_COLORS := {"grass": "#4f7d3f", "dirt": "#7a5c3b", "stone": "#8a8a8a", "concrete": "#6f7478", "wood": "#a9794a", "tile": "#c3d2da", "carpet": "#7a6290"}

	func _draw() -> void:
		var s: Vector2 = size
		var ws := Vector2(32, 24)
		var k: float = minf(s.x / ws.x, s.y / ws.y)
		draw_rect(Rect2(Vector2.ZERO, ws * k), Color(FLOOR_COLORS["grass"]))
		var floors: Array = []
		var walls: Array = []
		var objs: Array = []
		if template_id == "classic":
			for f in LotPicker.CLASSIC_FLOORS:
				floors.append({"rect": [f[0], f[1], f[2], f[3]], "type": f[4]})
			for w in LotPicker.CLASSIC_WALLS:
				walls.append({"a": [w[0], w[1]], "b": [w[2], w[3]], "type": "wall"})
			walls.append({"a": [2, 2], "b": [30, 2], "type": "fence"})
			walls.append({"a": [30, 2], "b": [30, 22], "type": "fence"})
			walls.append({"a": [2, 22], "b": [30, 22], "type": "fence"})
			walls.append({"a": [2, 2], "b": [2, 22], "type": "fence"})
		else:
			var t: Dictionary = LotLoader.template(template_id)
			floors = t.get("floors", [])
			walls = t.get("walls", [])
			objs = t.get("objects", [])
		for fl in floors:
			var r: Array = fl["rect"]
			draw_rect(Rect2(Vector2(r[0], r[1]) * k, Vector2(r[2] - r[0] + 1, r[3] - r[1] + 1) * k), Color(FLOOR_COLORS.get(str(fl["type"]), "#888888")))
		for o in objs:
			var d: String = str(o["def"])
			if d == "door" or d == "window":
				continue
			var p := Vector2(o["tile"][0], o["tile"][1]) * k
			draw_rect(Rect2(p + Vector2(1, 1), Vector2(k - 2, k - 2)), Color(0.22, 0.2, 0.18, 0.85))
		for wl in walls:
			var a := Vector2(wl["a"][0], wl["a"][1]) * k
			var b := Vector2(wl["b"][0], wl["b"][1]) * k
			var fence: bool = str(wl["type"]) == "fence"
			draw_line(a, b, Color("#d9c9a8") if fence else Color("#f1ece2"), 1.0 if fence else 2.5)
		draw_rect(Rect2(Vector2.ZERO, ws * k), Color(1, 1, 1, 0.12), false, 1.0)
