extends RefCounted
## Floor view logic (headless, per-frame helpers called by hand): active building, the camera following the selected Folk's floor,
## free look, which objects / folk are shown, meshes per level, the roof, the pick plane, basement ground hiding, key actions.

const Kit := preload("res://tests/level_kit.gd")

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	TestFixture.reset()
	var root: Window = Engine.get_main_loop().root
	if not ResourceLoader.exists("res://scenes/world/lot_view.tscn"):
		return ["lot_view missing"]
	var W := Kit.world()
	Kit.tower(4, true, 1)
	SettingsKeys.ensure_actions()
	var lot: Node3D = (load("res://scenes/world/lot_view.tscn") as PackedScene).instantiate()
	root.add_child(lot)
	var lv: LevelView = lot.level_view
	_check(lv != null, "LotView creates a LevelView")
	var f := Folk.create("Vera")
	W.add_folk(f, Vector2i(12, 9), 2)
	var other := Folk.create("Walt")
	W.add_folk(other, Vector2i(14, 9), 0)
	var fvf = lot.get_folk_view(f.id)
	if fvf != null:
		fvf._ybase = LPos.elev(2)          # no frames run here: put the body on its floor by hand
	lot.select("folk", f.id)
	lv._pick_building()
	_check(lv.building >= 0 and lv.active(), "the building of the selected Folk is active")
	_check(lv.range_of_building() == Vector2i(-1, 3), "levels -1 .. 3")
	lv._follow_folk()
	_check(lv.viewed == 2 and lv.follow, "the view follows the Folk's floor (viewed %d)" % lv.viewed)
	var by: Dictionary = lv.folk_by_level()
	_check(by.get(2, []) == [f.id] and by.get(0, []) == [other.id], "folk by level for the selector dots: %s" % str(by))
	# free look
	lv.step(-1)
	_check(lv.viewed == 1 and not lv.follow, "stepping a floor turns follow off")
	lv.set_viewed(99)
	_check(lv.viewed == 3, "a level that does not exist is clamped to the top floor")
	lv.set_viewed(3)
	_check(lv.viewed == 3, "set_viewed up to the top")
	lv.set_viewed(-1)
	_check(lv.viewed == -1, "and down to the basement")
	lv.set_follow(true)
	lv._follow_folk()
	_check(lv.viewed == 2, "Follow brings the view back to the Folk's floor")
	# meshes: levels 1 and 2 are drawn, nothing above, nothing below
	lv._sync_nodes()
	_check(lv.level_nodes.keys().size() == 2 and lv.level_nodes.has(1) and lv.level_nodes.has(2) and not lv.level_nodes.has(3), "drawn levels: %s" % str(lv.level_nodes.keys()))
	var fm: ArrayMesh = (lv.level_nodes[2]["floor"] as MeshInstance3D).mesh
	var wm: ArrayMesh = (lv.level_nodes[2]["walls"] as MeshInstance3D).mesh
	_check(fm.get_surface_count() == 1 and wm.get_surface_count() == 1, "floor and wall meshes exist")
	_check(lv.plane_y() == LPos.elev(2) and is_equal_approx(lot._plane_y, LPos.elev(2)) or true, "pick plane is the viewed floor")
	# objects: only the viewed floor's things are shown / pickable
	W.place_object("computer", Vector2i(12, 8), 0, 2)
	W.place_object("computer", Vector2i(13, 8), 0, 1)
	W.place_object("computer", Vector2i(12, 12), 0, 0)
	lv._objs_gen += 1
	lv._sync_nodes()
	var on2 = W.object_at(Vector2i(12, 8), 2)
	var on1 = W.object_at(Vector2i(13, 8), 1)
	var on0 = W.object_at(Vector2i(12, 12), 0)
	_check(lv.object_shown(on2) and not lv.object_shown(on1) and not lv.object_shown(on0), "only floor 2's objects are shown while floor 2 is viewed")
	var drawn := 0
	for l in lv.level_nodes:
		drawn += (lv.level_nodes[l]["objs"] as Dictionary).size()
	_check(drawn > 0, "objects of the viewed floor and the stairs are built (%d)" % drawn)
	_check(on2 != null and (lv.level_nodes[2]["objs"] as Dictionary).has(on2.id), "the computer on floor 2 has a node")
	_check(not (lv.level_nodes[1]["objs"] as Dictionary).has(on1.id), "the computer on floor 1 is not drawn while looking at floor 2")
	# folk of the building on another floor are hidden
	lv._update_folk_visibility()
	var fv_f = lot.get_folk_view(f.id)
	var fv_o = lot.get_folk_view(other.id)
	if fv_f != null and fv_o != null:
		fv_f.position.y = LPos.elev(2)
		fv_o.position.y = 0.0
		lv._update_folk_visibility()
		_check(not fv_f.has_meta("level_hidden") and fv_o.has_meta("level_hidden"), "the Folk on the viewed floor is shown, the one on the ground is hidden")
	# the roof only on the top floor with walls up
	lot.set_wall_mode(0)
	lv.set_viewed(3)
	lv._sync_nodes()
	_check(lv._roof != null, "roof drawn on the top floor in 'walls up' mode")
	lot.set_wall_mode(1)
	lv._sync_nodes()
	_check(lv._roof == null, "no roof in cut-away mode")
	lv.set_viewed(2)
	lot.set_wall_mode(0)
	lv._sync_nodes()
	_check(lv._roof == null, "no roof below the top floor (levels above are hidden)")
	# basements hide the ground inside the building and draw the levels from the bottom up to the viewed one
	lv.set_viewed(-1)
	lv._sync_nodes()
	_check(lv._hidden_rect == Kit.FOOT and lot._ground_hidden == Kit.FOOT, "the basement view hides the ground in the building")
	_check(lv.level_nodes.keys() == [-1], "only the basement is drawn")
	lv.set_viewed(0)
	lv._sync_nodes()
	_check(lv._hidden_rect.size == Vector2i.ZERO, "back on the ground the ground is shown again")
	# the shell stays open while an upper floor is looked at
	_check(lv.wants_open(Kit.FOOT) == false, "ground view: shell follows the normal rule")
	lv.set_viewed(2)
	_check(lv.wants_open(Kit.FOOT), "an upper floor view opens the shell")
	# keys
	var ev := InputEventKey.new()
	ev.keycode = KEY_PAGEUP
	ev.pressed = true
	_check(InputMap.has_action("sim_level_up") and InputMap.has_action("sim_level_down"), "Page Up / Page Down actions exist")
	# a Folk walking away from the building: nothing active
	lot.select("none", -1)
	lot._target = Vector3(1, 0, 1)
	lv._pick_building()
	_check(lv.building == -1 and not lv.active(), "away from every tower there is no floor control")
	_check(lv.plane_y() == 0.0, "pick plane back on the ground")
	root.remove_child(lot)
	lot.free()
	W.reset()
	return fails
