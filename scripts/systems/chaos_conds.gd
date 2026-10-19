class_name ChaosConds
extends RefCounted
## The `chaos` condition key of incidents (IncidentCond hands it over): a dictionary, all entries must hold.
##   plumbing true        the home has a sink / toilet / bath / shower / washer (far lots: always)
##   appliance true       the home has a working appliance that can break (far lots: always)
##   messy_at_least N     dirty dishes, spoiled food, full bins: a mess score (far lots: a quarter of them are messy in any given week)
##   pests_below X        roach level lower than X          pests_at_least X   roach level at least X
##   pest_free true|false   an exterminator was here lately
##   leaking true|false   water is running right now
## Real lots read the real objects; far lots have no objects, so the answers are fixed by data / a stable hash (the statistical version).

const FIXTURES := ["sink", "toilet", "bathtub", "shower", "washing_machine"]

static func check(v: Variant, subj) -> bool:
	if not (v is Dictionary):
		return false
	var hid: int = subj.household_id
	var home: bool = str(subj.lot_key).begins_with("home:")
	for key in v:
		var want: Variant = v[key]
		var ok := false
		match str(key):
			"plumbing":
				ok = (not home or not fixtures(hid).is_empty()) == bool(want)
			"appliance":
				ok = (not home or not appliances(hid).is_empty()) == bool(want)
			"messy_at_least":
				ok = (mess_score(hid) if home else far_mess(str(subj.lot_key))) >= int(want)
			"pests_below":
				ok = ChaosState.pest_level(hid) < float(want)
			"pests_at_least":
				ok = ChaosState.pest_level(hid) >= float(want)
			"pest_free":
				ok = (int((ChaosState.pests.get(str(hid), {}) as Dictionary).get("free_until", -1)) > SysUtil.day()) == bool(want)
			"leaking":
				ok = (not ChaosState.leak_of(hid).is_empty()) == bool(want)
		if not ok:
			return false
	return true

static func fixtures(hid: int) -> Array:
	return _objs(hid, FIXTURES, false)

static func appliances(hid: int) -> Array:
	return _objs(hid, ChaosState.cfg("appliance").get("objects", []), true)

static func _objs(hid: int, ids: Array, working_only: bool) -> Array:
	var out: Array = []
	for o in Economy.objects_of(hid):
		if ids.has(str(o.def_id)) and not (working_only and bool(WorldIface.state_get(o, "broken", false))):
			out.append(o)
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out

## Mess the roaches like: a dirty surface counts 1, a fridge with spoiled food 2, an overflowing bin 1.
static func mess_score(hid: int) -> int:
	var c: Dictionary = ChaosState.cfg("pests")
	var n := 0
	for o in Economy.objects_of(hid):
		var id: String = str(o.def_id)
		if id == "trash_bin":
			n += 1 if float(WorldIface.state_get(o, "fullness", 0.0)) >= float(c.get("bin_full", 7.0)) else 0
			continue
		if id == "fridge" and float(WorldIface.state_get(o, "spoiled", 0.0)) > 0.0:
			n += 2
		if float(WorldIface.state_get(o, "dirtiness", 0.0)) >= float(c.get("dirty_at", 6.0)):
			n += 1
	return n

static func far_mess(lot_key: String) -> int:
	var week: int = SysUtil.day() / 7
	return 3 if absi(("%s:%d" % [lot_key, week]).hash()) % 100 < int(ChaosState.cfg("pests").get("far_messy_pct", 25)) else 0
