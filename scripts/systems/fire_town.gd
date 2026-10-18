class_name FireTown
extends RefCounted
## Far lots and townies. Their houses have no real objects, so each townie lot gets a deterministic list of the things that matter for fire
## (`town_objects` in the Story records: stove, fireplace, smoke alarm, extinguisher, sprinkler ...) from config.fire.town_objects. The incident
## conditions (has_object ...) read it, so a townie with a smoke alarm really is safer. The hidden `holiday_today` marker is kept on the
## townie records so holiday candle fires roll for far lots too. A burnt-out far lot loses some of its things and gets them back after 10 days.

const REBUILD_DAYS := 10

static var _n: int = -1

static func reset() -> void:
	_n = -1

## Cheap (compares the townie count); called every minute by Fire.on_minute.
static func ensure() -> void:
	if Story.townies.size() == _n:
		return
	_n = Story.townies.size()
	for tid in _sorted_ids():
		var rec: Dictionary = Story.townies[tid]
		if bool(rec.get("alive", false)) and int(rec.get("lot", 0)) > 0 and not rec.has("town_objects"):
			rec["town_objects"] = objects_for_lot(int(rec["lot"]))

static func _sorted_ids() -> Array:
	var ids: Array = Story.townies.keys()
	ids.sort()
	return ids

static func objects_for_lot(n: int) -> Array:
	var g := RandomNumberGenerator.new()
	g.seed = n * 7919 + 17
	var table: Dictionary = FireRules.cfg().get("town_objects", {})
	var ids: Array = table.keys()
	ids.sort()
	var out: Array = []
	for id in ids:
		if g.randf() < float(table[id]):
			out.append(str(id))
	return out

static func on_day(day: int) -> void:
	ensure()
	var holiday: bool = not Holidays.today(day).is_empty()
	for tid in _sorted_ids():
		var rec: Dictionary = Story.townies[tid]
		if not bool(rec.get("alive", false)):
			continue
		var buffs: Array = rec.get("buffs", [])
		if holiday and not buffs.has("holiday_today"):
			buffs.append("holiday_today")
		elif not holiday and buffs.has("holiday_today"):
			buffs.erase("holiday_today")
		rec["buffs"] = buffs
		if rec.has("fire_day") and day - int(rec["fire_day"]) >= REBUILD_DAYS:
			rec.erase("fire_day")
			rec["town_objects"] = objects_for_lot(int(rec.get("lot", 0)))

## Statistical fire damage: the lot loses up to `n` of its things (the same ones for everybody who lives there).
static func damage(lot_key: String, n: int) -> void:
	if not lot_key.begins_with("town:"):
		return
	var lot: int = int(lot_key.get_slice(":", 1))
	var recs: Array = []
	var pool: Array = []
	for tid in _sorted_ids():
		var rec: Dictionary = Story.townies[tid]
		if int(rec.get("lot", -1)) == lot:
			recs.append(rec)
			for o in rec.get("town_objects", []):
				if not pool.has(o):
					pool.append(o)
	var gone: Array = []
	for _i in n:
		if pool.is_empty():
			break
		var pick: String = str(pool[Incidents.rng.randi_range(0, pool.size() - 1)])
		pool.erase(pick)
		gone.append(pick)
	for rec2 in recs:
		var objs: Array = rec2.get("town_objects", [])
		for g in gone:
			objs.erase(g)
		rec2["town_objects"] = objs
		rec2["fire_day"] = SysUtil.day()
