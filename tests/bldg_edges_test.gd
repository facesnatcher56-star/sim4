extends RefCounted
## The rough edges of part A: a lift shaft follows a new basement down (and back up on undo), stairs going down are an opening in the ground
## floor, rain and snow start above the tallest roof, the floor selector scrolls and shows the floor names.

const Kit = preload("res://tests/level_kit.gd")

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	TestFixture.reset()
	_lift_follows_basement()
	_stairs_down_hole()
	_precip_height()
	_selector_scrolls()
	Kit.world().reset()
	return fails


func _lift_follows_basement() -> void:
	var W := Kit.world()
	var bid: int = Kit.tower(2, true)
	var lift = W.objects_of_def("elevator")[0]
	_check(lift.level == 0 and lift.span == 1, "the lift runs 0 .. 1")
	_check(W.place_object("stairs_down", Vector2i(6, 13), 0, 0) >= 0, "stairs down to a future basement: %s" % W.last_error)
	var lv: int = W.lbuild.add_level(bid, false)
	_check(lv == -1, "a basement is added (%d): %s" % [lv, W.last_error])
	lift = W.objects_of_def("elevator")[0]
	_check(lift.level == -1 and lift.span == 2, "the lift now starts in the basement (level %d, span %d)" % [lift.level, lift.span])
	var stop := Vector2i(16, 9)
	_check(W.has_route(Vector3i(stop.x, stop.y, -1), Vector3i(stop.x, stop.y, 1)), "a lift ride from the basement to the top floor")
	_check(W.portals.record(lift.id).get("stops", []).size() == 3, "three stops: basement, ground, 1st floor")
	_check(W.undo_last(), "undo the basement")
	var back = W.objects_of_def("elevator")
	_check(back.size() == 1 and back[0].level == 0 and back[0].span == 1, "the lift is shortened again by the undo")
	_check(W.has_route(Vector3i(stop.x, stop.y, 0), Vector3i(stop.x, stop.y, 1)), "and still works")
	W.reset()


func _stairs_down_hole() -> void:
	var W := Kit.world()
	Kit.tower(2, true, 1)
	_check(W.levels.ground_holes.has(Vector2i(6, 13)) and W.levels.ground_holes.has(Vector2i(7, 13)), "stairs down are an opening in the ground floor")
	var o = null
	for x in W.objects_of_def("stairs_down"):
		o = x
	W.remove_object(o.id)
	_check(not W.levels.ground_holes.has(Vector2i(6, 13)), "the opening closes when the stairs go")
	W.reset()
	_check(W.levels.ground_holes.is_empty(), "a world reset clears every opening")


class FakeLevelView:
	extends RefCounted
	var viewed: int = 3
	var follow: bool = false
	var building: int = 0
	func active() -> bool:
		return true
	func range_of_building() -> Vector2i:
		return Vector2i(-1, 14)
	func folk_by_level() -> Dictionary:
		return {}
	func step(_d: int) -> void:
		pass
	func set_viewed(l: int, _k: bool = false) -> void:
		viewed = l
	func set_follow(on: bool) -> void:
		follow = on


class FakeLot:
	extends Node
	var level_view = FakeLevelView.new()
	var tool: String = "select"
	var selected_kind: String = ""
	var selected_id: int = -1


func _precip_height() -> void:
	var W := Kit.world()
	W.reset(32, 24)
	var wv := WeatherView.new()
	wv.rain = wv._make_rain()
	wv.snow = wv._make_snow()
	wv._fit_to_buildings()
	var low_y: float = wv._rain_y
	_check(is_equal_approx(low_y, 17.0) and is_equal_approx(wv.rain.lifetime, 0.8), "no buildings: the old sky (y %.1f)" % low_y)
	Kit.tower(15, true)
	wv._fit_to_buildings()
	_check(wv._rain_y >= 15.0 * LPos.H and wv._rain_y > low_y, "rain starts above a 15-storey roof (y %.1f, roof %.1f)" % [wv._rain_y, 15.0 * LPos.H])
	_check(wv.rain.lifetime * 26.0 >= wv._rain_y, "and lives long enough to reach the ground (%.2f s)" % wv.rain.lifetime)
	_check(wv.rain.amount > 2200, "with more drops, so the density is the same (%d)" % wv.rain.amount)
	_check(wv._snow_y >= 15.0 * LPos.H and wv.snow.lifetime > 9.0, "snow too (y %.1f, %.1f s)" % [wv._snow_y, wv.snow.lifetime])
	wv.rain.free()
	wv.snow.free()
	wv.free()
	W.reset()


func _selector_scrolls() -> void:
	var root: Window = Engine.get_main_loop().root
	var lot := FakeLot.new()
	lot.add_to_group("lot_view")
	root.add_child(lot)
	var sel := FloorSelector.new()
	root.add_child(sel)
	sel.lot_view = lot
	sel.refresh()
	_check(sel.visible and sel._scroll != null, "the selector shows for a tall building and has a scroll area")
	_check(sel._rows.size() == 16, "one row per floor (%d)" % sel._rows.size())
	_check(sel._scroll.custom_minimum_size.y < 16.0 * 40.0, "the list is shorter than 16 rows: it scrolls (%.0f px)" % sel._scroll.custom_minimum_size.y)
	_check(sel._scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "vertical only")
	_check((sel._rows[0] as Button).text.begins_with("G") and (sel._rows[-1] as Button).text.begins_with("B1"), "labels G and B1")
	sel.queue_free()
	lot.queue_free()
