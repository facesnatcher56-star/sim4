class_name WorldSave
extends RefCounted
## Starter lot, save_dict / load_dict.
## Back-references the World autoload as `world`; World keeps one-line delegates for the public API.

var world: WorldGrid


func _init(w: WorldGrid) -> void:
	world = w


# ------------------------------------------------------------------ starter lot

## Furnished 2-bedroom house + yard. Fills starter_spawn_tiles / starter_bedroom_tile.
func load_starter_house() -> void:
	world.reset(world.DEFAULT_W, world.DEFAULT_H)
	world.StarterHouse.build(world)
	world.clear_undo()
	world.rooms.invalidate_all()
	world._emit("world_reset")

# ------------------------------------------------------------------ save / load

## Maps above this many tiles store floors run-length encoded (["grass", 311, "asphalt", 6, ...]) instead of one entry per tile.
const RLE_MIN_TILES := 4096

func _floors_rle() -> Array:
	var out: Array = []
	var fl := world.floors
	if fl.is_empty():
		return out
	var cur: String = fl[0]
	var n := 0
	for s in fl:
		if s == cur:
			n += 1
		else:
			out.append(cur)
			out.append(n)
			cur = s
			n = 1
	out.append(cur)
	out.append(n)
	return out

func _load_floors(d: Dictionary) -> void:
	if d.has("floors_rle"):
		var rle: Array = d["floors_rle"]
		var i := 0
		var pos := 0
		while i + 1 < rle.size() and pos < world.floors.size():
			var cnt := mini(int(rle[i + 1]), world.floors.size() - pos)
			var type := str(rle[i])
			for k in cnt:
				world.floors[pos + k] = type
			pos += cnt
			i += 2
	else:
		var fl: Array = d.get("floors", [])
		for i in mini(fl.size(), world.floors.size()):
			world.floors[i] = str(fl[i])
	# water tiles are not walkable
	for y in world.height:
		for x in world.width:
			if world.floors[y * world.width + x] == "water":
				world._blocked[Vector2i(x, y)] = true

func save_dict(include_folk: bool = false) -> Dictionary:
	var wl: Array = []
	for e in world.walls:
		var is_mount: bool = world.mounts.has(e)
		if is_mount:
			continue   # the mounted object recreates its edge
		wl.append([e.x, e.y, e.z, world.walls[e]])
	var ol: Array = []
	for o in world.objects.values():
		ol.append(o.to_dict())
	var ml: Array = []
	for t in world.mess:
		ml.append([t.x, t.y, world.mess[t]])
	var d := {
		"version": 1, "width": world.width, "height": world.height,
		"walls": wl, "objects": ol, "mess": ml, "next_id": world._next_id,
		"spawn": world.starter_spawn_tiles.map(func(t): return [t.x, t.y]),
		"bedroom": [world.starter_bedroom_tile.x, world.starter_bedroom_tile.y],
	}
	if world.floors.size() >= RLE_MIN_TILES:
		d["floors_rle"] = _floors_rle()
	else:
		d["floors"] = Array(world.floors)
	if world.regions.has_regions():
		d["regions"] = world.regions.to_dict()
	if include_folk:
		var fl: Array = []
		for f in world.folk.values():
			if f.has_method("to_dict"):
				fl.append(f.to_dict())
		d["folk"] = fl
	return d

func load_dict(d: Dictionary) -> void:
	world.reset(int(d.get("width", world.DEFAULT_W)), int(d.get("height", world.DEFAULT_H)))
	_load_floors(d)
	if d.has("regions"):
		world.regions.from_dict(d["regions"])
	for w in d.get("walls", []):
		world.walls[Vector3i(int(w[0]), int(w[1]), int(w[2]))] = str(w[3])
	for od in d.get("objects", []):
		var t: Array = od["tile"]
		var nid := world._create_object(str(od["def_id"]), Vector2i(int(t[0]), int(t[1])), int(od["rot"]), int(od["id"]))
		if nid != -1:
			var st: Dictionary = od.get("state", {})
			for k in st:
				world.objects[nid].state[k] = st[k]
	for m in d.get("mess", []):
		world.mess[Vector2i(int(m[0]), int(m[1]))] = float(m[2])
	world._next_id = maxi(world._next_id, int(d.get("next_id", 1)))
	world.starter_spawn_tiles.clear()
	for s in d.get("spawn", []):
		world.starter_spawn_tiles.append(Vector2i(int(s[0]), int(s[1])))
	var b: Array = d.get("bedroom", [0, 0])
	world.starter_bedroom_tile = Vector2i(int(b[0]), int(b[1]))
	if d.has("folk") and ResourceLoader.exists("res://scripts/sim/folk.gd"):
		var fs: Script = load("res://scripts/sim/folk.gd")
		for fd in d["folk"]:
			var f = fs.from_dict(fd)
			if f != null:
				world.folk[f.id] = f
				world._emit("folk_added", f.id)
	world.rooms.dirty = true
	world._emit("world_reset")
