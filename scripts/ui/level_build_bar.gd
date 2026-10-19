class_name LevelBuildBar
extends VBoxContainer
## Build panel section for multi-floor building: add a floor above / a basement below, roof style, and the reason when it is not
## possible yet ("Place stairs going up on the top floor first"). The floor you build on is the one shown by FloorSelector.

var _above: Button
var _below: Button
var _roof: OptionButton
var _hint: Label
var _floor_label: Label
var _sig: String = ""


func _ready() -> void:
	add_child(UIU.make_label("FLOORS", 11, UITheme.ACCENT))
	_floor_label = UIU.make_label("", 13)
	_floor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_floor_label.custom_minimum_size = Vector2(270, 0)
	add_child(_floor_label)
	var row := VBoxContainer.new()
	add_child(row)
	_above = Button.new()
	_above.pressed.connect(func(): _add(true))
	row.add_child(_above)
	_below = Button.new()
	_below.pressed.connect(func(): _add(false))
	row.add_child(_below)
	var rr := HBoxContainer.new()
	add_child(rr)
	rr.add_child(UIU.make_label("Roof", 13))
	_roof = OptionButton.new()
	for s in LevelBuild.ROOF_STYLES:
		_roof.add_item("%s (%d C)" % [UIU.sentence(str(s)), int(LevelBuild.ROOF_PRICE[s])])
		_roof.set_item_metadata(_roof.item_count - 1, s)
	_roof.item_selected.connect(_on_roof)
	rr.add_child(_roof)
	_hint = UIU.make_label("", 12, UITheme.MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(270, 0)
	add_child(_hint)


func _lot():
	return get_tree().get_first_node_in_group("lot_view")


func _lv():
	var l = _lot()
	return l.get("level_view") if l != null else null


func _bid() -> int:
	var lv = _lv()
	return int(lv.building) if lv != null else -1


func _process(_d: float) -> void:
	if not is_visible_in_tree():
		return
	var bid := _bid()
	var lv = _lv()
	var sig := "%d|%d|%d" % [bid, World.levels.gen, lv.viewed if lv != null else 0]
	if sig == _sig:
		return
	_sig = sig
	refresh()


func refresh() -> void:
	var bid := _bid()
	var lv = _lv()
	if bid < 0 or lv == null:
		_above.text = "Add floor"
		_below.text = "Add basement"
		_above.disabled = true
		_below.disabled = true
		_hint.text = "Build on your own lot to add floors."
		return
	var b: Dictionary = World.levels.building(bid)
	var hi := int(b["max"])
	var lo := int(b["min"])
	_floor_label.text = "Building: %d floor%s%s. Showing: %s" % [hi + 1, "" if hi == 0 else "s", "" if lo == 0 else " + %d basement%s" % [-lo, "" if lo == -1 else "s"], LPos.level_name(lv.viewed)]
	_above.text = "Add floor (%d C)" % World.lbuild.level_price(hi + 1)
	_below.text = "Add basement (%d C)" % World.lbuild.level_price(lo - 1)
	var wa := World.lbuild.why_not_add(bid, true)
	var wb := World.lbuild.why_not_add(bid, false)
	_above.disabled = wa != ""
	_below.disabled = wb != ""
	_above.tooltip_text = wa if wa != "" else "Adds a new top floor over the building. It starts as the footprint below."
	_below.tooltip_text = wb if wb != "" else "Digs a basement under the building."
	_hint.text = wa if wa != "" else "Stairs are in place: you can add a floor above."
	if wb == "":
		_hint.text += " A basement can be dug too."
	for i in _roof.item_count:
		if str(_roof.get_item_metadata(i)) == str(b["roof"]):
			_roof.select(i)


func _add(above: bool) -> void:
	var bid := _bid()
	if bid < 0:
		return
	var lvl := World.lbuild.add_level(bid, above)
	if lvl == 0:
		UIU.notify(World.last_error if World.last_error != "" else "Can't add a floor yet", "warn")
		return
	var lv = _lv()
	if lv != null:
		lv.set_viewed(lvl)
	_sig = ""


func _on_roof(i: int) -> void:
	var bid := _bid()
	if bid < 0:
		return
	if not World.lbuild.set_roof(bid, str(_roof.get_item_metadata(i))):
		UIU.notify(World.last_error, "warn")
	_sig = ""
