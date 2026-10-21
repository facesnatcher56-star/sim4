class_name BuildPanel
extends PanelContainer
## Build/Buy mode panel: catalog from objects.json grouped by tag, wall/floor/sell tools, undo.
## Ghost preview, R-rotate, click-to-place, wall dragging and Ctrl+Z all live in LotView (world agent);
## this panel just drives it via LotView.set_tool(tool, arg) and shows prices.
signal mode_changed(active: bool)

var lot_view = null
var active := false
var tool := "place"               # place | wall | floor | sell | select
var selected_def := ""
var wall_type := "wall"
var floor_id := "wood"
var catalog_box: VBoxContainer
var info_label: Label
var tool_buttons: Dictionary = {}
var catalog_buttons: Dictionary = {}
var wall_option: OptionButton
var floor_option: OptionButton

func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(300, 0)
	var root := VBoxContainer.new()
	add_child(root)
	root.add_child(UIU.make_label("Build / Buy", 18))
	var tools := HFlowContainer.new()
	root.add_child(tools)
	for t in ["place", "wall", "floor", "sell"]:
		var b := Button.new()
		b.text = {"place": "Buy", "wall": "Wall", "floor": "Floor", "sell": "Sell"}[t]
		b.toggle_mode = true
		b.pressed.connect(set_tool.bind(t))
		tools.add_child(b)
		tool_buttons[t] = b
	var u := Button.new()
	u.text = "Undo"
	u.tooltip_text = "Undo last build action (Ctrl+Z)"
	u.pressed.connect(undo)
	tools.add_child(u)
	var opts := HBoxContainer.new()
	root.add_child(opts)
	wall_option = OptionButton.new()
	for w in ["wall", "fence", "none"]:
		wall_option.add_item({"wall": "Wall", "fence": "Fence", "none": "Erase wall"}[w])
		wall_option.set_item_metadata(wall_option.item_count - 1, w)
	wall_option.item_selected.connect(func(i):
		wall_type = wall_option.get_item_metadata(i)
		if tool == "wall": set_tool("wall"))
	opts.add_child(wall_option)
	floor_option = OptionButton.new()
	var fd = World.get("FLOOR_DEFS")
	var fnames: Array = fd.keys() if fd is Dictionary else ["wood", "tile", "carpet", "stone"]
	if fd is Dictionary:
		fnames = fnames.filter(func(k): return not bool(fd[k].get("terrain", false)))   # roads/water aren't player floors
	for fl in fnames:
		floor_option.add_item(UIU.sentence(str(fl)))
		floor_option.set_item_metadata(floor_option.item_count - 1, fl)
	floor_option.add_item("Remove floor")
	floor_option.set_item_metadata(floor_option.item_count - 1, "none")
	floor_option.item_selected.connect(func(i):
		floor_id = str(floor_option.get_item_metadata(i))
		if tool == "floor": set_tool("floor"))
	opts.add_child(floor_option)
	for i in floor_option.item_count:
		if str(floor_option.get_item_metadata(i)) == "wood":
			floor_option.select(i)
	floor_id = str(floor_option.get_item_metadata(floor_option.selected)) if floor_option.item_count > 0 else "wood"
	info_label = UIU.make_label("", 12, UITheme.MUTED)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(info_label)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 360)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	root.add_child(LevelBuildBar.new())          # floors and roofs: below the things to buy (docs/UI_STYLE.md: the first thing a poor player needs is a bed)
	catalog_box = VBoxContainer.new()
	catalog_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(catalog_box)
	build_catalog()
	_refresh_buttons()

func build_catalog(table: Dictionary = {}) -> void:
	for c in catalog_box.get_children():
		c.queue_free()
	catalog_buttons.clear()
	var objs: Dictionary = table if not table.is_empty() else UIU.tbl("objects")
	var groups: Dictionary = {}
	for id in objs:
		var tags: Array = objs[id].get("tags", [])
		var g := UIU.sentence(str(tags[0])) if tags.size() > 0 else "Misc"
		if not groups.has(g):
			groups[g] = []
		groups[g].append(id)
	var names: Array = groups.keys()
	names.sort()
	for g in names:
		catalog_box.add_child(UIU.make_label(g.to_upper(), 11, UITheme.ACCENT))
		var fl := HFlowContainer.new()
		catalog_box.add_child(fl)
		for id in groups[g]:
			var d: Dictionary = objs[id]
			var b := Button.new()
			b.text = "%s\n%d C" % [d.get("label", id), int(d.get("price", 0))]
			b.custom_minimum_size = Vector2(88, 48)
			b.tooltip_text = "%s: %d Coins. Click, then click on your lot to place it (R rotates)." % [d.get("label", id), int(d.get("price", 0))]
			b.pressed.connect(select_def.bind(id))
			fl.add_child(b)
			catalog_buttons[id] = b

func set_active(on: bool) -> void:
	if active == on:
		return
	active = on
	visible = on
	if lot_view and lot_view.has_method("set_tool"):
		if on:
			set_tool(tool if selected_def != "" or tool != "place" else "place")
		else:
			lot_view.call("set_tool", "select")
	mode_changed.emit(on)

func set_tool(t: String) -> void:
	tool = t
	var arg := ""
	match t:
		"place": arg = selected_def
		"wall": arg = wall_type
		"floor": arg = floor_id
	if lot_view and lot_view.has_method("set_tool"):
		if t == "place" and arg == "":
			lot_view.call("set_tool", "select")
		else:
			lot_view.call("set_tool", t, arg)
	var own: String = " You can only build on your own lot (the grid shows it)." if World.regions.has_regions() else ""
	info_label.text = {
		"place": "Pick an item below, then click on your lot. R rotates.",
		"wall": "Drag on your lot to draw a wall line (5 C per segment).",
		"floor": "Drag a rectangle to paint floor (2 C per tile).",
		"sell": "Click an object to sell it (you get part of the price back).",
	}.get(t, "") + (own if t != "" and t != "select" else "")
	_refresh_buttons()

func select_def(id: String) -> void:
	selected_def = id
	set_tool("place")

func _refresh_buttons() -> void:
	for k in tool_buttons:
		tool_buttons[k].set_pressed_no_signal(k == tool)

func undo() -> bool:
	if World.has_method("undo_last"):
		return bool(World.call("undo_last"))
	return false
