class_name Traffic
extends RefCounted
## Road-risk hook for accidents (task 05). Ambient traffic (phase 5) does not exist yet, so the risk of being hit is a RULE on road tiles
## that phase 5 can replace: set `Traffic.provider` to a Callable (tile: Vector2i, hour: float) -> float (0..1 "chance a car is
## really there") and the rule below is skipped. Everything else (markers, the traffic_hit incidents) stays the same.
##   Traffic.risk_at(tile, hour) -> 0..1      Traffic.road_kind(tile) -> "" | "asphalt" | "crosswalk"
## Data: config.accidents.traffic in data/incidents/05_accidents.json (night / dusk / day exposure, crosswalk and jaywalking factors).

static var provider: Callable = Callable()
## Tests (no World floors): tile -> floor name.
static var test_floors: Dictionary = {}

static func cfg() -> Dictionary:
	return (IncidentDefs.cfg("accidents", {}) as Dictionary).get("traffic", {})

## "asphalt" / "crosswalk" for a road tile, else "".
static func road_kind(tile: Vector2i) -> String:
	var fl: String = ""
	if test_floors.has(tile):
		fl = str(test_floors[tile])
	else:
		var w = WorldIface.world()
		if w != null and w.has_method("get_floor"):
			fl = str(w.get_floor(tile))
	return fl if (fl == "asphalt" or fl == "crosswalk") else ""

## Chance that a car is really coming for somebody standing on `tile` at `hour` (0 off the road).
static func risk_at(tile: Vector2i, hour: float) -> float:
	var kind: String = road_kind(tile)
	if kind == "":
		return 0.0
	if provider.is_valid():
		return clampf(float(provider.call(tile, hour)), 0.0, 1.0)
	return clampf(risk_for_hour(hour, kind) * TransportTraffic.tile_mult(tile, hour, kind), 0.0, 1.0)      # task 12: traffic lights at the junctions

## The built-in rule without a tile (far townies): night is the dangerous time, jaywalking beats the crosswalk.
static func risk_for_hour(hour: float, kind: String = "crosswalk") -> float:
	var c: Dictionary = cfg()
	var base: float = float(c.get("day", 0.25))
	if hour >= float(c.get("night_from", 21.0)) or hour < float(c.get("night_to", 5.0)):
		base = float(c.get("night", 1.0))
	elif hour >= float(c.get("dusk_from", 18.0)) or hour < float(c.get("dawn_to", 7.0)):
		base = float(c.get("dusk", 0.5))
	if kind == "asphalt":
		base *= float(c.get("jaywalk_factor", 1.6))
	return clampf(base, 0.0, 1.0)
