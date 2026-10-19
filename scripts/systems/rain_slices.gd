class_name RainSlices
extends RefCounted
## The plants' share of a rainy hour, spread over the clock (task 17.4). WeatherWorld._hourly_objects only counts one owed rain hour per lot
## (`Weather._rain_deferred`, saved with the weather); this minute row waters the lots near an anchor a few per minute, so no frame pays for every
## lot's room test and plant writes at once (a rainy hour was 100-400 ms in the big town). Lots that stay far away keep their count and are caught
## up by the daily pass (WeatherWorld.on_day -> DaySlices).
## Tier behaviour: places only. Lots near an anchor (Tiers.lot_distances) are watered here, far lots by the daily catch-up. Cadence: minute row
## "WeatherWorld.rain", gated by "something is owed" (idle = zero cost). Caps: at most 60 lots exist; at most max(MIN_BATCH, pending / SPREAD) lots are watered per minute.

const MIN_BATCH := 2                  # lots watered per minute at least (every lot owed is paid within about 30 minutes)
const SPREAD := 12                    # a long list is paid at pending / SPREAD lots a minute

static var _job: SimJob = null
static var _sched_id: int = 0

static func install(sched: SimScheduler, group: String) -> void:
	_sched_id = sched.get_instance_id()
	_job = sched.add("WeatherWorld.rain", "WeatherWorld", group, 1, 215, SimScheduler.NORMAL, RainSlices.run, "", Callable(RainSlices, "active"),
		"plants of the lots near an anchor catch the owed rain a few lots per minute (far lots: the daily catch-up)")

static func enabled() -> bool:
	return _job != null and not _job.removed and _job.enabled and SimScheduler.of(SimEnv.clock()).get_instance_id() == _sched_id

static func active() -> bool:
	return not Weather._rain_deferred.is_empty()

## Lots owed rain that are near an anchor now, in lot-name order (cheap: the near table is cached by Tiers; the plant index is only touched for the street).
static func due_lots() -> Array:
	var out: Array = []
	var anchored: bool = not Tiers.anchors.is_empty()
	var near: Dictionary = Tiers.lot_distances(int(Tiers.cfg().get("near_radius", 64))) if anchored else {}
	for lot in Weather._rain_deferred.keys():
		var l: String = str(lot)
		if not anchored or (near.has(l) if l != "" else not WeatherWorld.lot_is_far(l, WeatherWorld._rain_by_lot().get(l, {"plants": []}))):
			out.append(l)
	out.sort()
	return out

static func run() -> void:
	var due: Array = due_lots()
	if due.is_empty():
		return
	var n: int = maxi(MIN_BATCH, ceili(float(due.size()) / float(SPREAD)))
	for i in mini(n, due.size()):
		var lot: String = due[i]
		WeatherWorld.water_lot(lot, int(Weather._rain_deferred.get(lot, 0)))
		Weather._rain_deferred.erase(lot)
