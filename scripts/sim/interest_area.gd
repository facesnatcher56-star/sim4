class_name InterestArea
extends RefCounted
## Geometry of "interest" (task 17.3, stage 1): how close a position is to the people the player cares about (the ANCHORS: every non-away folk of a
## controlled household and the camera focus), with cheap line-of-sight rules instead of ray casts:
##   * same lot as an anchor                                   -> ACTIVE (a lot is one room for line of sight purposes)
##   * both outdoors (street / open ground) within active_radius -> ACTIVE
##   * a closed building blocks the view: from inside a building only the street right outside it (within adjacent_rect of its rectangle) is seen;
##     a person inside a foreign closed lot is ACTIVE only when the anchor stands within adjacent_rect of that lot
##   * open lots (parks: cfg open_lot_types) do not block the view
##   * everything else within near_radius -> NEAR, beyond -> TOWN
## Pure functions of (tile, lot, anchors, cfg): no randomness, no state beyond the lot-rectangle cache.

const ACTIVE := 0
const NEAR := 1
const TOWN := 2
const FAR := 1 << 20

static var _info: Dictionary = {}       # lot id -> {"rect": Rect2i, "open": bool}
static var _rg_id: int = 0
static var _rg_n: int = -1

static func reset() -> void:
	_info.clear()
	_rg_id = 0
	_rg_n = -1

static func _regions():
	var w = WorldIface.world()
	return w.regions if (w != null and "regions" in w) else null

## Lot rectangle + open flag (cached; the cache drops itself when the world's region table changes).
static func lot_info(lot_id: String, open_types: Array) -> Dictionary:
	var rg = _regions()
	var id: int = 0 if rg == null else rg.get_instance_id()
	var n: int = 0 if rg == null else (rg.regions as Dictionary).size()
	if id != _rg_id or n != _rg_n:
		_info.clear()
		_rg_id = id
		_rg_n = n
	if _info.has(lot_id):
		return _info[lot_id]
	var rec := {"rect": NeighborhoodLots.rect_of(lot_id), "open": open_types.has(Venues.type_of_lot(lot_id))}
	_info[lot_id] = rec
	return rec

static func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

static func rect_dist(tile: Vector2i, rc: Rect2i) -> int:
	if rc.size == Vector2i.ZERO:
		return FAR
	var dx := maxi(maxi(rc.position.x - tile.x, tile.x - (rc.end.x - 1)), 0)
	var dy := maxi(maxi(rc.position.y - tile.y, tile.y - (rc.end.y - 1)), 0)
	return maxi(dx, dy)

static func make_anchor(tile: Vector2i) -> Dictionary:
	return {"tile": tile, "lot": NeighborhoodLots.lot_at(tile)}

## Tier of a position (tile, in lot `lot`) seen from ONE anchor: [tier, distance].
static func pair(tile: Vector2i, lot: String, a: Dictionary, c: Dictionary) -> Array:
	var d: int = cheb(tile, a["tile"])
	var alot: String = a["lot"]
	var ar: int = int(c.get("active_radius", 24))
	var adj: int = int(c.get("adjacent_rect", 8))
	var open_types: Array = c.get("open_lot_types", ["park"])
	if lot != "" and lot == alot:
		return [ACTIVE, d]
	if d > int(c.get("near_radius", 64)):
		return [TOWN, d]
	var a_open: bool = alot == "" or bool(lot_info(alot, open_types)["open"])
	if lot == "":
		if a_open:
			return [ACTIVE if d <= ar else NEAR, d]
		return [ACTIVE if rect_dist(tile, lot_info(alot, open_types)["rect"]) <= adj else NEAR, d]
	var info: Dictionary = lot_info(lot, open_types)
	if bool(info["open"]):
		return [ACTIVE if (a_open and d <= ar) else NEAR, d]
	if a_open and rect_dist(a["tile"], info["rect"]) <= adj:
		return [ACTIVE, d]
	return [NEAR, d]

## Best tier over all anchors: [tier, distance score]. No anchors at all = everybody ACTIVE (small worlds / tests without residents behave as before).
static func classify(tile: Vector2i, lot: String, anchors: Array, c: Dictionary) -> Array:
	if anchors.is_empty():
		return [ACTIVE, 0]
	var best_t: int = TOWN
	var best_d: int = FAR
	for a in anchors:
		var r: Array = pair(tile, lot, a, c)
		if int(r[0]) < best_t or (int(r[0]) == best_t and int(r[1]) < best_d):
			best_t = int(r[0])
			best_d = int(r[1])
	return [best_t, best_d]

## Lots whose rectangle is within `radius` of a tile (linear scan over the lot table; callers cache the answer per anchor cell).
static func lots_within(tile: Vector2i, radius: int) -> Array:
	var out: Array = []
	for lot_id in Neighborhood.lot_ids():
		if NeighborhoodLots.distance_to(tile, lot_id) <= radius:
			out.append(lot_id)
	return out
