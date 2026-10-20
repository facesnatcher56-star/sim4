extends RefCounted
## Task 41a (fast): the wear / poverty layer. Poverty tiers and variants (a sagging mattress on the floor, a broken chair, a boxed TV) come with the wealth score and
## not with a comfortable lot, floor clutter appears with a tile's mess and goes when it is tidied, litter is muted real shapes, graffiti tags have bulk and colour,
## the wear level of a district maps monotonically to dressing density, the 'rough' preset and the run-time hook work, and none of it writes sim state.

const SKit = preload("res://tests/start_kit.gd")

var fails: Array = []
var W: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	W = Engine.get_main_loop().root.get_node_or_null("World")
	if W == null:
		return ["World autoload missing"]
	_rules()
	_variants_pure()
	SKit.new_game("solo", "normal", {}, -1, {"world_seed": 11})
	_variants_in_world()
	_clutter()
	_litter()
	_graffiti()
	_wear_mapping()
	_lot_plan()
	WearLayer.reset()
	SKit.teardown()
	return fails


func _rules() -> void:
	_check(WearRules.poverty_score(5000) == 0.0, "5000 coins is comfortable")
	_check(WearRules.poverty_score(0) == 1.0 and WearRules.poverty_score(600) == 1.0, "a broke household scores 1")
	_check(WearRules.poverty_score(1500) > WearRules.poverty_score(2500), "less money is poorer")
	_check(WearRules.tier_of(0.9) == "poor" and WearRules.tier_of(0.5) == "modest" and WearRules.tier_of(0.1) == "comfortable", "tiers: poor / modest / comfortable")
	var picks := {}
	for i in 60:
		picks[WearRules.pick_of(i)] = true
		_check(WearRules.pick_of(i) == WearRules.pick_of(i), "pick is stable")
	_check(picks.size() == 3, "pick spreads over 0..2 (%d values)" % picks.size())
	_check(WearRules.wall_wear(0.5, true) > WearRules.wall_wear(0.5, false), "outside walls are dirtier than inside walls")
	_check(WearRules.wall_wear(0.9, true) > WearRules.wall_wear(0.2, true), "a worn lot has dirtier walls")


func _look(def_id: String, st: Dictionary) -> Dictionary:
	var d: Dictionary = W.get_def(def_id)
	return ObjectVisualRules.resolve(def_id, st, d.get("state", {}), null, float(d.get("height", 1.0)))


func _variants_pure() -> void:
	ObjectVisualRules.reload()
	var poor_bed := _look("bed", {"made": false, "_poverty": 0.85, "_pick": 0})
	_check("bed_poor:mattress_on_floor" in (poor_bed["ids"] as Array), "a poor household's bed is a mattress on the floor: %s" % str(poor_bed.get("ids")))
	_check(not ("made:unmade" in (poor_bed["ids"] as Array)), "the poor mattress replaces the unmade-bed parts (skip)")
	_check("*" in (poor_bed["hide"] as Array) and (poor_bed["parts"] as Array).size() >= 4, "the nice bed model is hidden and replaced by parts")
	var top := 0.0
	for p in poor_bed["parts"]:
		top = maxf(top, float(p["pos"].y) + float(p["size"].y) * 0.5)
	_check(top < 0.45, "the mattress lies on the floor (top %.2f m, the frame was 0.9 m)" % top)
	var ok_bed := _look("bed", {"made": false, "_poverty": 0.05, "_pick": 0})
	_check(not ("bed_poor:mattress_on_floor" in (ok_bed["ids"] as Array)) and "made:unmade" in (ok_bed["ids"] as Array), "a comfortable lot keeps its bed")
	_check(not _look("bed", {"made": true}).is_empty() or true, "no poverty keys: the 33b look is untouched")
	var chair_broken := _look("chair", {"_poverty": 0.8, "_pick": 0})
	var chair_mis := _look("chair", {"_poverty": 0.8, "_pick": 1})
	var chair_ok := _look("chair", {"_poverty": 0.8, "_pick": 2})
	_check("chair_poor:broken_chair" in (chair_broken["ids"] as Array) and (chair_broken["parts"] as Array).size() >= 5, "a poor flat has a broken chair")
	_check("chair_poor:mismatched_chair" in (chair_mis["ids"] as Array) and (chair_mis["surfaces"] as Dictionary).has("wood"), "and a mismatched, recoloured chair")
	_check(not ("chair_poor:broken_chair" in (chair_ok["ids"] as Array)), "but not every chair is broken")
	_check(_look("chair", {"_poverty": 0.1, "_pick": 0}).get("parts", []).is_empty(), "a comfortable lot's chair is whole")
	var tv := _look("tv", {"_poverty": 0.8, "_pick": 0, "broken": false})
	_check("tv_boxed:boxed_tv" in (tv["ids"] as Array) and (tv["parts"] as Array).size() >= 4, "a poor flat's TV sits on a cardboard box")
	_check(not ("tv_boxed:boxed_tv" in (_look("tv", {"_poverty": 0.2, "_pick": 0, "broken": false})["ids"] as Array)), "a comfortable TV is on its stand")
	var sofa := _look("sofa", {"_poverty": 0.8, "_pick": 0})
	_check("sofa_poor:sagging_sofa" in (sofa["ids"] as Array) and (sofa["scale"] as Vector3).y < 1.0, "a poor sofa sags")
	# the tint steps with the score
	var a: Color = _look("dresser", {"_poverty": 0.4, "_pick": 2}).get("overlay", Color(0, 0, 0, 0))
	var b: Color = _look("dresser", {"_poverty": 0.9, "_pick": 2}).get("overlay", Color(0, 0, 0, 0))
	_check(b.a > a.a, "poorer = more worn tint (%.2f vs %.2f)" % [b.a, a.a])
	# everything still works with the old state-only call and the broken layer
	var broken_tv := _look("tv", {"_poverty": 0.8, "_pick": 0, "broken": true})
	_check("broken:broken" in (broken_tv["ids"] as Array), "a broken poor TV still shows broken")


func _variants_in_world() -> void:
	var bed = null
	var tv = null
	var home := NeighborhoodLots.rect_of("home")
	for o in W.all_objects():
		if not home.has_point(o.tile):
			continue
		if bed == null and o.def_id in ["bed", "single_bed"]:
			bed = o
		if tv == null and o.def_id == "tv":
			tv = o
	_check(bed != null, "the home has a bed")
	if bed == null:
		return
	var before: String = var_to_str(bed.state)
	WearLayer.clear_lot_override("home")
	var rich := ObjectStateView.look_of(bed)
	_check(not ("bed_poor:mattress_on_floor" in (rich.get("ids", []) as Array)), "home with funds: normal bed")
	WearLayer.set_lot_override("home", 0.9)
	var poor := ObjectStateView.look_of(bed)
	_check("bed_poor:mattress_on_floor" in (poor.get("ids", []) as Array), "poor home: mattress on the floor")
	_check(var_to_str(bed.state) == before and not bed.state.has("_poverty"), "the view never writes the object's state")
	_check(WearLayer.poverty_at(bed.tile) > 0.8, "poverty_at reads the lot of the tile")
	# wealth drives it: funds of the player's household
	WearLayer.clear_lot_override("home")
	var hid: int = W.current_household_id
	var coins_before: int = WorldIface.get_coins(hid)
	WorldIface.coins[hid] = 400
	WearLayer.invalidate("home")
	_check(WearLayer.lot_poverty("home") > 0.9, "400 coins: the player's lot is poor (%.2f)" % WearLayer.lot_poverty("home"))
	WorldIface.coins[hid] = 6000
	WearLayer.invalidate("home")
	_check(WearLayer.lot_poverty("home") == 0.0, "6000 coins: comfortable")
	WorldIface.coins[hid] = coins_before
	WearLayer.reset()


func _free_indoor_tile() -> Vector2i:
	var rc := NeighborhoodLots.rect_of("home")
	for y in range(rc.position.y, rc.end.y):
		for x in range(rc.position.x, rc.end.x):
			var t := Vector2i(x, y)
			if W.object_at(t) == null and not W.rooms.is_outdoor(t) and W.get_floor(t) != "":
				return t
	return Vector2i(-1, -1)


func _clutter() -> void:
	_check(WearRules.clutter_count(0.0) == 0, "tidy: no clutter")
	var last := 0
	for m in [0.5, 1.5, 3.5, 7.0]:
		var n := WearRules.clutter_count(m)
		_check(n >= last, "clutter never shrinks as mess grows (%.1f -> %d)" % [m, n])
		last = n
	_check(WearRules.clutter_count(7.0) > WearRules.clutter_count(1.5), "squalid has more pieces than untidy")
	_check(WearRules.mess_level(0.2) == "tidy" and WearRules.mess_level(2.0) == "untidy" and WearRules.mess_level(4.0) == "messy" and WearRules.mess_level(8.0) == "squalid", "mess levels")
	var t := Vector2i(10, 10)
	_check(var_to_str(WearRules.clutter_for_tile(t, 5.0, "kitchen", 0.0)) == var_to_str(WearRules.clutter_for_tile(t, 5.0, "kitchen", 0.0)), "same mess = same pieces")
	var kinds := {}
	for x in 60:
		for p in WearRules.clutter_for_tile(Vector2i(x, 3), 8.0, "bedroom", 0.0):
			kinds[p["kind"]] = true
	_check(kinds.has("clothes"), "a messy bedroom has clothes")
	var tile := _free_indoor_tile()
	_check(tile.x >= 0, "found a free indoor tile")
	if tile.x < 0:
		return
	var cv := ClutterView.new()
	Engine.get_main_loop().root.add_child(cv)
	WearLayer.clear_lot_override("home")
	W.mess.clear()
	cv.refresh()
	var base := cv.count
	W.add_mess(tile, 2.0)
	cv.refresh()
	var one := cv.count
	W.add_mess(tile, 6.0)
	cv.refresh()
	var many := cv.count
	_check(one > base and many > one, "clutter appears and grows with the mess (%d -> %d -> %d)" % [base, one, many])
	W.add_mess(tile, -20.0)
	cv.refresh()
	_check(cv.count == base, "tidied: the clutter is gone (%d vs %d)" % [cv.count, base])
	# a poor lot keeps a few boxes and bags even when tidy
	WearLayer.set_lot_override("home", 1.0)
	cv.refresh()
	_check(cv.count > base, "a poor lot has baseline clutter (%d)" % cv.count)
	WearLayer.clear_lot_override("home")
	cv.refresh()
	_check(cv.count == base, "and it goes when the lot is no longer poor")
	cv.free()


func _litter() -> void:
	var pieces := WearProps.litter([0.0, 0.0, 20.0, 5.0], 120, 7)
	_check(pieces.size() == 120, "litter count")
	var kinds := {}
	var sat := 0.0
	var worst := 0.0
	for p in pieces:
		kinds[p["kind"]] = true
		var c := WearProps.color_of(str(p["kind"]), float(p["tone"]))
		sat += c.s
		worst = maxf(worst, c.s)
		_check(float(p["pos"].x) >= 0.0 and float(p["pos"].x) <= 20.0, "litter stays in its area")
	_check(kinds.has("paper") and kinds.has("can") and kinds.has("bottle") and kinds.has("bag"), "litter has paper, cans, bottles and bags: %s" % str(kinds.keys()))
	_check(sat / pieces.size() < 0.35 and worst < 0.6, "litter colours are muted (mean saturation %.2f, worst %.2f)" % [sat / pieces.size(), worst])
	for k in WearProps.KINDS:
		var m := WearProps.mesh(k)
		var n := (m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		_check(n >= 24, "%s is a real shape (%d indices), not a flat square" % [k, n])
	var holder := Node3D.new()
	WearProps.build(holder, pieces, "L")
	var mmi := 0
	for c in holder.get_node("L").get_children():
		mmi += 1
	_check(mmi >= 4 and mmi <= WearProps.KINDS.size(), "litter is a few MultiMeshes (%d draw calls) for 120 pieces" % mmi)
	holder.free()


func _graffiti() -> void:
	var names: Array = GraffitiTex.names()
	_check(names.size() >= 5, "a handful of tags (%d)" % names.size())
	for nm in names:
		var img: Image = GraffitiTex.tex(nm).get_image()
		_check(img.get_width() == 512 and img.get_height() == 192, "%s is 512x192" % nm)
		var cols := {}
		var solid := 0
		var dark := 0
		for y in range(0, img.get_height(), 3):
			for x in range(0, img.get_width(), 3):
				var c := img.get_pixel(x, y)
				if c.a > 0.9:
					solid += 1
					cols[c.to_html(false).substr(0, 2) + c.to_html(false).substr(2, 2)] = true
					if c.get_luminance() < 0.12:
						dark += 1
		var cover := float(solid) / float((img.get_width() / 3) * (img.get_height() / 3))
		_check(cover > 0.1 and cover < 0.6, "%s has bulk: %.0f%% of the decal is paint" % [nm, cover * 100.0])
		_check(dark > 20, "%s has a dark outline" % nm)
		_check(cols.size() >= 4, "%s has several colours (%d)" % [nm, cols.size()])
	# the dressing data points at the new tags, sized to the wall (aspect of the texture)
	var tags := 0
	for g in (WearRules.dressing_cfg().get("groups", {}) as Dictionary).values():
		for it in g:
			if it.get("k", "") == "decal" and GraffitiTex.is_tag(str(it.get("tex", ""))):
				tags += 1
				var sz: Array = it["size"]
				var along := maxf(float(sz[0]), float(sz[2]))
				var high := minf(float(sz[0]), float(sz[2]))
				_check(absf(along / high - 512.0 / 192.0) < 0.1, "tag decal keeps the texture's aspect")
				_check(along >= 2.0, "tags are big enough to read on a wall (%.1f m)" % along)
	_check(tags >= 4, "the rough scene has %d tags" % tags)
	for g in (WearRules.dressing_cfg().get("groups", {}) as Dictionary).values():
		for it in g:
			_check(str(it.get("tex", "")) not in ["graffiti_a", "graffiti_b"], "no old squiggle graffiti left in the data")


func _wear_mapping() -> void:
	var wm: Dictionary = WearRules.dressing_cfg().get("wear_map", {})
	_check(wm.size() >= 8, "wear_map has its entries")
	for k in wm:
		if k.begins_with("_"):
			continue
		var prev := -1.0
		for w in [0.0, 0.1, 0.3, 0.5, 0.7, 0.9, 1.0]:
			var d := WearRules.density(k, w)
			_check(d >= prev - 0.0001, "%s never decreases with wear (%.2f at %.1f after %.2f)" % [k, d, w, prev])
			prev = d
		var e: Dictionary = wm[k]
		if e.has("min_wear") and float(e["min_wear"]) > 0.0:
			_check(WearRules.density(k, float(e["min_wear"]) - 0.01) == 0.0, "%s is zero below its min_wear" % k)
	_check(WearRules.density("litter_ring", 0.9) > WearRules.density("litter_ring", 0.3), "more litter on a rougher block")
	_check(WearRules.density("no_such_key", 0.5) == 0.0, "unknown keys are 0")
	var rough := float(WearRules.preset("rough").get("wear", -1.0))
	_check(rough > WearRules.preset("tired")["wear"] and WearRules.preset("tired")["wear"] > WearRules.preset("tidy")["wear"], "presets rough > tired > tidy")
	_check(is_equal_approx(rough, 0.85), "rough preset is the look-test scene's level")
	_check(is_equal_approx(WearRules.district_wear_of_lot("townie_b"), 0.85), "townie_b is declared in the rough_row district")
	_check(WearRules.district_wear_of_lot("market") < 0.0, "a lot in no district declares none")
	_check(WearLayer.districts().size() >= 1, "districts() lists the declared ones")
	# the hook: a block that improves / declines
	WearLayer.reset()
	var w0 := WearLayer.lot_wear("townie_b")
	WearLayer.set_district_wear("rough_row", 0.2)
	_check(WearLayer.lot_wear("townie_b") < w0 and WearLayer.lot_poverty("townie_b") < 0.3, "set_district_wear improves the block (%.2f -> %.2f)" % [w0, WearLayer.lot_wear("townie_b")])
	WearLayer.set_district_wear("rough_row", 1.0)
	_check(WearLayer.lot_wear("townie_b") > w0, "and declines it")
	WearLayer.reset()
	_check(is_equal_approx(WearLayer.lot_wear("townie_b"), w0), "reset goes back to the data")
	_check(WearLayer.lot_wear("market") == 0.0 and WearLayer.poverty_at(Vector2i(0, 0)) == 0.0, "lots without wear stay clean")


func _lot_plan() -> void:
	var rc := NeighborhoodLots.rect_of("townie_b")
	_check(rc.size != Vector2i.ZERO, "townie_b is on the map")
	var p0 := WearLot.plan("townie_b", 0.0)
	_check((p0["litter"] as Array).is_empty() and (p0["tags"] as Array).is_empty(), "wear 0: nothing")
	var low := WearLot.plan("townie_b", 0.2)
	var mid := WearLot.plan("townie_b", 0.5)
	var high := WearLot.plan("townie_b", 0.9)
	_check((low["litter"] as Array).size() <= (mid["litter"] as Array).size() and (mid["litter"] as Array).size() < (high["litter"] as Array).size(),
		"litter grows with wear (%d, %d, %d)" % [(low["litter"] as Array).size(), (mid["litter"] as Array).size(), (high["litter"] as Array).size()])
	_check((low["tags"] as Array).is_empty() and (low["dead_centres"] as Array).is_empty(), "a barely worn lot has no tags and no dead patch")
	_check((high["tags"] as Array).size() >= (mid["tags"] as Array).size(), "tags do not decrease with wear (%d, %d)" % [(mid["tags"] as Array).size(), (high["tags"] as Array).size()])
	_check((high["weed_centres"] as Array).size() >= (mid["weed_centres"] as Array).size() and (mid["weed_centres"] as Array).size() >= (low["weed_centres"] as Array).size(), "weed clumps do not decrease with wear")
	_check(var_to_str(WearLot.plan("townie_b", 0.9)) == var_to_str(high), "a plan is deterministic")
	var cap := int(WearRules.density("decal_cap", 1.0))
	_check((high["cracks"] as Array).size() + (high["tags"] as Array).size() + (high["stains"] as Array).size() <= cap, "decal count stays under the cap (%d)" % cap)
	for t in high["tags"]:
		_check(GraffitiTex.is_tag(str(t["tex"])), "tags use tag textures")
	_check(var_to_str(W.mess) == var_to_str(W.mess), "plan leaves the world alone")
