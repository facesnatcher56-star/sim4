class_name HouseCands
extends RefCounted
## Candidate generators for HouseFurnish: each returns [[score, tile, rot], ...] for one object def inside `rect`.
## at = wall | corner | free | island | grid | path | facing | front | near | beside | seat | rug | ceil

static func fits(rect: Rect2i, fp: Array) -> bool:
	for t in fp:
		if not rect.has_point(t):
			return false
	return true


static func gen(fz: HouseFurnish, ri: int, did: String, at: String, it: Dictionary, rect: Rect2i) -> Array:
	match at:
		"wall", "corner", "free":
			return scan(fz, rect, did, at, it)
		"island":
			return island(fz, rect, did)
		"grid":
			return grid(fz, rect, did, it)
		"path":
			return along_path(fz, rect, did)
		"facing", "front":
			return front(fz, ri, did, it)
		"near":
			return near(fz, ri, did, it)
		"beside":
			return beside(fz, ri, did, it)
		"seat":
			return seat(fz, ri, did, it)
		"rug":
			return rug(fz, ri, did, it, rect)
		"ceil":
			return ceil_piece(fz, ri, did, it, rect)
	return []


static func center(fp: Array) -> Vector2:
	var c := Vector2.ZERO
	for t in fp:
		c += Vector2(t)
	return c / float(fp.size())


## Free tiles around the footprint (Chebyshev `gap`) so pieces do not touch (tables in a cafe).
static func gap_ok(plan: HousePlan, fp: Array, gap: int) -> bool:
	for t in fp:
		for dx in range(-gap, gap + 1):
			for dy in range(-gap, gap + 1):
				var n: Vector2i = t + Vector2i(dx, dy)
				if n not in fp and plan.occ.has(n):
					return false
	return true


static func scan(fz: HouseFurnish, rect: Rect2i, did: String, at: String, it: Dictionary) -> Array:
	var plan := fz.plan
	var d := HousePlan.def_of(did)
	var pref := str(it.get("pref", ""))
	var gap := int(it.get("gap", 0))
	var out: Array = []
	var mid := Vector2(rect.position) + Vector2(rect.size) * 0.5
	for rot in 4:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var t := Vector2i(x, y)
				var fp := HousePlan.footprint(d, t, rot)
				if not fits(rect, fp):
					continue
				var s := fz.rng.randf()
				match at:
					"wall":
						if not plan.back_to_wall(fp, rot):
							continue
						if pref == "corner" and plan.wall_sides(fp) >= 2:
							s += 2.0
					"corner":
						if not plan.back_to_wall(fp, rot) or plan.wall_sides(fp) < 2:
							continue
					"free":
						if plan.wall_sides(fp) > 0 or (gap > 0 and not gap_ok(plan, fp, gap)):
							continue
						if pref != "spread":
							s -= (Vector2(t) - mid).length() * 0.25
				out.append([s, t, rot])
	return out


## Lattice placement (venues): objects on a regular grid inside the rect, facing `rot`.
static func grid(fz: HouseFurnish, rect: Rect2i, did: String, it: Dictionary) -> Array:
	var d := HousePlan.def_of(did)
	var step: Array = it.get("step", [2, 3])
	var off: Array = it.get("off", [1, 1])
	var rot := int(it.get("rot", 0))
	var out: Array = []
	var y: int = rect.position.y + int(off[1])
	while y < rect.end.y:
		var x: int = rect.position.x + int(off[0])
		while x < rect.end.x:
			if fits(rect, HousePlan.footprint(d, Vector2i(x, y), rot)):
				out.append([fz.rng.randf(), Vector2i(x, y), rot])
			x += int(step[0])
		y += int(step[1])
	return out


## One tile away from a wall, leaving a walkway behind (staff side of a counter).
static func island(fz: HouseFurnish, rect: Rect2i, did: String) -> Array:
	var plan := fz.plan
	var d := HousePlan.def_of(did)
	var out: Array = []
	for rot in 4:
		var back: Vector2i = -HousePlan.FRONT[rot]
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var t := Vector2i(x, y)
				var fp := HousePlan.footprint(d, t, rot)
				if not fits(rect, fp):
					continue
				var sh: Array = []
				for f in fp:
					sh.append(f + back)
				if not fits(rect, sh) or not plan.back_to_wall(sh, rot):
					continue
				var free := true
				for f in sh:
					if plan.occ.has(f) or plan.clear.has(f):
						free = false
				if free:
					out.append([fz.rng.randf(), t, rot])
	return out


## Next to a path tile, turned towards it (park benches).
static func along_path(fz: HouseFurnish, rect: Rect2i, did: String) -> Array:
	var plan := fz.plan
	var d := HousePlan.def_of(did)
	var out: Array = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var t := Vector2i(x, y)
			if plan.paths.has(t):
				continue
			for dir in HousePlan.DIRS4:
				if plan.paths.has(t + dir):
					var rot := HousePlan.FRONT.find(dir)
					if fits(rect, HousePlan.footprint(d, t, rot)):
						out.append([fz.rng.randf(), t, rot])
	return out


## Opposite a reference object, `dist` tiles along its front (sofa facing the tv, coffee table in front of the sofa).
static func front(fz: HouseFurnish, ri: int, did: String, it: Dictionary) -> Array:
	var plan := fz.plan
	var ref := fz.ref(ri, str(it.get("ref", "")))
	if ref < 0:
		return []
	var ro: Dictionary = plan.objects[ref]
	var f: Vector2i = HousePlan.FRONT[int(ro["rot"])]
	var perp := Vector2i(-f.y, f.x)
	var d := HousePlan.def_of(did)
	var rot := (int(ro["rot"]) + 2) % 4
	var dist: Array = it.get("dist", [2, 2])
	var rc := center(plan.fp_of(ref))
	var out: Array = []
	for dd in range(int(dist[0]), int(dist[1]) + 1):
		for lat in range(-2, 3):
			var t: Vector2i = (ro["tile"] as Vector2i) + f * dd + perp * lat
			var diff := absf((center(HousePlan.footprint(d, t, rot)) - rc).dot(Vector2(perp)))
			out.append([fz.rng.randf() * 0.3 - diff * 0.7 - float(dd) * 0.05, t, rot])
	return out


## Within 2 tiles of the reference, turned towards it (armchair beside the coffee table).
static func near(fz: HouseFurnish, ri: int, did: String, it: Dictionary) -> Array:
	var ref := fz.ref(ri, str(it.get("ref", "")))
	if ref < 0:
		return []
	var rfp := fz.plan.fp_of(ref)
	var out: Array = []
	for t0 in rfp:
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var t: Vector2i = t0 + Vector2i(dx, dy)
				if t in rfp:
					continue
				var best := 99
				var bt := t0
				for r in rfp:
					var m := absi(r.x - t.x) + absi(r.y - t.y)
					if m < best:
						best = m
						bt = r
				var dv: Vector2i = bt - t
				var dir := Vector2i(signi(dv.x), 0) if absi(dv.x) > absi(dv.y) else Vector2i(0, signi(dv.y))
				if dir != Vector2i.ZERO:
					out.append([fz.rng.randf() - float(best) * 0.4, t, HousePlan.FRONT.find(dir)])
	return out


## Next to the reference with the same orientation (nightstand at the head of the bed, counter after counter).
static func beside(fz: HouseFurnish, ri: int, did: String, it: Dictionary) -> Array:
	var plan := fz.plan
	var ref := fz.ref(ri, str(it.get("ref", "")))
	if ref < 0:
		return []
	var rot := int(plan.objects[ref]["rot"])
	var d := HousePlan.def_of(did)
	var rfp := plan.fp_of(ref)
	var f: Vector2i = HousePlan.FRONT[rot]
	var need_wall := bool(it.get("wall", true))
	var out: Array = []
	for dir in [Vector2i(-f.y, f.x), Vector2i(f.y, -f.x)]:
		for t0 in rfp:
			for k in range(1, 3):           # two-tile pieces anchor up to two tiles away on the far side
				var t: Vector2i = t0 + dir * k
				if t in rfp:
					continue
				if not need_wall or plan.back_to_wall(HousePlan.footprint(d, t, rot), rot):
					out.append([fz.rng.randf(), t, rot])
	return out


## Seats on the free tiles around tables / counters, facing them (slot side first). "all": around every matching piece.
static func seat(fz: HouseFurnish, ri: int, did: String, it: Dictionary) -> Array:
	var plan := fz.plan
	var refs: Array = fz.refs(ri, str(it.get("ref", "")))
	if refs.is_empty():
		return []
	if not bool(it.get("all", false)):
		refs = [refs[refs.size() - 1]]
	var out: Array = []
	for ref in refs:
		var ro: Dictionary = plan.objects[ref]
		var rfp := plan.fp_of(ref)
		var slots := HousePlan.slot_tiles(HousePlan.def_of(str(ro["def"])), ro["tile"], int(ro["rot"]))
		for t0 in rfp:
			for dir in HousePlan.DIRS4:
				var t: Vector2i = t0 + dir
				if t in rfp or plan.blocked_edge(t0, t) or (bool(it.get("slots", false)) and t not in slots):
					continue
				out.append([fz.rng.randf() * 0.5 + (1.0 if t in slots else 0.0), t, HousePlan.FRONT.find(-dir)])
	return out


## Rug covering as much as possible of the reference object (or the room centre).
static func rug(fz: HouseFurnish, ri: int, did: String, it: Dictionary, rect: Rect2i) -> Array:
	var plan := fz.plan
	var d := HousePlan.def_of(did)
	var target: Array = []
	var ref := fz.ref(ri, str(it.get("ref", ""))) if it.has("ref") else -1
	if ref >= 0:
		for t in plan.fp_of(ref):
			for dir in HousePlan.DIRS4 + [Vector2i.ZERO]:
				target.append(t + dir)
	else:
		var c := Vector2i(rect.position + rect.size / 2)
		target = [c, c + Vector2i(-1, -1), c + Vector2i(-1, 0), c + Vector2i(0, -1)]
	var out: Array = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var t := Vector2i(x, y)
			var fp := HousePlan.footprint(d, t, 0)
			if not fits(rect, fp):
				continue
			var ov := 0
			for f in fp:
				if f in target:
					ov += 1
			if ov > 0:
				out.append([float(ov) + fz.rng.randf() * 0.5, t, 0])
	return out


## Ceiling pieces: a light over the table / room centre, an alarm near a doorway.
static func ceil_piece(fz: HouseFurnish, ri: int, did: String, it: Dictionary, rect: Rect2i) -> Array:
	var plan := fz.plan
	var target := Vector2(rect.position) + Vector2(rect.size - Vector2i.ONE) * 0.5
	var ref := fz.ref(ri, str(it.get("ref", ""))) if it.has("ref") else -1
	if ref >= 0:
		target = center(plan.fp_of(ref))
	elif did == "smoke_alarm":
		for t in plan.clear:
			if rect.has_point(t):
				target = Vector2(t)
				break
	var out: Array = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			out.append([fz.rng.randf() * 0.6 - (Vector2(x, y) - target).length(), Vector2i(x, y), 0])
	return out
