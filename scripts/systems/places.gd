class_name Places
extends RefCounted
## The places of the town (task 14): data/life/*.json section "places". A place is a named, staffed, timed service point INSIDE one of the map's
## lots (the map has no free slot left, so a clinic, a bakery or a cinema is a wing of an existing building: `lot` is the host). Each place has
## opening hours, a staff roster (PlaceStaff: townies with matching jobs first, locals otherwise), prices and services (PlaceUse).
##
## Schema of a place: label, lot, kind, blurb, hours [open, close] (+ days [weekdays]) or schedule [{days, hours}] (close may pass 24 = after
## midnight), staff [{role, career, n}], min_staff (open needs this many on the roster, default 1; 0 = self-service), services {id: service}.
## Schema of a service: label, price, minutes, stages [..] | adult_only | min_stage, needs {need: +n}, buffs [..], skill_xp {skill: xp},
## handler + args (code for the special ones), once_per_day, text, note. See docs/LIFE.md.

static func all() -> Dictionary:
	return LifeDefs.section("places")

static func def(pid: String) -> Dictionary:
	return all().get(pid, {})

static func exists(pid: String) -> bool:
	return all().has(pid)

static func label(pid: String) -> String:
	return str(def(pid).get("label", pid.capitalize()))

static func lot_of(pid: String) -> String:
	return str(def(pid).get("lot", ""))

static func kind_of(pid: String) -> String:
	return str(def(pid).get("kind", ""))

## Is this place something this person could actually use? A home entry needs the thing in the home (a TV, a stereo, a pet); everything else is always there.
static func usable_by(pid: String, f) -> bool:
	var need: Dictionary = def(pid).get("needs_home", {})
	if need.is_empty() or f == null:
		return true
	var home: String = PlayerLots.home_of(f)
	var rc: Rect2i = NeighborhoodLots.rect_of(home)
	if bool(need.get("pet", false)) and PetState.of_household(int(f.household_id)).is_empty():
		return false
	var objs: Array = need.get("objects", [])
	if not objs.is_empty():
		var found: bool = false
		for o in WorldIface.objects_near(rc.get_center(), 80):
			if rc.has_point(o.tile) and objs.has(str(o.def_id)):
				found = true
				break
		if not found:
			return false
	return true

static func ids_of_kind(kind: String) -> Array:
	var out: Array = []
	for pid in all():
		if kind == "" or kind_of(pid) == kind:
			out.append(pid)
	out.sort()
	return out

static func services(pid: String) -> Dictionary:
	return def(pid).get("services", {})

## {place, id, def} of a service id (ids are unique across the town).
static func find_service(sid: String) -> Dictionary:
	for pid in all():
		var s: Dictionary = services(pid)
		if s.has(sid):
			return {"place": pid, "id": sid, "def": s[sid]}
	return {}

# ------------------------------------------------------------------ hours
static func schedule(pid: String) -> Array:
	var d: Dictionary = def(pid)
	if d.has("schedule"):
		return d["schedule"]
	return [{"days": d.get("days", []), "hours": d.get("hours", [0, 24])}]

static func _day_ok(days: Array, wd: int) -> bool:
	return days.is_empty() or SysUtil.has_int(days, wd)

static var _hol_day: int = -1
static var _hol_id: String = ""

## The holiday id on this day ("" = none).
static func _holiday_on(day: int) -> String:
	if day != _hol_day:
		_hol_day = day
		_hol_id = str(Holidays.today(day).get("id", ""))
	return _hol_id

## Does this schedule row apply on game day `day`? Weekdays (`days`), days of the year (`doy`, the block party) and holidays (`holiday`, the parade).
static func _row_day_ok(row: Dictionary, day: int) -> bool:
	if row.has("doy") and not SysUtil.has_int(row["doy"], Aging.doy(day)):
		return false
	var hol: Variant = row.get("holiday", false)
	if hol is String or hol is Array:
		if _holiday_on(day) == "" or (hol is String and _holiday_on(day) != hol) or (hol is Array and not (hol as Array).has(_holiday_on(day))):
			return false         # a named holiday (or a few): the parade is once a year, not at every festival
	elif bool(hol) and _holiday_on(day) == "":
		return false
	return _day_ok(row.get("days", []), SysUtil.weekday(day))

## Opening hours only (no staff check): is the door open at this absolute game minute?
static func open_at(pid: String, at_min: int = -1) -> bool:
	if at_min < 0:
		at_min = SimEnv.now_min()
	var d: Dictionary = def(pid)
	if d.is_empty():
		return false
	var h: float = float(at_min % 1440) / 60.0
	var day: int = at_min / 1440 + 1
	if d.has("seasons") and not (d["seasons"] as Array).has(Seasons.season_at_day(day)):
		return false
	for row in schedule(pid):
		var hr: Array = row.get("hours", [0, 24])
		var o: float = float(hr[0])
		var c: float = float(hr[1])
		if _row_day_ok(row, day) and h >= o and h < minf(c, 24.0):
			return true
		if c > 24.0 and h < c - 24.0 and _row_day_ok(row, day - 1):
			return true
	return false

## Open for business: inside the hours, staffed, and not shut by something else (a holiday, a closure).
static func is_open(pid: String, at_min: int = -1) -> bool:
	return open_at(pid, at_min) and PlaceStaff.staffed(pid) and not PlaceStaff.closed_today(pid)

## "Open until 18:00" / "Opens 17:00" / "Closed today" / "Short of staff" for the UI.
static func status_text(pid: String) -> String:
	if not exists(pid):
		return ""
	if PlaceStaff.closed_today(pid):
		return "Closed today"
	if open_at(pid) and not PlaceStaff.staffed(pid):
		return "Short of staff"
	var now: int = SimEnv.now_min()
	if open_at(pid, now):
		for step in range(1, 30 * 60 / 15):
			if not open_at(pid, now + step * 15):
				return "Open until %s" % _hh(float((now + step * 15) % 1440) / 60.0)
		return "Always open"
	for step in range(1, 7 * 24 * 4):
		if open_at(pid, now + step * 15):
			var at: int = now + step * 15
			var same_day: bool = at / 1440 == now / 1440
			return "Opens %s%s" % [_hh(float(at % 1440) / 60.0), "" if same_day else " (%s)" % _weekday_name(SysUtil.weekday(at / 1440 + 1))]
	return "Closed"

static func _hh(h: float) -> String:
	return "%02d:%02d" % [int(h) % 24, int(round((h - floorf(h)) * 60.0)) % 60]

static func _weekday_name(wd: int) -> String:
	return (["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] as Array)[posmod(wd, 7)]

# ------------------------------------------------------------------ the lot hook (Venues.is_open_type)
const HOME := "@home"          # a place in the person's own house (the radio, the TV)

static var _hosted: Dictionary = {}          # venue type -> [place ids]
static var _hosted_n: int = -1               # number of lots when it was built
static var _xcache: Dictionary = {}          # venue type -> {game minute: open because of a place}

static func reset() -> void:
	_hosted = {}
	_hosted_n = -1
	_xcache.clear()
	_hol_day = -1

static func _build_hosted() -> void:
	_hosted = {}
	_xcache.clear()
	_hosted_n = Neighborhood.lots().size()
	for pid in all():
		var lot: Dictionary = Neighborhood.lot(lot_of(pid))
		if lot.is_empty():
			continue
		var vt: String = str(lot.get("type", ""))
		if not _hosted.has(vt):
			_hosted[vt] = []
		(_hosted[vt] as Array).append(pid)

## A lot whose own venue hours are over is still open while a place inside it is (evening classes in the school, the club in the cafe).
static func extra_open(vtype: String, at_min: int) -> bool:
	if _hosted_n != Neighborhood.lots().size():
		_build_hosted()
	var places: Array = _hosted.get(vtype, [])
	if places.is_empty():
		return false
	var cache: Dictionary = _xcache.get(vtype, {})
	if cache.has(at_min):
		return bool(cache[at_min])
	var open := false
	for pid in places:
		if open_at(str(pid), at_min):
			open = true
			break
	if cache.size() > 600:
		cache.clear()
	cache[at_min] = open
	_xcache[vtype] = cache
	return open

## Is the host lot really on the map (a test world or the classic single lot has none: then nobody has to walk anywhere)?
static func on_map(lot: String) -> bool:
	var rg = NeighborhoodLots._regions()
	if lot == HOME:
		return rg != null and rg.has_regions()
	return lot != "" and rg != null and not rg.by_lot(lot).is_empty()

## Is this person standing in the place's lot (always true when the lot is not on the map)?
static func is_there(f, pid: String) -> bool:
	var lot: String = lot_of(pid)
	if lot == HOME:
		return not on_map(lot) or Neighborhood.lot_of(f) == PlayerLots.home_of(f)
	return not on_map(lot) or Neighborhood.lot_of(f) == lot

## Name of the place's lot for the player ("Home" for a place in the house).
static func lot_label(pid: String) -> String:
	var lot: String = lot_of(pid)
	return "Home" if lot == HOME else Neighborhood.label_of(lot)

# ------------------------------------------------------------------ rules
## The service's label with the programme title of the week filled in ("Family Film: {title}").
static func service_label(pid: String, sid: String) -> String:
	var svc: Dictionary = services(pid).get(sid, {})
	var l: String = str(svc.get("label", sid))
	if l.find("{title}") >= 0:
		l = l.replace("{title}", Programme.title(pid, str(svc.get("programme_slot", ""))))
	return l

## Place-level age rule (`adult_only`, `min_stage`): the bar and the nightclub keep children and teens out of every service.
static func place_reason(stage: String, pid: String) -> String:
	var d: Dictionary = def(pid)
	return stage_reason(stage, {"adult_only": d.get("adult_only", false), "min_stage": d.get("min_stage", "")}) if (d.has("adult_only") or d.has("min_stage")) else ""

## A service that is on only some days or weeks ("when": {"days": [weekdays], "week_mod": [m, k]}): "" when it is on now.
static func when_reason(svc: Dictionary, at_min: int = -1) -> String:
	var w: Dictionary = svc.get("when", {})
	if w.is_empty():
		return ""
	if at_min < 0:
		at_min = SimEnv.now_min()
	var day: int = at_min / 1440 + 1
	if w.has("days") and not SysUtil.has_int(w["days"], SysUtil.weekday(day)):
		return "Not today."
	if w.has("season") and not (w["season"] as Array).has(Seasons.season_at_day(day)):
		return "Not in this season."
	if w.has("week_mod") and ((day - 1) / 7) % int(w["week_mod"][0]) != int(w["week_mod"][1]):
		return "Not on the menu this week."
	return ""

## Is this life stage allowed to use the service? ("" = yes, else a plain-word reason.)
static func stage_reason(stage: String, svc: Dictionary) -> String:
	if svc.has("stages"):
		if not (svc["stages"] as Array).has(stage):
			return "Not for %s." % (stage + "s")
		return ""
	var idx: int = Aging.stage_index(stage)
	if bool(svc.get("adult_only", false)) and idx < Aging.stage_index("adult"):
		return "Only for adults."
	if str(svc.get("min_stage", "")) != "" and idx < Aging.stage_index(str(svc["min_stage"])):
		return "Too young for that."
	return ""
