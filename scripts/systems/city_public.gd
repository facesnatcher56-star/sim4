class_name CityPublic
extends RefCounted
## Public spaces and ageing infrastructure (task 12.5). Per zone: street lamps (they break as the town's infrastructure ages and are fixed by the budget; a dark zone
## feels unsafe and counts against crime), bins (full bins turn into litter, the parks budget empties them), benches, public toilets, fountains and playgrounds (the
## parks budget adds one every couple of months), and seasonal decoration on holidays. `age` is the town's infrastructure age (0 new .. 1 falling apart): pipes and
## cables fail more often with it (CityBudget.maintenance_mult), the utilities budget renews it.
##   CityPublic.working_lamps(zone) / lamp_equiv() / litter(zone) / quality() -> -1 .. +1 (the town's feeling about its public places)
## Tier behaviour: per zone numbers only (4 zones); nothing per person. Cadence: daily. Objects for these things exist as content (streetlamp, bench, public_bin,
## public_toilet, fountain, playground) so a player can put them on their own lot; the town's own are numbers.

static var lamps: Dictionary = {}        # zone -> working lamps
static var broken: Dictionary = {}       # zone -> broken lamps
static var bin_fill: Dictionary = {}     # zone -> 0..1
static var litter_now: Dictionary = {}   # zone -> 0..1
static var amenities: Dictionary = {}    # zone -> {benches, toilets, fountains, playgrounds, bins}
static var age: float = 0.0
static var decor_until: int = -1
static var decor_holiday: String = ""
static var weeks_since_amenity: int = 0
static var told: Dictionary = {}         # zone -> {lamps: bool, litter: bool} (so a problem is announced once)

static func reset() -> void:
	lamps = {}
	broken = {}
	bin_fill = {}
	litter_now = {}
	amenities = {}
	age = 0.0
	decor_until = -1
	decor_holiday = ""
	weeks_since_amenity = 0
	told = {}

static func cfg() -> Dictionary:
	return CityState.cfg().get("public", {})

static func _init_zone(z: String) -> void:
	if lamps.has(z):
		return
	var c: Dictionary = cfg()
	lamps[z] = int(c.get("lamps", 8))
	broken[z] = 0
	bin_fill[z] = 0.2
	litter_now[z] = 0.05
	amenities[z] = {"benches": int(c.get("benches", 4)), "toilets": int(c.get("toilets", 1)), "fountains": int(c.get("fountains", 1)),
		"playgrounds": int(c.get("playgrounds", 1)), "bins": int(c.get("bins", 5))}
	told[z] = {"lamps": false, "litter": false}

static func ensure() -> void:
	for z in CityState.zone_ids():
		_init_zone(str(z))

static func working_lamps(zone: String) -> int:
	_init_zone(zone)
	return int(lamps[zone])

static func total_lamps(zone: String) -> int:
	_init_zone(zone)
	return int(lamps[zone]) + int(broken[zone])

static func lamp_share() -> float:
	ensure()
	var w: float = 0.0
	var t: float = 0.0
	for z in CityState.zone_ids():
		w += float(working_lamps(str(z)))
		t += float(total_lamps(str(z)))
	return w / maxf(t, 1.0)

## What the crime rate counts as "street lamps": lamp_equiv at full coverage (the old per-object count), less when lamps are out.
static func lamp_equiv() -> int:
	return int(round(lamp_share() * float(cfg().get("lamp_equiv", 8))))

static func litter(zone: String) -> float:
	_init_zone(zone)
	return float(litter_now[zone])

static func decorated() -> bool:
	return decor_until >= SysUtil.day()

## The town's feeling about its public places, -1 .. +1 (CityMood part "public").
static func quality() -> float:
	ensure()
	var l: float = 0.0
	for z in CityState.zone_ids():
		l += litter(str(z))
	l /= float(maxi(CityState.zone_ids().size(), 1))
	var q: float = (lamp_share() - 0.7) * 2.0 - (l - 0.25) * 2.0 + (float(cfg().get("decor_mood", 0.12)) if decorated() else 0.0)
	return clampf(q, -1.0, 1.0)

# ------------------------------------------------------------------ the day
static func on_day(day: int) -> void:
	ensure()
	var c: Dictionary = cfg()
	var parks: float = CityBudget.funding("parks")
	var util: float = CityBudget.funding("utilities")
	var a: Dictionary = c.get("age", {})
	age = clampf(age + float(a.get("per_day", 0.0016)) - float(a.get("relief", 0.0032)) * clampf(util - 0.6, 0.0, 1.0), 0.0, 1.0)
	for zone in CityState.zone_ids():
		var z: String = str(zone)
		_lamps_day(z, c, parks)
		_litter_day(z, c, parks)
	if day % 7 == 0:
		_week(c, parks)
	_decoration(day, c)

static func _lamps_day(z: String, c: Dictionary, parks: float) -> void:
	var p: float = float(c.get("lamp_break_per_day", 0.012)) * (1.0 + age * 1.5)
	for i in int(lamps[z]):
		if CityState.chance(p):
			lamps[z] = int(lamps[z]) - 1
			broken[z] = int(broken[z]) + 1
	if int(broken[z]) * 3 >= total_lamps(z) and not bool(told[z]["lamps"]):
		told[z]["lamps"] = true
		if CityState.zone_of_household(Players.primary_household()) == z:
			SysUtil.notify(str(c.get("texts", {}).get("lamps_out", "")).replace("{zone}", CityState.zone_label(z)), "warn")
		ChronicleHook.note("town", str(c.get("texts", {}).get("lamps_out", "")).replace("{zone}", CityState.zone_label(z)), [], "", 1, true)

static func _litter_day(z: String, c: Dictionary, _parks: float) -> void:
	var bins: int = int((amenities[z] as Dictionary).get("bins", 5))
	bin_fill[z] = minf(float(bin_fill[z]) + float(c.get("bin_fill_per_day", 0.09)) * 5.0 / float(maxi(bins, 1)), 1.0)
	if float(bin_fill[z]) >= 1.0:
		litter_now[z] = minf(float(litter_now[z]) + float(c.get("litter_up", 0.035)), 1.0)
		if float(litter_now[z]) > 0.6 and not bool(told[z]["litter"]):
			told[z]["litter"] = true
			var t: String = str(c.get("texts", {}).get("litter", "")).replace("{zone}", CityState.zone_label(z))
			if CityState.zone_of_household(Players.primary_household()) == z:
				SysUtil.notify(t, "warn")
	else:
		litter_now[z] = maxf(float(litter_now[z]) - float(c.get("litter_down", 0.03)), 0.0)
		if float(litter_now[z]) < 0.3:
			told[z]["litter"] = false

static func _week(c: Dictionary, parks: float) -> void:
	for zone in CityState.zone_ids():
		var z: String = str(zone)
		# crews fix lamps (more with the budget) and empty the bins
		var want: float = float(c.get("lamps_fixed_per_week", 2)) * parks
		var fix: int = int(floor(want)) + (1 if CityState.chance(want - floor(want)) else 0)
		var n: int = mini(fix, int(broken[z]))
		lamps[z] = int(lamps[z]) + n
		broken[z] = int(broken[z]) - n
		if int(broken[z]) == 0 and bool(told[z]["lamps"]):
			told[z]["lamps"] = false
			if CityState.zone_of_household(Players.primary_household()) == z:
				SysUtil.notify(str(c.get("texts", {}).get("lamps_fixed", "")).replace("{zone}", CityState.zone_label(z)), "good")
		bin_fill[z] = maxf(float(bin_fill[z]) - float(c.get("bins_emptied_per_week", 1.2)) * parks, 0.0)
	# the parks budget builds a new amenity every so often
	weeks_since_amenity += 1
	if weeks_since_amenity >= int(c.get("amenity_every_weeks", 8)) and parks >= 1.05:
		weeks_since_amenity = 0
		_build_amenity(c)

static func _build_amenity(c: Dictionary) -> void:
	var caps: Dictionary = c.get("amenity_cap", {})
	var costs: Dictionary = c.get("amenity_cost", {})
	var kinds: Array = ["benches", "toilets", "fountains", "playgrounds", "bins"]
	var zones: Array = CityState.zone_ids()
	var z: String = str(zones[CityState.rng.randi_range(0, zones.size() - 1)])
	var what: String = str(kinds[CityState.rng.randi_range(0, kinds.size() - 1)])
	if int((amenities[z] as Dictionary).get(what, 0)) >= int(caps.get(what, 5)) or CityGov.treasury < float(costs.get(what, 100)):
		return
	CityGov.treasury -= float(costs.get(what, 100))
	amenities[z][what] = int(amenities[z][what]) + 1
	var label: String = {"benches": "bench", "toilets": "public toilet", "fountains": "fountain", "playgrounds": "playground", "bins": "bin"}[what]
	var t: String = str(c.get("texts", {}).get("amenity", "")).replace("{what}", label).replace("{zone}", CityState.zone_label(z))
	CityGov.note("public", t)
	if CityState.zone_of_household(Players.primary_household()) == z:
		SysUtil.notify(t, "good")

static func _decoration(day: int, c: Dictionary) -> void:
	var h: Dictionary = Holidays.today(day)
	if not h.is_empty() and decor_until < day:
		decor_until = day + int(c.get("decor_days", 3))
		decor_holiday = str(h.get("id", ""))
		var t: String = str(c.get("texts", {}).get("decor", "")).replace("{label}", str(h.get("label", "the holiday")))
		SysUtil.notify(t, "info")
		CityGov.note("public", t)

static func to_dict() -> Dictionary:
	return {"lamps": lamps.duplicate(), "broken": broken.duplicate(), "bin_fill": bin_fill.duplicate(), "litter": litter_now.duplicate(), "amenities": amenities.duplicate(true),
		"age": age, "decor_until": decor_until, "decor_holiday": decor_holiday, "weeks": weeks_since_amenity, "told": told.duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	for k in (d.get("lamps", {}) as Dictionary):
		lamps[str(k)] = int(d["lamps"][k])
	for k2 in (d.get("broken", {}) as Dictionary):
		broken[str(k2)] = int(d["broken"][k2])
	bin_fill = (d.get("bin_fill", {}) as Dictionary).duplicate()
	litter_now = (d.get("litter", {}) as Dictionary).duplicate()
	amenities = (d.get("amenities", {}) as Dictionary).duplicate(true)
	for z in amenities:
		for kk in amenities[z]:
			amenities[z][kk] = int(amenities[z][kk])
	age = float(d.get("age", 0.0))
	decor_until = int(d.get("decor_until", -1))
	decor_holiday = str(d.get("decor_holiday", ""))
	weeks_since_amenity = int(d.get("weeks", 0))
	told = (d.get("told", {}) as Dictionary).duplicate(true)
