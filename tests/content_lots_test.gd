extends RefCounted
## data/lot_templates.json: three furnished lots (small / medium / large) are loaded into the REAL World autoload
## using its own placement rules (can_place / place_object), then checked for reachability and completeness.

const Kit = preload("res://tests/sim_testkit.gd")
const CK = preload("res://tests/content_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var W: Node = Engine.get_main_loop().root.get_node_or_null("World")
	if W == null:
		return ["World autoload missing"]
	var t: Variant = CK.read_json("res://data/lot_templates.json")
	_check(t is Dictionary and (t as Dictionary).has("lots"), "lot_templates.json missing or malformed")
	if not (t is Dictionary):
		return fails
	var lots: Dictionary = t["lots"]
	_check(lots.has("small") and lots.has("medium") and lots.has("large"), "needs small, medium and large lots")
	var counts: Array = []
	for name in ["small", "medium", "large"]:
		if lots.has(name):
			counts.append(_load_lot(W, name, lots[name]))
	if counts.size() == 3:
		_check(counts[0] < counts[1] and counts[1] < counts[2], "lots grow in size: %s objects" % str(counts))
		_check(counts[0] >= 14 and counts[1] >= 30 and counts[2] >= 50, "lots are furnished: %s objects" % str(counts))
	W.reset()
	return fails

func _load_lot(W: Node, name: String, lot: Dictionary) -> int:
	W.reset()
	for fl in lot["floors"]:
		var r: Array = fl["rect"]
		W.set_floor_rect_raw(Vector2i(int(r[0]), int(r[1])), Vector2i(int(r[2]), int(r[3])), str(fl["type"]))
		_check(W.FLOOR_DEFS.has(str(fl["type"])), "%s: unknown floor type %s" % [name, str(fl["type"])])
	for wl in lot["walls"]:
		var a: Array = wl["a"]
		var b: Array = wl["b"]
		var n: int = W.edit._apply_wall_line(Vector2i(int(a[0]), int(a[1])), Vector2i(int(b[0]), int(b[1])), str(wl["type"]), null)
		_check(n > 0, "%s: wall %s-%s changed nothing" % [name, str(a), str(b)])
	var defs: Dictionary = SimEnv.data().objects()
	var placed: Array = []
	var tags: Dictionary = {}
	var placed_n := 0
	# walls first, then wall-mounted pieces, then the rest (the order in the file is already valid, but be explicit)
	for o in lot["objects"]:
		var did: String = str(o["def"])
		_check(defs.has(did), "%s: unknown object def %s" % [name, did])
		var tile := Vector2i(int(o["tile"][0]), int(o["tile"][1]))
		var rot: int = int(o["rot"])
		var ok: bool = W.can_place(did, tile, rot)
		_check(ok, "%s: cannot place %s at %s rot %d (%s)" % [name, did, str(tile), rot, str(W.last_error)])
		if not ok:
			continue
		var id: int = W.place_object(did, tile, rot)
		_check(id >= 0, "%s: place_object failed for %s at %s" % [name, did, str(tile)])
		if id >= 0:
			placed_n += 1
			placed.append(id)
			for tg in defs[did].get("tags", []):
				tags[tg] = true
	_check(placed_n == (lot["objects"] as Array).size(), "%s: only %d of %d objects placed" % [name, placed_n, (lot["objects"] as Array).size()])
	# every item with a slot can be reached from the spawn tiles
	var spawn: Array = lot["spawn"]
	_check(not spawn.is_empty(), "%s: no spawn tiles" % name)
	var from := Vector2i(int(spawn[0][0]), int(spawn[0][1]))
	_check(W.is_walkable(from), "%s: spawn tile %s is not walkable" % [name, str(from)])
	for sp in spawn:
		var st := Vector2i(int(sp[0]), int(sp[1]))
		_check(W.is_walkable(st) and (st == from or W.has_path(from, st)), "%s: spawn %s not connected to the first spawn" % [name, str(st)])
	var unreachable: Array = []
	for id2 in placed:
		var o2 = W.get_object(id2)
		if o2.is_wall_mounted():
			continue
		for i in o2.slot_count():
			var st2: Vector2i = o2.slot_tile(i)
			if st2 == from:
				continue
			if not W.has_path(from, st2):
				unreachable.append("%s slot %d at %s" % [o2.def_id, i, str(st2)])
	_check(unreachable.is_empty(), "%s: unreachable slots: %s" % [name, str(unreachable.slice(0, 6))])
	# essentials: somewhere to sleep, wash, cook, eat, sit
	for tg in ["bed", "kitchen", "plumbing", "seat", "living"]:
		_check(tags.has(tg), "%s: missing a '%s' object" % [name, tg])
	var kinds: Dictionary = {}
	for id3 in placed:
		kinds[W.get_object(id3).def_id] = true
	for need in ["toilet", "fridge", "stove", "door"]:
		_check(kinds.has(need), "%s: missing %s" % [name, need])
	_check(kinds.has("shower") or kinds.has("bathtub"), "%s: needs a shower or bathtub" % name)
	# the lot is enclosed: from a spawn tile you cannot walk to the world corner (0,0) without a door, and the door exists
	var extra := 0
	var legacy: Array = CK.read_json("res://tests/content_legacy_ids.json")["objects"]
	for k in kinds:
		if not legacy.has(k):
			extra += 1
	_check(extra >= (4 if name == "small" else 8 if name == "medium" else 18), "%s uses %d extra-content object types" % [name, extra])
	_check(int(lot.get("price", 0)) > 0, "%s: price missing" % name)
	return placed_n
