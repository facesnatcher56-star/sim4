class_name MapLots
extends RefCounted
## New game / load: the continuous map WITH its lots. MapBuilder.build lays out roads and the empty lot rectangles; this
## places every lot's template at its region rect (LotLoader.place, origin = rect position), with `World.regions.enforce`
## off while it works, then switches build rules on (only the home region stays buildable).
##
##   MapLots.build(World, home_template, picks = {lot_id: template}) -> {ok, reports: {lot_id: LotLoader.report}, seconds}
##   MapLots.walk_spot(lot_id)           tile inside the lot where visitors arrive / walk to (door side, standable)
##   MapLots.gate(lot_id)                street-side gate tile of the lot (last row of its rect)
## Region fields set here: template (home = the chosen one), door = walk_spot.

static func build(w, home_template: String, picks: Dictionary = {}) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	MapBuilder.build(w)
	var rg: WorldRegions = w.regions
	rg.enforce = false
	var reports: Dictionary = {}
	var ok := true
	var home: Dictionary = {}
	for r in rg.regions.values():
		if not rg.is_lot(int(r["id"])):
			continue
		if str(r["kind"]) == "home":
			home = r
			continue
		r["template"] = str(picks.get(str(r["lot"]), r["template"]))
		ok = _place(w, r, str(r["template"]), reports) and ok
	if not home.is_empty():          # last: leaves the home's spawn tiles in the world
		home["template"] = home_template
		ok = _place(w, home, home_template, reports) and ok
	rg.enforce = true
	w.clear_undo()
	w.rooms.invalidate_all()
	w._emit("world_reset")
	return {"ok": ok, "reports": reports, "seconds": float(Time.get_ticks_usec() - t0) / 1.0e6}

static func _place(w, r: Dictionary, tid: String, reports: Dictionary) -> bool:
	if tid == "":
		return true
	var rc: Rect2i = r["rect"]
	var good: bool = LotLoader.place(tid, w, rc.position)
	var rep: Dictionary = LotLoader.report.duplicate(true)
	reports[str(r["lot"])] = rep
	r["door"] = _standable_near(w, rep["entry"] as Vector2i, rc)
	return good

## Nearest tile to `t` (inside rc) that is walkable and not a doorway edge case.
static func _standable_near(w, t: Vector2i, rc: Rect2i) -> Vector2i:
	for rad in 4:
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var c := t + Vector2i(dx, dy)
				if rc.has_point(c) and w.is_walkable(c):
					return c
	return t

static func walk_spot(lot_id: String) -> Vector2i:
	var r: Dictionary = WorldIface.world().regions.by_lot(lot_id)
	if r.is_empty():
		return Vector2i(-1, -1)
	return r.get("door", r["entry"])

static func gate(lot_id: String) -> Vector2i:
	var r: Dictionary = WorldIface.world().regions.by_lot(lot_id)
	return Vector2i(-1, -1) if r.is_empty() else (r["entry"] as Vector2i)
