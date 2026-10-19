class_name StorytellerScan
extends RefCounted
## Lookup cache for ONE card pick (perf, step 17.4 style). While the deck weighs ~100 cards for a key, eligibility asks the same questions over and over
## (who lives in this household, who is on this lot, which lots are in this zone, how wealthy is this key). Each answer was a pass over all folk or all
## townies per card. Nothing in the town changes during a pick (eligibility draws no random numbers and writes nothing), so the answers are memoised
## between begin() and end() and the results are identical. Outside a pick every call goes straight to the source, so tests and cards see live data.

static var _depth: int = 0
static var _lots: Dictionary = {}          # lot -> townie ids (sorted); {} until built
static var _lots_built: bool = false
static var _homes: Dictionary = {}         # hid -> residents
static var _zones: Dictionary = {}         # zone -> lots (sorted)
static var _tiers: Dictionary = {}         # key -> "rich" | "mid" | "poor"

static func begin() -> void:
	if _depth == 0:
		_lots_built = false
		_lots.clear()
		_homes.clear()
		_zones.clear()
		_tiers.clear()
	_depth += 1

static func end() -> void:
	_depth = maxi(_depth - 1, 0)
	if _depth == 0:
		_lots.clear()
		_homes.clear()
		_zones.clear()
		_tiers.clear()
		_lots_built = false

static func active() -> bool:
	return _depth > 0

static func lot_members(n: int) -> Array:
	if not _lots_built:
		for tid in Story.townies:
			var t: Dictionary = Story.townies[tid]
			if bool(t["alive"]):
				var lot: int = int(t.get("lot", 0))
				if not _lots.has(lot):
					_lots[lot] = []
				(_lots[lot] as Array).append(int(tid))
		for lot2 in _lots:
			(_lots[lot2] as Array).sort()
		_lots_built = true
	return (_lots.get(n, []) as Array).duplicate()

static func residents(hid: int, source: Callable) -> Array:
	if not _homes.has(hid):
		_homes[hid] = source.call()
	return (_homes[hid] as Array).duplicate()

static func zone_lots(zone: String, source: Callable) -> Array:
	if not _zones.has(zone):
		_zones[zone] = source.call()
	return (_zones[zone] as Array).duplicate()

static func tier(key: String, source: Callable) -> String:
	if not _tiers.has(key):
		_tiers[key] = source.call()
	return str(_tiers[key])
