extends RefCounted
## Generated towns for the scale benchmark (tests/perf_scale.gd). Built through the REAL game paths: Neighborhood.start_game ->
## MapLots.build -> MapBuilder (roads, regions, nav graph) -> LotLoader.place for every lot, SystemsManager.new_game, Story townies.
## The game's own map (data/map_layout.json, data/neighborhood.json, World.MAP_W x MAP_H) is NOT changed: this file swaps the
## in-memory layout / lot table / MapBuilder.size_override for the length of a test and `restore()` puts everything back.
##
##   PerfTown.build("mini" | "big", seed)  -> info {profile, map, lots, lots_by_type, townies, folk, towers, build_s, ...}   (the game must be reset by the caller's teardown)
##   PerfTown.build("today", seed)         -> the unchanged game town (3 household folk + 12 townies)
##   PerfTown.teardown()                   -> frees the game and restores the tables
##
## Profiles: "mini" = 4x3 slots (fast tier, 11 lots, ~24 townies), "big" = 8x8 slots on 320x272 (4x today's 160x136 area,
## 63 lots incl. 9 offices + 4 apartment blocks (multi-floor templates) + 3 level_kit towers, 200+ townies).
## Known limits of the existing systems (see docs/PERFORMANCE.md "Scale gaps"): Story gives each townie a home number 1..6, so this file
## re-spreads it over the generated townie homes; hospital / police / courthouse are single lots (data keyed by id).

const Kit = preload("res://tests/hood_kit.gd")
const LevelKit = preload("res://tests/level_kit.gd")

const ROAD_W := 6
const BLOCK_W := 38                   # slot pitch of data/map_layout.json
const BLOCK_H := 30

const PROFILES := {
	"mini": {"cols": 4, "rows": 3, "map": Vector2i(160, 106), "townies": 24, "strip_y": 97,
		"compose": {"home": 1, "cafe": 1, "market": 1, "office": 1, "school": 1, "townie_a": 1, "townie_b": 1, "apartments": 1, "hospital": 1, "police": 1, "tower": 1}, "active_cap": 45},
	"big": {"cols": 8, "rows": 8, "map": Vector2i(320, 272), "townies": 200, "strip_y": 247, "active_cap": 220,      # folk IN THE WORLD (the crowd is capped per lot, not globally); the ACTIVE tier has its own cap (data/tiers.json active_cap)
		
		"compose": {"home": 1, "hospital": 1, "police": 1, "courthouse": 1, "park": 3, "cafe": 7, "gym": 3, "library": 3, "market": 4, "school": 3, "office": 9,
			"townie_a": 8, "townie_b": 8, "townie_c": 4, "apartments": 4, "tower": 3}},
}
const VENUE_ORDER := ["cafe", "market", "park", "gym", "library", "school", "office"]
const HOME_ORDER := ["townie_a", "townie_b", "apartments", "townie_c", "tower"]
const TOWER_BASE := {"id": "tower", "label": "Glass Tower", "type": "tower", "template": "", "color": "#5b8def", "blurb": "A tall office block (level_kit tower)."}

static var _saved_table: Variant = null
static var _active: bool = false


static func build(profile: String, seed_value: int = 777) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	if profile != "today":
		install(profile)
	var folk: Array = Kit.new_game("classic", seed_value)
	var info := populate(profile)
	info["household"] = folk.size()
	info["build_s"] = float(Time.get_ticks_usec() - t0) / 1.0e6
	return info


## After the game exists (Kit.new_game, or tests/perf_scale_view.gd's main.start_new_game): the townies, the towers, the numbers.
static func populate(profile: String) -> Dictionary:
	var info: Dictionary = {"profile": profile, "towers": 0}
	if profile != "today":
		var p: Dictionary = PROFILES[profile]
		var have := Story.townies.size()
		Story.generate_townies(maxi(int(p["townies"]) - have, 0))
		_spread_townie_homes()
		info["towers"] = _build_towers()
	info["townies"] = Story.alive_townies().size()
	info["lots"] = Neighborhood.lot_ids().size()
	info["lots_by_type"] = _by_type()
	var w: WorldGrid = Kit.world()
	info["map"] = Vector2i(w.width, w.height)
	info["objects"] = w.objects.size()
	info["buildings"] = w.levels.buildings.size()
	return info


static func teardown() -> void:
	Kit.teardown()
	restore()


static func restore() -> void:
	if _active:
		SimEnv.data().tables["neighborhood"] = _saved_table
		MapBuilder.size_override = Vector2i.ZERO
		MapBuilder._layout = {}
		MapBuilder._hood = {}
		_saved_table = null
		_active = false


# ------------------------------------------------------------------ generation
## Swap in the generated layout / lot table / map size (before Neighborhood.start_game). `restore()` undoes it.
static func install(profile: String) -> void:
	_active = true
	var p: Dictionary = PROFILES[profile]
	var tables: Dictionary = SimEnv.data().tables
	_saved_table = tables["neighborhood"]
	var base_lots: Dictionary = {}
	for l in (_saved_table["lots"] as Array):
		base_lots[str(l["id"])] = l
	base_lots["tower"] = TOWER_BASE
	var cols: int = p["cols"]
	var rows: int = p["rows"]
	var slots: Array = []                       # [col, row] sorted by distance from the middle of the town
	for r in rows:
		for c in cols:
			slots.append([c, r])
	var mid := Vector2(float(cols - 1) * 0.5, float(rows - 1) * 0.5)
	slots.sort_custom(func(a, b): return Vector2(a[0], a[1]).distance_squared_to(mid) < Vector2(b[0], b[1]).distance_squared_to(mid))
	var green: Array = slots.pop_at(mini(3, slots.size() - 1))
	var order: Array = _recipe_order(p["compose"])
	var lots: Array = []
	var layout_lots: Dictionary = {}
	var seen: Dictionary = {}
	for i in mini(order.size(), slots.size()):
		var btype: String = order[i]
		var base: Dictionary = (base_lots[btype] as Dictionary).duplicate(true)
		var n: int = int(seen.get(btype, 0)) + 1
		seen[btype] = n
		if n > 1:
			base["id"] = "%s_%d" % [btype, n]
			base["label"] = "%s %d" % [str(base.get("label", btype)), n]
		base["pos"] = [slots[i][0], slots[i][1]]
		lots.append(base)
		layout_lots[str(base["id"])] = [slots[i][0], slots[i][1]]
	var nb: Dictionary = (_saved_table as Dictionary).duplicate(false)
	nb["lots"] = lots
	nb["grid"] = [cols, rows]
	tables["neighborhood"] = nb
	var vx: Array = []
	for k in cols + 1:
		vx.append(1 + BLOCK_W * k)
	var hy: Array = []
	for k in rows + 1:
		hy.append(1 + BLOCK_H * k)
	MapBuilder._layout = {"version": 1, "road_w": ROAD_W, "vroads_x": vx, "hroads_y": hy, "lot_size": [32, 24], "lots": layout_lots,
		"green": {"slot": green, "label": "Town Green", "pond": [8, 6, 23, 17]}, "south_strip": {"y": int(p["strip_y"]), "label": "Southwoods"},
		"tree_density": 0.16, "tree_seed": 20241}
	MapBuilder._hood = {"lots": lots}
	MapBuilder.size_override = p["map"]


## Lot types in assignment order: home first, then the venues round-robin (they end up next to the home, so a crowd forms), the
## services, then the townie homes / towers round-robin (the outskirts).
static func _recipe_order(compose: Dictionary) -> Array:
	var left: Dictionary = compose.duplicate()
	var out: Array = []
	for first in ["home"]:
		if int(left.get(first, 0)) > 0:
			out.append(first)
			left[first] = int(left[first]) - 1
	_round_robin(out, left, VENUE_ORDER)
	for s in ["hospital", "police", "courthouse"]:
		while int(left.get(s, 0)) > 0:
			out.append(s)
			left[s] = int(left[s]) - 1
	_round_robin(out, left, HOME_ORDER)
	return out


static func _round_robin(out: Array, left: Dictionary, kinds: Array) -> void:
	var more := true
	while more:
		more = false
		for k in kinds:
			if int(left.get(k, 0)) > 0:
				out.append(k)
				left[k] = int(left[k]) - 1
				more = true


## Story gives every townie a home number 1..6; the generated town has dozens of townie homes.
static func _spread_townie_homes() -> void:
	var homes := 0
	for l in Neighborhood.lots():
		if str(l.get("type", "")) == "townie_home":
			homes += 1
	if homes <= 0:
		return
	var i := 0
	for id in Story.townies:
		(Story.townies[id] as Dictionary)["lot"] = 1 + i % homes
		i += 1


## level_kit towers (6 storeys, lift + stairs) inside the empty "tower" lots.
static func _build_towers() -> int:
	var w: WorldGrid = Kit.world()
	var n := 0
	w.regions.enforce = false
	for l in Neighborhood.lots():
		if str(l.get("type", "")) != "tower":
			continue
		var rc: Rect2i = Neighborhood.rect_of(str(l["id"]))
		if rc.size == Vector2i.ZERO:
			continue
		LevelKit.add_tower(w, Rect2i(rc.position + Vector2i(8, 4), Vector2i(16, 12)), 6, true)
		n += 1
	w.regions.enforce = true
	w.rooms.invalidate_all()
	return n


static func _by_type() -> Dictionary:
	var out: Dictionary = {}
	for l in Neighborhood.lots():
		var t := str(l.get("type", ""))
		out[t] = int(out.get(t, 0)) + 1
	return out
