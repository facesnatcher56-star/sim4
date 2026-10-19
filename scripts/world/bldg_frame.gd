class_name BldgFrame
extends RefCounted
## Abstract frame of a multi-floor building: `u` runs ALONG the corridor, `v` ACROSS it (band A at v = 0, then the corridor, then band B).
## axis "ew": u = +x, v = +y (bands north / south). axis "ns": u = +y, v = +x (bands west / east). flip_u / flip_v mirror either axis.
## Also the stair core (BldgFrame.core_*): the one place where the stairs and the lift of every level sit.
##
## Core (abstract, relative to the corridor start `cu`, `cv`): 4 tiles along u (+1 column for a lift), 3 across (the corridor thickness).
##   row 0 / row 1 carry the flights (switchback: even levels climb along row 0 in +u, odd levels along row 1 in -u), row 2 is the walkway.
##   Up flight at level L (even): stairs f0 = (cu+1, 0) rot +u, walk on at (cu, 0), off at (cu+3, 0) one level up; odd: f0 = (cu+2, 1) rot -u,
##   on at (cu+3, 1), off at (cu, 1). Down flights (stairs_down, placed on the UPPER level L <= 0) mirror that: even: row 1 / -u, odd: row 0 / +u.
##   The lift shaft is (cu+4, 0) with its stop (cu+4, 1). The walkway tile (cu, 2) is free on every level (the level's entry tile).

const CORE_W := 4
const CORE_H := 3

var shell: Rect2i
var axis: String = "ew"
var len_u: int = 0
var len_v: int = 0
var eu: Vector2i = Vector2i(1, 0)
var ev: Vector2i = Vector2i(0, 1)
var origin: Vector2i = Vector2i.ZERO
var cu: int = 0            # core start along u
var cv: int = 0            # core start across (= corridor start)
var lift: bool = false


func _init(sh: Rect2i, ax: String, flip_u: bool, flip_v: bool, da: int, has_lift: bool) -> void:
	shell = sh
	axis = ax
	var bu := Vector2i(1, 0) if ax == "ew" else Vector2i(0, 1)
	var bv := Vector2i(0, 1) if ax == "ew" else Vector2i(1, 0)
	len_u = sh.size.x if ax == "ew" else sh.size.y
	len_v = sh.size.y if ax == "ew" else sh.size.x
	eu = -bu if flip_u else bu
	ev = -bv if flip_v else bv
	origin = sh.position
	if flip_u:
		origin += bu * (len_u - 1)
	if flip_v:
		origin += bv * (len_v - 1)
	lift = has_lift
	cv = da
	cu = 0
	if ax == "ns" and eu.y < 0:          # the front door is on the south wall: the core sits at the far (north) end of the corridor
		cu = len_u - (CORE_W + (1 if has_lift else 0))


func tile(u: int, v: int) -> Vector2i:
	return origin + eu * u + ev * v


func rect(u: int, v: int, du: int, dv: int) -> Rect2i:
	var a := tile(u, v)
	var b := tile(u + du - 1, v + dv - 1)
	return Rect2i(Vector2i(mini(a.x, b.x), mini(a.y, b.y)), Vector2i(absi(a.x - b.x) + 1, absi(a.y - b.y) + 1))


static func rot_of(vec: Vector2i) -> int:
	if vec == Vector2i(1, 0):
		return 0
	if vec == Vector2i(0, 1):
		return 1
	if vec == Vector2i(-1, 0):
		return 2
	return 3


## Rotation of an object whose FRONT faces +v (the lift).
func lift_rot() -> int:
	if ev == Vector2i(0, 1):
		return 0
	if ev == Vector2i(-1, 0):
		return 1
	if ev == Vector2i(0, -1):
		return 2
	return 3


func core_width() -> int:
	return CORE_W + (1 if lift else 0)


func core_rect() -> Rect2i:
	return rect(cu, cv, core_width(), CORE_H)


func core_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k in core_width():
		for j in CORE_H:
			out.append(tile(cu + k, cv + j))
	return out


## Walkable tile of the core that is free on every level (where a level's plan starts its reachability).
func entry_tile() -> Vector2i:
	return tile(cu, cv + 2)


## Stairs of level L as [{def, tile, rot}] (the lift is separate: lift_object).
func flights(level: int, bottom: int, top: int) -> Array:
	var out: Array = []
	if level >= 0 and level < top:
		out.append(_flight("stairs", level))
	if level <= 0 and level > bottom:
		out.append(_flight("stairs_down", level))
	return out


func _flight(def_id: String, level: int) -> Dictionary:
	var even := posmod(level, 2) == 0
	var up := def_id == "stairs"
	var row_a := (up and even) or ((not up) and not even)          # climbs along row 0 in +u
	if row_a:
		return {"def": def_id, "tile": tile(cu + 1, cv), "rot": rot_of(eu), "level": level}
	return {"def": def_id, "tile": tile(cu + 2, cv + 1), "rot": rot_of(-eu), "level": level}


func lift_object(bottom: int) -> Dictionary:
	return {"def": "elevator", "tile": tile(cu + CORE_W, cv), "rot": lift_rot(), "level": bottom}


func lift_stop() -> Vector2i:
	return tile(cu + CORE_W, cv + 1)
