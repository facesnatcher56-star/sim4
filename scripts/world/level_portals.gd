class_name LevelPortals
extends RefCounted
## Ways between levels (`World.portals`): stairs, ladders, elevators, fire escapes. Every object whose def has a `portal` block
## is registered here when it is placed (WorldObjects calls on_created / on_removed) and becomes edges of the routing graph.
##
## def.portal = {"kind": "stairs"|"ladder"|"elevator", "dz": 1 | -1}      (elevators: `span` levels above the placed level in the object)
##   stairs   2x1, rot picks the direction. Footprint f0, f1 on the placed level L; walk on at a = f0 - dir (level L), off at
##            b = f1 + dir (level L+dz). Going up the opening above (f0, f1 on L+1) is a hole (no floor, not walkable).
##   ladder   1x1. Foot a = the tile in front of it on L, top b = the same tile on L+dz; the ladder tile itself is the hatch.
##   elevator 1x1 shaft on every level L .. L+span (WorldObject.span); stop on each level = the tile in front of it. Out of order =
##            state.out_of_order or broken. Capacity / waiting: LevelElevators.
## A record: {id, kind, dz, base, top, tile, stairs: [a, b] endpoints as Vector3i, run: [Vector3i...] walked on the way from a to b,
##            stops: [Vector3i...] (elevator), exterior: bool}.

const STAIR_PEN := 4.0                # route-cost units (1 unit = one tile step) added per level climbed by stairs / ladder
const LADDER_PEN := 6.0
const ELEV_BASE := 4.0                # fixed cost of waiting for / boarding a lift
const ELEV_PER_LEVEL := 1.0

var world: WorldGrid
var portals: Dictionary = {}          # object id -> record
var _run_all: Dictionary = {}         # Vector3i -> slope offset of every staircase / ladder tile
var elevators: LevelElevators


func _init(w: WorldGrid) -> void:
	world = w
	elevators = LevelElevators.new(w)


func reset() -> void:
	portals.clear()
	_run_all.clear()
	elevators.reset()


static func is_portal_def(d: Dictionary) -> bool:
	return d.has("portal")


# ------------------------------------------------------------------ registration (called by WorldObjects)

func on_created(o) -> void:
	var pd: Dictionary = o.def.get("portal", {})
	if pd.is_empty():
		return
	var rec := _record(o, pd)
	portals[o.id] = rec
	_run_all.merge(rec["run_y"], true)
	_mark_geometry(rec, o, true)
	world.levels.touch()
	world.nav.touch_tile(o.tile)


func on_removed(o) -> void:
	if not portals.has(o.id):
		return
	var rec: Dictionary = portals[o.id]
	_mark_geometry(rec, o, false)
	for k in rec["run_y"]:
		_run_all.erase(k)
	portals.erase(o.id)
	elevators.forget(o.id)
	world.levels.touch()
	world.nav.touch_tile(o.tile)


func _record(o, pd: Dictionary) -> Dictionary:
	var kind := str(pd.get("kind", "stairs"))
	var dz := int(pd.get("dz", 1))
	var rec: Dictionary = {"id": o.id, "kind": kind, "dz": dz, "base": o.level, "top": o.level + o.span, "tile": o.tile, "exterior": bool(pd.get("exterior", false)),
		"run": [], "stairs": [], "stops": [], "run_y": {}}
	var rot: int = o.rot
	var t: Vector2i = o.tile
	var L: int = o.level
	if kind == "stairs":
		var dir := WorldObject.rotate_offset(Vector2i(1, 0), rot)
		var f0 := t
		var f1 := t + dir
		var a := LPos.make(f0 - dir, L)
		var b := LPos.make(f1 + dir, L + dz)
		rec["stairs"] = [a, b]
		rec["run"] = [LPos.make(f0, L), LPos.make(f1, L)]
		(rec["run_y"] as Dictionary)[LPos.make(f0, L)] = float(dz) / 3.0
		(rec["run_y"] as Dictionary)[LPos.make(f1, L)] = float(dz) * 2.0 / 3.0
	elif kind == "ladder":
		var front := t + WorldObject.rotate_offset(Vector2i(0, 1), rot)
		rec["stairs"] = [LPos.make(front, L), LPos.make(front, L + dz)]
		rec["run"] = [LPos.make(t, L)]
		(rec["run_y"] as Dictionary)[LPos.make(t, L)] = float(dz) * 0.5
	else:
		var front2 := t + WorldObject.rotate_offset(Vector2i(0, 1), rot)
		var stops: Array = []
		for m in range(L, L + o.span + 1):
			stops.append(LPos.make(front2, m))
		rec["stops"] = stops
	return rec


## Occupancy of the parts of the object that are NOT on its own level (stairwell openings, shaft on the other levels).
func _mark_geometry(rec: Dictionary, o, on: bool) -> void:
	var lv: WorldLevels = world.levels
	var tiles_upper: Array[Vector2i] = []
	var upper_level := 0
	match str(rec["kind"]):
		"stairs":
			upper_level = o.level + int(rec["dz"])
			if int(rec["dz"]) > 0:
				for p in rec["run"]:
					tiles_upper.append(LPos.tile(p))
		"ladder":
			upper_level = o.level + int(rec["dz"])
			if int(rec["dz"]) > 0:
				tiles_upper.append(o.tile)
		"elevator":
			for m in range(o.level + 1, o.level + o.span + 1):
				_mark_tile(m, o.tile, o.id, on, false)
			return
	for t in tiles_upper:
		_mark_tile(upper_level, t, o.id, on, true)


func _mark_tile(level: int, t: Vector2i, oid: int, on: bool, hole: bool) -> void:
	if level == 0:
		if on:
			world._blocked[t] = true
			world.levels.ground_holes[t] = true
		else:
			world._blocked.erase(t)
			world.levels.ground_holes.erase(t)
		world.nav.touch_tile(t)
		return
	var lay := world.levels.layer(level)
	if on:
		lay.blocked[t] = true
		if hole:
			lay.holes[t] = true
		else:
			lay.occ[t] = oid
	else:
		lay.blocked.erase(t)
		lay.holes.erase(t)
		if lay.occ.get(t, -1) == oid:
			lay.occ.erase(t)
	lay.touch()


# ------------------------------------------------------------------ queries

func record(oid: int) -> Dictionary:
	return portals.get(oid, {})


## Is the portal usable right now (object there, not broken / out of order, the far side exists and can be stood on)?
func is_active(rec: Dictionary) -> bool:
	var o = world.objects.get(int(rec["id"]), null)
	if o == null or bool(o.state.get("broken", false)) or bool(o.state.get("out_of_order", false)):
		return false
	if str(rec["kind"]) == "elevator":
		return (rec["stops"] as Array).size() >= 2
	var ends: Array = rec["stairs"]
	for p in ends:
		if not _end_ok(p):
			return false
	return true


func _end_ok(p: Vector3i) -> bool:
	if p.z != 0:
		var bid := world.levels.building_at(LPos.tile(p))
		if bid < 0 or not world.levels.has_level(bid, p.z):
			return false
	return world.levels.is_walkable(LPos.tile(p), p.z)


## Active portals touching a building (by footprint of the portal tile).
func of_building(bid: int) -> Array:
	var out: Array = []
	for rec in portals.values():
		if world.levels.building_at(rec["tile"]) == bid and is_active(rec):
			out.append(rec)
	return out


## Route nodes: every walkable end of an active portal of the building. [{pos, rec}]
func nodes_of(bid: int) -> Array:
	var out: Array = []
	for rec in of_building(bid):
		var ends: Array = rec["stops"] if str(rec["kind"]) == "elevator" else rec["stairs"]
		for p in ends:
			if _end_ok(p):
				out.append({"pos": p, "rec": rec})
	return out


## Height offset (0..1 of a level, signed) of a walked tile on a staircase / ladder; 0.0 for normal floor.
func run_offset(tile: Vector2i, level: int) -> float:
	return float(_run_all.get(LPos.make(tile, level), 0.0))


## World height (metres) of standing on (tile, level): floor of the level plus the slope of a staircase / ladder under the feet.
func walk_y(tile: Vector2i, level: int) -> float:
	return (float(level) + run_offset(tile, level)) * LPos.H


## Cost (route units) and the entries to walk to take portal `rec` from endpoint `from_p` to `to_p`.
## Returns {cost, steps: Array[Vector3i]} (steps end on the destination endpoint). smult scales the stair / ladder effort.
func traverse(rec: Dictionary, from_p: Vector3i, to_p: Vector3i, smult: float = 1.0) -> Dictionary:
	var steps: Array[Vector3i] = []
	var kind := str(rec["kind"])
	if kind == "elevator":
		var tile := LPos.tile(from_p)
		var shaft := LPos.make(rec["tile"], from_p.z)
		var shaft2 := LPos.make(rec["tile"], to_p.z)
		steps.append(shaft)
		steps.append(shaft2)
		steps.append(to_p)
		var cost := ELEV_BASE + 2.0 + ELEV_PER_LEVEL * float(absi(to_p.z - from_p.z)) + elevators.wait_units(int(rec["id"]))
		return {"cost": cost, "steps": steps, "tile": tile}
	var run: Array = rec["run"]
	var ends: Array = rec["stairs"]
	var up: bool = from_p == ends[0]
	if up:
		for p in run:
			steps.append(p)
	else:
		for i in range(run.size() - 1, -1, -1):
			steps.append(run[i])
	steps.append(to_p)
	var pen: float = LADDER_PEN if kind == "ladder" else STAIR_PEN
	return {"cost": (float(run.size()) + pen) * smult + 1.0, "steps": steps}


## Effort multiplier for stairs / ladders for a folk: elders, toddlers, injured and exhausted folk are slower (Health.speed_mult).
static func stair_mult(f) -> float:
	if f == null:
		return 1.0
	var m := 1.0 / maxf(0.3, Health.speed_mult(f))
	match str(f.age_stage):
		"elder":
			m *= 1.5
		"toddler":
			m *= 1.7
		"child":
			m *= 1.05
	return m
