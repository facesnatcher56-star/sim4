class_name DisasterDamage
extends RefCounted
## What a disaster does to the HOME lot, FULL mode (real objects, real folk). Numbers are in config.disasters.damage[kind]
## (arrays indexed by power 1..3). Preparation: shield objects (shutters, sandbags) lower the power by one; the shelter and
## bathroom fixtures keep people safe; insurance pays back part of the loss (claim()).

const PROTECTED := ["mailbox", "debris", "grave", "urn", "door", "window", "generator", "storm_shelter", "storm_shutters", "sandbags", "meteorite", "fishing_spot"]
const MAX_DEBRIS := 6

static func cfg(kind: String) -> Dictionary:
	return (DisasterState.cfg("damage").get(kind, {}) as Dictionary)

static func at(arr: Array, power: int) -> float:
	if arr.is_empty():
		return 0.0
	return float(arr[clampi(power - 1, 0, arr.size() - 1)])

static func objects(hid: int) -> Array:
	var out: Array = Economy.objects_of(hid).duplicate()
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out

static func def_of(o) -> Dictionary:
	return SimEnv.data().object_def(str(o.def_id))

static func tags_of(o) -> Array:
	return def_of(o).get("tags", [])

static func has_object(hid: int, def_id: String) -> bool:
	for o in Economy.objects_of(hid):
		if str(o.def_id) == def_id:
			return true
	return false

static func is_outdoor(o) -> bool:
	var w = WorldIface.world()
	if w != null and w.has_method("is_outdoor"):
		return bool(w.is_outdoor(o.tile, LevelInfo.lv(o)))
	return tags_of(o).has("outdoor")

## Power after the household's preparations (shutters, sandbags ...). 0 = the lot got away with it.
static func effective_power(hid: int, kind: String, power: int) -> int:
	for sid in cfg(kind).get("shield", []):
		if has_object(hid, str(sid)):
			return maxi(power - 1, 0)
	return power

static func _in_scope(o, scope: String) -> bool:
	if PROTECTED.has(str(o.def_id)):
		return false
	var tags: Array = tags_of(o)
	if tags.has("structure") or tags.has("door") or tags.has("window") or tags.has("grave"):
		return false
	var out: bool = is_outdoor(o)
	match scope:
		"outdoor":
			return out
		"plants":
			return out and (tags.has("plant") or tags.has("garden"))
		"floor":
			return not out and not tags.has("ceiling") and (float(def_of(o).get("height", 1.0)) < 1.4 or tags.has("appliance"))
		"furniture":
			return not out and not tags.has("ceiling")
	return false

static func place_debris(tile: Vector2i, hid: int) -> void:
	var rec: Dictionary = DisasterState.lot("home:%d" % hid)
	if int(rec["debris"]) >= MAX_DEBRIS:
		return
	var w = WorldIface.world()
	if w == null or not w.has_method("place_object"):
		return
	if w.has_method("can_place") and not bool(w.can_place("debris", tile, 0)):
		return
	var did: int = int(w.place_object("debris", tile, 0))
	if did >= 0:
		Economy.owner[did] = hid
		rec["debris"] = int(rec["debris"]) + 1

## Remove an object for good (leaves debris). Returns its value.
static func destroy(o, hid: int, leave_debris: bool = true) -> int:
	var value: int = Economy.object_price(o)
	var tile: Vector2i = o.tile
	var oid: int = int(o.id)
	var w = WorldIface.world()
	if w != null and w.has_method("remove_object"):
		w.remove_object(oid)
	Economy.on_object_removed(oid)
	if leave_debris:
		place_debris(tile, hid)
	return value

## Hit the household's objects. Returns {broken:[labels], destroyed:[labels], crops:int, value:int}.
static func strike(hid: int, kind: String, power: int) -> Dictionary:
	var d: Dictionary = cfg(kind)
	var res := {"broken": [], "destroyed": [], "crops": 0, "value": 0}
	var p: float = at(d.get("object_hit", []), power)
	var scope: String = str(d.get("scope", "none"))
	if p <= 0.0 or scope == "none":
		return res
	var rec: Dictionary = DisasterState.lot("home:%d" % hid)
	for o in objects(hid):
		if not _in_scope(o, scope):
			continue
		var pp: float = p * (1.5 if scope == "furniture" and float(def_of(o).get("height", 1.0)) >= 1.4 else 1.0) * LevelDisasters.hit_mult(kind, o)   # floors: flood hits the basement first, quakes the upper floors
		if Incidents.rng.randf() >= pp:
			continue
		var od: Dictionary = def_of(o)
		var label: String = str(od.get("label", o.def_id)).to_lower()
		if str(o.def_id) == "garden_plot":
			WorldIface.state_set(o, "growth", 0.0)
			res["crops"] = int(res["crops"]) + 1
		elif (od.get("state", {}) as Dictionary).has("broken") and Incidents.rng.randf() < 0.7:
			WorldIface.state_set(o, "broken", true)
			(res["broken"] as Array).append(label)
			if not (rec["broken"] as Array).has(int(o.id)):
				(rec["broken"] as Array).append(int(o.id))
		elif Incidents.rng.randf() < float(d.get("destroy_share", 1.0)):
			res["value"] = int(res["value"]) + destroy(o, hid)
			(res["destroyed"] as Array).append(label)
	return res

## Structural damage (roof, cracks, flooded floors) and its repair cost. Returns the cost added.
static func structure(hid: int, kind: String, power: int) -> int:
	var d: Dictionary = cfg(kind)
	var rec: Dictionary = DisasterState.lot("home:%d" % hid)
	for part in ["roof", "cracks", "flood"]:
		if d.has(part):
			rec[part] = minf(1.0, float(rec[part]) + at(d[part], power))
	var cost: int = int(at(d.get("cost", []), power))
	rec["cost"] = int(rec["cost"]) + cost
	return cost

# ------------------------------------------------------------------ people
static func folk_on_lot(hid: int) -> Array:
	var out: Array = []
	for f in WorldIface.all_folk():
		if SysUtil.is_away(f) or Hospital.is_in(f):
			continue
		if int(f.household_id) == hid or (hid == Economy.primary_household() and f.has_meta("visitor")):
			out.append(f)
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out

## "cover" (hiding in the shelter / next to a bathroom fixture), "out" (outside) or "in" (indoors, unprotected).
static func exposure(f, hid: int) -> String:
	if f.current != null and str(f.current.def_id) == "take_cover":
		return "cover"
	if WeatherFolk.is_outside(f):
		return "out"
	if LevelDisasters.in_basement(f):
		return "cover"                                      # the basement / storm-shelter room
	for o in objects(hid):
		if (tags_of(o).has("bathroom") or str(o.def_id) == "storm_shelter") and LevelInfo.lv(o) == LevelInfo.lv(f) and LevelInfo.lv(f) <= 0 				and absi(o.tile.x - f.tile.x) + absi(o.tile.y - f.tile.y) <= 2:
			return "cover"
	return "in"

## Roll injuries and (rarely) deaths for everybody on the home lot. Returns {injured:[names], dead:[names], safe:int}.
static func hurt_people(hid: int, kind: String, power: int) -> Dictionary:
	var d: Dictionary = cfg(kind)
	var res := {"injured": [], "dead": [], "safe": 0}
	if power <= 0:
		return res
	for f in folk_on_lot(hid):
		var ex: String = exposure(f, hid)
		var hurt: float = at(d.get("cover_hurt" if ex == "cover" else ("out_hurt" if ex == "out" else "in_hurt"), []), power) * (LevelDisasters.folk_mult(kind, f) if ex == "in" else 1.0)
		var kill: float = 0.0 if ex == "cover" else at(d.get("out_kill" if ex == "out" else "in_kill", []), power)
		var nm: String = str(f.name)
		if kill > 0.0 and Incidents.rng.randf() < kill:
			Aging.kill(int(f.id), str(d.get("cause", "tornado")))
			DisasterState.deaths.append({"id": int(f.id), "name": nm, "cause": str(d.get("cause", "")), "day": SysUtil.day()})
			(res["dead"] as Array).append(nm)
		elif hurt > 0.0 and Incidents.rng.randf() < hurt:
			Hospital.injure(f, 2 if power >= 2 else 1, str(d.get("reason", "the storm")))
			f.add_buff("storm_shaken")
			(res["injured"] as Array).append(nm)
		else:
			res["safe"] = int(res["safe"]) + 1
			if power >= 2 and ex != "cover":
				f.add_buff("storm_shaken")
	return res

# ------------------------------------------------------------------ money
## Insurance pays its share of `loss` now. Returns the coins paid (0 without a policy).
static func claim(hid: int, loss: int) -> int:
	DisasterInsurance.ensure()
	var paid: int = Incidents.insurance_cover(loss, hid)
	if paid > 0:
		Economy.deposit(hid, paid, "insurance payout")
	return paid

## "a rug, a lamp and 2 chairs": a short readable list.
static func list_text(labels: Array) -> String:
	if labels.is_empty():
		return ""
	var counts: Dictionary = {}
	for l in labels:
		counts[l] = int(counts.get(l, 0)) + 1
	var parts: Array = []
	var keys: Array = counts.keys()
	keys.sort()
	for k in keys:
		parts.append(("%d x %s" % [int(counts[k]), k]) if int(counts[k]) > 1 else str(k))
	if parts.size() > 3:
		return "%s and %d other things" % [", ".join(parts.slice(0, 2)), parts.size() - 2]
	return " and ".join(parts) if parts.size() <= 2 else "%s and %s" % [", ".join(parts.slice(0, parts.size() - 1)), parts[parts.size() - 1]]