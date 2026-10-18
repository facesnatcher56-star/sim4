class_name LevelLayer
extends RefCounted
## Sparse content of ONE level (not 0) of the whole map: only tiles that have something cost memory, so a 20-storey tower
## is 20 small dictionaries, not 20 grids. Buildings never overlap in x / y, so one layer per level number serves every building
## (WorldLevels keeps the building records: rect + level range).
## Same conventions as the ground level: edge key Vector3i(x, y, dir) (0 north / 1 west side of tile (x, y)), tile = Vector2i.

var level: int = 0
var floors: Dictionary = {}       # Vector2i -> floor type (a tile without an entry is void: nothing to stand on)
var walls: Dictionary = {}        # Vector3i edge -> wall / door / window / fence
var mounts: Dictionary = {}       # Vector3i edge -> object id (door / window objects)
var blocked: Dictionary = {}      # Vector2i -> true (blocking object, stairwell opening, shaft)
var holes: Dictionary = {}        # Vector2i -> true (opening in the floor: stairwell above stairs; drawn without a floor)
var occ: Dictionary = {}          # Vector2i -> object id (main layer)
var occ_floor: Dictionary = {}    # Vector2i -> object id (rugs)
var gen: int = 0                  # bumped on every change (render + route caches)


func _init(p_level: int = 0) -> void:
	level = p_level


func touch() -> void:
	gen += 1


func is_empty() -> bool:
	return floors.is_empty() and walls.is_empty() and occ.is_empty() and occ_floor.is_empty() and holes.is_empty()


func to_dict() -> Dictionary:
	var fl: Array = []
	for t in floors:
		fl.append([t.x, t.y, floors[t]])
	var wl: Array = []
	for e in walls:
		if mounts.has(e):
			continue                  # the mounted object recreates its edge
		wl.append([e.x, e.y, e.z, walls[e]])
	var hl: Array = []
	for t in holes:
		hl.append([t.x, t.y])
	return {"level": level, "floors": fl, "walls": wl, "holes": hl}


func load_dict(d: Dictionary) -> void:
	level = int(d.get("level", level))
	for f in d.get("floors", []):
		floors[Vector2i(int(f[0]), int(f[1]))] = str(f[2])
	for w in d.get("walls", []):
		walls[Vector3i(int(w[0]), int(w[1]), int(w[2]))] = str(w[3])
	for h in d.get("holes", []):
		var t := Vector2i(int(h[0]), int(h[1]))
		holes[t] = true
		blocked[t] = true
	gen += 1
