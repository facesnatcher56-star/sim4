class_name DisasterState
extends RefCounted
## Saved state of the natural-disaster layer (task 06). Everything else in disaster_*.gd is stateless.
##   active    town events that are still running: {id, kind, start, end, power, hids:[households hit], phase, due, data:{}}
##   lots      per-lot damage records ("home:<hid>" real, "town:<n>" statistical): {cost, roof, cracks, flood, mould, debris, broken:[ids], events:[{kind, day, text}], repair_day}
##   insurance household id -> "basic" | "full" (absent = none)
##   streak    rain_days / dry_days in a row (feeds the flood and wildfire conditions) + the running counts of today
##   aftermath neighbours still to visit: {hid, day, kind, cost, deaths}
## Hooked into Incidents.reset / to_dict / from_dict (one line each).

const MAX_ACTIVE := 12
const MAX_EVENTS_PER_LOT := 6

static var active: Array = []
static var lots: Dictionary = {}
static var insurance: Dictionary = {}
static var rain_days: int = 0
static var dry_days: int = 0
static var rain_hours_today: int = 0
static var precip_hours_today: int = 0
static var watch_day: Dictionary = {}
static var counts: Dictionary = {}
static var deaths: Array = []              # [{id, name, cause, day}] killed by a disaster, waiting for the shared-grief pass
static var aftermath: Array = []
static var seq: int = 1
## Tests / screenshots: when true a forced tornado plays the siren first instead of hitting at once.
static var siren_when_forced: bool = false

static func reset() -> void:
	active.clear()
	lots.clear()
	insurance.clear()
	rain_days = 0
	dry_days = 0
	rain_hours_today = 0
	precip_hours_today = 0
	watch_day.clear()
	counts.clear()
	deaths.clear()
	aftermath.clear()
	seq = 1
	siren_when_forced = false

static func cfg(key: String = "") -> Dictionary:
	var d: Dictionary = IncidentDefs.cfg("disasters", {})
	return d if key == "" else d.get(key, {})

## The damage record of a lot (created on demand).
static func lot(key: String) -> Dictionary:
	if not lots.has(key):
		lots[key] = {"cost": 0, "roof": 0.0, "cracks": 0.0, "flood": 0.0, "mould": 0.0, "debris": 0, "broken": [], "events": [], "repair_day": -1}
	return lots[key]

static func lot_damaged(key: String) -> bool:
	var r: Dictionary = lots.get(key, {})
	return not r.is_empty() and (int(r["cost"]) > 0 or float(r["mould"]) > 0.0 or int(r["debris"]) > 0)

static func note_lot_event(key: String, kind: String, text: String) -> void:
	var ev: Array = lot(key)["events"]
	ev.append({"kind": kind, "day": SysUtil.day(), "text": text})
	while ev.size() > MAX_EVENTS_PER_LOT:
		ev.pop_front()

# ------------------------------------------------------------------ town events
## Start (or join: same kind rolled in the same minute) a town-level event. Returns its record. `headline` is the one toast + chronicle line.
static func begin(kind: String, minutes: int, power: int = 1, headline: String = "", sev: int = 3, data: Dictionary = {}) -> Dictionary:
	var now: int = SysUtil.now()
	for r in active:
		if str(r["kind"]) == kind and int(r["start"]) == now:
			r["power"] = maxi(int(r["power"]), power)
			return r
	var rec: Dictionary = {"id": seq, "kind": kind, "start": now, "end": now + minutes, "power": power, "hids": [], "phase": "on", "due": -1, "data": data.duplicate(true)}
	seq += 1
	active.append(rec)
	while active.size() > MAX_ACTIVE:
		active.pop_front()
	counts[kind] = int(counts.get(kind, 0)) + 1
	if headline != "":
		SysUtil.notify(headline, "bad" if sev >= 4 else "warn")
		ChronicleHook.note(kind, headline, [], "", sev, true)
	SysUtil.game_event("disaster", {"kind": kind, "phase": "start", "minutes": minutes, "power": power, "folk_id": -1})
	return rec

static func find(kind: String) -> Dictionary:
	for r in active:
		if str(r["kind"]) == kind:
			return r
	return {}

static func running(kind: String) -> bool:
	var now: int = SysUtil.now()
	for r in active:
		if str(r["kind"]) == kind and int(r["end"]) > now:
			return true
	return false

## Does any running event of `kind` include household `hid`?
static func affects(kind: String, hid: int) -> bool:
	var now: int = SysUtil.now()
	for r in active:
		if str(r["kind"]) == kind and int(r["end"]) > now and SysUtil.has_int(r["hids"], hid):
			return true
	return false

## NeighborhoodTravel hook: roads are closed while a blizzard runs.
static func travel_blocked() -> bool:
	return running("blizzard")

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"active": active.duplicate(true), "lots": lots.duplicate(true), "insurance": SysUtil.str_keys(insurance), "rain_days": rain_days, "dry_days": dry_days,
		"rain_hours": rain_hours_today, "precip_hours": precip_hours_today, "watch_day": watch_day.duplicate(), "counts": counts.duplicate(), "deaths": deaths.duplicate(true),
		"aftermath": aftermath.duplicate(true), "seq": seq}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	for r in d.get("active", []):
		var q: Dictionary = (r as Dictionary).duplicate(true)
		SysUtil.ints_in(q, ["id", "start", "end", "power", "due"])
		q["hids"] = SysUtil.to_ints(q.get("hids", []))
		active.append(q)
	var src: Dictionary = d.get("lots", {})
	for k in src:
		var rec: Dictionary = (src[k] as Dictionary).duplicate(true)
		SysUtil.ints_in(rec, ["cost", "debris", "repair_day"])
		rec["broken"] = SysUtil.to_ints(rec.get("broken", []))
		lots[str(k)] = rec
	insurance = SysUtil.int_keys(d.get("insurance", {}))
	rain_days = int(d.get("rain_days", 0))
	dry_days = int(d.get("dry_days", 0))
	rain_hours_today = int(d.get("rain_hours", 0))
	precip_hours_today = int(d.get("precip_hours", 0))
	watch_day = d.get("watch_day", {}).duplicate()
	for k2 in watch_day:
		watch_day[k2] = int(watch_day[k2])
	counts = d.get("counts", {}).duplicate()
	for k3 in counts:
		counts[k3] = int(counts[k3])
	deaths = (d.get("deaths", []) as Array).duplicate(true)
	aftermath = (d.get("aftermath", []) as Array).duplicate(true)
	for a in aftermath:
		SysUtil.ints_in(a, ["hid", "day", "cost"])
	seq = int(d.get("seq", 1))
