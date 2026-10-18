class_name LotLoader
extends RefCounted
## Places a lot template into the World: floors, walls, wall-mounted doors/windows, objects and spawn tiles.
## A template id comes from data/lot_templates.json (hand made) OR data/generated_lots.json (HouseGenerator; the file may be
## missing). "classic" is the hand-built starter house (StarterHouse).
##
##   LotLoader.place("small", World, origin)   put the template on the big map with its top-left at `origin` (no reset)
##   LotLoader.apply("small")                  legacy: a fresh 32x24 world holding only that lot (tests, thumbnails)
##   LotLoader.entry_of("cafe")                tile (template coordinates) where visitors arrive / walk to
## Every call fills `report` {id, placed, failed:[...], objects, spawn, entry, staff, venue} in WORLD coordinates.

const CLASSIC := "classic"
const GENERATED_PATH := "res://data/generated_lots.json"
const DEFAULT_ENTRY := Vector2i(15, 19)      # yard in front of the door (templates without an explicit "entry")

static var report: Dictionary = {}
static var _cache: Dictionary = {}
static var _gen: Dictionary = {}
static var _gen_loaded: bool = false

static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func _templates() -> Dictionary:
	if _cache.is_empty():
		_cache = _read("res://data/lot_templates.json")
	return (_cache.get("lots", {}) as Dictionary)

static func _generated() -> Dictionary:
	if not _gen_loaded:
		_gen = (_read(GENERATED_PATH).get("lots", {}) as Dictionary)
		_gen_loaded = true
	return _gen

static func reload() -> void:
	_cache = {}
	_gen = {}
	_gen_loaded = false

static func has_template(template_id: String) -> bool:
	return template_id == CLASSIC or _templates().has(template_id) or _generated().has(template_id)

## classic + the hand made templates (the generated ones: generated_ids()).
static func template_ids() -> Array:
	var ids: Array = [CLASSIC]
	ids.append_array(_templates().keys())
	return ids

static func generated_ids() -> Array:
	return _generated().keys()

static func template(template_id: String) -> Dictionary:
	if template_id == CLASSIC:
		return {"label": "Fernwood Classic", "kind": "home", "description": "The original starter house."}
	if _templates().has(template_id):
		return (_templates()[template_id] as Dictionary)
	return (_generated().get(template_id, {}) as Dictionary)

static func _world():
	return WorldIface.world()

## Entry tile (where arrivals appear), template coordinates.
static func entry_of(template_id: String) -> Vector2i:
	var t := template(template_id)
	if t.has("entry"):
		return Vector2i(int(t["entry"][0]), int(t["entry"][1]))
	return DEFAULT_ENTRY

## Footprint of the building itself (template coordinates): the bounding box of its "wall" edges. Rect2i() when the lot has no
## building (park). The classic house is hand built: walls x4..20, y4..16.
static func building_rect(template_id: String) -> Rect2i:
	if template_id == CLASSIC:
		return Rect2i(4, 4, 16, 12)
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for wl in template(template_id).get("walls", []):
		if str(wl["type"]) != "wall":
			continue
		for k in ["a", "b"]:
			var v := Vector2i(int(wl[k][0]), int(wl[k][1]))
			lo = Vector2i(mini(lo.x, v.x), mini(lo.y, v.y))
			hi = Vector2i(maxi(hi.x, v.x), maxi(hi.y, v.y))
	if lo.x > hi.x:
		return Rect2i()
	return Rect2i(lo, hi - lo)

## Legacy single lot: a fresh 32x24 world that holds only this template.
static func apply(template_id: String, w = null) -> bool:
	if w == null:
		w = _world()
	if w == null:
		report = {"id": template_id, "placed": 0, "failed": ["no world"], "objects": 0, "spawn": [], "entry": Vector2i(-1, -1), "staff": [], "venue": ""}
		return false
	var ws: Array = _world_size()
	w.reset(int(ws[0]), int(ws[1]))
	var ok := place(template_id, w, Vector2i.ZERO)
	w.clear_undo()
	w.rooms.invalidate_all()
	w.emit_signal("world_reset")
	return ok

## Put `template_id` on the map with its top-left corner at `origin`. Does not reset the world; callers on the big map set
## `World.regions.enforce = false` first (non-home lots are not buildable by the player).
static func place(template_id: String, w, origin: Vector2i) -> bool:
	report = {"id": template_id, "placed": 0, "failed": [], "objects": 0, "spawn": [], "entry": Vector2i(-1, -1), "staff": [], "venue": ""}
	if template_id == CLASSIC:
		w.starter_spawn_tiles.clear()
		w.StarterHouse.build(w, origin)
		report["objects"] = w.objects.size()
		report["placed"] = w.objects.size()
		report["spawn"] = (w.starter_spawn_tiles as Array).duplicate()
		report["entry"] = DEFAULT_ENTRY + origin
		return true
	var t: Dictionary = template(template_id)
	if t.is_empty():
		(report["failed"] as Array).append("unknown template %s" % template_id)
		return false
	for fl in t.get("floors", []):
		var r: Array = fl["rect"]
		w.set_floor_rect_raw(Vector2i(int(r[0]), int(r[1])) + origin, Vector2i(int(r[2]), int(r[3])) + origin, str(fl["type"]))
	for wl in t.get("walls", []):
		var a: Array = wl["a"]
		var b: Array = wl["b"]
		_wall_line(w, Vector2i(int(a[0]), int(a[1])) + origin, Vector2i(int(b[0]), int(b[1])) + origin, str(wl["type"]))
	var ol: Array = t.get("objects", [])
	report["objects"] = ol.size()
	# wall-mounted pieces need their wall first (all walls exist by now); everything else follows
	for pass_i in 2:
		for o in ol:
			var d: Dictionary = w.get_def(str(o["def"]))
			var mounted: bool = str(d.get("mount", "")) == "wall"
			if (pass_i == 0) != mounted:
				continue
			var tile := Vector2i(int(o["tile"][0]), int(o["tile"][1])) + origin
			var rot: int = int(o.get("rot", 0))
			var id: int = w.place_object(str(o["def"]), tile, rot)
			if id == -1:
				(report["failed"] as Array).append("%s at %s rot %d: %s" % [o["def"], str(tile), rot, str(w.last_error)])
			else:
				report["placed"] = int(report["placed"]) + 1
	w.starter_spawn_tiles.clear()
	for sp in t.get("spawn", []):
		w.starter_spawn_tiles.append(Vector2i(int(sp[0]), int(sp[1])) + origin)
	var br: Array = t.get("bedroom", [])
	if br.size() >= 2:
		w.starter_bedroom_tile = Vector2i(int(br[0]), int(br[1])) + origin
	else:
		w.starter_bedroom_tile = w.starter_spawn_tiles[0] if w.starter_spawn_tiles.size() > 0 else origin
	report["spawn"] = (w.starter_spawn_tiles as Array).duplicate()
	report["entry"] = entry_of(template_id) + origin
	var staff: Array = (t.get("staff", []) as Array).duplicate(true)
	for sd in staff:
		sd["tile"] = [int(sd["tile"][0]) + origin.x, int(sd["tile"][1]) + origin.y]
	report["staff"] = staff
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

## Objects (optionally only those inside `rect`) whose use tiles cannot be reached from `from`. Empty = playable.
static func unreachable_objects(w, from: Vector2i, rect: Rect2i = Rect2i()) -> Array:
	var bad: Array = []
	for o in w.all_objects():
		if o.is_wall_mounted() or o.is_floor_layer():
			continue
		if rect.size != Vector2i.ZERO and not rect.has_point(o.tile):
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
