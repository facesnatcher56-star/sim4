class_name DestLoader
extends RefCounted
## Loads a holiday map (DestDefs) into one of the ZONES of the one continuous map (the Southwoods strip, 4 slots of 32 x 22 tiles from
## data/vacation.json config.zones) and takes it out again. Only the zones that a trip needs exist; everything else in the strip stays woods.
## A loaded zone is an ordinary "venue" region (lot id given by the caller) with a real template, so autonomy, rooms, levels, routing,
## saves and the view treat it like any other lot. Folk must have left before unload_zone().
##
##   DestLoader.zone_rect(i) / zone_count()
##   DestLoader.load_zone(i, map_id, lot_id, label) -> {ok, rect, entry, door, spawn: [Vector2i], failed: [String], region}
##   DestLoader.unload_zone(i) -> int objects removed
##   DestLoader.cabin_list(map_id, rect) / posts(map_id, rect)       ship data in world coordinates

static func zone_count() -> int:
	return (DestDefs.zone_config().get("xs", []) as Array).size()

static func zone_rect(i: int) -> Rect2i:
	var z: Dictionary = DestDefs.zone_config()
	var xs: Array = z.get("xs", [6])
	# the zones sit in the woods strip below the lots: its top row (data/map_layout.json south_strip.y) + `below_strip`
	var y: int = int((MapBuilder.layout().get("south_strip", {}) as Dictionary).get("y", 127)) + int(z.get("below_strip", 2))
	return Rect2i(int(xs[clampi(i, 0, xs.size() - 1)]), y, int(z.get("w", 32)), int(z.get("h", 22)))

static func _world():
	return WorldIface.world()

static func region_of_zone(i: int) -> int:
	var w = _world()
	if w == null or not w.regions.has_regions():
		return -1
	var rc := zone_rect(i)
	for r in w.regions.regions.values():
		if (r["rect"] as Rect2i) == rc:
			return int(r["id"])
	return -1

## Put the map into zone `i`. Returns {ok: false, failed: [...]} when it cannot.
static func load_zone(i: int, map_id: String, lot_id: String, label: String) -> Dictionary:
	var w = _world()
	var tpl: Dictionary = DestDefs.map(map_id)
	if w == null or tpl.is_empty() or not w.regions.has_regions():
		return {"ok": false, "failed": ["no world, map or regions (%s)" % map_id]}
	unload_zone(i)                                  # a leftover of an earlier trip
	var rc := zone_rect(i)
	var entry_l: Array = tpl.get("entry", [15, 21])
	var entry: Vector2i = rc.position + Vector2i(int(entry_l[0]), int(entry_l[1]))
	var rg: WorldRegions = w.regions
	var was_enforce: bool = rg.enforce
	rg.enforce = false
	var keep_spawn: Array = (w.starter_spawn_tiles as Array).duplicate()
	var keep_bed: Vector2i = w.starter_bedroom_tile
	var rid: int = rg.add_region({"rect": rc, "kind": "venue", "venue_type": "", "owner": "public", "template": "dest_" + map_id, "label": label,
		"lot": lot_id, "entry": entry, "door": entry})
	var tid: String = "dest_" + map_id
	var lots: Dictionary = LotLoader._templates()
	lots[tid] = tpl
	var good: bool = LotLoader.place(tid, w, rc.position)
	var failed: Array = (LotLoader.report.get("failed", []) as Array).duplicate()
	lots.erase(tid)
	w.starter_spawn_tiles.clear()
	for t in keep_spawn:
		w.starter_spawn_tiles.append(t)
	w.starter_bedroom_tile = keep_bed
	rg.enforce = was_enforce
	var spawn: Array = []
	for s in tpl.get("spawn", []):
		spawn.append(Vector2i(int(s[0]), int(s[1])) + rc.position)
	if spawn.is_empty():
		spawn.append(entry)
	rg.regions[rid]["door"] = _standable_near(w, spawn[0], rc)
	w.rooms.invalidate_all()
	w._emit("floors_changed")
	w._emit("walls_changed")
	return {"ok": good, "rect": rc, "entry": entry, "door": rg.regions[rid]["door"], "spawn": spawn, "failed": failed, "region": rid}

static func _standable_near(w, t: Vector2i, rc: Rect2i) -> Vector2i:
	for rad in 5:
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var c := t + Vector2i(dx, dy)
				if rc.has_point(c) and w.is_walkable(c):
					return c
	return t

## Take the zone out again: objects, walls, floors (back to the woods' grass), upper levels, the building record and the region.
static func unload_zone(i: int) -> int:
	var w = _world()
	if w == null:
		return 0
	var rc := zone_rect(i)
	var rid: int = region_of_zone(i)
	if rid < 0 and not _has_content(w, rc):
		return 0
	var ids: Array = []
	for o in w.objects.values():
		if rc.has_point(o.tile):
			ids.append(int(o.id))
	ids.sort()
	for oid in ids:
		w.remove_object(oid)
		Economy.owner.erase(oid)
	for y in range(rc.position.y, rc.end.y + 1):
		for x in range(rc.position.x, rc.end.x + 1):
			w.walls.erase(Vector3i(x, y, 0))
			w.walls.erase(Vector3i(x, y, 1))
	for y2 in range(rc.position.y, rc.end.y):
		for x2 in range(rc.position.x, rc.end.x):
			var t := Vector2i(x2, y2)
			w.floors[y2 * w.width + x2] = "grass"
			w._blocked.erase(t)
			w._occ.erase(t)
			w._occ_floor.erase(t)
			w.mess.erase(t)
			w.regions.mark_floor_dirty(t)
	for lay in w.levels.layers.values():
		_clear_layer(lay, rc)
	for bid in w.levels.buildings.keys():
		if (w.levels.buildings[bid]["rect"] as Rect2i).intersects(rc):
			w.levels.buildings.erase(bid)
	w.levels.touch()
	if rid >= 0:
		w.regions.remove_region(rid)
	w.rooms.invalidate_all()
	w.nav.reset()
	w._emit("floors_changed")
	w._emit("walls_changed")
	return ids.size()

static func _has_content(w, rc: Rect2i) -> bool:
	for o in w.objects.values():
		if rc.has_point(o.tile):
			return true
	return false

static func _clear_layer(lay: LevelLayer, rc: Rect2i) -> void:
	for dname in ["floors", "blocked", "holes", "occ", "occ_floor"]:
		var d: Dictionary = lay.get(dname)
		for k in d.keys():
			if rc.has_point(k):
				d.erase(k)
	for dname2 in ["walls", "mounts"]:
		var d2: Dictionary = lay.get(dname2)
		for e in d2.keys():
			if e.x >= rc.position.x and e.x <= rc.end.x and e.y >= rc.position.y and e.y <= rc.end.y:
				d2.erase(e)
	lay.touch()

# ------------------------------------------------------------------ ship data in world coordinates
static func cabin_list(map_id: String, rc: Rect2i) -> Array:
	var out: Array = []
	for c in DestDefs.map(map_id).get("cabins", []):
		out.append({"id": str(c["id"]), "class": str(c["class"]), "level": int(c["level"]), "tile": Vector2i(int(c["tile"][0]), int(c["tile"][1])) + rc.position})
	return out

static func posts(map_id: String, rc: Rect2i) -> Array:
	var out: Array = []
	for p in DestDefs.map(map_id).get("posts", []):
		out.append({"role": str(p["role"]), "level": int(p["level"]), "tile": Vector2i(int(p["tile"][0]), int(p["tile"][1])) + rc.position})
	return out
