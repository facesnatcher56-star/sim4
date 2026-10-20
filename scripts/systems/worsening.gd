class_name Worsening
extends RefCounted
## Task 34: which conditions really get worse with time (data/worsening.json). One question for every rule: "why would this happen?".
##   Worsening.cause(reason) -> {id, ambulance, worsens, why, worsen_after, worsen_chance, strain}    the first row whose words appear in the reason
##   Worsening.needs_ambulance(reason, severity) -> bool      Worsening.worsens(reason) -> bool      Worsening.why(reason) -> String
##   Worsening.strain_extra(folk) -> float     extra minutes a minor injury loses per minute of walking or working on it (it heals slower)
## A sprain never needs an ambulance and never worsens while waiting; bleeding, burns, a heart attack and the like do.

static func cfg() -> Dictionary:
	return SysUtil.table("worsening")

static func cause(reason: String) -> Dictionary:
	var r: String = reason.to_lower()
	var c: Dictionary = cfg()
	for row in c.get("causes", []):
		for w in (row as Dictionary).get("match", []):
			if r.contains(str(w)):
				return row
	return c.get("default", {"id": "other", "ambulance": "by_severity", "worsens": false})

static func needs_ambulance(reason: String, severity: int) -> bool:
	var mode: String = str(cause(reason).get("ambulance", "by_severity"))
	if mode == "never":
		return false
	if mode == "always":
		return true
	return severity >= int(CityServices.cfg().get("ambulance", {}).get("hold_from_severity", 2))

static func worsens(reason: String) -> bool:
	return bool(cause(reason).get("worsens", false))

static func why(reason: String) -> String:
	return str(cause(reason).get("why", ""))

## A person with a minor injury who keeps walking or working on it heals slower.
static func strain_extra(f) -> float:
	if f == null or f.current == null:
		return 0.0
	var sc: Dictionary = cfg().get("strain", {})
	var cur = f.current
	if str(cur.state) == "walking":
		return float(sc.get("extra_per_min_walking", 0.5))
	var tags: Array = (cur.def as Dictionary).get("tags", [])
	if tags.has("work") or tags.has("exercise") or tags.has("physical"):
		return float(sc.get("extra_per_min_working", 0.5))
	return 0.0
