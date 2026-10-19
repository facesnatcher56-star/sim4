class_name CityMood
extends RefCounted
## The town's mood about its government (task 12.4): -1 (angry) .. +1 (happy). It is built from things the player can see and change: how fast the services come,
## how often the utilities fail, taxes, crime and the roads. Elections are driven by it: a happy town re-elects the mayor, an angry one turns to whoever promises
## to fix the biggest complaint. `complaint()` names that complaint (the platform tag that answers it).
##   CityMood.update() (daily)    CityMood.parts() -> {services, utilities, tax, crime, roads} each -1 .. +1     CityMood.complaint() -> "crime" | "services" | "tax" | "roads" | "utilities"

static func cfg() -> Dictionary:
	return CityGov.cfg().get("mood", {})

static func parts() -> Dictionary:
	var m: Dictionary = cfg()
	var out: Dictionary = {}
	# services: response times against their targets
	var s: float = 0.0
	var targets: Dictionary = CityServices.cfg().get("targets", {})
	for svc in ["fire", "ambulance", "police"]:
		var t: float = float(targets.get(svc, 10))
		s += clampf((t - CityServices.typical(svc)) / t, -1.0, 1.0)
	out["services"] = clampf(s / 3.0 + 0.2, -1.0, 1.0)
	# utilities: hours down per zone since the last count (a term)
	var down: int = int(Utilities.stats.get("hours_down", 0)) - CityGov.hours_down_mark
	var zones: int = maxi(CityState.zone_ids().size(), 1)
	var days: int = maxi(SysUtil.day() - int(CityGov.mayor.get("since", 0)), 7)
	var per_zone_day: float = float(down) / float(zones) / float(days)
	out["utilities"] = clampf(0.3 - per_zone_day * float(m.get("outage_scale", 25.0)) / 24.0 * 4.0, -1.0, 0.5)
	out["tax"] = clampf((1.0 - CityGov.tax) * 2.0, -1.0, 1.0)
	out["crime"] = clampf((float(m.get("crime_ok", 35.0)) - CrimeRate.value()) / 50.0, -1.0, 1.0)
	out["roads"] = clampf((TransportTraffic.mean_quality() - float(m.get("road_ok", 0.6))) * 3.0, -1.0, 1.0)
	return out

static func update() -> float:
	var w: Dictionary = cfg().get("weights", {})
	var p: Dictionary = parts()
	var total: float = 0.0
	var wsum: float = 0.0
	for k in p:
		total += float(p[k]) * float(w.get(k, 0.2))
		wsum += float(w.get(k, 0.2))
	CityGov.mood_now = clampf(total / maxf(wsum, 0.01) * 1.6, -1.0, 1.0)
	return CityGov.mood_now

static func complaint() -> String:
	var p: Dictionary = parts()
	var worst: String = "services"
	var lo: float = 9.0
	for k in p:
		if float(p[k]) < lo:
			lo = float(p[k])
			worst = str(k)
	return worst

## Approval for the mayor, 0 .. 100 (the town's mood in plain numbers).
static func approval() -> int:
	return int(round(50.0 + CityGov.mood_now * 50.0))

static func words() -> String:
	var a: int = approval()
	if a >= 70:
		return "The town is happy with its mayor."
	if a >= 50:
		return "Most people are content with the mayor."
	if a >= 30:
		return "People are grumbling about the mayor."
	return "The town is angry with its mayor."
