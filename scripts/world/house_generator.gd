class_name HouseGenerator
extends RefCounted
## Procedural homes for the neighbourhood: same schema as data/lot_templates.json, deterministic per spec seed.
##   HouseGenerator.template("small_03") -> Dictionary   (from data/generated_lots.json)
##   HouseGenerator.make_home(spec, taken) -> {template, report}   (spec from data/house_specs.json)
## Method: treemap of rooms inside the footprint (optionally around a hall) -> walls, front door, spanning-tree doors /
## arches -> furnish every room from data/house_rules.json (each placement keeps doors + object slots reachable) ->
## windows -> yard -> quality gate (HouseScore) and a uniqueness gate (HouseSignature); retry with the next sub-seed.

const RULES_PATH := "res://data/house_rules.json"
const SPECS_PATH := "res://data/house_specs.json"
const GENERATED_PATH := "res://data/generated_lots.json"
const MAX_TRIES := 1200

static var _rules: Dictionary = {}
static var _specs: Dictionary = {}
static var _generated: Dictionary = {}


static func _load(path: String) -> Dictionary:
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return p if p is Dictionary else {}


static func rules() -> Dictionary:
	if _rules.is_empty():
		_rules = _load(RULES_PATH)
	return _rules


static func specs() -> Dictionary:
	if _specs.is_empty():
		_specs = _load(SPECS_PATH)
	return _specs


static func reload() -> void:
	_rules = {}
	_specs = {}
	_generated = {}


## Pre-generated lots (data/generated_lots.json): {"lots": {id: template}}.
static func lots() -> Dictionary:
	if _generated.is_empty():
		_generated = _load(GENERATED_PATH)
	return _generated.get("lots", {})


static func template(id: String) -> Dictionary:
	return lots().get(id, {})


static func ids() -> Array:
	return lots().keys()


## Ids of one kind of home, sorted: pool("small") -> [small_01 .. small_06]; pool("townie") -> [townie_a, townie_b, townie_c].
static func pool(kind: String) -> Array:
	var out: Array = []
	for id in lots():
		if str(id).begins_with(kind + "_"):
			out.append(str(id))
	out.sort()
	return out


## The hand-made venue template followed by its generated alternates: venue_pool("cafe") -> [cafe, cafe_v1, cafe_v2, cafe_v3].
static func venue_pool(venue_type: String) -> Array:
	return [venue_type] + pool(venue_type)


## Try sub-seeds until a layout passes the quality gate and its signatures are not in `taken`.
## Returns {template, report} or {} when nothing worked.
static func make_home(spec: Dictionary, taken: Dictionary = {}) -> Dictionary:
	var rl := rules()
	var rng := RandomNumberGenerator.new()
	var why: Dictionary = {}
	for attempt in MAX_TRIES:
		rng.seed = int(spec["seed"]) * 7919 + attempt * 104729
		var plan := HousePlan.new()
		var issues := _attempt(plan, spec, rl, rng, attempt)
		if not issues.is_empty():
			var k := str(issues[0]).substr(0, 28)
			why[k] = int(why.get(k, 0)) + 1
			continue
		var t := _export(plan, spec, rl)
		var ps := HouseSignature.plan_sig(t)
		var ls := HouseSignature.layout_sig(t)
		if taken.has(ps) or taken.has(ls):
			why["duplicate"] = int(why.get("duplicate", 0)) + 1
			continue
		var rep := HouseScore.stats(plan)
		rep["tries"] = attempt + 1
		rep["plan_sig"] = ps
		rep["layout_sig"] = ls
		rep["rejected"] = why
		return {"template": t, "report": rep}
	return {"report": {"failed": true, "rejected": why}}


## One attempt; returns the list of issues (empty = the plan in `plan` is a finished, valid home).
static func _attempt(plan: HousePlan, spec: Dictionary, rl: Dictionary, rng: RandomNumberGenerator, attempt: int) -> Array:
	var fp: Dictionary = rl["footprints"][str(spec["size"])]
	var s: Array = fp["shell"]
	plan.shell = Rect2i(int(s[0]), int(s[1]), int(s[2]), int(s[3]))
	plan.bounds = plan.shell
	var hall := int(spec.get("hall", 0))
	var band := false
	if hall == 0 and attempt >= 60 and (spec.get("private", []) as Array).size() >= 4:
		band = attempt % 3 != 0  # many bedrooms and no luck with a free treemap: public band + private band (every bedroom touches a day room)
		if attempt % 3 == 2:
			hall = 1
	if not HouseRooms.layout(plan, HouseRooms.program(spec, rl), hall, rl, rng, band):
		return ["layout does not fit"]
	if not HouseDoors.front_door(plan, rl, rng):
		return ["front door impossible"]
	var links := HouseDoors.links(plan, spec, rl, rng)
	if links.is_empty():
		return ["links impossible"]
	var issues := HouseScore.layout(plan, links, rl)
	if not issues.is_empty():
		return issues
	var back: Dictionary = {}
	if str(spec["size"]) != "small":
		back = HouseDoors.back_door(plan, rl, HouseYard.yard_rect(plan, fp), rng)
	var inside_entry := plan.entry
	var fz := HouseFurnish.new(plan, rng)
	var rt: Dictionary = rl["rooms"]
	var extras: Dictionary = spec.get("extras", {})
	for ri in plan.rooms.size():
		var t := str(plan.rooms[ri]["type"])
		fz.room(ri, (rt[t]["items"] as Array) + (extras.get(t, []) as Array))
	for k in int(spec.get("decor", 0)):
		var ri := rng.randi_range(0, plan.rooms.size() - 1)
		if str(plan.rooms[ri]["type"]) in ["hall", "bath", "powder", "garage", "laundry"]:
			continue
		fz.room(ri, [{"d": ["plant", "lamp", "bookshelf", "plant"], "at": ["corner", "wall"]}])
	if not fz.missing.is_empty():
		return ["required: " + str(fz.missing[0])]
	HouseDoors.windows(plan, rl, rng)
	issues = HouseScore.final(plan, links, rl, str(spec["size"]))
	if not issues.is_empty():
		return issues
	var yard := HouseYard.build(plan, fz, spec, fp, rl, back, rng)
	plan.yard_out = yard
	plan.entry = inside_entry
	plan.bounds = yard["yard"]
	if not plan.valid():
		return ["yard blocks the house"]
	return []


# ------------------------------------------------------------------ export
static func _floor_type(room_type: String, style: Dictionary, rt: Dictionary, rng: RandomNumberGenerator) -> String:
	var fm: Dictionary = style.get("floor", {})
	if fm.has(room_type):
		return str(fm[room_type])
	var l: Array = rt[room_type]["floor"]
	return str(l[rng.randi_range(0, l.size() - 1)])


static func _export(plan: HousePlan, spec: Dictionary, rl: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec["seed"]) + 17
	var style: Dictionary = rl["styles"].get(str(spec["style"]), {})
	var floors: Array = []
	for r in plan.rooms:
		var rc: Rect2i = r["rect"]
		floors.append({"rect": [rc.position.x, rc.position.y, rc.end.x - 1, rc.end.y - 1], "type": _floor_type(str(r["type"]), style, rl["rooms"], rng)})
	for f in plan.yard_out["floors"]:
		floors.append(f)
	var walls: Array = _wall_lines(plan)
	for w in plan.yard_out["walls"]:
		walls.append(w)
	var objs: Array = []
	var price := 0
	for m in plan.mounts:
		objs.append({"def": m["def"], "tile": [m["tile"].x, m["tile"].y], "rot": m["rot"]})
		price += int(HousePlan.def_of(str(m["def"])).get("price", 0))
	for o in plan.objects:
		objs.append({"def": o["def"], "tile": [o["tile"].x, o["tile"].y], "rot": o["rot"]})
		price += int(HousePlan.def_of(str(o["def"])).get("price", 0))
	var spawn := _spawns(plan, int(rl["footprints"][str(spec["size"])]["spawns"]))
	var bed_tile: Vector2i = spawn[1] if spawn.size() > 1 else spawn[0]
	return {"label": spec["label"], "description": spec["desc"], "kind": "home", "size": spec["size"], "style": spec["style"],
		"floors": floors, "walls": walls, "objects": objs,
		"spawn": spawn.map(func(t): return [t.x, t.y]), "entry": [plan.entry.x, plan.entry.y],
		"bedroom": [bed_tile.x, bed_tile.y], "price": price}


## Merge wall edges (type wall / door / window, inside the shell rectangle) into maximal straight lines.
static func _wall_lines(plan: HousePlan) -> Array:
	var h: Dictionary = {}
	var v: Dictionary = {}
	for e in plan.walls:
		if not (str(plan.walls[e]) in ["wall", "door", "window"]):
			continue
		var tiles := HousePlan.edge_tiles(e)
		if not plan.shell.has_point(tiles[0]) and not plan.shell.has_point(tiles[1]):
			continue
		if e.z == 0:
			if not h.has(e.y):
				h[e.y] = []
			h[e.y].append(e.x)
		else:
			if not v.has(e.x):
				v[e.x] = []
			v[e.x].append(e.y)
	var out: Array = []
	for y in h:
		for run in _runs(h[y]):
			out.append({"a": [run[0], y], "b": [run[1] + 1, y], "type": "wall"})
	for x in v:
		for run in _runs(v[x]):
			out.append({"a": [x, run[0]], "b": [x, run[1] + 1], "type": "wall"})
	return out


static func _runs(vals: Array) -> Array:
	vals.sort()
	var out: Array = []
	var start: int = vals[0]
	var prev: int = vals[0]
	for i in range(1, vals.size()):
		if int(vals[i]) != prev + 1:
			out.append([start, prev])
			start = vals[i]
		prev = vals[i]
	out.append([start, prev])
	return out


## Spawn tiles: just inside the front door, then beside the beds (one per bedroom), then any free tile near the entry.
static func _spawns(plan: HousePlan, count: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = [plan.entry]
	var reach := plan.flood(plan.entry, plan.shell)
	for i in plan.objects.size():
		var d := HousePlan.def_of(str(plan.objects[i]["def"]))
		if not ("bed" in (d.get("tags", []) as Array)) or out.size() >= count:
			continue
		for s in HousePlan.slot_tiles(d, plan.objects[i]["tile"], int(plan.objects[i]["rot"])):
			if reach.has(s) and s not in out and not plan.clear.has(s):
				out.append(s)
				break
	var rest: Array = reach.keys()
	rest.sort_custom(func(a, b): return absi(a.x - plan.entry.x) + absi(a.y - plan.entry.y) < absi(b.x - plan.entry.x) + absi(b.y - plan.entry.y))
	for t in rest:
		if out.size() >= count:
			break
		if t not in out and not plan.clear.has(t):
			out.append(t)
	return out
