class_name HouseVenues
extends RefCounted
## Alternate internal layouts for the 7 venue types (data/house_specs.json "venues"): same footprint, door side and spawn tiles
## as the hand-made venue, different rooms, partitions and furniture. Rooms are given as rectangles; walls, arches / doors,
## windows, furniture and staff posts come from the same machinery as the homes.

const MAX_TRIES := 200
const SPAWN := [[15, 19], [16, 19], [14, 19]]
const PARK_SPAWN := [[15, 22], [16, 22], [14, 22]]


static func rules() -> Dictionary:
	var rl: Dictionary = HouseGenerator.rules().duplicate(true)
	(rl["rooms"] as Dictionary).merge(HouseGenerator.specs().get("venue_rooms", {}))
	return rl


## Returns {template, report} for one alternate layout, or {report: {failed}}.
static func make(vt: String, alt: Dictionary, bump: int, taken: Dictionary, legacy: Dictionary) -> Dictionary:
	var vspec: Dictionary = HouseGenerator.specs()["venues"][vt]
	var rl := rules()
	var rng := RandomNumberGenerator.new()
	var why: Dictionary = {}
	var park := vt == "park"
	for attempt in MAX_TRIES:
		rng.seed = str(alt["id"]).hash() + bump * 1009 + attempt * 7919
		var plan := HousePlan.new()
		var fz := HouseFurnish.new(plan, rng)
		var res: Variant = _attempt(plan, fz, vspec, alt, rl, rng, park)
		if res is String:
			why[res] = int(why.get(res, 0)) + 1
			continue
		var t: Dictionary = _export(plan, vt, vspec, alt, res, park)
		var ls := HouseSignature.layout_sig(t)
		if taken.has(ls):
			why["duplicate"] = int(why.get("duplicate", 0)) + 1
			continue
		var worst := 0.0
		for other in legacy:
			worst = maxf(worst, HouseSignature.similarity(t, legacy[other]))
		if worst > 0.5 and not park:
			why["too like " + str(vt)] = int(why.get("too like " + str(vt), 0)) + 1
			continue
		var rep := HouseScore.stats(plan)
		rep["tries"] = attempt + 1
		rep["layout_sig"] = ls
		rep["similarity"] = snappedf(worst, 0.01)
		return {"template": t, "report": rep}
	return {"report": {"failed": true, "rejected": why}}


## Build into `plan`; returns the staff list on success, or a String reason.
static func _attempt(plan: HousePlan, fz: HouseFurnish, vspec: Dictionary, alt: Dictionary, rl: Dictionary, rng: RandomNumberGenerator, park: bool) -> Variant:
	var s: Array = vspec["shell"]
	plan.shell = Rect2i(int(s[0]), int(s[1]), int(s[2]), int(s[3]))
	plan.bounds = plan.shell
	var gids: Dictionary = {}
	for r in alt["rooms"]:
		var rc: Array = r["rect"]
		var g := str(r["g"])
		if not gids.has(g):
			gids[g] = gids.size()
		plan.rooms.append({"id": plan.rooms.size(), "type": r["type"], "gtype": r["type"], "group": gids[g], "zone": false,
			"rect": Rect2i(plan.shell.position.x + int(rc[0]), plan.shell.position.y + int(rc[1]), int(rc[2]), int(rc[3]))})
	plan.index_rooms()
	if park:
		for pr in alt["paths"]:
			for y in range(int(pr[1]), int(pr[1]) + int(pr[3])):
				for x in range(int(pr[0]), int(pr[0]) + int(pr[2])):
					plan.paths[Vector2i(x, y)] = true
					plan.clear[Vector2i(x, y)] = true
		plan.entry = Vector2i(15, plan.shell.end.y - 1)
	else:
		HouseRooms._walls(plan)
		var dx: int = plan.shell.position.x + int(alt.get("door_x", 10))
		plan.add_mount("door", Vector3i(dx, plan.shell.end.y, 0))
		plan.entry = Vector2i(dx, plan.shell.end.y - 1)
		plan.clear[plan.entry] = true
		plan.must.append(plan.entry)
		if gids.size() > 1 and HouseDoors.links(plan, {"open_default": float(alt.get("open_default", 0.5)), "loops": 0.4}, rl, rng).is_empty():
			return "links impossible"
	for ri in plan.rooms.size():
		fz.room(ri, rl["rooms"][str(plan.rooms[ri]["type"])]["items"])
	if not fz.missing.is_empty():
		return "required " + str(fz.missing[0])
	if not park:
		HouseDoors.windows(plan, rl, rng)
	var kinds: Dictionary = {}
	for o in plan.objects:
		kinds[str(o["def"])] = true
	for w in vspec["wants"]:
		if not kinds.has(str(w)):
			return "lacks " + str(w)
	if plan.objects.size() + plan.mounts.size() < int(vspec["min_objects"]):
		return "too few objects"
	if not plan.valid():
		return "blocked"
	var staff := _staff(plan, fz, vspec, rng)
	if staff.size() != (vspec["staff"] as Array).size():
		return "no staff post"
	return staff


## Staff posts: behind island counters, beside a piece of furniture, or a free spot in a room type.
static func _staff(plan: HousePlan, fz: HouseFurnish, vspec: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var reach := plan.flood(plan.entry, plan.shell)
	var used: Array[Vector2i] = []
	var n := 0
	for sd in vspec["staff"]:
		var cands: Array[Vector2i] = []
		match str(sd["mode"]):
			"behind":
				for t in fz.behind:
					if reach.has(t) and t not in used:
						cands.append(t)
				cands.sort_custom(func(a, b): return a.x * 100 + a.y < b.x * 100 + b.y)
				var pick := mini(cands.size() - 1, int((float(n) + 0.5) * float(cands.size()) / float((vspec["staff"] as Array).size())))
				if pick >= 0:
					cands = [cands[pick]]
			"beside":
				for i in plan.objects.size():
					if str(plan.objects[i]["def"]) == str(sd["def"]):
						for t in plan.fp_of(i):
							for d in HousePlan.DIRS4:
								var c: Vector2i = t + d
								if reach.has(c) and c not in used and not plan.clear.has(c) and not plan.blocked_edge(t, c):
									cands.append(c)
						break
			_:
				for ri in plan.rooms.size():
					if str(plan.rooms[ri]["type"]) != str(sd.get("room", "")):
						continue
					var rc: Rect2i = plan.rooms[ri]["rect"]
					for y in range(rc.position.y, rc.end.y):
						for x in range(rc.position.x, rc.end.x):
							var c := Vector2i(x, y)
							var open := 0
							for d in HousePlan.DIRS4:
								if reach.has(c + d):
									open += 1
							if reach.has(c) and open >= 4 and c not in used and not plan.clear.has(c):
								cands.append(c)
				HouseRooms._shuffle(cands, rng)
		if cands.is_empty():
			break
		used.append(cands[0])
		var e := {"role": sd["role"], "tile": [cands[0].x, cands[0].y]}
		if sd.has("hours"):
			e["hours"] = sd["hours"]
		out.append(e)
		n += 1
	return out


static func _export(plan: HousePlan, vt: String, vspec: Dictionary, alt: Dictionary, staff: Array, park: bool) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = str(alt["id"]).hash()
	var rt: Dictionary = rules()["rooms"]
	var floors: Array = []
	if park:
		floors.append({"rect": [0, 22, 31, 23], "type": "concrete"})
	else:
		floors.append({"rect": [0, 18, 31, 18], "type": "stone"})
		floors.append({"rect": [0, 19, 31, 23], "type": "concrete"})
	for r in plan.rooms:
		var rc: Rect2i = r["rect"]
		var fl: Array = rt[str(r["type"])]["floor"]
		if park and str(fl[0]) == "grass":
			continue
		floors.append({"rect": [rc.position.x, rc.position.y, rc.end.x - 1, rc.end.y - 1], "type": fl[rng.randi_range(0, fl.size() - 1)]})
	if park:
		for pr in alt["paths"]:
			floors.append({"rect": [int(pr[0]), int(pr[1]), int(pr[0]) + int(pr[2]) - 1, int(pr[1]) + int(pr[3]) - 1], "type": "stone"})
	var objs: Array = []
	for m in plan.mounts:
		objs.append({"def": m["def"], "tile": [m["tile"].x, m["tile"].y], "rot": m["rot"]})
	for o in plan.objects:
		objs.append({"def": o["def"], "tile": [o["tile"].x, o["tile"].y], "rot": o["rot"]})
	var spawn: Array = PARK_SPAWN if park else SPAWN
	return {"label": vspec["label"], "description": "%s (%s)" % [vspec["description"], alt["label"]], "kind": "venue", "venue": vt, "variant": alt["label"],
		"floors": floors, "walls": [] if park else HouseGenerator._wall_lines(plan), "objects": objs, "spawn": spawn, "entry": spawn[0],
		"staff": staff, "price": 0}


## All alternates of all venue types. Returns {lots, reports, failed}.
static func make_all(bump: int, taken: Dictionary, only: PackedStringArray = PackedStringArray()) -> Dictionary:
	var lots: Dictionary = {}
	var reports: Dictionary = {}
	var failed: Array = []
	var legacy_all := HouseSignature.legacy_templates()
	for vt in HouseGenerator.specs().get("venues", {}):
		var legacy: Dictionary = {}
		if legacy_all.has(vt):
			legacy[vt] = legacy_all[vt]
		for alt in HouseGenerator.specs()["venues"][vt]["alts"]:
			var id := str(alt["id"])
			if not only.is_empty() and id not in only:
				continue
			var r := make(vt, alt, bump, taken, legacy)
			if not r.has("template"):
				failed.append(id)
				reports[id] = r["report"]
				continue
			lots[id] = r["template"]
			reports[id] = r["report"]
			taken[HouseSignature.layout_sig(r["template"])] = id
			legacy[id] = r["template"]
	return {"lots": lots, "reports": reports, "failed": failed}
