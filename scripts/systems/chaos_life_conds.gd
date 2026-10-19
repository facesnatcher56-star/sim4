class_name ChaosLifeConds
extends RefCounted
## More keys of the `chaos` condition (task 07b); ChaosConds hands every key it does not know to `check_key`. All entries of one `chaos` dictionary must hold.
##   gas true            the home has a stove that can leak (far lots: always)
##   damp true           a damp home: wet bathroom surfaces, long rain, or water damage not yet repaired (far lots: a fifth of them in any given week)
##   mould_below X       the mould level of the home is lower than X (far lots: true)
##   employed true       the person has a job (townie records: a career)
##   midlife true        an adult in their middle years (age window in config.chaos.life)
##   unhappy_days_at_least N / unhappy_days_below N      days in a row a teen has been miserable (ChaosTeen)
##   behind true         bills overdue AND something was already repossessed lately (ChaosMoney.behind)
##   theft_open false    no identity theft waits to be sorted out
##   estate_relative true   a real, old relative of somebody in the home has an estate to leave (ChaosKin)
##   performing true     doing well at work (career performance at the configured mark)
##   tickets true        the household holds market lottery tickets (BankGamble)
## Real homes read the real objects and records; far subjects have none, so they answer with data or a stable hash (the statistical version).

static func check_key(key: String, want: Variant, subj) -> bool:
	var hid: int = subj.household_id
	var home: bool = str(subj.lot_key).begins_with("home:")
	match key:
		"gas":
			return (not home or has_stove(hid)) == bool(want)
		"damp":
			return (damp(hid) if home else far_damp(str(subj.lot_key))) == bool(want)
		"mould_below":
			return not home or mould_of(hid) < float(want)
		"employed":
			return employed(subj) == bool(want)
		"midlife":
			return midlife(subj) == bool(want)
		"unhappy_days_at_least":
			return subj.folk != null and int(ChaosState.unhappy.get(int(subj.folk.id), 0)) >= int(want)
		"unhappy_days_below":
			return subj.folk == null or int(ChaosState.unhappy.get(int(subj.folk.id), 0)) < int(want)
		"behind":
			return home and ChaosMoney.behind(hid) == bool(want)
		"theft_open":
			return ChaosState.theft.has(hid) == bool(want)
		"estate_relative":
			return home and (ChaosKin.estate_relative(hid) != null) == bool(want)
		"performing":
			return subj.folk != null and (CareerProgress.performance_of(int(subj.folk.id)) >= float(ChaosState.cfg("life").get("performing_at", 75))) == bool(want)
		"tickets":
			return home and (BankGamble.tickets_of(hid) > 0) == bool(want)
	return false

static func has_stove(hid: int) -> bool:
	for o in Economy.objects_of(hid):
		if str(o.def_id) == "stove":
			return true
	return false

static func mould_of(hid: int) -> float:
	return float((DisasterState.lots.get("home:%d" % hid, {}) as Dictionary).get("mould", 0.0))

## Wet surfaces in a home that has water fixtures: a dirty bath / sink / washer, a long run of rainy days, or flood water that was never dealt with.
static func damp(hid: int) -> bool:
	var c: Dictionary = ChaosState.cfg("mould")
	var wet := false
	var dirty := false
	for o in Economy.objects_of(hid):
		var id: String = str(o.def_id)
		if ChaosConds.FIXTURES.has(id):
			wet = true
			if float(WorldIface.state_get(o, "dirtiness", 0.0)) >= float(c.get("dirty_at", 6.0)):
				dirty = true
	if not wet:
		return false
	var flood: float = float((DisasterState.lots.get("home:%d" % hid, {}) as Dictionary).get("flood", 0.0))
	return dirty or flood >= float(c.get("flood_at", 0.05)) or DisasterState.rain_days >= int(c.get("rain_days", 4))

static func far_damp(lot_key: String) -> bool:
	var week: int = SysUtil.day() / 7
	return absi(("damp:%s:%d" % [lot_key, week]).hash()) % 100 < int(ChaosState.cfg("mould").get("far_damp_pct", 20))

static func employed(subj) -> bool:
	if subj.folk != null:
		return Careers.has_job(int(subj.folk.id))
	return subj.kind == "townie" and str(subj.t().get("career", "")) != ""

static func midlife(subj) -> bool:
	var id: int = int(subj.folk.id) if subj.folk != null else int(subj.id)
	if subj.kind == "lot" or id < 0:
		return false
	var c: Dictionary = ChaosState.cfg("life")
	var age: float = Family.age_days_of(id)
	return age >= float(c.get("midlife_from", 112)) and age <= float(c.get("midlife_to", 148))
