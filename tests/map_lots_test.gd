extends RefCounted
## All 19 lots of data/neighborhood.json are placed on the one continuous map at their region rectangles (MapLots): every
## object sits inside its lot, every usable object is reachable from the lot's entry tile, the venues' staff posts are
## standable, only the home lot is buildable, ownership is per object (home = household, everything else community).

const Kit = preload("res://tests/hood_kit.gd")
const SKit = preload("res://tests/start_kit.gd")
const SEEDS := [11, 2222, 33333, 444444, 5555555]
const SCENARIOS := ["solo", "couple", "family", "roommates", "sandbox"]

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	for i in TestFixture.pick(SEEDS.size(), 3):       # real new-game path, five world seeds (three in the fast tier), every scenario
		var sc: String = SCENARIOS[i]
		SKit.new_game(sc, "normal", {}, -1, {"world_seed": SEEDS[i]})
		_whole_map("%s/%d" % [sc, SEEDS[i]])
		_distinct(sc, int(SEEDS[i]))
	SKit.teardown()
	_same_seed_same_map()
	_build_rules()
	_ownership()
	Kit.teardown()
	return fails

## All the lots pairwise distinct layouts; home from the scenario's pool; seed saved.
func _distinct(sc: String, wseed: int) -> void:
	var seen: Dictionary = {}
	var rg: WorldRegions = Kit.world().regions
	for l in Neighborhood.lots():
		var tid: String = str(rg.by_lot(str(l["id"]))["template"])
		var sig: String = LotPicker.signature(tid)
		_check(not seen.has(sig), "%s/%d: %s and %s share a layout (%s)" % [sc, wseed, str(l["id"]), str(seen.get(sig, "")), tid])
		seen[sig] = str(l["id"])
	var home: String = Neighborhood.home_template
	var pool: Array = LotPicker.home_pool(str(Scenario.def(sc).get("start_id", "classic")))          # the New Game screen's own pool for this kind of start
	_check(pool.has(home) or (sc == "sandbox" and home == "classic"), "%s: home %s is not from its pool %s" % [sc, home, str(pool)])
	_check(rg.home()["template"] == home and Neighborhood.world_seed == wseed, "%s: home template / seed recorded" % sc)
	for lid in ["townie_a", "townie_b", "townie_c"]:
		var t: String = Neighborhood.template_of(lid)
		_check(HouseGenerator.pool({"townie_a": "medium", "townie_b": "small", "townie_c": "large"}[lid]).has(t) or BuildingGen.pool({"townie_a": "medium", "townie_b": "small", "townie_c": "large"}[lid]).has(t) or t == lid, "%s: %s got %s" % [sc, lid, t])
	for l in Neighborhood.lots():          # venues: an alternate of their own type
		if str(l.get("type", "")) in ["park", "cafe", "gym", "library", "market", "office", "school", "hospital", "police", "courthouse"]:
			_check(HouseGenerator.venue_pool(str(l["type"])).has(Neighborhood.template_of(str(l["id"]))) or BuildingGen.venue_pool(str(l["type"])).has(Neighborhood.template_of(str(l["id"]))), "%s: venue %s wrong template" % [sc, l["id"]])
	# save -> new game with another seed -> restore: template ids and seed come back, same layouts
	var before: Dictionary = {}
	for l in Neighborhood.lots():
		before[str(l["id"])] = Neighborhood.template_of(str(l["id"]))
	var snap: Variant = JSON.parse_string(JSON.stringify(SaveLoad.snapshot("seeds")))
	SKit.new_game("solo", "normal", {}, -1, {"world_seed": wseed + 1})
	_check(SaveLoad.restore(snap), "%s/%d: restore" % [sc, wseed])
	_check(Neighborhood.world_seed == wseed, "%s/%d: world seed restored (%d)" % [sc, wseed, Neighborhood.world_seed])
	for lid in before:
		_check(Neighborhood.template_of(lid) == before[lid], "%s/%d: %s template %s -> %s after load" % [sc, wseed, lid, before[lid], Neighborhood.template_of(lid)])

## Same seed -> identical map; another seed -> a different one.
func _same_seed_same_map() -> void:
	var a: Dictionary = LotPicker.pick(77, "medium")
	_check(a == LotPicker.pick(77, "medium"), "same seed, same picks")
	var differs := false
	for s in range(78, 90):
		differs = differs or LotPicker.pick(s, "medium") != a
	_check(differs, "other seeds give other maps")
	_check(LotPicker.pick(5, "medium", "medium_03")["home"] == "medium_03", "a chosen home stays")

func _whole_map(start: String) -> void:
	var W: Node = Kit.world()
	var rg: WorldRegions = W.regions
	_check(W.width == World.MAP_W and W.height == World.MAP_H, "%s: the map is %dx%d" % [start, W.width, W.height])
	var min_objects := {"classic": 40, "small": 14, "medium": 30, "large": 50, "park": 25, "cafe": 30, "gym": 25, "library": 40, "market": 25, "office": 30, "school": 40}
	for gid in LotLoader.generated_ids():
		var g: Dictionary = LotLoader.template(str(gid))
		min_objects[gid] = {"small": 14, "medium": 30, "large": 50, "classic": 40}.get(str(g.get("size", "")), 10) if str(g.get("kind", "")) == "home" else int(min_objects.get(str(g.get("venue", "")), 10))
	var lots: Array = Neighborhood.lots()
	_check(lots.size() == 21, "%s: 21 lots (%d)" % [start, lots.size()])          # 19 + the later apartments and shelter lots
	var per_lot: Dictionary = {}
	for o in W.all_objects():
		var l: String = Neighborhood.lot_at(o.tile)
		per_lot[l] = int(per_lot.get(l, 0)) + 1
		for t in o.footprint():
			_check(rg.region_at(t) == rg.region_at(o.tile), "%s: %s@%s sticks out of its lot at %s" % [start, o.def_id, str(o.tile), str(t)])
	_check(not per_lot.has(""), "%s: %d objects stand outside every lot" % [start, int(per_lot.get("", 0))])
	var home_id: int = rg.home_id
	for l in lots:
		var lid: String = str(l["id"])
		var r: Dictionary = rg.by_lot(lid)
		_check(not r.is_empty(), "%s: lot %s has a region" % [start, lid])
		if r.is_empty():
			continue
		var rc: Rect2i = r["rect"]
		_check(rc == MapBuilder.lot_rect(lid), "%s: %s region = layout slot" % [start, lid])
		var tid: String = Neighborhood.template_of(lid)
		_check(str(r["template"]) == tid, "%s: %s region template %s vs %s" % [start, lid, str(r["template"]), tid])
		_check(int(per_lot.get(lid, 0)) >= int(min_objects.get(tid, 10)), "%s: %s (%s) has only %d objects" % [start, lid, tid, int(per_lot.get(lid, 0))])
		var door: Vector2i = Neighborhood.entry_tile(lid)
		_check(rc.has_point(door) and W.is_walkable(door), "%s: %s entry %s walkable inside the lot" % [start, lid, str(door)])
		# everything usable can be reached from the door, the staff posts and spawn tiles are standable
		var bad: Array = LotLoader.unreachable_objects(W, door, rc)
		_check(bad.is_empty(), "%s: %s unreachable objects from %s: %s" % [start, lid, str(door), str(bad)])
		for sd in LotLoader.template(tid).get("staff", []):
			var st := Vector2i(int(sd["tile"][0]), int(sd["tile"][1])) + rc.position
			_check(W.is_walkable(st) and W.has_path(door, st), "%s: %s staff post %s not standable / reachable" % [start, lid, str(st)])
		for sp in Neighborhood.spawns_of(lid):
			_check(rc.has_point(sp) and W.is_walkable(sp) and W.has_path(door, sp), "%s: %s spawn %s disconnected" % [start, lid, str(sp)])
		# the street gate connects to the door (a folk can walk in from the sidewalk)
		var gate: Vector2i = MapLots.gate(lid)
		_check(W.has_path(Vector2i(gate.x, rc.end.y), door), "%s: %s door not reachable from the street" % [start, lid])
		_check(lid == "home" or rg.region_at(door) != home_id, "%s: only home is the home region" % start)
	_check(W.starter_spawn_tiles.size() > 0 and Neighborhood.lot_at(W.starter_spawn_tiles[0]) == "home", "%s: new folk spawn inside the home lot" % start)

func _build_rules() -> void:
	Kit.new_game("small")
	var W: Node = Kit.world()
	var home: Rect2i = W.regions.home()["rect"]
	var cafe: Rect2i = Neighborhood.rect_of("cafe")
	var free_home := Vector2i(home.position.x + 2, home.position.y + 20)
	_check(W.can_build(free_home), "home yard is buildable")
	_check(not W.can_build(Vector2i(cafe.position.x + 2, cafe.position.y + 2)), "the cafe lot is not buildable")
	_check(not W.can_build(Vector2i(0, 0)), "streets are not buildable")
	var before: int = W.objects.size()
	_check(W.place_object("plant", Vector2i(cafe.position.x + 1, cafe.position.y + 1), 0) == -1 and W.last_error == WorldRegions.BUILD_ERROR, "cannot place in the cafe: %s" % W.last_error)
	_check(W.objects.size() == before, "nothing was placed")
	_check(W.set_wall_line(cafe.position, cafe.position + Vector2i(4, 0), "wall", 1) == 0, "no walls in the cafe lot")
	_check(W.place_object("plant", free_home, 0) != -1, "plant placed in the home lot: %s" % W.last_error)
	for lid in ["townie_a", "townie_b", "townie_c", "park", "market", "school"]:
		var rc: Rect2i = Neighborhood.rect_of(lid)
		_check(not W.can_build(rc.position + Vector2i(3, 3)), "%s is not buildable" % lid)

func _ownership() -> void:
	Kit.new_game("classic")
	var W: Node = Kit.world()
	Economy.refresh_objects()
	var home_n := 0
	var other_n := 0
	for o in W.all_objects():
		var own: int = int(Economy.owner.get(int(o.id), -2))
		if Neighborhood.lot_at(o.tile) == "home":
			home_n += 1
			_check(own == 1, "home object %s owned by the household (%d)" % [o.def_id, own])
		else:
			other_n += 1
			if own != -1:
				_check(false, "%s in %s should be community property (%d)" % [o.def_id, Neighborhood.lot_at(o.tile), own])
				break
	_check(home_n > 30 and other_n > 200, "objects counted: %d home, %d elsewhere" % [home_n, other_n])
	var value: int = Economy.lot_value(1)
	var home_value := 0
	for o in W.all_objects():
		if Neighborhood.lot_at(o.tile) == "home":
			home_value += Economy.object_price(o)
	_check(value == home_value and value > 0, "lot value (bills) counts the home lot only (%d vs %d)" % [value, home_value])