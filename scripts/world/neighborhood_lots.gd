class_name NeighborhoodLots
extends RefCounted
## Where things are on the one map: lot lookups by tile (derived from World.regions) and the per-minute region watcher that
## reacts when a resident walks into / out of a lot (entry rules at venues, arrival toasts, groceries at home).
##
## Watcher: each resident carries the meta "in_lot" (lot id they were last seen in, "" = street). When it changes:
##   leaving   -> forget a refused entry
##   entering  -> visits +1; home: groceries from the pantry; venues: Venues.check_entry -> refused folk get a toast and
##                walk back out to the street, otherwise Venues.charge_entry (per folk) unless they came with a free pass.
## A folk that is only walking THROUGH a lot on its way elsewhere is ignored until it stops.

const IN_LOT := "in_lot"

static func _regions():
	var w = WorldIface.world()
	return w.regions if (w != null and "regions" in w) else null

# ------------------------------------------------------------------ lookups
## Neighbourhood lot id at a tile ("" on streets, parks and open ground). A world without regions (the classic single lot of
## small tests) is entirely the home lot.
static func lot_at(tile: Vector2i) -> String:
	var rg = _regions()
	if rg == null or not rg.has_regions():
		return Neighborhood.HOME
	var r: Dictionary = rg.region_of(tile)
	if r.is_empty() or not (str(r["kind"]) in WorldRegions.LOT_KINDS):
		return ""
	return str(r["lot"])

static func rect_of(lot_id: String) -> Rect2i:
	var rg = _regions()
	if rg == null:
		return Rect2i()
	var r: Dictionary = rg.by_lot(lot_id)
	return Rect2i() if r.is_empty() else (r["rect"] as Rect2i)

## Tile visitors walk to (inside the lot, door side).
static func entry_tile(lot_id: String) -> Vector2i:
	var rg = _regions()
	var r: Dictionary = {} if rg == null else rg.by_lot(lot_id)
	if r.is_empty():
		return Vector2i(-1, -1)
	return r.get("door", r["entry"])

## Street tile just outside the lot's gate.
static func street_tile(lot_id: String) -> Vector2i:
	var rc := rect_of(lot_id)
	return Vector2i(rc.position.x + MapBuilder.GATE_X, rc.end.y)

## Tiles where crowd NPCs / arrivals appear: the template's spawn tiles moved to the lot (home: the real spawn tiles).
static func spawns_of(lot_id: String) -> Array:
	var out: Array = []
	var rc := rect_of(lot_id)
	if lot_id == Neighborhood.HOME:
		var w = WorldIface.world()
		if w != null and "starter_spawn_tiles" in w:
			out.append_array(w.starter_spawn_tiles)
	else:
		for sp in LotLoader.template(Neighborhood.template_of(lot_id)).get("spawn", []):
			out.append(Vector2i(int(sp[0]), int(sp[1])) + rc.position)
	if out.is_empty():
		out.append(entry_tile(lot_id))
	return out

## Tiles from `tile` to the lot's rectangle (0 inside).
static func distance_to(tile: Vector2i, lot_id: String) -> int:
	var rc := rect_of(lot_id)
	if rc.size == Vector2i.ZERO:
		return 1 << 20
	var dx := maxi(maxi(rc.position.x - tile.x, tile.x - (rc.end.x - 1)), 0)
	var dy := maxi(maxi(rc.position.y - tile.y, tile.y - (rc.end.y - 1)), 0)
	return maxi(dx, dy)

## True when a visible resident (not away at work / school / party) is within `radius` tiles of the lot.
static func player_near(lot_id: String, radius: int) -> bool:
	for f in SysUtil.residents():
		if not SysUtil.is_away(f) and distance_to(f.tile, lot_id) <= radius:
			return true
	return false

# ------------------------------------------------------------------ walking helpers
## Lot a folk is currently walking to (travel() tags its go_here), "" if none.
static func walking_to(f) -> String:
	if f == null:
		return ""
	if f.current != null and f.current.def_id == "go_here" and f.current.params.has("lot"):
		return str(f.current.params["lot"])
	for q in f.queue:
		if (q as Interaction).def_id == "go_here" and (q as Interaction).params.has("lot"):
			return str((q as Interaction).params["lot"])
	return ""

static func walk_to(f, tile: Vector2i, lot_id: String) -> bool:
	var ir := Interaction.create_goto(f, tile, true)
	if ir == null:
		return false
	ir.params["lot"] = lot_id
	f.enqueue(ir)
	return true

## Away "travel" (fast travel) of a folk ends without placing it anywhere.
static func detach_travel(f) -> void:
	if f == null:
		return
	var fid: int = int(f.id)
	var reason: String = str(Away.info(fid).get("reason", ""))
	if reason == "" and Away.pending.has(fid):
		reason = str((Away.pending[fid] as Dictionary).get("reason", ""))
	if reason != Neighborhood.TRAVEL:
		return
	if Away.pending.has(fid):
		for q in f.queue.duplicate():
			if (q as Interaction).def_id == Away.IID:
				f.queue.erase(q)
		Away.pending.erase(fid)
	if Away.active.has(fid):
		if f.current != null and f.current.def_id == Away.IID:
			f.current.cancel("detached")
		else:
			Away.active.erase(fid)
	if f.has_meta("away") and str(f.get_meta("away")) == Neighborhood.TRAVEL:
		f.remove_meta("away")
		f.remove_buff("away")

# ------------------------------------------------------------------ region watcher
static func on_minute() -> void:
	for f in SysUtil.residents():
		if SysUtil.is_away(f):
			continue
		var now: String = lot_at(f.tile)
		if not f.has_meta(IN_LOT):
			f.set_meta(IN_LOT, now)
			continue
		var prev: String = str(f.get_meta(IN_LOT))
		if now == prev:
			continue
		var heading: String = walking_to(f)
		if f.current != null and f.current.state == "walking" and heading != now:
			continue          # just passing through
		f.set_meta(IN_LOT, now)
		if prev != "":
			_on_leave(f, prev)
		if now != "":
			_on_enter(f, now)

static func mark_inside(f, lot_id: String) -> void:
	f.set_meta(IN_LOT, lot_id)

static func _on_leave(f, lot_id: String) -> void:
	if f.has_meta("denied") and str(f.get_meta("denied")) == lot_id:
		f.remove_meta("denied")

static func _on_enter(f, lot_id: String) -> void:
	var fid: int = int(f.id)
	Neighborhood.visits[lot_id] = int(Neighborhood.visits.get(lot_id, 0)) + 1
	if str(f.get_meta("walk_to", "")) == lot_id:
		f.remove_meta("walk_to")
		Neighborhood.loc.erase(fid)
		SysUtil.notify("%s arrived at %s." % [f.name, Neighborhood.label_of(lot_id)], "travel")
	if lot_id == Neighborhood.HOME:
		Neighborhood.apply_pantry()
		return
	if str(f.get_meta("free_pass", "")) == lot_id:
		f.remove_meta("free_pass")
		return
	if f.has_meta("denied") and str(f.get_meta("denied")) == lot_id:
		return
	var chk: Dictionary = Venues.check_entry(lot_id, [fid], int(f.household_id))
	if not bool(chk["ok"]):
		SysUtil.notify(str(chk["reason"]), "warn")
		f.set_meta("denied", lot_id)
		f.cancel_current("denied")
		f.clear_queue()
		walk_to(f, street_tile(lot_id), "")
		return
	Venues.charge_entry(lot_id, [fid], int(f.household_id))
