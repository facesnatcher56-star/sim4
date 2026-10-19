class_name LevelDisasters
extends RefCounted
## Disasters in a building with floors (task 10 part B). DisasterDamage / DisasterAftermath ask here:
##   cover: a tornado is survived in the BASEMENT (any folk below ground counts as covered, the storm-shelter room lives there) or next to a
##          fixture (bathtub, shower, toilet, storm shelter) on the GROUND floor; fixtures upstairs are not safe (the roof goes first);
##   floods hit the basement first (objects below ground are hit 3x as often, upper floors stay dry);
##   earthquakes shake the upper floors harder (+30% per floor) and the basement less;
##   storms (tornado / hail) hit the upper floors and roof harder.
const FIXTURES := ["storm_shelter", "bathtub", "shower", "toilet"]


## Chance multiplier of an object being hit by `kind`, by the floor it stands on.
static func hit_mult(kind: String, o) -> float:
	return LevelInfo.height_mult(kind, LevelInfo.lv(o))


## Injury multiplier for a folk standing on an upper floor / in the basement.
static func folk_mult(kind: String, f) -> float:
	var lv: int = LevelInfo.lv(f)
	if lv == 0:
		return 1.0
	return LevelInfo.height_mult(kind, lv) if kind != "flood" else (1.0 if lv < 0 else 0.0)


## Is the folk below ground (basement / shelter room)? Counts as cover in a tornado.
static func in_basement(f) -> bool:
	return LevelInfo.lv(f) < 0


## Safe spots of the household's lot for a tornado: basement fixtures first, then ground-floor fixtures. Upper floors are not safe.
static func cover_spots(objs: Array) -> Array:
	var low: Array = []
	var ground: Array = []
	for o in objs:
		if not FIXTURES.has(str(o.def_id)):
			continue
		if LevelInfo.lv(o) < 0:
			low.append(o)
		elif LevelInfo.lv(o) == 0:
			ground.append(o)
	return low if not low.is_empty() else ground


## A tile in the basement of the household's building where people can wait out the storm ("" when there is none): [tile, level].
static func basement_spot(objs: Array) -> Array:
	var best = null
	for o in objs:
		if LevelInfo.lv(o) < 0 and not o.is_wall_mounted() and (best == null or LevelInfo.lv(o) > LevelInfo.lv(best)):
			best = o
	if best == null:
		return []
	return [WorldIface.use_tile(best, 0), LevelInfo.lv(best)]
