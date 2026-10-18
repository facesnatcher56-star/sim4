class_name BusinessState
extends RefCounted
## Businesses (task 13, slice 3): the records. A business is a data entry on a SLOT of an existing commercial lot (cafe, market, gym, library,
## office): the lot keeps its venue and crowd, the business adds a counter run by a player household or a townie. All of them run the same
## STATISTICAL daily model (BusinessSim), whether the owner is near or far. Data: data/businesses.json.
## Tier: town-wide, DAILY. Active set: open businesses (<= sum of slots = 10). Caps: reviews 8, history 7 days.

static var list: Dictionary = {}        # id -> business dict (see make())
static var _seq: int = 1
static var closed_log: Array = []       # [{day, name, type, why, owner_kind}] last 12 (news)

static func reset() -> void:
	list.clear()
	closed_log.clear()
	_seq = 1

static func cfg() -> Dictionary:
	return SysUtil.table("businesses")

static func type_def(t: String) -> Dictionary:
	return (cfg().get("types", {}) as Dictionary).get(t, {})

static func type_ids() -> Array:
	var ids: Array = (cfg().get("types", {}) as Dictionary).keys()
	ids.sort()
	return ids

static func slots_of(lot: String) -> int:
	return int((cfg().get("slots", {}) as Dictionary).get(lot, 0))

static func used_slots(lot: String) -> int:
	var n: int = 0
	for id in list:
		if str(list[id]["lot"]) == lot:
			n += 1
	return n

static func free_slots(lot: String) -> int:
	return slots_of(lot) - used_slots(lot)

## Lots where this type may open and a slot is free.
static func open_lots_for(t: String) -> Array:
	var out: Array = []
	for lot in type_def(t).get("lots", []):
		if free_slots(str(lot)) > 0:
			out.append(str(lot))
	return out

static func make(t: String, lot: String, mode: String, owner_kind: String, owner: int, nm: String) -> Dictionary:
	var td: Dictionary = type_def(t)
	var hrs: Array = td.get("hours", [9, 18])
	var b: Dictionary = {"id": _seq, "name": nm, "type": t, "lot": lot, "mode": mode, "owner_kind": owner_kind, "owner": owner,
		"founded": SysUtil.day(), "open": true, "level": 1, "price": 1.0, "hours": [int(hrs[0]), int(hrs[1])], "staff": [],
		"stock": 0, "auto_stock": true, "rep": 50.0, "cash": 0.0, "stars": 3.5, "reviews": [], "hist": [], "profit_total": 0.0,
		"auto_sweep": true, "neg_days": 0, "last": {}, "closed_day": -1, "owner_skill": 3.0, "lot_paid": mode == "own"}
	_seq += 1
	list[int(b["id"])] = b
	return b

static func get_biz(id: int) -> Dictionary:
	return list.get(id, {})

static func of_owner(kind: String, owner: int) -> Array:
	var out: Array = []
	for id in list:
		var b: Dictionary = list[id]
		if str(b["owner_kind"]) == kind and int(b["owner"]) == owner:
			out.append(b)
	return out

static func ids_sorted() -> Array:
	var ids: Array = list.keys()
	ids.sort()
	return ids

static func stock_cap(b: Dictionary) -> int:
	return int(cfg().get("stock", {}).get("cap_per_level", 120)) * int(b["level"])

static func close(b: Dictionary, why: String) -> void:
	list.erase(int(b["id"]))
	closed_log.append({"day": SysUtil.day(), "name": str(b["name"]), "type": str(b["type"]), "why": why, "owner_kind": str(b["owner_kind"])})
	while closed_log.size() > 12:
		closed_log.pop_front()
	for s in b["staff"]:
		var t: Dictionary = Story.townies.get(int(s["tid"]), {})
		if not t.is_empty():
			t.erase("job_biz")
	if str(b["owner_kind"]) == "townie":
		var o: Dictionary = Story.townies.get(int(b["owner"]), {})
		if not o.is_empty():
			o.erase("owner_biz")

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"list": SysUtil.str_keys(list).duplicate(true), "seq": _seq, "closed_log": closed_log.duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	list = SysUtil.int_keys((d.get("list", {}) as Dictionary).duplicate(true))
	for id in list:
		var b: Dictionary = list[id]
		SysUtil.ints_in(b, ["id", "owner", "founded", "level", "stock", "neg_days", "closed_day"])
		for k in ["price", "rep", "cash", "stars", "profit_total", "owner_skill"]:
			b[k] = float(b[k])
		b["hours"] = SysUtil.to_ints(b["hours"])
		for s in b["staff"]:
			SysUtil.ints_in(s, ["tid", "wage", "skill"])
	_seq = int(d.get("seq", 1))
	closed_log = (d.get("closed_log", []) as Array).duplicate(true)
