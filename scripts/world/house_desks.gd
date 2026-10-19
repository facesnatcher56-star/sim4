class_name HouseDesks
extends RefCounted
## Every desk, computer and terminal of a generated home gets a chair on its use tile (the view sits the folk down on it:
## typing, writing and homework are seated). No rng draws, so the rest of the layout does not shift.

const TYPES := ["desk", "computer", "terminal"]


## Desk-like objects in the plan.
static func count(plan: HousePlan) -> int:
	var n := 0
	for o in plan.objects:
		if str(o["def"]) in TYPES:
			n += 1
	return n


## Places a chair on the first free use tile of each desk-like object. Returns how many were added.
static func add_chairs(plan: HousePlan, fz: HouseFurnish) -> int:
	var added := 0
	for i in plan.objects.size():
		var o: Dictionary = plan.objects[i]
		if not (str(o["def"]) in TYPES):
			continue
		var d := HousePlan.def_of(str(o["def"]))
		var fp := plan.fp_of(i)
		var ri: int = int(plan.room_of.get(fp[0], -1))
		if ri < 0:
			continue
		var rect: Rect2i = plan.rooms[ri]["rect"]
		var cands: Array = []
		for s in HousePlan.slot_tiles(d, o["tile"], int(o["rot"])):
			if s in fp or plan.occ.has(s):
				continue
			for t0 in fp:
				var dir: Vector2i = s - t0
				if absi(dir.x) + absi(dir.y) == 1:
					cands.append([1.0, s, HousePlan.FRONT.find(-dir)])
					break
		for c in cands:
			if c[1] == plan.entry or c[1] in plan.must or not plan.can_put("chair", c[1], c[2], rect, true):          # a use tile on a walkway is fine as long as every room stays reachable
				continue
			var idx := plan.put("chair", c[1], c[2])
			if not plan.valid():
				plan.pop()
				continue
			fz._record(ri, "chair", idx)
			added += 1
			break
	return added
