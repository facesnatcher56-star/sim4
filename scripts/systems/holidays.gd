class_name Holidays
extends RefCounted
## Seasonal holidays (data/holidays.json). A holiday is a fixed day of a season (Seasons API). While it lasts every folk
## carries the holiday's buff plus the hidden `holiday_today` marker (which unlocks the gift interaction); an
## announcement is sent at dawn; residents in a decorated spot (>= 2 plants / lamps / fireplaces nearby) get `festive_home`;
## Story parties get a score bonus every game hour; each holiday injects a whim into the Goals whim table
## (see WeatherContent).
##
## API: Holidays.today(day) -> {id, label, ...} or {} ; Holidays.on_day(day) ; Holidays.next_after(day) ; Holidays.holiday_day(id, year)
##      Holidays.decor_count(folk) ; Holidays.party_bonus() ; Holidays.active_id()

static var _active: String = ""
static var _announced_eve: int = -1

static func cfg() -> Dictionary:
	return SysUtil.table("holidays")

static func all() -> Dictionary:
	return cfg().get("holidays", {})

static func reset() -> void:
	_active = ""
	_announced_eve = -1

static func active_id() -> String:
	return _active

## Day of the season (1-based) a holiday falls on for the current season length.
static func _dos(h: Dictionary) -> int:
	var d: int = int(h.get("day", 1))
	var n: int = Seasons.length()
	if d < 0:
		d = n + 1 + d
	return clampi(d, 1, n)

## The holiday on absolute game `day` (default today), or {}.
static func today(day: int = -1) -> Dictionary:
	var d: int = int(SimEnv.clock().day()) if day < 0 else day
	var sid: String = Seasons.season_at_day(d)
	var dos: int = Seasons.day_of_season_at(d)
	var yr: int = Seasons.year_at(d)
	var hs: Dictionary = all()
	var ids: Array = hs.keys()
	ids.sort()
	for id in ids:
		var h: Dictionary = hs[id]
		if str(h.get("season", "")) == sid and _dos(h) == dos and yr >= int(h.get("min_year", 1)):
			var out: Dictionary = h.duplicate(true)
			out["id"] = str(id)
			return out
	return {}

static func holiday_day(id: String, year: int) -> int:
	var h: Dictionary = all().get(id, {})
	if h.is_empty():
		return -1
	var si: int = Seasons.IDS.find(str(h.get("season", "spring")))
	var d0: int = ((year - 1) * 4 + si) * Seasons.length() + (_dos(h) - 1)
	return d0 + 1 - Seasons._offset

## Next holiday strictly after `day` (looks up to 2 years ahead). Returns {id, label, day}.
static func next_after(day: int) -> Dictionary:
	var d: int = day + 1
	var limit: int = d + Seasons.length() * 8 + 1
	while d <= limit:
		var h: Dictionary = today(d)
		if not h.is_empty():
			h["day"] = d
			return h
		d += 1
	return {}

static func party_bonus() -> float:
	var h: Dictionary = today()
	if h.is_empty():
		return 0.0
	return float(h.get("party_bonus", cfg().get("default_party_bonus", 1.5)))

static func buff_ids() -> Array:
	var out: Array = []
	for id in all():
		var b: String = str((all()[id] as Dictionary).get("buff", ""))
		if b != "":
			out.append(b)
	return out

# ------------------------------------------------------------------ folk
static func _has_def(b: String) -> bool:
	return not SimEnv.data().buff_def(b).is_empty()

## Give (or take away) the holiday buffs on a single folk to match today's holiday.
static func sync_folk(f) -> void:
	var h: Dictionary = today()
	var want: String = str(h.get("buff", ""))
	if not _has_def("holiday_today"):
		return
	if h.is_empty():
		if f.has_buff("holiday_today"):
			f.remove_buff("holiday_today")
		for b in buff_ids():
			if f.has_buff(str(b)):
				f.remove_buff(str(b))
		return
	if not f.has_buff("holiday_today"):
		f.add_buff("holiday_today")
	for b2 in buff_ids():
		if str(b2) != want and f.has_buff(str(b2)):
			f.remove_buff(str(b2))
	if want != "" and _has_def(want) and not f.has_buff(want):
		f.add_buff(want)

static func decor_count(f) -> int:
	var dc: Dictionary = cfg().get("decor", {})
	var tags: Array = dc.get("tags", ["plant", "light", "fire"])
	var n: int = 0
	for o in WorldIface.objects_near(f.tile, int(dc.get("radius", 7))):
		var otags: Array = SimEnv.data().object_def(str(o.def_id)).get("tags", [])
		for t in tags:
			if otags.has(t):
				n += 1
				break
	return n

# ------------------------------------------------------------------ ticks
static func on_day(day: int) -> void:
	var h: Dictionary = today(day)
	var id: String = str(h.get("id", ""))
	if id != _active:
		if _active != "":
			SysUtil.game_event("holiday_ended", {"holiday": _active, "folk_id": -1})
		_active = id
		if id != "":
			SysUtil.notify(str(h.get("notify", "%s has begun!" % str(h.get("label", id)))), "holiday")
			SysUtil.game_event("holiday_started", {"holiday": id, "label": str(h.get("label", id)), "folk_id": -1})
	for f in WorldIface.all_folk():
		sync_folk(f)
	# eve notice for tomorrow
	var nxt: Dictionary = today(day + 1)
	if not nxt.is_empty() and _announced_eve != day:
		_announced_eve = day
		SysUtil.notify("Tomorrow: %s." % str(nxt.get("label", "a holiday")), "holiday")

static func on_hour() -> void:
	var h: Dictionary = today()
	if h.is_empty():
		return
	var dc: Dictionary = cfg().get("decor", {})
	var need: int = int(dc.get("min_count", 2))
	var buff: String = str(dc.get("buff", "festive_home"))
	for f in WorldIface.all_folk():
		sync_folk(f)
		if SysUtil.is_resident(f) and not SysUtil.is_away(f) and _has_def(buff) and decor_count(f) >= need:
			f.add_buff(buff)
	# party score bonus
	var bonus: float = party_bonus()
	if bonus > 0.0:
		for sit in Story.situations:
			if str(sit.get("kind", "")) == "party" and (str(sit.get("state", "")) == "mingle" or str(sit.get("state", "")) == "arrive"):
				sit["score"] = float(sit.get("score", 0.0)) + bonus

# ------------------------------------------------------------------ save / load
static func to_dict() -> Dictionary:
	return {"active": _active, "eve": _announced_eve}

static func from_dict(d: Dictionary) -> void:
	_active = str(d.get("active", ""))
	_announced_eve = int(d.get("eve", -1))
