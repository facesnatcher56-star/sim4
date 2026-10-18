class_name HouseScore
extends RefCounted
## Quality gate for generated homes. layout() runs before furnishing (room sizes, door graph), final() after
## (fixtures per room, windows, doors clear, object counts). Both return a list of issue strings; empty = pass.

const BEDS := ["bed", "single_bed", "bunk_bed", "crib"]
const STORE := ["wardrobe", "dresser"]
const BEDROOMS := ["bedroom", "master", "kids", "nursery"]


static func layout(plan: HousePlan, links: Array, rules: Dictionary) -> Array:
	var issues: Array = []
	var rt: Dictionary = rules["rooms"]
	for r in plan.rooms:
		var d: Dictionary = rt.get(str(r["type"]), {})
		var rc: Rect2i = r["rect"]
		var area := rc.size.x * rc.size.y
		var lo := mini(rc.size.x, rc.size.y)
		var hi := maxi(rc.size.x, rc.size.y)
		var zone := bool(r["zone"])
		if area < int(float(d.get("min_area", 4)) * (0.6 if zone else 1.0)):
			issues.append("%s too small (%d)" % [r["type"], area])
		if area > int(float(d.get("max_area", 999)) * maxf(1.0, plan.scale * 0.8)):
			issues.append("%s too big (%d)" % [r["type"], area])
		if lo < (2 if zone else int(d.get("min_dim", 1))):
			issues.append("%s too narrow" % r["type"])
		if not zone and lo > 0 and float(hi) / float(lo) > float(d.get("aspect", 3.0)):
			issues.append("%s too long (%dx%d)" % [r["type"], rc.size.x, rc.size.y])
	# door graph: everything reachable; bedrooms reach a full bathroom without crossing another bedroom
	var gtype: Dictionary = {}
	for r in plan.rooms:
		gtype[int(r["group"])] = str(r["gtype"])
	var nb: Dictionary = {}
	for g in gtype:
		nb[g] = []
	for l in links:
		nb[l["ga"]].append(l["gb"])
		nb[l["gb"]].append(l["ga"])
	var start := plan.group_at(plan.entry)
	if _reach(nb, start, gtype, "").size() != gtype.size():
		issues.append("rooms not all connected")
	var has_bath := false
	for g in gtype:
		if gtype[g] == "bath":
			has_bath = true
	for g in gtype:
		if str(gtype[g]) in BEDROOMS:
			var r2 := _reach(nb, g, gtype, "bedroom")
			var ok := not has_bath
			for x in r2:
				if gtype[x] == "bath":
					ok = true
			if not ok:
				issues.append("%s cannot reach a bathroom" % gtype[g])
			var pubnb := false
			for x in nb[g]:
				if not (str(gtype[x]) in HouseRooms.PRIV):
					pubnb = true
			if not pubnb:
				issues.append("%s opens only into private rooms" % gtype[g])
	var es := str(gtype.get(start, ""))
	if not (es in ["living", "hall"]):
		var hop := false
		for x in nb.get(start, []):
			if str(gtype[x]) == "living":
				hop = true
		if not hop and es != "lounge":
			issues.append("entry does not lead to a living space")
	return issues


## Groups reachable from `from`; bedrooms other than `from` are not traversed when mode is "bedroom".
static func _reach(nb: Dictionary, from: int, gtype: Dictionary, mode: String) -> Array:
	var seen := {from: true}
	var stack: Array = [from]
	while not stack.is_empty():
		var c: int = stack.pop_back()
		for x in nb[c]:
			if seen.has(x):
				continue
			if mode == "bedroom" and str(gtype[x]) in BEDROOMS:
				continue
			seen[x] = true
			stack.append(x)
	return seen.keys()


static func final(plan: HousePlan, links: Array, rules: Dictionary, size_class: String) -> Array:
	var issues: Array = []
	var fp: Dictionary = rules["footprints"][size_class]
	var kinds: Dictionary = {}
	for o in plan.objects:
		kinds[str(o["def"])] = true
	if plan.objects.size() < int(fp["min_objects"]) - plan.mounts.size():
		issues.append("only %d objects" % plan.objects.size())
	if kinds.size() < int(fp["min_kinds"]):
		issues.append("only %d kinds of object" % kinds.size())
	for r in plan.rooms:
		var inside := _defs_in(plan, r["rect"])
		var t := str(r["type"])
		var n := 0
		for k in inside:
			n += int(inside[k])
		if t != "hall" and n < 2 and not bool(r["zone"]):
			issues.append("%s nearly empty" % t)
		match t:
			"bath":
				if not (inside.has("toilet") and inside.has("sink") and (inside.has("shower") or inside.has("bathtub"))):
					issues.append("bathroom lacks fittings")
			"powder":
				if not (inside.has("toilet") and inside.has("sink")):
					issues.append("powder room lacks fittings")
			"kitchen", "kitchen_diner":
				if not (inside.has("fridge") and inside.has("stove") and inside.has("counter") and inside.has("sink")):
					issues.append("kitchen lacks fridge/stove/counter/sink")
			"bedroom", "master", "kids", "nursery", "sleep":
				var bed := false
				for b in BEDS:
					bed = bed or inside.has(b)
				var store := false
				for s in STORE:
					store = store or inside.has(s)
				if not bed or not store:
					issues.append("%s lacks bed or storage" % t)
			"living":
				if not (inside.has("tv") and inside.has("sofa")):
					issues.append("living area lacks tv/sofa")
	# kitchen near dining
	var tables: Array = []
	var stoves: Array = []
	for o in plan.objects:
		if str(o["def"]) == "table":
			tables.append(o["tile"])
		elif str(o["def"]) == "stove":
			stoves.append(o["tile"])
	for o in plan.objects:
		if str(o["def"]) == "bar_counter":
			tables.append(o["tile"])
	if tables.is_empty():
		issues.append("nowhere to eat")
	else:
		var near := 99
		for a in tables:
			for b in stoves:
				near = mini(near, absi(a.x - b.x) + absi(a.y - b.y))
		if near > (12 if size_class == "large" else 9):
			issues.append("dining table far from the kitchen (%d)" % near)
	for w in HouseDoors.missing_windows(plan, rules):
		issues.append("%s has no window" % w)
	# nothing on door tiles, no tall furniture in front of windows
	for t in plan.clear:
		if plan.occ.has(t):
			issues.append("furniture on a doorway %s" % str(t))
	for m in plan.mounts:
		if str(m["def"]) == "window" and HouseDoors._tall(plan, m["tile"]):
			issues.append("tall furniture in front of a window")
	return issues


static func _defs_in(plan: HousePlan, rect: Rect2i) -> Dictionary:
	var out: Dictionary = {}
	for i in plan.objects.size():
		if rect.has_point(plan.objects[i]["tile"]):
			var k := str(plan.objects[i]["def"])
			out[k] = int(out.get(k, 0)) + 1
	return out


## Numbers for the contact-sheet / test report.
static func stats(plan: HousePlan) -> Dictionary:
	var kinds: Dictionary = {}
	var min_area := 999
	var windows := 0
	var doors := 0
	for o in plan.objects:
		kinds[str(o["def"])] = true
	for r in plan.rooms:
		if not bool(r["zone"]):
			min_area = mini(min_area, r["rect"].size.x * r["rect"].size.y)
	for m in plan.mounts:
		if str(m["def"]) == "window":
			windows += 1
		else:
			doors += 1
	var groups: Dictionary = {}
	for r in plan.rooms:
		groups[int(r["group"])] = true
	return {"rooms": groups.size(), "min_room_area": min_area, "objects": plan.objects.size() + plan.mounts.size(),
		"kinds": kinds.size(), "windows": windows, "doors": doors}
