class_name FloorSelector
extends PanelContainer
## Floor controls (right edge): one button per level of the building you are looking at (top floor first), up / down arrows, a
## "Follow" box (the view follows the selected Folk's floor) and dots for the Folk on each floor, so you always know where everybody is.
## Page Up / Page Down do the same (actions sim_level_up / sim_level_down). Shown only while the active building has more than one level,
## or in Build mode (to add floors). Display only: all state is in LevelView.

var lot_view = null
var _box: VBoxContainer
var _rows: Dictionary = {}
var _follow: CheckBox
var _clock: float = 0.0
var _sig: String = ""


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_right = -12
	offset_left = -118
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BOTH
	_box = VBoxContainer.new()
	add_child(_box)


func _lv():
	if lot_view == null:
		lot_view = get_tree().get_first_node_in_group("lot_view")
	return lot_view.get("level_view") if lot_view != null else null


func _process(delta: float) -> void:
	_clock += delta
	if _clock < 0.25:
		return
	_clock = 0.0
	refresh()


func refresh() -> void:
	var lv = _lv()
	if lv == null or not lv.active():
		visible = false
		return
	var r: Vector2i = lv.range_of_building()
	var building_mode: bool = lot_view != null and str(lot_view.get("tool")) != "select"
	visible = r.y > r.x or building_mode
	if not visible:
		return
	offset_right = -332.0 if building_mode else -12.0      # beside the build panel, not under it
	offset_left = offset_right - 106.0
	var by_level: Dictionary = lv.folk_by_level()
	var sel_id := int(lot_view.get("selected_id")) if str(lot_view.get("selected_kind")) == "folk" else -1
	var sig := "%d|%d|%d|%s|%s" % [r.x, r.y, lv.viewed, str(by_level), str(lv.follow)] + "|%d" % sel_id
	if sig == _sig:
		return
	_sig = sig
	for c in _box.get_children():
		c.queue_free()
	_rows.clear()
	_box.add_child(UIU.make_label("Floor", 13, UITheme.MUTED))
	var up := Button.new()
	up.text = "Up"
	up.tooltip_text = "Go up one floor (Page Up)"
	up.disabled = lv.viewed >= r.y
	up.pressed.connect(func(): lv.step(1))
	_box.add_child(up)
	for l in range(r.y, r.x - 1, -1):
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = l == lv.viewed
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var folk: Array = by_level.get(l, [])
		var dots := ""
		var you := sel_id >= 0 and folk.has(sel_id)
		for i in mini(folk.size() - (1 if you else 0), 5):
			dots += "o"
		b.text = "%s  %s%s" % [LPos.level_label(l), "*" if you else "", dots]
		b.tooltip_text = "%s - %d Folk here" % [LPos.level_name(l), folk.size()]
		b.pressed.connect(func(): lv.set_viewed(l))
		_box.add_child(b)
		_rows[l] = b
	var dn := Button.new()
	dn.text = "Down"
	dn.tooltip_text = "Go down one floor (Page Down)"
	dn.disabled = lv.viewed <= r.x
	dn.pressed.connect(func(): lv.step(-1))
	_box.add_child(dn)
	_follow = CheckBox.new()
	_follow.text = "Follow"
	_follow.tooltip_text = "The view follows the floor of the selected Folk"
	_follow.button_pressed = lv.follow
	_follow.toggled.connect(func(on): lv.set_follow(on))
	_box.add_child(_follow)
