class_name CityState
extends RefCounted
## Task 12 (city infrastructure): the one save block `systems.city` and the shared helpers of every city system.
##   utilities  Utilities.to_dict()    outages per zone, boil notices, history
##   transport  Transport.to_dict()    cars, parking, tows, bus service, road works, traffic lights   (added by the transport slice)
##   services   CityServices.to_dict() calls answered by the fire / ambulance / police stations     (emergency slice)
##   gov        CityGov.to_dict()      budget, mayor, council, elections, policies                      (government slice)
## Zones: the town is cut into a few districts (data/city.json `zones`). A household belongs to a zone by its id, a townie lot by its number,
## so the network layers can hit "the east side" while far townies are only summarised. Tier behaviour of every city system: the player's
## household(s) are FULL (real objects, buffs, bills); townie lots are STATISTICAL (a one-line lot event, no per-person work); nothing loops
## all folk or all objects in a clock hook.

const SEED := 1212

static var rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func reset() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = SEED
	UtilityEvents.dice_on = true
	Utilities.reset()
	Transport.reset()
	CityServices.reset()

static func on_game_event(ev: String, payload: Dictionary) -> void:
	Utilities.on_event(ev, payload)
	CityCmd.on_event(ev, payload)

static func cfg() -> Dictionary:
	return SysUtil.table("city")

static func to_dict() -> Dictionary:
	return {"rng_seed": str(rng.seed), "rng_state": str(rng.state), "utilities": Utilities.to_dict(), "transport": Transport.to_dict(), "services": CityServices.to_dict()}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	rng.seed = int(str(d.get("rng_seed", SEED)))
	rng.state = int(str(d.get("rng_state", rng.state)))
	Utilities.from_dict(d.get("utilities", {}))
	Transport.from_dict(d.get("transport", {}))
	CityServices.from_dict(d.get("services", {}))

# ------------------------------------------------------------------ zones
static func zones() -> Array:
	return cfg().get("zones", [])

static func zone_ids() -> Array:
	var out: Array = []
	for z in zones():
		out.append(str((z as Dictionary).get("id", "")))
	return out

static func zone_label(zone: String) -> String:
	for z in zones():
		if str((z as Dictionary).get("id", "")) == zone:
			return str((z as Dictionary).get("label", zone))
	return zone

static func zone_of_household(hid: int) -> String:
	var ids: Array = zone_ids()
	if ids.is_empty():
		return ""
	return str(ids[posmod(maxi(hid, 1) - 1, ids.size())])

static func zone_of_town_lot(n: int) -> String:
	var ids: Array = zone_ids()
	if ids.is_empty():
		return ""
	return str(ids[posmod(n, ids.size())])

## The households that are simulated for real (the players' homes; everyone else is a statistical townie lot).
static func full_households() -> Array:
	var out: Array = []
	for pid in Players.ids():
		var h: int = Players.household_of(int(pid))
		if h > 0 and not out.has(h):
			out.append(h)
	if out.is_empty():
		out.append(Players.primary_household())
	return out

## Seeded dice that are part of the saved state (same seed + same commands = same town).
static func chance(p: float) -> bool:
	return rng.randf() < p

static func range_i(a: Array) -> int:
	return rng.randi_range(int(a[0]), int(a[1]))
