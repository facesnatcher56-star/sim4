extends RefCounted
## Every lot template (classic + data/lot_templates.json: homes, venues) builds into the REAL World through LotLoader,
## places every object, has walkable connected entry tiles and every usable object is reachable from the entry.
## The neighbourhood map itself is validated too (templates exist, venue types known, staff tiles standable).

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var root: Window = Engine.get_main_loop().root
	var W: Node = root.get_node_or_null("World")
	if W == null:
		return ["World autoload missing"]
	NeighborhoodContent.install()
	var data = SimEnv.data()
	_check(data.interactions().has("order_coffee") and data.interactions().has("sys_staff"), "venue interactions installed")
	_check(W.defs.has("park_bench") and W.defs.has("cafe_counter") and W.defs.has("grocery_cooler"), "venue objects installed into World.defs")
	var ids: Array = LotLoader.template_ids()
	_check(ids.size() >= 11, "classic + 3 homes + venues expected, got %s" % str(ids))
	var min_objects := {"classic": 40, "small": 14, "medium": 30, "large": 50, "park": 25, "cafe": 30, "gym": 25, "library": 40, "market": 25, "office": 30, "school": 40}
	for gid in LotLoader.generated_ids():          # generated layouts: the generator report's minimums per size class
		var g: Dictionary = LotLoader.template(str(gid))
		if str(g.get("kind", "")) == "home":
			min_objects[gid] = {"small": 14, "medium": 30, "large": 50, "classic": 40}.get(str(g.get("size", "")), 14)
		else:
			min_objects[gid] = int(min_objects.get(str(g.get("venue", "")), 10))
	ids.append_array(LotLoader.generated_ids())
	for tid in ids:
		var ok: bool = LotLoader.apply(str(tid))
		var rep: Dictionary = LotLoader.report
		_check(ok, "%s: apply failed: %s" % [tid, str(rep.get("failed", []))])
		_check(W.objects.size() >= int(min_objects.get(tid, 10)), "%s: only %d objects" % [tid, W.objects.size()])
		var spawn: Array = W.starter_spawn_tiles
		_check(not spawn.is_empty(), "%s: no spawn tiles" % tid)
		if spawn.is_empty():
			continue
		var from: Vector2i = spawn[0]
		_check(W.is_walkable(from), "%s: entry %s not walkable" % [tid, str(from)])
		for sp in spawn:
			_check(W.is_walkable(sp) and W.has_path(from, sp), "%s: spawn %s disconnected" % [tid, str(sp)])
		var bad: Array = LotLoader.unreachable_objects(W, from)
		_check(bad.is_empty(), "%s: unreachable objects: %s" % [tid, str(bad)])
		# walls: a door or gate must lead out of any building so the entry connects (checked above through reachability)
		for sd in LotLoader.template(str(tid)).get("staff", []):
			var st := Vector2i(int(sd["tile"][0]), int(sd["tile"][1]))
			_check(W.is_walkable(st) and W.has_path(from, st), "%s: staff post %s not reachable" % [tid, str(st)])
	# neighbourhood map
	var lots: Array = Neighborhood.lots()
	_check(lots.size() >= 10, "map has at least 10 lots (%d)" % lots.size())
	var seen: Dictionary = {}
	for l in lots:
		var lid: String = str(l["id"])
		_check(not seen.has(lid), "duplicate lot id %s" % lid)
		seen[lid] = true
		if lid != "home":
			_check(LotLoader.has_template(str(l.get("template", ""))), "lot %s: unknown template %s" % [lid, str(l.get("template", ""))])
		_check(not Venues.type_def(str(l.get("type", ""))).is_empty(), "lot %s: venue type %s undefined" % [lid, str(l.get("type", ""))])
	for need in ["park", "cafe", "gym", "library", "market", "office", "school", "townie_a", "townie_b", "townie_c"]:
		_check(seen.has(need), "map misses lot %s" % need)
	# the venue objects the brief asks for exist somewhere
	var want := {"park": ["park_bench", "fishing_spot", "grill"], "cafe": ["cafe_counter", "bar_stool", "stereo"],
		"gym": ["treadmill", "dumbbell_rack"], "library": ["bookcase_tall", "desk", "computer", "terminal"],
		"market": ["vending_machine", "grocery_cooler"]}
	for tid2 in want:
		var defs_used: Dictionary = {}
		for o in LotLoader.template(tid2).get("objects", []):
			defs_used[str(o["def"])] = true
		for d in want[tid2]:
			_check(defs_used.has(d), "%s lacks %s" % [tid2, d])
	W.reset()
	return fails
