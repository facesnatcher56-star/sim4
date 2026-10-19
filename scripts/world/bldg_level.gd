class_name BldgLevel
extends RefCounted
## One level of a multi-floor building as a HousePlan: a corridor (the `hall`, holding the stair core) between two bands of cells.
## Cells are room types ("ward", "office_pods", ...) or apartment units ("unit_studio", "unit_1br", "unit_2br"). Walls, doors, windows
## and furniture come from the same machinery as the homes (HouseRooms._walls, HouseFurnish, HouseDoors.windows).
##
##   BldgLevel.build(spec, level, frame, rules, rng) -> {plan, units, fz} or {fail: "reason"}
## A cell string is "type", "type:width" (tiles along the corridor) or "type!" (the cell the front door opens into, ground floor only).

const UNIT := {"unit_studio": {"area": 30.0, "min": 5, "depth": 8}, "unit_1br": {"area": 42.0, "min": 6, "depth": 8}, "unit_2br": {"area": 56.0, "min": 8, "depth": 8}}


static func build(spec: Dictionary, level: int, lv: Dictionary, fr: BldgFrame, rules: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var plan := HousePlan.new()
	plan.shell = fr.shell
	plan.bounds = fr.shell
	var rt: Dictionary = rules["rooms"]
	var corr := int(spec.get("corr", 3))
	var da := int(spec.get("da", 5))
	var db := fr.len_v - da - corr
	var ctype := str(lv.get("corr", "hall"))
	var along_x := fr.axis == "ew"
	var rooms: Array = []           # {type, gtype, group, rect}
	var units: Array = []
	var corr_doors: Dictionary = {}
	var front_room := -1
	var gid := 0
	rooms.append({"type": ctype, "rect": fr.rect(0, da, fr.len_u, corr), "group": 0})
	gid = 1
	for band in ["a", "b"]:
		var cells: Array = lv.get(band, [])
		if cells.is_empty():
			continue
		var brect: Rect2i = fr.rect(0, 0, fr.len_u, da) if band == "a" else fr.rect(0, da + corr, fr.len_u, db)
		var items: Array = []
		for c in cells:
			var cd := _cell(str(c), rt)
			if cd.is_empty():
				return {"fail": "unknown cell %s" % str(c)}
			items.append(cd)
		var leaves: Array = []
		if not _slice(brect, items, along_x, leaves):
			return {"fail": "band %s of level %d does not fit" % [band, level]}
		for lf in leaves:
			var it: Dictionary = lf["item"]
			var rc: Rect2i = lf["rect"]
			if str(it["type"]).begins_with("unit_"):
				var ur := _unit(str(it["type"]), rc, fr, _corr_high(rc, rooms[0]["rect"], along_x), gid, rng)
				if ur.is_empty():
					return {"fail": "unit %s does not fit %s" % [str(it["type"]), str(rc)]}
				var first := rooms.size()
				for r in ur["rooms"]:
					rooms.append(r)
				var un: Dictionary = ur["unit"]
				un["first"] = first
				un["count"] = (ur["rooms"] as Array).size()
				units.append(un)
				gid = int(ur["next"])
			else:
				if bool(it.get("front", false)):
					front_room = rooms.size()
				rooms.append({"type": it["type"], "rect": rc, "group": gid, "band": band})
				gid += 1
	if str(lv.get("front", "")) == "corr":
		front_room = 0
	for r in rooms:
		plan.rooms.append({"id": plan.rooms.size(), "type": r["type"], "gtype": r["type"], "group": r["group"], "zone": false, "rect": r["rect"]})
	plan.index_rooms()
	HouseRooms._walls(plan)
	for t in fr.core_tiles():
		plan.clear[t] = true
	plan.entry = fr.entry_tile()
	plan.must.append(plan.entry)
	# doors: every cell to the corridor (units: through their living room), unit rooms among themselves
	for i in range(1, rooms.size()):
		var r: Dictionary = rooms[i]
		if bool(r.get("unit_inner", false)):
			continue
		var from_corr: bool = bool(r.get("to_corridor", true))
		if from_corr:
			var dd := _door(plan, (rooms[0]["rect"] as Rect2i), (r["rect"] as Rect2i), rng)
			if dd.is_empty():
				return {"fail": "no door for %s" % str(r["type"])}
			corr_doors[i] = dd
	for u in units:
		for k in range(1, int(u["count"])):
			if _door(plan, (plan.rooms[int(u["first"])]["rect"] as Rect2i), (plan.rooms[int(u["first"]) + k]["rect"] as Rect2i), rng).is_empty():
				return {"fail": "no inner door in unit"}
		u["door"] = corr_doors.get(int(u["first"]), [Vector2i(-1, -1), Vector2i(-1, -1)])
	if level == 0 and bool(spec.get("front", true)):
		if front_room < 0:
			front_room = 0
		if not _front_door(plan, (plan.rooms[front_room]["rect"] as Rect2i), rng):
			return {"fail": "no front door"}
	var fz := HouseFurnish.new(plan, rng)
	for ri in plan.rooms.size():
		var t := str(plan.rooms[ri]["type"])
		if not rt.has(t):
			return {"fail": "no rules for room type %s" % t}
		fz.room(ri, rt[t]["items"])
		_ensure(fz, ri, t)
	if not fz.missing.is_empty():
		return {"fail": "required " + str(fz.missing[0])}
	if level >= 1 and str(spec.get("fire_escape", "")) != "" and not _escape_door(plan, str(spec["fire_escape"]), level):
		return {"fail": "no fire escape door on level %d" % level}
	HouseDoors.windows(plan, rules, rng)
	if not plan.valid():
		return {"fail": "blocked"}
	return {"plan": plan, "units": units, "fz": fz}


static func _cell(s: String, rt: Dictionary) -> Dictionary:
	var front := s.contains("!")
	s = s.replace("!", "")
	var parts := s.split(":")
	var t := parts[0]
	var w := int(parts[1]) if parts.size() > 1 else 0
	if UNIT.has(t):
		var ud: Dictionary = UNIT[t]
		return {"type": t, "area": float(ud["area"]), "min": int(ud["min"]), "width": w, "front": front}
	if not rt.has(t):
		return {}
	var rd: Dictionary = rt[t]
	return {"type": t, "area": float(rd.get("area", 12)), "min": int(rd.get("min_dim", 3)), "width": w, "front": front}


## Expand one apartment cell into rooms: a main room (living + kitchen) on the corridor side, bedroom(s) and a bath behind it.
## Room 0 of the unit is the main room (it gets the door from the corridor and a door to every other room of the unit).
static func _unit(kind: String, rc: Rect2i, fr: BldgFrame, band_a: bool, gid: int, rng: RandomNumberGenerator) -> Dictionary:
	var along_x := fr.axis == "ew"
	var du: int = rc.size.x if along_x else rc.size.y      # width along the corridor
	var dv: int = rc.size.y if along_x else rc.size.x      # depth away from it
	var front_d := clampi(int(round(float(dv) * 0.5)), 3, dv - 3)
	var back_d := dv - front_d
	if back_d < 3 or du < int(UNIT[kind]["min"]):
		return {}
	var out: Array = []
	out.append({"type": "unit_studio_main" if kind == "unit_studio" else "unit_main", "rect": _sub(rc, along_x, band_a, 0, front_d, 0, du), "group": gid, "to_corridor": true, "unit_inner": false})
	var bath_w := 3 if du >= 7 else 2
	var bed_w := du - bath_w
	var bath_first := rng.randf() < 0.5
	var nb := 0
	var g := gid + 1
	if kind == "unit_2br" and bed_w >= 6:
		var half := bed_w / 2
		var w0 := bath_w if bath_first else 0
		out.append({"type": "master", "rect": _sub(rc, along_x, band_a, front_d, back_d, w0, half), "group": g, "to_corridor": false, "unit_inner": true})
		out.append({"type": "bedroom", "rect": _sub(rc, along_x, band_a, front_d, back_d, w0 + half, bed_w - half), "group": g + 1, "to_corridor": false, "unit_inner": true})
		g += 2
		nb = 2
	elif kind != "unit_studio":
		out.append({"type": "bedroom", "rect": _sub(rc, along_x, band_a, front_d, back_d, bath_w if bath_first else 0, bed_w), "group": g, "to_corridor": false, "unit_inner": true})
		g += 1
		nb = 1
	else:
		bath_w = du
		bath_first = true
		bed_w = 0
	if kind == "unit_studio":
		# the bed lives in the main room: the back strip is a bath and a storage nook
		var bw := clampi(du / 2, 2, 3)
		out.append({"type": "bath", "rect": _sub(rc, along_x, band_a, front_d, back_d, 0 if bath_first else du - bw, bw), "group": g, "to_corridor": false, "unit_inner": true})
		out.append({"type": "laundry", "rect": _sub(rc, along_x, band_a, front_d, back_d, bw if bath_first else 0, du - bw), "group": g + 1, "to_corridor": false, "unit_inner": true})
		g += 2
	else:
		out.append({"type": "bath", "rect": _sub(rc, along_x, band_a, front_d, back_d, 0 if bath_first else bed_w, bath_w), "group": g, "to_corridor": false, "unit_inner": true})
		g += 1
	return {"rooms": out, "next": g, "unit": {"kind": kind, "rect": rc, "bedrooms": nb}}


## Cut a band into cells along the corridor: explicit widths stay, the rest share the remaining length by room area (each at least its `min`).
static func _slice(rect: Rect2i, items: Array, along_x: bool, out: Array) -> bool:
	var length: int = rect.size.x if along_x else rect.size.y
	var depth: int = rect.size.y if along_x else rect.size.x
	var fixed := 0
	var floor_sum := 0
	var weights := 0.0
	for it in items:
		if int(it["width"]) > 0:
			fixed += int(it["width"])
		else:
			floor_sum += int(it["min"])
			weights += float(it["area"])
		if depth < (6 if str(it["type"]).begins_with("unit_") else mini(int(it["min"]), 3)):
			return false
	if fixed + floor_sum > length:
		return false
	var free := length - fixed
	var sizes: Array = []
	var given := 0
	var extra := free - floor_sum
	for it in items:
		var s := int(it["width"])
		if s == 0:
			s = int(it["min"]) + (int(floor(float(extra) * float(it["area"]) / weights)) if weights > 0.0 else 0)
		sizes.append(s)
		given += s
	var i := 0
	var guard := 0
	while given < length and guard < 200:
		if int(items[i % items.size()]["width"]) == 0:
			sizes[i % sizes.size()] += 1
			given += 1
		i += 1
		guard += 1
	if given != length:
		return false
	var pos := 0
	for n in items.size():
		var r: Rect2i
		if along_x:
			r = Rect2i(rect.position.x + pos, rect.position.y, sizes[n], rect.size.y)
		else:
			r = Rect2i(rect.position.x, rect.position.y + pos, rect.size.x, sizes[n])
		out.append({"item": items[n], "rect": r})
		pos += int(sizes[n])
	return true


## True when the corridor lies on the high-coordinate side of the band cell `rc`.
static func _corr_high(rc: Rect2i, corr: Rect2i, along_x: bool) -> bool:
	return corr.position.y >= rc.end.y if along_x else corr.position.x >= rc.end.x


## Part of a unit cell: depth range [d0, d0 + dd) away from the corridor, [w0, w0 + ww) along it.
static func _sub(rc: Rect2i, along_x: bool, band_a: bool, d0: int, dd: int, w0: int, ww: int) -> Rect2i:
	# band_a here means: the corridor is on the HIGH side of the cell (depth grows toward low coordinates)
	if along_x:
		var y0: int = (rc.end.y - d0 - dd) if band_a else (rc.position.y + d0)
		return Rect2i(rc.position.x + w0, y0, ww, dd)
	var x0: int = (rc.end.x - d0 - dd) if band_a else (rc.position.x + d0)
	return Rect2i(x0, rc.position.y + w0, dd, ww)


## Door from the floor onto the fire escape balcony: on the outer wall at the landing tile of this level (BldgExport.escape_landing).
static func _escape_door(plan: HousePlan, side: String, level: int) -> bool:
	var lt: Array = BldgExport.escape_landing(plan.shell, side, level)       # [outside tile, inside tile, edge]
	var inside: Vector2i = lt[1]
	var e: Vector3i = lt[2]
	if str(plan.walls.get(e, "")) != "wall" or plan.clear.has(inside) or plan.room_of.get(inside, -1) == -1:
		return false
	plan.add_mount("door", e)
	plan.clear[inside] = true
	plan.must.append(inside)
	return true


## A door on a wall between rects `a` and `b`, away from existing doors and the core. Marks both sides clear + must-reach.
static func _door(plan: HousePlan, a: Rect2i, b: Rect2i, rng: RandomNumberGenerator) -> Array:
	var cands: Array = []
	for y in range(a.position.y, a.end.y):
		for x in range(a.position.x, a.end.x):
			var t := Vector2i(x, y)
			for d in HousePlan.DIRS4:
				var n: Vector2i = t + d
				if b.has_point(n):
					var e := HousePlan.edge(t, n)
					if str(plan.walls.get(e, "")) == "wall" and not HouseDoors._door_near(plan, e):
						cands.append([t, n, e])
	if cands.is_empty():
		return []
	var mid := Vector2((cands[0][0] as Vector2i) + (cands[cands.size() - 1][0] as Vector2i)) * 0.5
	cands.sort_custom(func(p, q): return Vector2(p[0]).distance_to(mid) < Vector2(q[0]).distance_to(mid))
	var pick: Array = cands[mini(cands.size() - 1, rng.randi_range(0, mini(2, cands.size() - 1)))]
	plan.add_mount("door", pick[2])
	for t in [pick[0], pick[1]]:
		plan.clear[t] = true
		if t not in plan.must:
			plan.must.append(t)
	return [pick[0], pick[1]]


## Front door in the south wall of `r` (the room the entrance opens into).
static func _front_door(plan: HousePlan, r: Rect2i, rng: RandomNumberGenerator) -> bool:
	var sh := plan.shell
	var y := sh.end.y - 1
	if r.end.y != sh.end.y:
		return false
	var xs: Array = []
	for x in range(r.position.x + (1 if r.size.x > 3 else 0), r.end.x - (1 if r.size.x > 3 else 0)):
		var t := Vector2i(x, y)
		if not plan.clear.has(t) and not plan.clear.has(t + Vector2i(0, -1)):
			xs.append(x)
	if xs.is_empty():
		return false
	var x: int = xs[(xs.size() - 1) / 2 + (rng.randi_range(0, 1) if xs.size() > 2 else 0)]
	plan.add_mount("door", Vector3i(x, y + 1, 0))
	plan.entry = Vector2i(x, y)
	plan.clear[plan.entry] = true
	plan.must.append(plan.entry)
	return true


## A unit's kitchen run is hard to fit in a small zone: make sure the three basics exist (fridge, stove, sink), placing them one by one.
static func _ensure(fz: HouseFurnish, ri: int, type: String) -> void:
	if type != "unit_main" and type != "unit_studio_main":
		return
	var rect: Rect2i = fz.plan.rooms[ri]["rect"]
	for did in ["fridge", "stove", "sink"]:
		if fz.refs(ri, did).is_empty():
			fz.try_place(ri, did, HouseCands.gen(fz, ri, did, "wall", {}, rect), rect)
	for did in ["fridge", "stove", "sink"]:
		if fz.refs(ri, did).is_empty():
			fz.missing.append("%s in %s" % [did, type])
