class_name LevelElevators
extends RefCounted
## Waiting for and sharing a lift. A lift (def.capacity, default 4) carries that many folk per trip; every route that uses it is BOOKED
## for the duration of its ride. Folk beyond the capacity wait for the next trip (CYCLE_MIN game minutes each full car ahead of them),
## and the route cost shows the queue so autonomy prefers the stairs when the lift is busy. Out of order (object state
## `out_of_order` or `broken`) = the lift is not part of the routing graph at all.
## Bookings are transient (not saved): a loaded game starts with an idle lift.

const BOARD_MIN := 0.25               # game minutes for the doors + boarding
const CYCLE_MIN := 0.8                # game minutes one full trip ahead of you costs
const MIN_PER_LEVEL := 0.1            # game minutes of riding per level
const UNITS_PER_MIN := 1.0 / 0.3      # route-cost units per game minute (Interaction.WALK_MIN_PER_TILE)

var world: WorldGrid
var _book: Dictionary = {}            # object id -> Array of [folk_id, until_min]


func _init(w: WorldGrid) -> void:
	world = w


func reset() -> void:
	_book.clear()


func forget(oid: int) -> void:
	_book.erase(oid)


func capacity(oid: int) -> int:
	var o = world.objects.get(oid, null)
	return 4 if o == null else maxi(1, int(o.def.get("capacity", 4)))


func _alive(oid: int, now: float) -> Array:
	var arr: Array = _book.get(oid, [])
	var keep: Array = []
	for b in arr:
		if float(b[1]) > now:
			keep.append(b)
	if keep.size() != arr.size():
		_book[oid] = keep
	return keep


## Folk currently riding / waiting.
func riders(oid: int) -> int:
	return _alive(oid, SimEnv.now_min()).size()


## Extra game minutes a new rider waits right now (0 while the car has room).
func wait_minutes(oid: int) -> float:
	var n := riders(oid)
	var cap := capacity(oid)
	if n < cap:
		return 0.0
	return float((n / cap)) * CYCLE_MIN + CYCLE_MIN * 0.5


func wait_units(oid: int) -> float:
	return wait_minutes(oid) * UNITS_PER_MIN


## A folk takes the lift for `ride_min` minutes starting after `start_min`. Returns the extra waiting time (minutes).
func book(oid: int, folk_id: int, start_min: float, ride_min: float) -> float:
	var now := SimEnv.now_min()
	var w := wait_minutes(oid)
	var arr := _alive(oid, now)
	var until := now + start_min + w + BOARD_MIN + ride_min
	for b in arr:
		if int(b[0]) == folk_id:
			b[1] = until
			return w
	arr.append([folk_id, until])
	_book[oid] = arr
	return w


## Book every lift ride on a route (entries are Vector3i; an elevator ride = two consecutive entries on the same tile at
## different levels, where the tile belongs to an elevator object). Returns the total extra waiting minutes.
func book_route(route: Array, folk_id: int, walk_min_per_step: float) -> float:
	var extra := 0.0
	for i in range(1, route.size()):
		var a: Vector3i = route[i - 1]
		var b: Vector3i = route[i]
		if a.x == b.x and a.y == b.y and a.z != b.z:
			var oid := lift_at(Vector2i(a.x, a.y), a.z)
			if oid >= 0:
				var ride := BOARD_MIN + MIN_PER_LEVEL * float(absi(a.z - b.z))
				extra += book(oid, folk_id, walk_min_per_step * float(i), ride)
				extra += ride
	return extra


## Object id of the elevator whose shaft contains (tile, level), -1 none.
func lift_at(tile: Vector2i, level: int) -> int:
	for rec in world.portals.portals.values():
		if str(rec["kind"]) == "elevator" and (rec["tile"] as Vector2i) == tile and level >= int(rec["base"]) and level <= int(rec["top"]):
			return int(rec["id"])
	return -1
