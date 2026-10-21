class_name WalkThen
extends RefCounted
## Walk up to a spot, then do something (task 53: the car door, the shop shelf, the till). If the pawn is already there, or there is no route, it is done at once.
## A cancelled walk drops it.   WalkThen.go(f, tile, then: Callable)      WalkThen.near(tile) -> a walkable tile next to it

static var pending: Dictionary = {}          # fid -> Callable

static func reset() -> void:
	pending = {}

static func go(f, tile: Vector2i, then: Callable) -> void:
	pending.erase(int(f.id))
	if f.tile == tile or not NeighborhoodLots.walk_to(f, tile, ""):
		then.call()
		return
	pending[int(f.id)] = then

static func waiting(fid: int) -> bool:
	return pending.has(fid)

static func near(tile: Vector2i) -> Vector2i:
	var w = WorldIface.world()
	if w == null or w.is_walkable(tile):
		return tile
	for rad in range(1, 4):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) == rad and w.is_walkable(tile + Vector2i(dx, dy)):
					return tile + Vector2i(dx, dy)
	return tile

static func on_interaction_finished(folk_id: int, iid: String, success: bool) -> void:
	if iid != "go_here" or not pending.has(folk_id):
		return
	var then: Callable = pending[folk_id]
	pending.erase(folk_id)
	if success:
		then.call()
