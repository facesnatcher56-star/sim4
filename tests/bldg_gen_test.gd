extends RefCounted
## BuildingGen: data/generated_buildings.json is up to date with the generator, every building is valid (schema, fits the 32x24 lot, places
## with no failures on the real World, every object of every floor reachable from the entrance, a stair for every level, a lift where
## wanted), layouts are pairwise distinct and differ from every home / venue ("no duplicate layouts"), and the file is deterministic.

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func _w() -> WorldGrid:
	return Engine.get_main_loop().root.get_node("World") as WorldGrid


func run() -> Array:
	fails = []
	TestFixture.reset()
	var lots: Dictionary = BuildingGen.lots()
	var specs: Array = BuildingGen.specs().get("buildings", [])
	_check(lots.size() == specs.size() and specs.size() >= 1, "one generated lot per spec (%d / %d)" % [lots.size(), specs.size()])
	var seen: Dictionary = {}
	var legacy := HouseSignature.legacy_templates()
	for id in legacy:
		seen[HouseSignature.layout_sig(legacy[id])] = "legacy " + str(id)
	for id in HouseGenerator.lots():
		seen[HouseSignature.layout_sig(HouseGenerator.lots()[id])] = str(id)
	var ids: Array = lots.keys()
	ids.sort()
	for id in ids:
		_building(str(id), lots[id], seen)
	_deterministic()
	_pools()
	_w().reset()
	return fails


func _building(id: String, t: Dictionary, seen: Dictionary) -> void:
	for k in ["label", "description", "floors", "walls", "objects", "spawn", "entry", "price", "levels", "roof", "floor_names", "stops"]:
		_check(t.has(k), "%s lacks %s" % [id, k])
	var sig := HouseSignature.layout_sig(t)
	_check(not seen.has(sig), "%s has the same layout as %s" % [id, str(seen.get(sig, ""))])
	seen[sig] = id
	var br := LotLoader.building_rect(id)
	_check(Rect2i(0, 0, 32, 24).encloses(br) and br.size.x >= 10 and br.size.y >= 7, "%s fits the lot (%s)" % [id, str(br)])
	var levels: Dictionary = t["levels"]
	var lo := 0
	var hi := 0
	for k in levels:
		lo = mini(lo, int(k))
		hi = maxi(hi, int(k))
	_check(hi > 0 or lo < 0, "%s is a multi-floor building" % id)
	for l in range(lo, hi + 1):
		_check(l == 0 or levels.has(str(l)), "%s has level %d" % [id, l])
		_check((t["floor_names"] as Dictionary).has(str(l)) and (t["stops"] as Dictionary).has(str(l)), "%s names / stops level %d" % [id, l])
	var W := _w()
	_check(LotLoader.apply(id), "%s places on the real world: %s" % [id, str(LotLoader.report.get("failed", []))])
	_check(W.levels.buildings.size() == 1, "%s registers one building" % id)
	var bad := LotLoader.unreachable_objects(W, Vector2i(int(t["entry"][0]), int(t["entry"][1])))
	_check(bad.is_empty(), "%s: unreachable objects %s" % [id, str(bad.slice(0, 6))])
	var up := 0
	var down := 0
	var lifts := 0
	var per_level: Dictionary = {}
	for o in W.all_objects():
		if o.def_id == "stairs":
			up += 1
		elif o.def_id == "stairs_down":
			down += 1
		elif o.def_id == "elevator":
			lifts += 1
		if not o.is_wall_mounted():
			per_level[o.level] = int(per_level.get(o.level, 0)) + 1
	_check(up == maxi(hi, 0) and down == maxi(-lo, 0), "%s: %d flights up / %d down for levels %d..%d" % [id, up, down, lo, hi])
	_check(lifts <= 1, "%s has at most one lift" % id)
	for l in range(lo, hi + 1):
		_check(int(per_level.get(l, 0)) >= 2, "%s level %d is furnished (%d)" % [id, l, int(per_level.get(l, 0))])
	# every level is connected to the ground by a route from the entrance
	var from := Vector3i(int(t["entry"][0]), int(t["entry"][1]), 0)
	for l in range(lo, hi + 1):
		var stop: Array = (t["stops"] as Dictionary)[str(l)]
		_check(W.has_route(from, Vector3i(int(stop[0]), int(stop[1]), l)), "%s: level %d reachable from the entrance" % [id, l])
	# the fire escape on the outside is a way down of its own: with every staircase broken and every lift off, each upper floor still gets out
	if t.has("fire_escape"):
		var escapes := 0
		for o in W.all_objects():
			if o.def_id == "fire_escape":
				escapes += 1
			elif o.def_id == "stairs" or o.def_id == "stairs_down":
				W.set_object_state(o.id, "broken", true)
			elif o.def_id == "elevator":
				W.set_object_state(o.id, "out_of_order", true)
		_check(escapes == maxi(hi, 0), "%s: a fire escape flight for every floor above the ground (%d)" % [id, escapes])
		for l in range(1, hi + 1):
			var st: Array = (t["stops"] as Dictionary)[str(l)]
			_check(W.has_route(Vector3i(int(st[0]), int(st[1]), l), Vector3i(int(t["entry"][0]), int(t["entry"][1]), 0)), "%s: floor %d reaches the street by the fire escape alone" % [id, l])
	# floors are named for the player (floor selector) and rooms are scored per level
	var nm: Dictionary = t["floor_names"]
	var bid0: int = int(W.levels.buildings.keys()[0])
	for l in range(lo, hi + 1):
		_check(W.levels.level_name(bid0, l) == str(nm[str(l)]), "%s level %d is called %s (%s)" % [id, l, str(nm[str(l)]), W.levels.level_name(bid0, l)])
		var stop2: Array = (t["stops"] as Dictionary)[str(l)]
		var sc: float = W.room_score(Vector2i(int(stop2[0]), int(stop2[1])), l)
		_check(not is_nan(sc) and not is_inf(sc), "%s level %d has a room score" % [id, l])
		_check(W.room_id(Vector2i(int(stop2[0]), int(stop2[1])), l) >= 0 or l == 0, "%s level %d: the landing is in a room" % [id, l])
	# the doors of the units of an apartment block stand in the right place
	for u in t.get("units", []):
		var dr: Array = u["door"]
		_check(W.levels.is_walkable(Vector2i(int(dr[0]), int(dr[1])), int(u["level"])), "%s unit %s door tile is walkable" % [id, str(u["id"])])


## The same spec and seed gives the identical template, and the committed file equals a fresh generation.
func _deterministic() -> void:
	var specs: Array = BuildingGen.specs().get("buildings", [])
	if specs.is_empty():
		return
	var spec: Dictionary = specs[0]
	var taken := BuildingGen.taken_registry()
	var a := BuildingGen.make(spec, taken.duplicate())
	var b := BuildingGen.make(spec, taken.duplicate())
	_check(a.has("template") and JSON.stringify(a["template"]) == JSON.stringify(b.get("template", {})), "same seed -> identical building")
	if a.has("template"):
		var norm: String = JSON.stringify(JSON.parse_string(JSON.stringify(a["template"])))
		_check(norm == JSON.stringify(BuildingGen.template(str(spec["id"]))), "data/generated_buildings.json is up to date (run tools/gen_buildings.gd)")


## The pools the map draws from: floored homes join the home pools, towers the office lot, a multi-floor lot only draws multi-floor buildings.
func _pools() -> void:
	_check(LotPicker.home_pool("medium").has("medium_f01") and LotPicker.home_pool("large").has("large_f02") and LotPicker.home_pool("classic").has("classic_f01"), "floored homes are in the home pools")
	var office: Array = LotPicker.lot_pool(Neighborhood.lot("office"))
	_check(office.has("office") and office.has("tower_01") and office.has("tower_02") and not office.has("office_v1"), "the office lot draws the office or a tower: %s" % str(office))
	_check(LotPicker.lot_pool(Neighborhood.lot("hospital")) == ["hospital_01"], "hospital pool")
	_check(LotPicker.lot_pool(Neighborhood.lot("apartments")).size() == 2, "two block layouts for the apartments lot")
	var school: Array = LotPicker.lot_pool(Neighborhood.lot("school"))
	_check(school.has("school") and school.has("school_01") and school.has("school_v1"), "the school lot may draw the 2-floor school too: %s" % str(school))
	for tid in BuildingGen.ids():
		_check(LotLoader.has_template(tid), "%s is a known template" % tid)
	_check(BuildingGen.venue_pool("hospital") == ["hospital_01"] and BuildingGen.pool("tower").size() == 2, "BuildingGen pools")
