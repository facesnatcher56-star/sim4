class_name WearWalls
extends RefCounted
## Task 41a (view only): the grime strength (0..1) of one wall edge for WearShader: its lot's wear / poverty (WearLayer), strong on an outside face, lighter indoors.

## `e` is a World.walls key (x, y, 0 = along x at the top of tile (x, y), 1 = along y at the left of tile (x, y)).
static func wear_of_edge(e: Vector3i) -> float:
	var a := Vector2i(e.x, e.y)
	var b := Vector2i(e.x, e.y - 1) if e.z == 0 else Vector2i(e.x - 1, e.y)
	var lot := NeighborhoodLots.lot_at(a)
	if lot == "":
		lot = NeighborhoodLots.lot_at(b)
	var lw: float = WearLayer.lot_wear(lot) if lot != "" else 0.0
	var exterior: bool = World.rooms.is_outdoor(a) or World.rooms.is_outdoor(b)
	return WearRules.wall_wear(lw, exterior) - float((WearRules.cfg().get("wall", {}) as Dictionary).get("base", 0.1))
