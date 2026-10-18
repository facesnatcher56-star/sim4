class_name HouseFurnish
extends RefCounted
## Furnishes the rooms of a HousePlan from item lists (data/house_rules.json). Every placement is checked with
## HousePlan.valid() (doors and slots stay reachable), so a layout can never trap the player behind furniture.
## Item keys: d, at, ref, n, p, dist, pref, gap, wall, all, req, deep (min room thickness), big (min room area),
## rep + items (repeat a group), run (list of def sequences along one wall), rows (def in rows) + len / n_rows / step_y / rot.

var plan: HousePlan
var rng: RandomNumberGenerator
var placed: Dictionary = {}        # room index -> {def: [object index]}
var missing: Array = []            # required items that did not fit
var behind: Array = []             # tiles behind island counters (staff posts)


func _init(p: HousePlan, g: RandomNumberGenerator) -> void:
	plan = p
	rng = g


func room(ri: int, items: Array) -> void:
	var r: Rect2i = plan.rooms[ri]["rect"]
	var thick := mini(r.size.x, r.size.y)
	for it in items:
		_item(ri, it, thick)


func _count(v: Variant) -> int:
	if v is Array:
		return rng.randi_range(int(v[0]), int(v[1]))
	return int(v)


func _item(ri: int, it: Dictionary, thick: int) -> void:
	if it.has("deep") and thick < int(it["deep"]):
		return
	if it.has("big") and (plan.rooms[ri]["rect"] as Rect2i).get_area() < int(it["big"]):
		return
	if it.has("p") and rng.randf() > float(it["p"]):
		return
	if it.has("rep"):
		for k in _count(it["rep"]):
			for sub in it["items"]:
				_item(ri, sub, thick)
		return
	if it.has("run"):
		if not _run(ri, it["run"]) and it.has("req"):
			missing.append("run:%s" % str(plan.rooms[ri]["type"]))
		return
	if it.has("rows"):
		_rows(ri, it)
		return
	for k in _count(it.get("n", 1)):
		if not _one(ri, it):
			if it.has("req") and k == 0:
				missing.append("%s in %s" % [str(it["d"]), str(plan.rooms[ri]["type"])])
			break


func _pick(v: Variant) -> String:
	if v is Array:
		return str(v[rng.randi_range(0, v.size() - 1)])
	return str(v)


func _one(ri: int, it: Dictionary) -> bool:
	var did := _pick(it["d"])
	var ats: Array = []
	if it.get("at", "wall") is Array:
		ats = (it["at"] as Array).duplicate()
		HouseRooms._shuffle(ats, rng)
	else:
		ats = [str(it.get("at", "wall"))]
	var rect: Rect2i = plan.rooms[ri]["rect"]
	for at in ats:
		if try_place(ri, did, HouseCands.gen(self, ri, did, str(at), it, rect), rect):
			if str(at) == "island":
				_note_behind(plan.objects.size() - 1)
			return true
	return false


func _note_behind(idx: int) -> void:
	var o: Dictionary = plan.objects[idx]
	var back: Vector2i = -HousePlan.FRONT[int(o["rot"])]
	for t in plan.fp_of(idx):
		if (t + back) not in plan.fp_of(idx):
			behind.append(t + back)


## Put the best candidate [score, tile, rot] that fits `rect` and keeps the plan valid. `ri` keys the placed-registry.
func try_place(ri: int, did: String, cands: Array, rect: Rect2i) -> bool:
	cands.sort_custom(func(a, b): return a[0] > b[0])
	var fl := HousePlan.is_floor_layer(HousePlan.def_of(did))
	var tries := 0
	for c in cands:
		tries += 1
		if tries > 30:
			break
		if not plan.can_put(did, c[1], c[2], rect):
			continue
		var idx := plan.put(did, c[1], c[2])
		if not fl and not plan.valid():
			plan.pop()
			continue
		_record(ri, did, idx)
		return true
	return false


func _record(ri: int, did: String, idx: int) -> void:
	if not placed.has(ri):
		placed[ri] = {}
	if not (placed[ri] as Dictionary).has(did):
		placed[ri][did] = []
	placed[ri][did].append(idx)


## All placed objects (indices, oldest first) of any def in the "a|b" list in this room.
func refs(ri: int, spec: String) -> Array:
	var out: Array = []
	for dn in spec.split("|"):
		out.append_array((placed.get(ri, {}) as Dictionary).get(dn, []))
	out.sort()
	return out


## Latest placed object of the "a|b" list in this room; -1 when none.
func ref(ri: int, spec: String) -> int:
	var r := refs(ri, spec)
	return -1 if r.is_empty() else int(r[r.size() - 1])


## A straight run of different pieces against one wall (kitchen units, bathroom fittings).
func _run(ri: int, variants: Array) -> bool:
	var rect: Rect2i = plan.rooms[ri]["rect"]
	var vs: Array = variants.duplicate()
	HouseRooms._shuffle(vs, rng)
	if rng.randf() < 0.7:
		vs.sort_custom(func(a, b): return a.size() > b.size())
	for v in vs:
		var seq: Array = (v as Array).duplicate()
		if rng.randf() < 0.5:
			seq.reverse()
		var starts: Array = []
		for rot in 4:
			var along := Vector2i(1, 0) if rot % 2 == 0 else Vector2i(0, 1)
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					starts.append([rot, Vector2i(x, y), along])
		HouseRooms._shuffle(starts, rng)
		for s in starts:
			if _try_run(ri, rect, seq, s[0], s[1], s[2]):
				return true
	return false


func _try_run(ri: int, rect: Rect2i, seq: Array, rot: int, start: Vector2i, along: Vector2i) -> bool:
	var cursor := 0                  # next free position along the run, relative to `start`
	var n := 0
	for k in seq.size():
		var did := str(seq[k])
		var d := HousePlan.def_of(did)
		var fp0 := HousePlan.footprint(d, Vector2i.ZERO, rot)
		var lo := 99
		var hi := -99
		for f in fp0:
			lo = mini(lo, f.x * along.x + f.y * along.y)
			hi = maxi(hi, f.x * along.x + f.y * along.y)
		var t: Vector2i = start + along * (cursor - lo)
		var fp := HousePlan.footprint(d, t, rot)
		if HouseCands.fits(rect, fp) and plan.back_to_wall(fp, rot) and plan.can_put(did, t, rot, rect):
			_record(ri, did, plan.put(did, t, rot))
			n += 1
			cursor += hi - lo + 1
			continue
		_undo(ri, n)
		return false
	if plan.valid():
		return true
	_undo(ri, n)
	return false


func _undo(ri: int, n: int) -> void:
	for k in n:
		var o: Dictionary = plan.objects[plan.objects.size() - 1]
		(placed[ri][str(o["def"])] as Array).pop_back()
		plan.pop()


## Rows of one def with aisles between them (library shelves, school desks, market coolers, office pods).
func _rows(ri: int, it: Dictionary) -> void:
	var rect: Rect2i = plan.rooms[ri]["rect"]
	var did := str(it["rows"])
	var rot := int(it.get("rot", 0))
	var off: Array = it.get("off", [1, 1])
	var sy := int(it.get("step_y", 3))
	var ys: Array = []
	var y: int = rect.position.y + int(off[1])
	while y < rect.end.y:
		ys.append(y)
		y += sy
	HouseRooms._shuffle(ys, rng)
	for j in mini(ys.size(), _count(it.get("n_rows", 2))):
		var n := _count(it.get("len", [3, 5]))
		var x0 := rng.randi_range(rect.position.x + int(off[0]), maxi(rect.position.x + int(off[0]), rect.end.x - n))
		for i in n:
			if not try_place(ri, did, [[1.0, Vector2i(x0 + i, ys[j]), rot]], rect):
				break
