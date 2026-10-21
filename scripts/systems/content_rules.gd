class_name ContentRules
extends RefCounted
## Data-driven daily rules for the extra content (data/content_rules.json + state-spec keys in data/objects.json).
## Called once per game day from Careers.on_day. Object state specs may carry:
##   "daily_add": n               add n to the value each day (negative = drain; clamped to min/max)
##   "daily_requires": [key, min] only add when another state key is >= min (e.g. garden growth needs water)
##   "daily_reset": v             set the value to v each day (e.g. the fireplace burns out)
##   "spoil_per_day": r           (on a stock key) each day floor(stock * r) items spoil; the fraction is a chance.
##                                "spoiled_key" counts rotten items awaiting disposal, "spoil_dirt_key" gets mess.
## New skills (guitar, piano, gardening, fishing, writing) need no registration: Folk.add_skill_xp creates them on first use.
## They are listed in content_rules.json "skills" so UI code can show labels.

static func cfg() -> Dictionary:
	return SysUtil.table("content_rules")

static func skill_ids() -> Array:
	return (cfg().get("skills", {}) as Dictionary).keys()

static func skill_label(skill: String) -> String:
	return str((cfg().get("skills", {}) as Dictionary).get(skill, {}).get("label", skill.capitalize()))

static func _all_objects() -> Array:
	var w = WorldIface.world()
	if w == null:
		return []
	if w.has_method("all_objects"):
		return w.all_objects()
	if "objects" in w and w.objects is Dictionary:
		return (w.objects as Dictionary).values()
	return []

static var _last_spoil_toast: int = -99

static func reset() -> void:
	_last_spoil_toast = -99
	_daily_memo = {}

static func on_day(_day: int) -> void:
	var spoiled_total: int = 0
	for o in _all_objects():
		if _has_daily(str(o.def_id)):               # only the few object kinds with a daily rule (the other 90% cost one lookup, not a state walk)
			var n_sp: int = apply_object_day(o)
			if not SoloHome.active or int(Economy.owner.get(int(o.id), -1)) == Economy.primary_household():
				spoiled_total += n_sp          # the toast is about YOUR fridge, not every fridge in town
	if spoiled_total > 0:
		var st: Dictionary = cfg().get("spoil_toast", {})
		if spoiled_total >= int(st.get("min_items", 4)) and _day - _last_spoil_toast >= int(st.get("gap_days", 3)):
			_last_spoil_toast = _day
			SysUtil.notify("A lot of food in the fridge went bad.", "warn")

static var _daily_memo: Dictionary = {}        # object def id -> does any state key carry a daily rule?

static func _has_daily(def_id: String) -> bool:
	if _daily_memo.has(def_id):
		return bool(_daily_memo[def_id])
	var spec: Dictionary = SimEnv.data().object_def(def_id).get("state", {})
	var yes := false
	for key in spec:
		var sd: Variant = spec[key]
		if sd is Dictionary and ((sd as Dictionary).has("daily_reset") or (sd as Dictionary).has("daily_add") or (sd as Dictionary).has("spoil_per_day")):
			yes = true
			break
	_daily_memo[def_id] = yes
	return yes

## Apply the daily rules to one object. Returns the number of items that spoiled.
static func apply_object_day(o) -> int:
	var def: Dictionary = SimEnv.data().object_def(str(o.def_id))
	var spec: Dictionary = def.get("state", {})
	var lost_total: int = 0
	for key in spec:
		var s: Variant = spec[key]
		if not (s is Dictionary):
			continue
		var sd: Dictionary = s
		if sd.has("daily_reset"):
			if WorldIface.state_get(o, str(key), null) != sd["daily_reset"]:
				WorldIface.state_set(o, str(key), sd["daily_reset"])
		if sd.has("daily_add"):
			var ok: bool = true
			if sd.has("daily_requires"):
				var rq: Array = sd["daily_requires"]
				ok = float(WorldIface.state_get(o, str(rq[0]), 0.0)) >= float(rq[1])
			if ok:
				WorldIface.state_add(o, str(key), float(sd["daily_add"]))
		if sd.has("spoil_per_day"):
			lost_total += _spoil(o, str(key), sd)
	return lost_total

static func _spoil(o, key: String, sd: Dictionary) -> int:
	var stock: float = float(WorldIface.state_get(o, key, 0.0))
	if stock <= 0.0:
		return 0
	var rate: float = float(sd["spoil_per_day"])
	if bool(WorldIface.state_get(o, "broken", false)):
		rate *= 2.0   # a broken fridge does not keep things cold
	var exact: float = stock * rate
	var lost: int = int(floor(exact))
	if SysUtil.rng.randf() < exact - float(lost):
		lost += 1
	lost = mini(lost, int(stock))
	if lost <= 0:
		return 0
	WorldIface.state_add(o, key, -float(lost))
	if sd.has("spoiled_key"):
		WorldIface.state_add(o, str(sd["spoiled_key"]), float(lost))
	if sd.has("spoil_dirt_key"):
		WorldIface.state_add(o, str(sd["spoil_dirt_key"]), 0.5 * float(lost))
	SysUtil.game_event("food_spoiled", {"folk_id": -1, "object_id": int(o.id), "items": lost})
	return lost