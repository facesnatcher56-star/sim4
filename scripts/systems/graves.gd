class_name Graves
extends RefCounted
## Memorials. Aging.kill / DeathCauses.kill_townie call place_for(): a `grave` (tombstone) or `urn` object (data/incidents.json content) is
## placed on a free yard tile of the household's home lot, or in the park for townies, and a record {name, born, died, cause, ...} is kept
## here (saved with the incidents block). The objects do not block movement (blocks:false), so they never close a path or a doorway.
## "Remember" / "Mourn" (interactions on the objects) end with game events handled by on_game_event(): memory + mood.

static var records: Dictionary = {}     # object_id (or -(folk_id) when nothing could be placed) -> record

static func reset() -> void:
	records.clear()

# ------------------------------------------------------------------ placing
static func place_for(legacy: Dictionary, folk, cdef: Dictionary) -> Dictionary:
	var style: String = str(cdef.get("grave_style", "stone"))
	var def_id: String = "urn" if style == "urn" else "grave"
	var townie: bool = bool(legacy.get("townie", false)) or folk == null or int(folk.household_id) <= 0
	var anchor: Vector2i = folk.tile if folk != null else Vector2i(-1, -1)
	var oid: int = -1
	var tile: Vector2i = Vector2i(-1, -1)
	IncidentContent.install()
	var w = WorldIface.world()
	if w != null:
		var has_reg: bool = "regions" in w and w.regions != null
		var old_enforce: bool = true
		if has_reg:
			old_enforce = w.regions.enforce
			w.regions.enforce = false      # memorials go where they belong (park or yard), not only where the player may build
		var found: Vector2i = _find_tile(w, def_id, townie, anchor)
		if found.x >= 0:
			oid = int(w.place_object(def_id, found, 0))
			if oid >= 0:
				tile = found
		if has_reg:
			w.regions.enforce = old_enforce
	var key: int = oid if oid >= 0 else -int(legacy.get("folk_id", 0)) - 1
	var born: int = int(legacy.get("born_day", 0))
	var rec: Dictionary = {"object_id": oid, "folk_id": int(legacy.get("folk_id", -1)), "name": str(legacy.get("name", "")), "born": born,
		"died": int(legacy.get("day", SysUtil.day())), "years": int(legacy.get("years", 0)), "stage": str(legacy.get("stage", "adult")), "cause": str(legacy.get("cause", "")),
		"cause_id": str(legacy.get("cause_id", "")), "style": style, "def": def_id, "park": townie, "tile": [tile.x, tile.y], "visits": 0}
	records[key] = rec
	legacy["grave"] = key
	return rec

static func _find_tile(w, def_id: String, townie: bool, anchor: Vector2i) -> Vector2i:
	var cands: Array = []
	if "regions" in w and w.regions != null and w.regions.has_regions():
		var reg: Dictionary = {}
		if townie:
			var parks: Array = w.regions.of_kind("park")
			if not parks.is_empty():
				reg = parks[0]
		else:
			reg = w.regions.home()
		if reg.is_empty():
			return Vector2i(-1, -1)
		var r: Rect2i = reg["rect"] if reg["rect"] is Rect2i else Rect2i(Vector2i(int(reg["rect"][0]), int(reg["rect"][1])), Vector2i(int(reg["rect"][2]), int(reg["rect"][3])))
		var c: Vector2i = anchor if (anchor.x >= 0 and r.has_point(anchor)) else r.get_center()
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				cands.append(Vector2i(x, y))
		cands.sort_custom(func(a, b): return (a - c).length_squared() < (b - c).length_squared())
	else:
		var c2: Vector2i = anchor if anchor.x >= 0 else Vector2i(4, 4)
		for dy in range(-8, 9):
			for dx in range(-8, 9):
				cands.append(c2 + Vector2i(dx, dy))
		cands.sort_custom(func(a, b): return (a - c2).length_squared() < (b - c2).length_squared())
	var prefer_indoor: bool = def_id == "urn"
	for pass_i in (2 if prefer_indoor else 1):
		for t in cands:
			if _ok(w, def_id, t, prefer_indoor and pass_i == 0):
				return t
	return Vector2i(-1, -1)

static func _ok(w, def_id: String, t: Vector2i, want_indoor: bool) -> bool:
	if t.x < 1 or t.y < 1:
		return false
	var front: Vector2i = t + Vector2i(0, 1)
	if w.has_method("can_place"):
		if not w.can_place(def_id, t, 0):
			return false
		if w.has_method("is_outdoor") and bool(w.is_outdoor(t)) == want_indoor:
			return false
		if w.has_method("is_walkable") and not w.is_walkable(front):
			return false
		if w.has_method("object_at") and w.object_at(front) != null:
			return false
		if w.has_method("get_floor") and not _open_lawn(w, t):
			return false
	else:
		for o in SysUtil.all_world_objects():
			if o.tile == t or o.tile == front:
				return false
	for r in records.values():
		var rt: Array = r["tile"]
		if absi(int(rt[0]) - t.x) <= 1 and absi(int(rt[1]) - t.y) <= 1:
			return false
	return true

## A yard tile with open ground all around it: not on a path, doorstep or against a wall, so a memorial never blocks a route.
static func _open_lawn(w, t: Vector2i) -> bool:
	var fl: String = str(w.get_floor(t))
	if fl in ["stone", "tile", "wood", "carpet", "road", ""]:
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := t + Vector2i(dx, dy)
			if str(w.get_floor(n)) != fl:
				return false
			if w.has_method("object_at") and w.object_at(n) != null:
				return false
			if w.has_method("is_outdoor") and not bool(w.is_outdoor(n)):
				return false
	return true

# ------------------------------------------------------------------ lookup / text
static func record_for_object(object_id: int) -> Dictionary:
	return records.get(object_id, {})

static func list() -> Array:
	return records.values()

static func hover_text(obj) -> String:
	var r: Dictionary = record_for_object(int(obj.id))
	if r.is_empty():
		return ""
	var st: String = str(r.get("stage", "adult"))
	return "%s\nDied as %s %s on day %d\n%s" % [r["name"], Aging.article(st), str(Aging.stage_def(st).get("label", st)).to_lower(), int(r["died"]), r["cause"]]

# ------------------------------------------------------------------ interactions
static func on_game_event(ev: String, payload: Dictionary) -> void:
	if ev != "grave_remembered" and ev != "grave_mourned":
		return
	var f = SysUtil.folk(int(payload.get("folk_id", -1)))
	var r: Dictionary = record_for_object(int(payload.get("object_id", -1)))
	if f == null or r.is_empty():
		return
	r["visits"] = int(r["visits"]) + 1
	var key: String = "folk:%d" % int(r["folk_id"])
	if ev == "grave_remembered":
		Emotions.imprint(f, key, 0.2, "remember", "happy", "remembering %s" % r["name"])
	else:
		Emotions.imprint(f, key, 0.15, "mourn", "sad", "saying goodbye to %s" % r["name"])
		for b in ["grieving", "grieving_heavy", "grieving_shattered"]:
			f.remove_buff(b)
		f.add_buff("at_peace")

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"records": SysUtil.str_keys(records).duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	reset()
	var src: Dictionary = d.get("records", {})
	for k in src:
		var r: Dictionary = (src[k] as Dictionary).duplicate(true)
		SysUtil.ints_in(r, ["object_id", "folk_id", "born", "died", "years", "visits"])
		r["tile"] = SysUtil.to_ints(r.get("tile", [-1, -1]))
		records[int(str(k))] = r