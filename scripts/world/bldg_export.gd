class_name BldgExport
extends RefCounted
## Assembles the lot template of a generated multi-floor building from its per-level plans (see BuildingGen).



static func template(spec: Dictionary, fr: BldgFrame, plans: Dictionary, units: Array, lvs: Dictionary, bottom: int, top: int, rl: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec["seed"]) + 17
	var rt: Dictionary = rl["rooms"]
	var sh := fr.shell
	var floors0: Array = []
	var walls0: Array = []
	var levels: Dictionary = {}
	var objs: Array = []
	var stops: Dictionary = {}
	var names: Dictionary = {}
	var price := 0
	var house := str(spec.get("kind", "tower")) in ["house", "apartments"]
	var real_house := str(spec.get("kind", "tower")) == "house"
	var entry := Vector2i.ZERO
	for l in range(bottom, top + 1):
		var plan: HousePlan = plans[l]["plan"]
		var fl: Array = []
		for r in plan.rooms:
			var rc: Rect2i = r["rect"]
			var opts: Array = rt[str(r["type"])]["floor"]
			var ft := str(opts[rng.randi_range(0, opts.size() - 1)])
			var ov: Dictionary = spec.get("floor_types", {})
			if ov.has(str(r["type"])):
				ft = str(ov[str(r["type"])])
			if l < 0 and ft in ["wood", "carpet"] and str(r["type"]) not in ["bedroom", "master"]:
				ft = "concrete"
			fl.append({"rect": [rc.position.x, rc.position.y, rc.end.x - 1, rc.end.y - 1], "type": ft})
		var wl := HouseGenerator._wall_lines(plan)
		if l == 0:
			floors0 = fl
			entry = plan.entry
			walls0 = wl
			_apron(floors0, sh, real_house, entry)
		else:
			levels[str(l)] = {"floors": fl, "walls": wl}
		for m in plan.mounts:
			var o: Dictionary = {"def": m["def"], "tile": [m["tile"].x, m["tile"].y], "rot": m["rot"]}
			if l != 0:
				o["level"] = l
			objs.append(o)
			price += int(HousePlan.def_of(str(m["def"])).get("price", 0))
		for o in plan.objects:
			var od: Dictionary = {"def": o["def"], "tile": [o["tile"].x, o["tile"].y], "rot": o["rot"]}
			if l != 0:
				od["level"] = l
			objs.append(od)
			price += int(HousePlan.def_of(str(o["def"])).get("price", 0))
		for f in fr.flights(l, bottom, top):
			objs.append(_obj(f["def"], f["tile"], f["rot"], l))
			price += int(HousePlan.def_of(str(f["def"])).get("price", 0))
		var e := fr.entry_tile()
		stops[str(l)] = [e.x, e.y]
		var lvd: Dictionary = lvs.get(l, {})
		names[str(l)] = str(lvd.get("name", LPos.level_name(l)))
	var esc: String = str(spec.get("fire_escape", ""))
	if esc != "":
		for l in range(0, top):
			var lt: Array = escape_landing(sh, esc, l)
			var dirr: int = 0 if esc == "north" else 1
			var ft: Vector2i = lt[0] + (Vector2i(1, 0) if esc == "north" else Vector2i(0, 1))
			objs.append(_obj("fire_escape", ft, dirr, l))
			price += int(HousePlan.def_of("fire_escape").get("price", 0))
		for l in range(1, top + 1):                        # balcony floors on the ring: the landing tile and the two tiles of the flight below it
			var rc: Array = _balcony_rect(sh, esc, l, top)
			(levels[str(l)]["floors"] as Array).append({"rect": rc, "type": "concrete"})
	if fr.lift and top > bottom:
		var lo: Dictionary = fr.lift_object(bottom)
		objs.append(_obj(lo["def"], lo["tile"], lo["rot"], bottom))
		price += int(HousePlan.def_of("elevator").get("price", 0))
	var spawn: Array = _spawns(sh, plans[0]["plan"], real_house)
	var kind := "home" if house else "venue"
	var t: Dictionary = {"label": spec["label"], "description": spec["desc"], "kind": kind, "floors": floors0, "walls": walls0, "objects": objs,
		"spawn": spawn, "entry": spawn[0] if not real_house else [entry.x, entry.y], "price": price + 300 * (top - bottom), "roof": str(spec.get("roof", "flat")),
		"levels": levels, "floor_names": names, "stops": stops, "staff": []}
	if real_house:
		t["size"] = str(spec.get("size", "medium"))
		t["style"] = str(spec.get("style", "modern"))
		t["bedroom"] = spawn[1] if spawn.size() > 1 else spawn[0]
	else:
		t["venue"] = str(spec.get("venue", spec.get("kind", "office")))
	t["variant"] = str(spec.get("variant", ""))
	if esc != "":
		t["fire_escape"] = esc
	if spec.has("career_floors"):
		t["career_floors"] = spec["career_floors"]
	if not units.is_empty():
		t["units"] = _unit_records(units)
	for k in ["tags", "wards"]:
		if spec.has(k):
			t[k] = spec[k]
	return t


## The landing of the fire escape on `level` (where the door of that floor is): [outside tile (ring), inside tile, wall edge].
## The escape climbs in flights of 3 tiles along one wall: side "west" / "east" (x ring, flights run south) or "north" (y ring, flights run east).
static func escape_landing(sh: Rect2i, side: String, level: int) -> Array:
	match side:
		"west":
			var y: int = sh.position.y + 3 * level
			return [Vector2i(sh.position.x - 1, y), Vector2i(sh.position.x, y), Vector3i(sh.position.x, y, 1)]
		"east":
			var y2: int = sh.position.y + 3 * level
			return [Vector2i(sh.end.x, y2), Vector2i(sh.end.x - 1, y2), Vector3i(sh.end.x, y2, 1)]
	var x: int = sh.position.x + 3 * level
	return [Vector2i(x, sh.position.y - 1), Vector2i(x, sh.position.y), Vector3i(x, sh.position.y, 0)]


## Floor rect [x0, y0, x1, y1] of the balcony ring tiles on `level` (landing + the flight that leaves it; the top floor: just the landing).
static func _balcony_rect(sh: Rect2i, side: String, level: int, top: int) -> Array:
	var a: Vector2i = escape_landing(sh, side, level)[0]
	var n := 0 if level >= top else 2
	if side == "north":
		return [a.x, a.y, a.x + n, a.y]
	return [a.x, a.y, a.x, a.y + n]


static func _obj(def_id: String, tile: Vector2i, rot: int, level: int) -> Dictionary:
	var o: Dictionary = {"def": def_id, "tile": [tile.x, tile.y], "rot": rot}
	if level != 0:
		o["level"] = level
	return o


## Forecourt (venues) or a stone path to the lot edge (homes) in front of the south door.
static func _apron(floors0: Array, sh: Rect2i, house: bool, entry: Vector2i) -> void:
	if house:
		floors0.append({"rect": [entry.x, sh.end.y, entry.x, 23], "type": "stone"})
		return
	floors0.append({"rect": [0, sh.end.y, 31, sh.end.y], "type": "stone"})
	if sh.end.y + 1 <= 23:
		floors0.append({"rect": [0, sh.end.y + 1, 31, 23], "type": "concrete"})


static func _spawns(sh: Rect2i, plan0: HousePlan, house: bool) -> Array:
	if not house:
		var y := mini(sh.end.y + 1, 22)
		return [[15, y], [16, y], [14, y]]
	var out: Array = [[plan0.entry.x, plan0.entry.y]]
	var reach := plan0.flood(plan0.entry, plan0.shell)
	var rest: Array = reach.keys()
	rest.sort_custom(func(a, b): return absi(a.x - plan0.entry.x) + absi(a.y - plan0.entry.y) < absi(b.x - plan0.entry.x) + absi(b.y - plan0.entry.y))
	for t in rest:
		if out.size() >= 3:
			break
		if [t.x, t.y] not in out and not plan0.clear.has(t):
			out.append([t.x, t.y])
	return out


static func _unit_records(units: Array) -> Array:
	var out: Array = []
	var n := 0
	for u in units:
		n += 1
		var rc: Rect2i = u["rect"]
		var d: Array = u.get("door", [Vector2i(-1, -1), Vector2i(-1, -1)])
		out.append({"id": "u%d" % n, "level": int(u["level"]), "rect": [rc.position.x, rc.position.y, rc.size.x, rc.size.y], "kind": str(u["kind"]),
			"bedrooms": int(u["bedrooms"]), "door": [(d[0] as Vector2i).x, (d[0] as Vector2i).y]})
	return out
