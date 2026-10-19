class_name Utilities
extends RefCounted
## Power, water and sewage, phone and internet as real networks (task 12.1). The town is cut into zones (CityState); each utility can be DOWN in a zone for
## some hours (an outage record) and a zone can be under a boil water notice. Causes are data (data/city.json utilities.causes): storms, an overloaded grid,
## failed equipment, a burst main, a pumping fault, a cable fault, contamination after a flood. What a home does about it (generator, solar panels, water
## tank, well, boiling water) is UtilityHomes; the dice are UtilityEvents; bills are split by utility in UtilityBills.
##   Utilities.is_down(util, zone) / home_has(util, hid) / begin(util, zone, hours, cause) / report(outage) / status_lines(hid)
## Tier behaviour: the zone state is world-level (a handful of records); the player's household(s) are FULL (buffs, lamps, fridge, bills); townie lots are
## STATISTICAL (one lot event line per hit, capped). Cadence: one cheap check per minute while an outage is running (gate `busy`), hourly dice for every zone
## (zones x causes, ~10 rolls), daily boil upkeep. Caps: history 40, townie lot events per lot 6 (DisasterState), outages are few by construction.

static var outages: Array = []            # {id, util, zone, cause, start, end, told, reported, data:{}}
static var boil: Dictionary = {}          # zone -> minute the boil water notice ends
static var boiled: Dictionary = {}        # str(household) -> minute their boiled-water supply runs out
static var reserve: Dictionary = {}       # str(household) -> hours left in the water tank
static var history: Array = []            # finished outages {util, zone, cause, day, hours}
static var stats: Dictionary = {}         # counters: outages, by util, by cause, hours down
static var seq: int = 1

const UTILS := ["power", "water", "internet"]

static func reset() -> void:
	outages.clear()
	boil.clear()
	boiled.clear()
	reserve.clear()
	history.clear()
	stats.clear()
	seq = 1
	UtilityHomes.reset()
	UtilityBills.reset()

static func cfg() -> Dictionary:
	return CityState.cfg().get("utilities", {})

static func count(key: String, n: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + n

static func busy() -> bool:
	return not outages.is_empty() or not boil.is_empty()

# ------------------------------------------------------------------ queries
static func outage_of(util: String, zone: String) -> Dictionary:
	for o in outages:
		if str(o["util"]) == util and str(o["zone"]) == zone:
			return o
	return {}

static func is_down(util: String, zone: String) -> bool:
	return not outage_of(util, zone).is_empty()

static func boil_active(zone: String) -> bool:
	return int(boil.get(zone, 0)) > SysUtil.now()

static func label(util: String) -> String:
	return str((cfg().get("labels", {}) as Dictionary).get(util, util))

static func short(util: String) -> String:
	return str((cfg().get("short", {}) as Dictionary).get(util, util))

static func minutes_left(o: Dictionary) -> int:
	return maxi(int(o["end"]) - SysUtil.now(), 0)

# ------------------------------------------------------------------ outages
## Start an outage of `util` in `zone` lasting about `hours`. A utility already down in that zone is left alone (returns that record).
## opts: forced, silent, apply (false = only the network state, the homes are handled elsewhere: the old town-wide power cut).
static func begin(util: String, zone: String, hours: float, cause: String, opts: Dictionary = {}) -> Dictionary:
	var cur: Dictionary = outage_of(util, zone)
	if not cur.is_empty():
		return cur
	var now: int = SysUtil.now()
	var o: Dictionary = {"id": seq, "util": util, "zone": zone, "cause": cause, "start": now, "end": now + maxi(int(round(hours * 60.0)), 5),
		"told": false, "reported": false, "apply": bool(opts.get("apply", true)), "data": {}}
	seq += 1
	outages.append(o)
	count("outages")
	count("util_" + util)
	count("cause_" + cause)
	if cause == "burst_main":
		TransportTraffic.add_works(zone, "pipe", maxf(hours / 24.0, 0.1))      # the repair crew digs up the street
	if bool(opts.get("apply", true)):
		UtilityHomes.on_start(o)
	if not bool(opts.get("silent", false)):
		_announce(o)
	SysUtil.game_event("utility_down", {"util": util, "zone": zone, "cause": cause, "hours": hours, "folk_id": -1})
	return o

static func _text_for(o: Dictionary) -> String:
	var spec: Dictionary = ((cfg().get("causes", {}) as Dictionary).get(str(o["util"]), {}) as Dictionary).get(str(o["cause"]), {})
	return str(spec.get("text", "The %s is out on {zone}." % short(str(o["util"])))).replace("{zone}", CityState.zone_label(str(o["zone"])))

## One toast when it is the players' own zone (household policy), one chronicle line for the big ones.
static func _announce(o: Dictionary) -> void:
	var zone: String = str(o["zone"])
	var mine: bool = false
	for hid in CityState.full_households():
		if CityState.zone_of_household(int(hid)) == zone:
			mine = true
	var text: String = _text_for(o)
	if mine:
		SysUtil.notify(text, "warn")
		o["told"] = true
	var hours: float = float(int(o["end"]) - int(o["start"])) / 60.0
	if hours >= float(cfg().get("chronicle_hours", 3)) or str(o["util"]) == "water":
		ChronicleHook.note("utility", text, [], "", 2, true)

## The old town-wide power cut (a disaster incident, which handles the homes itself): every zone is without power for `minutes`.
static func external_power(minutes: int) -> void:
	for zone in CityState.zone_ids():
		begin("power", str(zone), float(minutes) / 60.0, "storm", {"apply": false, "silent": true})

## The player (or anyone with a phone) reports it: crews work faster. Once per outage. Needs a working phone line when asked from a home.
static func report(o: Dictionary) -> bool:
	if o.is_empty() or bool(o["reported"]):
		return false
	o["reported"] = true
	var left: int = minutes_left(o)
	o["end"] = SysUtil.now() + int(round(float(left) * (1.0 - float((cfg().get("repair", {}) as Dictionary).get("report_cut", 0.25)))))
	count("reports")
	return true

static func finish(o: Dictionary) -> void:
	if o.is_empty():
		return
	outages.erase(o)
	var hours: float = float(SysUtil.now() - int(o["start"])) / 60.0
	count("hours_down", int(round(hours)))
	count("hours_" + str(o["util"]), int(round(hours)))
	history.append({"util": str(o["util"]), "zone": str(o["zone"]), "cause": str(o["cause"]), "day": SysUtil.day(), "hours": snappedf(hours, 0.1)})
	while history.size() > int(cfg().get("history_cap", 40)):
		history.pop_front()
	if bool(o.get("apply", true)):
		UtilityHomes.on_end(o)
	if bool(o["told"]):
		SysUtil.notify("The %s is back on %s." % [short(str(o["util"])), CityState.zone_label(str(o["zone"]))], "good")
	# a burst main leaves a boil water notice behind (sometimes)
	var spec: Dictionary = ((cfg().get("causes", {}) as Dictionary).get(str(o["util"]), {}) as Dictionary).get(str(o["cause"]), {})
	if str(o["cause"]) == "burst_main" and CityState.chance(float(spec.get("boil_after", 0.0))):
		start_boil(str(o["zone"]))
	SysUtil.game_event("utility_up", {"util": str(o["util"]), "zone": str(o["zone"]), "hours": hours, "folk_id": -1})

## A boil water notice for the zone (days rolled from data). Households with a well, or who boiled their water, are fine.
static func start_boil(zone: String, days: int = -1) -> void:
	var b: Dictionary = cfg().get("boil", {})
	var d: int = days if days > 0 else CityState.range_i(b.get("days", [2, 4]))
	var was: bool = boil_active(zone)
	boil[zone] = maxi(int(boil.get(zone, 0)), SysUtil.now() + d * 1440)
	if was:
		return
	count("boil_notices")
	var text: String = str(b.get("text", "")).replace("{zone}", CityState.zone_label(zone))
	for hid in CityState.full_households():
		if CityState.zone_of_household(int(hid)) == zone:
			SysUtil.notify(text, "warn")
			UtilityHomes.mark_boil(int(hid))
	ChronicleHook.note("utility", text, [], "", 2, true)
	SysUtil.game_event("boil_notice", {"zone": zone, "folk_id": -1})

# ------------------------------------------------------------------ the hooks (sim_registry rows)
static func on_minute() -> void:
	var now: int = SysUtil.now()
	for o in outages.duplicate():
		if now >= int(o["end"]):
			finish(o)

static func on_hour(_hour: int = 0) -> void:
	UtilityContent.ensure()
	UtilityEvents.roll_hour()
	UtilityHomes.on_hour()

static func on_day(_day: int) -> void:
	for z in boil.keys():
		if not boil_active(str(z)):
			boil.erase(z)
			var t: String = str((cfg().get("boil", {}) as Dictionary).get("over_text", "")).replace("{zone}", CityState.zone_label(str(z)))
			for hid in CityState.full_households():
				if CityState.zone_of_household(int(hid)) == str(z):
					SysUtil.notify(t, "good")
					UtilityHomes.clear_boil(int(hid))
	UtilityHomes.on_day()

# ------------------------------------------------------------------ interactions (game events of the mailbox / kettle)
static func on_event(ev: String, payload: Dictionary) -> void:
	var f = SysUtil.folk(int(payload.get("folk_id", -1)))
	if f == null or int(f.household_id) <= 0:
		return
	var hid: int = int(f.household_id)
	match ev:
		"check_utilities":
			for line in status_lines(hid):
				SysUtil.notify(str(line), "info")
		"report_outage":
			var reported: int = 0
			for o in outages.duplicate():
				if str(o["zone"]) == CityState.zone_of_household(hid) and report(o):
					reported += 1
			SysUtil.notify("The crews know. They will be quicker." if reported > 0 else "Nothing is broken that has not been reported.", "good" if reported > 0 else "info")
		"boil_water":
			UtilityHomes.boil_water(hid)
			SysUtil.notify("The water is boiled and safe to drink for a while.", "good")

# ------------------------------------------------------------------ for the player
## Plain-word lines for the household: what is on and off, why, and how long.
static func status_lines(hid: int) -> Array:
	var out: Array = []
	var zone: String = CityState.zone_of_household(hid)
	for u in UTILS:
		var ok: bool = UtilityHomes.has(u, hid)
		if ok:
			out.append("%s: working." % label(u))
			continue
		var o: Dictionary = outage_of(u, zone)
		if o.is_empty():
			out.append("%s: off (%s)." % [label(u), UtilityHomes.why_off(u, hid)])
		else:
			var spec: Dictionary = ((cfg().get("causes", {}) as Dictionary).get(u, {}) as Dictionary).get(str(o["cause"]), {})
			var left: int = minutes_left(o)
			out.append("%s: off because of %s. Back in about %s." % [label(u), str(spec.get("short", "a fault")), _span(left)])
	if boil_active(zone) and not UtilityHomes.water_safe(hid):
		out.append("Boil the tap water before drinking it.")
	return out

static func _span(minutes: int) -> String:
	if minutes < 90:
		return "%d minutes" % maxi(minutes, 1)
	return "%d hours" % int(round(float(minutes) / 60.0))

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"outages": outages.duplicate(true), "boil": SysUtil.str_keys(boil), "boiled": boiled.duplicate(), "reserve": reserve.duplicate(),
		"history": history.duplicate(true), "stats": stats.duplicate(), "seq": seq, "homes": UtilityHomes.to_dict(), "bills": UtilityBills.to_dict()}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	outages = (d.get("outages", []) as Array).duplicate(true)
	for o in outages:
		for k in ["id", "start", "end"]:
			o[k] = int(o[k])
	boil = {}
	for k in (d.get("boil", {}) as Dictionary):
		boil[str(k)] = int(d["boil"][k])
	boiled = (d.get("boiled", {}) as Dictionary).duplicate()
	reserve = (d.get("reserve", {}) as Dictionary).duplicate()
	history = (d.get("history", []) as Array).duplicate(true)
	for hrec in history:
		SysUtil.ints_in(hrec, ["day"])
	stats = {}
	for k2 in (d.get("stats", {}) as Dictionary):
		stats[str(k2)] = int(d["stats"][k2])
	seq = int(d.get("seq", 1))
	UtilityHomes.from_dict(d.get("homes", {}))
	UtilityBills.from_dict(d.get("bills", {}))
