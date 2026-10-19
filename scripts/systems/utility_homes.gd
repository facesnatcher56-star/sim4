class_name UtilityHomes
extends RefCounted
## What the utility networks mean for a FULL household (task 12.1): does the home have power, water, phone and internet RIGHT NOW (the zone's service plus the
## home's own backup: generator, solar panels, water tank, well), the markers that make interactions refuse (`power_out`, `no_water`, `no_signal`, `offline`,
## `boil_notice`), lamps going dark, a warm fridge spoiling, generator fuel and tank reserve burning down by the hour, and boiling water.
## Cadence: refresh on an outage start / end and every game hour while something is wrong at home. Idle homes cost one dictionary lookup per hour.

const LAMPS := ["lamp", "pendant_light", "nightstand"]
const MARKERS := {"power": "power_out", "water": "no_water", "phone": "no_signal", "online": "offline"}

static var state: Dictionary = {}          # str(hid) -> {power, water, phone, online, boil: bool, lamps: [object ids], spoil_told...}
static var _cache_hour: int = -1
static var _cache: Dictionary = {}         # hid -> {def_id: [objects]}  (one pass over the home's objects per game hour)

static func reset() -> void:
	state.clear()
	_cache.clear()
	_cache_hour = -1

static func to_dict() -> Dictionary:
	return {"state": state.duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	state = (d.get("state", {}) as Dictionary).duplicate(true)

# ------------------------------------------------------------------ the home's things
static func defs_of(hid: int) -> Dictionary:
	var h: int = SysUtil.now() / 60
	if h != _cache_hour:
		_cache.clear()
		_cache_hour = h
	if not _cache.has(hid):
		var m: Dictionary = {}
		for o in Economy.objects_of(hid):
			var k: String = str(o.def_id)
			if not m.has(k):
				m[k] = []
			(m[k] as Array).append(o)
		_cache[hid] = m
	return _cache[hid]

static func forget_cache() -> void:
	_cache.clear()
	_cache_hour = -1

static func _working(hid: int, def_id: String) -> Array:
	var out: Array = []
	for o in defs_of(hid).get(def_id, []):
		if not bool(WorldIface.state_get(o, "broken", false)):
			out.append(o)
	return out

static func generator(hid: int):
	for o in _working(hid, "generator"):
		if float(WorldIface.state_get(o, "fuel", 0.0)) > 0.0:
			return o
	return null

static func solar_up(hid: int) -> bool:
	return not _working(hid, "solar_panel").is_empty() and Weather.daylight() >= float(Utilities.cfg().get("resilience", {}).get("solar_daylight", 0.3))

static func has_well(hid: int) -> bool:
	return not _working(hid, "well").is_empty()

static func tank_hours(hid: int) -> float:
	var n: int = _working(hid, "water_tank").size()
	return float(n) * float((Utilities.cfg().get("objects", {}) as Dictionary).get("water_tank", {}).get("hours", 36))

static func zone(hid: int) -> String:
	return CityState.zone_of_household(hid)

# ------------------------------------------------------------------ service at home
static func has_power(hid: int) -> bool:
	if not Utilities.is_down("power", zone(hid)):
		return true
	return generator(hid) != null or solar_up(hid)

static func has_water(hid: int) -> bool:
	if not Utilities.is_down("water", zone(hid)):
		return true
	if float(Utilities.reserve.get(str(hid), 0.0)) > 0.0:
		return true
	return has_well(hid) and (has_power(hid) or not bool(Utilities.cfg().get("resilience", {}).get("well_needs_power", true)))

static func has_phone(hid: int) -> bool:
	return not Utilities.is_down("internet", zone(hid)) and not _bill_cut("internet", hid)

static func has_online(hid: int) -> bool:
	return has_phone(hid) and has_power(hid)

static func has(util: String, hid: int) -> bool:
	match util:
		"power":
			return has_power(hid)
		"water":
			return has_water(hid)
		"internet":
			return has_online(hid)
	return true

static func _bill_cut(util: String, hid: int) -> bool:
	var o: Dictionary = Utilities.cfg().get("overdue", {})
	return util == "internet" and int(Economy.missed.get(hid, 0)) >= int(o.get("internet_after_missed", 1)) and int(o.get("internet_after_missed", 1)) > 0

static func why_off(util: String, hid: int) -> String:
	if util == "internet":
		if _bill_cut("internet", hid):
			return "the bills are overdue"
		if not has_power(hid):
			return "no power for the router"
	return "a fault"

static func water_safe(hid: int) -> bool:
	if not Utilities.boil_active(zone(hid)):
		return true
	return has_well(hid) or int(Utilities.boiled.get(str(hid), 0)) > SysUtil.now()

## The player boils a batch of water: safe to drink for a while.
static func boil_water(hid: int) -> void:
	var hrs: int = int((Utilities.cfg().get("boil", {}) as Dictionary).get("boiled_hours", 12))
	Utilities.boiled[str(hid)] = SysUtil.now() + hrs * 60
	refresh(hid)

# ------------------------------------------------------------------ people
static func members(hid: int) -> Array:
	var out: Array = []
	for f in WorldIface.all_folk():
		if int(f.household_id) == hid and not bool(f.has_meta("visitor")):
			out.append(f)
	return out

static func _rec(hid: int) -> Dictionary:
	if not state.has(str(hid)):
		state[str(hid)] = {"power": true, "water": true, "phone": true, "online": true, "boil": false, "lamps": []}
	return state[str(hid)]

## Bring the markers, lamps and buffs of the household in line with what it has now. Cheap when nothing changed.
static func refresh(hid: int) -> void:
	var rec: Dictionary = _rec(hid)
	var now_has: Dictionary = {"power": has_power(hid), "water": has_water(hid), "phone": has_phone(hid), "online": has_online(hid)}
	var boil_on: bool = Utilities.boil_active(zone(hid)) and not water_safe(hid)
	var changed: bool = boil_on != bool(rec["boil"])
	for k in MARKERS:
		if bool(now_has[k]) != bool(rec[k]):
			changed = true
	var all_ok: bool = bool(now_has["power"]) and bool(now_has["water"]) and bool(now_has["phone"]) and bool(now_has["online"]) and not boil_on
	if not changed and all_ok:
		return
	if not bool(now_has["power"]) and bool(rec["power"]):
		_lamps_off(hid, rec)
	if bool(now_has["power"]) and not bool(rec["power"]):
		_lamps_on(rec)
	for f in members(hid):
		for k2 in MARKERS:
			var b: String = str(MARKERS[k2])
			if not bool(now_has[k2]):
				if not f.has_buff(b):
					f.add_buff(b)
			elif f.has_buff(b):
				f.remove_buff(b)
		if boil_on:
			if not f.has_buff("boil_notice"):
				f.add_buff("boil_notice")
		elif f.has_buff("boil_notice"):
			f.remove_buff("boil_notice")
	for k3 in MARKERS:
		rec[k3] = now_has[k3]
	rec["boil"] = boil_on
	if all_ok and not bool(rec.get("keep", false)):
		state.erase(str(hid))

static func _lamps_off(hid: int, rec: Dictionary) -> void:
	var off: Array = []
	for lamp_def in LAMPS:
		for o in defs_of(hid).get(lamp_def, []):
			if bool(WorldIface.state_get(o, "on", false)):
				WorldIface.state_set(o, "on", false)
				off.append(int(o.id))
	rec["lamps"] = off
	rec["since"] = SysUtil.now()

static func _lamps_on(rec: Dictionary) -> void:
	for oid in rec.get("lamps", []):
		var o = WorldIface.get_object(int(oid))
		if o != null and not bool(WorldIface.state_get(o, "broken", false)):
			WorldIface.state_set(o, "on", true)
	rec["lamps"] = []

static func mark_boil(hid: int) -> void:
	refresh(hid)

static func clear_boil(hid: int) -> void:
	refresh(hid)

# ------------------------------------------------------------------ outage start / end
static func on_start(o: Dictionary) -> void:
	forget_cache()
	var zone_id: String = str(o["zone"])
	var util: String = str(o["util"])
	for hid in CityState.full_households():
		if CityState.zone_of_household(int(hid)) != zone_id:
			continue
		var h: int = int(hid)
		if util == "water" and tank_hours(h) > 0.0 and not Utilities.reserve.has(str(h)):
			Utilities.reserve[str(h)] = tank_hours(h)
		if util == "power" and generator(h) != null:
			SysUtil.notify("The power failed, but your generator kicked in and the lights stay on.", "good")
		refresh(h)
	_townie_lots(o)

## Far townie lots: one line each in the lot's history, nothing else (statistical).
static func _townie_lots(o: Dictionary) -> void:
	var cap: int = int(Utilities.cfg().get("townie_lot_cap", 6))
	for n in range(1, cap + 1):
		if CityState.zone_of_town_lot(n) == str(o["zone"]):
			DisasterState.note_lot_event("town:%d" % n, "utility", "No %s for a while." % Utilities.short(str(o["util"])))

static func on_end(o: Dictionary) -> void:
	forget_cache()
	for hid in CityState.full_households():
		if CityState.zone_of_household(int(hid)) == str(o["zone"]):
			refresh(int(hid))

# ------------------------------------------------------------------ the hour
static func on_hour() -> void:
	var u: Dictionary = Utilities.cfg()
	var res: Dictionary = u.get("resilience", {})
	for hid in CityState.full_households():
		var h: int = int(hid)
		var z: String = zone(h)
		var water_down: bool = Utilities.is_down("water", z)
		var power_down: bool = Utilities.is_down("power", z)
		if not (water_down or power_down or state.has(str(h)) or Utilities.reserve.has(str(h))):
			continue
		forget_cache()
		_tank(h, water_down, res)
		if power_down:
			_backup_burn(h, res)
		refresh(h)
		var rec: Dictionary = _rec(h)
		if not bool(rec["power"]):
			_dark_hour(h, rec, res)
	for k in state.keys():
		if bool((state[k] as Dictionary).get("power", true)) and bool((state[k] as Dictionary).get("water", true)) \
				and bool((state[k] as Dictionary).get("phone", true)) and bool((state[k] as Dictionary).get("online", true)) and not bool((state[k] as Dictionary).get("boil", false)):
			state.erase(k)

static func _tank(hid: int, water_down: bool, res: Dictionary) -> void:
	var cap: float = tank_hours(hid)
	var key: String = str(hid)
	if cap <= 0.0:
		Utilities.reserve.erase(key)
		return
	var cur: float = float(Utilities.reserve.get(key, cap))
	if water_down:
		cur = maxf(cur - 1.0, 0.0)
	else:
		cur = minf(cur + float(res.get("tank_refill_per_hour", 6)), cap)
	if cur >= cap:
		Utilities.reserve.erase(key)
	else:
		Utilities.reserve[key] = cur

static func _backup_burn(hid: int, res: Dictionary) -> void:
	var g = generator(hid)
	if g == null or DisasterState.running("outage"):            # the disaster layer burns the fuel of its own power cuts
		return
	WorldIface.state_add(g, "fuel", -float(res.get("generator_fuel_per_hour", 1.0)))
	if float(WorldIface.state_get(g, "fuel", 0.0)) <= 0.0:
		SysUtil.notify("The generator ran out of fuel. The power is off again.", "warn")

static func _dark_hour(hid: int, rec: Dictionary, res: Dictionary) -> void:
	var hours: float = float(SysUtil.now() - int(rec.get("since", SysUtil.now()))) / 60.0
	var pseudo: Dictionary = {"data": rec}
	if hours >= float(res.get("spoil_after_hours", 2)):
		DisasterEvents._spoil_fridge(hid, pseudo, float(res.get("spoil_chance", 0.5)))
	if Weather.temperature() < float(DisasterState.cfg("outage").get("cold_below", 8.0)):
		DisasterEvents._chill(hid)

# ------------------------------------------------------------------ the day
static func on_day() -> void:
	var b: Dictionary = Utilities.cfg().get("boil", {})
	for hid in CityState.full_households():
		var h: int = int(hid)
		if not Utilities.boil_active(zone(h)) or water_safe(h):
			continue
		for f in members(h):
			if CityState.chance(float(b.get("ill_chance_per_day", 0.07))):
				Health.fall_ill(f, "food_poisoning", 1, "unsafe tap water")
				Utilities.count("boil_ill")
