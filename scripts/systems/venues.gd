class_name Venues
extends RefCounted
## Venue rules from data/venues.json: opening hours / days, entry fees, crowd targets by time of day, venue buffs
## and per-interaction bonus skill xp. A "venue type" ("park", "cafe", ...) is attached to each lot in
## data/neighborhood.json. Everything is read-only config; runtime state lives in Neighborhood / Crowd.

static func cfg() -> Dictionary:
	return SysUtil.table("venues")

static func type_def(vtype: String) -> Dictionary:
	return (cfg().get("types", {}) as Dictionary).get(vtype, {})

static func type_of_lot(lot_id: String) -> String:
	return str(Neighborhood.lot(lot_id).get("type", "home"))

static func crowd_cap() -> int:
	return int(cfg().get("crowd_cap", 6))

static func label(vtype: String) -> String:
	return str(type_def(vtype).get("label", vtype.capitalize()))

## [open_hour, close_hour]
static func hours(vtype: String) -> Array:
	return type_def(vtype).get("hours", [0, 24])

static func fee(vtype: String) -> int:
	return int(type_def(vtype).get("fee", 0))

static func is_open_type(vtype: String, at_min: int = -1) -> bool:
	if at_min < 0:
		at_min = SimEnv.now_min()
	var td: Dictionary = type_def(vtype)
	if td.is_empty():
		return true
	var day: int = at_min / 1440 + 1
	var h: float = float(at_min % 1440) / 60.0
	var hr: Array = hours(vtype)
	if _open_on(td.get("days", []), SysUtil.weekday(day)) and h >= float(hr[0]) and h < float(hr[1]):
		return true
	return Places.extra_open(vtype, at_min)          # task 14: a place inside the lot (evening classes, a club) keeps it open

## Empty list = every day.
static func _open_on(days: Array, weekday: int) -> bool:
	return days.is_empty() or SysUtil.has_int(days, weekday)

static func is_open(lot_id: String, at_min: int = -1) -> bool:
	return is_open_type(type_of_lot(lot_id), at_min)

## Minutes until closing time today (0 when closed / no closing).
static func minutes_to_close(lot_id: String, at_min: int = -1) -> int:
	if at_min < 0:
		at_min = SimEnv.now_min()
	var vtype := type_of_lot(lot_id)
	if not is_open_type(vtype, at_min):
		return 0
	var hr: Array = hours(vtype)
	if float(hr[1]) >= 24.0 and float(hr[0]) <= 0.0:
		return 100000
	var base: int = int(float(hr[1]) * 60.0) - at_min % 1440
	if base >= 0 and not is_open_type(vtype, at_min + base):
		return base
	for step in range(1, 24 * 4 + 1):          # task 14: a place inside the lot keeps it open past the venue's own hours: look for the real closing time
		if not is_open_type(vtype, at_min + step * 15):
			return step * 15
	return 100000

## Is the lot open for the whole stretch [start, start + span) minutes? A walk that ends at a shut door, or a service that
## would be cut by closing time (half the price back, "left early"), is not worth setting off for.
static func open_for(lot_id: String, start_min: int, span: int = 0) -> bool:
	if not is_open(lot_id, start_min):
		return false
	return span <= 0 or minutes_to_close(lot_id, start_min) >= span

## Human readable status for the UI.
static func status_text(lot_id: String) -> String:
	var vtype := type_of_lot(lot_id)
	var hr: Array = hours(vtype)
	if float(hr[0]) <= 0.0 and float(hr[1]) >= 24.0:
		return "Always open"
	var today_ok: bool = _open_on(type_def(vtype).get("days", []), SysUtil.weekday())
	var h: float = SimEnv.hour_f()
	var span := "%s-%s" % [_hh(float(hr[0])), _hh(float(hr[1]))]
	if not today_ok:
		return "Closed today (%s on weekdays)" % span
	if is_open_type(vtype):
		return "Open until %s" % _hh(float(hr[1]))
	if h < float(hr[0]):
		return "Closed - opens %s" % _hh(float(hr[0]))
	return "Closed - opens tomorrow %s" % _hh(float(hr[0]))

static func _hh(h: float) -> String:
	return "%02d:%02d" % [int(h) % 24 if h < 24.0 else 24, int(round((h - floorf(h)) * 60.0))]

## Target number of ambient NPCs at hour `hour` (step function over [[hour, count], ...]).
static func crowd_target(vtype: String, hour: float) -> int:
	var table: Array = type_def(vtype).get("crowd", [])
	var n: int = 0
	for row in table:
		if hour >= float(row[0]):
			n = int(row[1])
	if not is_open_type(vtype):
		return 0
	return mini(n, crowd_cap())

static func stay_range(vtype: String) -> Array:
	return type_def(vtype).get("stay", [60, 150])

static func ambient(vtype: String) -> Dictionary:
	return type_def(vtype).get("ambient", {})

static func interaction_xp(vtype: String) -> Dictionary:
	return type_def(vtype).get("interaction_xp", {})

## Entry fee for these folk: a pass of a place inside the lot (task 14, the gym pass) waives it for its holder.
static func entry_total(lot_id: String, folk_ids: Array) -> int:
	var per: int = fee(type_of_lot(lot_id))
	if per <= 0:
		return 0
	var n := 0
	for id in folk_ids:
		if not PlaceMember.covers_lot(int(id), lot_id):
			n += 1
	return per * n

## Can these folk (ids) enter lot_id now? -> {ok, reason, fee}. Does not charge.
static func check_entry(lot_id: String, folk_ids: Array, household_id: int = -1) -> Dictionary:
	var closed: String = CityPolicy.blocks_entry(lot_id, folk_ids)       # task 12: park hours and the curfew
	if closed != "":
		return {"ok": false, "reason": closed, "fee": 0}
	var vtype := type_of_lot(lot_id)
	if not is_open_type(vtype):
		return {"ok": false, "reason": "%s is closed. %s." % [str(Neighborhood.lot(lot_id).get("label", lot_id)), status_text(lot_id)], "fee": 0}
	var total: int = entry_total(lot_id, folk_ids)
	if total > 0:
		var hid: int = household_id if household_id > 0 else Economy.primary_household()
		if not Economy.can_afford(hid, total):
			return {"ok": false, "reason": "Entry costs %d coins (you have %d)." % [total, Economy.balance(hid)], "fee": total}
	return {"ok": true, "reason": "", "fee": total}

static func charge_entry(lot_id: String, folk_ids: Array, household_id: int = -1) -> bool:
	var total: int = entry_total(lot_id, folk_ids)
	if total <= 0:
		return true
	var hid: int = household_id if household_id > 0 else Economy.primary_household()
	return Economy.spend(hid, total, "entry: %s" % str(Neighborhood.lot(lot_id).get("label", lot_id)))
