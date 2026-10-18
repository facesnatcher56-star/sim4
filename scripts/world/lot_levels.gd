class_name LotLevels
extends RefCounted
## Multi-floor part of a lot template (called by LotLoader.place). A template with a `levels` block is a building with several floors:
##
##   "roof": "flat",                                  optional roof style (flat | gable | hip | none)
##   "levels": {"1": {"floors": [...], "walls": [...]}, "2": {...}, "-1": {...}}      same shape as the ground floor / walls lists
##   objects: any entry may carry "level": n (default 0); stairs / ladders / lifts are ordinary objects with a `portal` block
##
## prepare() registers the building (footprint = the ground walls' bounding box + 1 tile, range = the highest / lowest key) and
## lays the floors and walls of every level BEFORE any object is placed, so objects and wall-mounted doors / windows of every level
## find their walls and floors. Lifts placed on level 0 run up to the highest level automatically (WorldObjects.default_span).

static func prepare(t: Dictionary, w, origin: Vector2i, template_id: String) -> int:
	var lv: Dictionary = t.get("levels", {})
	if lv.is_empty():
		return -1
	var lo := 0
	var hi := 0
	for k in lv:
		lo = mini(lo, int(k))
		hi = maxi(hi, int(k))
	var br := LotLoader.building_rect(template_id)
	var rc := Rect2i(br.position + origin, br.size).grow(1)
	var rid: int = w.regions.region_at(rc.position + rc.size / 2) if w.regions.has_regions() else -1
	var bid: int = w.levels.add_building(rc, lo, hi, {"roof": str(t.get("roof", "flat")), "region": rid, "label": str(t.get("label", ""))})
	for key in lv:
		var level := int(key)
		var ld: Dictionary = lv[key]
		for fl in ld.get("floors", []):
			var r: Array = fl["rect"]
			w.levels.set_floor_rect_raw(Vector2i(int(r[0]), int(r[1])) + origin, Vector2i(int(r[2]), int(r[3])) + origin, str(fl["type"]), level)
		for wl in ld.get("walls", []):
			var a: Array = wl["a"]
			var b: Array = wl["b"]
			LotLoader._wall_line(w, Vector2i(int(a[0]), int(a[1])) + origin, Vector2i(int(b[0]), int(b[1])) + origin, str(wl["type"]), level)
	return bid
