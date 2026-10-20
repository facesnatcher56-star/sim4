class_name SleepPlaces
extends RefCounted
## Sleeping places of a household: every move-in makes sure the newcomer has somewhere to lie down (a sofa bed is bought when the
## beds are full, paid through Economy) and autonomy asks "is any bed free?" before somebody sleeps rough on a sofa or the floor.

const EXTRA_BED := "sofa_bed"
const SEARCH_RADIUS := 7
const MAX_BUY := 3

## Lying places (bed slots) the household owns.
static func capacity(hid: int) -> int:
	var n: int = 0
	for o in Economy.objects_of(hid):
		n += _bed_slots(o)
	return n

static func _bed_slots(o) -> int:
	var def: Dictionary = SimEnv.data().object_def(str(o.def_id))
	if not (def.get("tags", []) as Array).has("bed"):
		return 0
	var n: int = 0
	for s in def.get("slots", []):
		if str((s as Dictionary).get("pose", "")) == "lie":
			n += 1
	return n

## Residents who sleep in a bed (babies have a crib).
static func sleepers(hid: int) -> int:
	var n: int = 0
	for f in SysUtil.residents():
		if int(f.household_id) == hid and str(f.age_stage) != "baby":
			n += 1
	return n

## Make room for one more sleeper (called BEFORE the move-in). True = there is a place (maybe new sofa beds); false = no room and no money.
static func make_room(hid: int, who: String, stage: String) -> bool:
	if stage == "baby" or hid <= 0:
		return true
	var w = WorldIface.world()
	if w == null or not w.has_method("can_place") or not w.has_method("place_object"):
		return true                                    # a world that cannot place furniture (test stubs) is not checked
	var need: int = sleepers(hid) + 1 - capacity(hid)
	if need <= 0:
		return true
	var price: int = Economy.price_of_def(EXTRA_BED)
	if need > MAX_BUY or not Economy.can_afford(hid, price * need):
		return false
	var bought: int = 0
	for _i in need:
		var spot: Vector2i = _free_spot(hid, w)
		if spot.x < 0 or Economy.buy_object(hid, EXTRA_BED, spot, 0) < 0:
			break
		bought += 1
	if bought > 0:
		var what: String = "a sofa bed was" if bought == 1 else "%d sofa beds were" % bought
		SysUtil.notify("%s needs a bed: %s added for %d coins." % [who, what, price * bought], "story")
	return bought == need

## A free floor spot near the household's furniture where the new bed can be reached.
static func _free_spot(hid: int, w) -> Vector2i:
	var anchors: Array = []
	var objs: Array = Economy.objects_of(hid)
	for o in objs:
		if _bed_slots(o) > 0:
			anchors.append(o)
	if anchors.is_empty():
		anchors = objs
	for a in anchors:
		for r in range(1, SEARCH_RADIUS + 1):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dy)) != r:
						continue
					var t: Vector2i = a.tile + Vector2i(dx, dy)
					if w.can_place(EXTRA_BED, t, 0, int(a.level)) and _reachable(w, t, a):
						return t
	return Vector2i(-1, -1)

## The standing tile of the new bed (below its left end) must connect to the anchor's neighbourhood.
static func _reachable(w, t: Vector2i, anchor) -> bool:
	var stand: Vector2i = t + Vector2i(0, 1)
	if not w.has_method("is_walkable") or not w.is_walkable(stand):
		return false
	for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var from: Vector2i = anchor.tile + n
		if w.is_walkable(from) and WorldIface.path_length(from, stand) >= 0:
			return true
	return false

## Autonomy test "no_free_bed": no bed within reach has a lying place for this folk.
static func no_free_bed(folk) -> bool:
	for o in WorldIface.objects_for(folk):
		if _bed_slots(o) > 0 and WorldIface.has_free_slot(o, int(folk.id)):
			return false
	return true

## Cond "lacks_object": true at home when no object of any def id in `defs` is within reach of the folk (bare-home fallbacks, task 32d).
static func lacks_any(folk, defs: Variant) -> bool:
	var w = WorldIface.world()
	if w != null and w.get("regions") != null and w.regions.has_regions() and Neighborhood.lot_of_folk(folk) != Neighborhood.HOME:
		return false                    # only inside the player home lot (a park has no toilet either, and nobody orders a snack there)
	var ids: Array = defs if defs is Array else [defs]
	for o in WorldIface.objects_for(folk):
		if str(o.def_id) in ids:
			return false
	return true
