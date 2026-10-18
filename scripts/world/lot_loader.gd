class_name LotLoader
extends RefCounted
## Builds a lot from data/lot_templates.json into the real World: floors, walls, wall-mounted doors/windows, objects and
## spawn tiles. `LotLoader.apply("small")`; "classic" is the hand-built starter house (World.load_starter_house()).
## Every apply() fills `report` {id, placed, failed:[...], objects, spawn, entry, staff, venue}.

const CLASSIC := "classic"

static var report: Dictionary = {}
static var _cache: Dictionary = {}

static func _templates() -> Dictionary:
	if _cache.is_empty():
		var txt := FileAccess.get_file_as_string("res://data/lot_templates.json")
		var parsed: Variant = JSON.parse_string(txt)
		if parsed is Dictionary:
			_cache = parsed
	return (_cache.get("lots", {}) as Dictionary)

static func reload() -> void:
	_cache = {}

static func has_template(template_id: String) -> bool:
	return template_id == CLASSIC or _templates().has(template_id)

static func template_ids() -> Array:
	var ids: Array = [CLASSIC]
	ids.append_array(_templates().keys())
	return ids

static func template(template_id: String) -> Dictionary:
	if template_id == CLASSIC:
		return {"label": "Fernwood Classic", "kind": "home", "description": "The original starter house."}
	return (_templates().get(template_id, {}) as Dictionary)

static func _world():
	return WorldIface.world()

## Entry tile (where arrivals appear) of a template.
static func entry_of(template_id: String) -> Vector2i:
	var t := template(template_id)
	if t.has("entry"):
		return Vector2i(int(t["entry"][0]), int(t["entry"][1]))
	var sp: Array = t.get("spawn", [])
	if not sp.is_empty():
		return Vector2i(int(sp[0][0]), int(sp[0][1]))
	return Vector2i(-1, -1)

## Build `template_id` into the World (replacing the current lot). Returns true when every piece was placed.
static func apply(template_id: String, w = null) -> bool:
	if w == null:
		w = _world()
	report = {"id": template_id, "placed": 0, "failed": [], "objects": 0, "spawn": [], "entry": Vector2i(-1, -1), "staff": [], "venue": ""}
	if w == null:
		(report["failed"] as Array).append("no world")
		return false
	if template_id == CLASSIC:
		w.call("load_starter_house")
		report["objects"] = w.objects.size()
		report["placed"] = w.objects.size()
		report["spawn"] = (w.starter_spawn_tiles as Array).duplicate()
		report["entry"] = (w.starter_spawn_tiles[0] if w.starter_spawn_tiles.size() > 0 else Vector2i(15, 16))
		return true
	var t: Dictionary = template(template_id)
	if t.is_empty():
		(report["failed"] as Array).append("unknown template %s" % template_id)
		return false
	var ws: Array = _world_size()
	w.reset(int(ws[0]), int(ws[1]))
	for fl in t.get("floors", []):
		var r: Array = fl["rect"]
		w.set_floor_rect_raw(Vector2i(int(r[0]), int(r[1])), Vector2i(int(r[2]), int(r[3])), str(fl["type"]))
	for wl in t.get("walls", []):
		var a: Array = wl["a"]
		var b: Array = wl["b"]
		_wall_line(w, Vector2i(int(a[0]), int(a[1])), Vector2i(int(b[0]), int(b[1])), str(wl["type"]))
	var ol: Array = t.get("objects", [])
	report["objects"] = ol.size()
	# wall-mounted pieces need their wall first (all walls exist by now); everything else follows
	for pass_i in 2:
		for o in ol:
			var d: Dictionary = w.get_def(str(o["def"]))
			var mounted: bool = str(d.get("mount", "")) == "wall"
			if (pass_i == 0) != mounted:
				continue
			var tile := Vector2i(int(o["tile"][0]), int(o["tile"][1]))
			var rot: int = int(o.get("rot", 0))
			var id: int = w.place_object(str(o["def"]), tile, rot)
			if id == -1:
				(report["failed"] as Array).append("%s at %s rot %d: %s" % [o["def"], str(tile), rot, str(w.last_error)])
			else:
				report["placed"] = int(report["placed"]) + 1
	w.starter_spawn_tiles.clear()
	for sp in t.get("spawn", []):
		w.starter_spawn_tiles.append(Vector2i(int(sp[0]), int(sp[1])))
	var br: Array = t.get("bedroom", [])
	if br.size() >= 2:
		w.starter_bedroom_tile = Vector2i(int(br[0]), int(br[1]))
	else:
		w.starter_bedroom_tile = w.starter_spawn_tiles[0] if w.starter_spawn_tiles.size() > 0 else Vector2i.ZERO
	w.clear_undo()
	w.rooms.dirty = true
	w.emit_signal("world_reset")
	report["spawn"] = (w.starter_spawn_tiles as Array).duplicate()
	report["entry"] = entry_of(template_id)
	report["staff"] = (t.get("staff", []) as Array).duplicate(true)
	report["venue"] = str(t.get("venue", ""))
	return (report["failed"] as Array).is_empty()

static func _world_size() -> Array:
	_templates()
	if _cache.has("world_size"):
		return _cache["world_size"]
	return [32, 24]

## Raw wall line (no coins, no undo). type "none" erases.
static func _wall_line(w, a: Vector2i, b: Vector2i, type: String) -> void:
	var edges: Array = []
	if a.y == b.y:
		for x in range(mini(a.x, b.x), maxi(a.x, b.x)):
			edges.append(Vector3i(x, a.y, 0))
	elif a.x == b.x:
		for y in range(mini(a.y, b.y), maxi(a.y, b.y)):
			edges.append(Vector3i(a.x, y, 1))
	for e in edges:
		w.set_edge(e, type)

## Tiles a folk can stand on to use `o` (slot approach tiles), for reachability checks.
static func use_tiles(w, o) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n: int = o.slot_count()
	if n == 0:
		out.append(o.tile)
		return out
	for i in n:
		out.append(o.slot_tile(i))
	return out

## Objects whose use tiles cannot be reached from `from`. Empty = playable.
static func unreachable_objects(w, from: Vector2i) -> Array:
	var bad: Array = []
	for o in w.all_objects():
		if o.is_wall_mounted() or o.is_floor_layer():
			continue
		var ok := false
		for t in use_tiles(w, o):
			if t == from or (w.in_bounds(t) and w.has_path(from, t)):
				ok = true
				break
			# slots inside the furniture: reachable through an adjacent free tile
			if w.in_bounds(t) and not w.is_walkable(t):
				var nb: Vector2i = w.nearest_reachable_neighbor(from, t)
				if nb.x >= 0:
					ok = true
					break
		if not ok:
			bad.append("%s@%s" % [o.def_id, str(o.tile)])
	return bad
