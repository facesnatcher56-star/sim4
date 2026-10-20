class_name SoloMove
extends RefCounted
## Moving house (one-character play, R12.3). The lot called "home" is a ROLE of whichever lot the pawn lives in, so every system keeps asking for
## "home" and gets the right place: `swap_roles` exchanges the roles "home" and another lot (id, kind, owner, label; the table row's map position
## follows the physical lot). Belongings: what the pawn owns in the old place goes into the movers' store (up to `moving.max_objects`, the dearest
## first, a flat fee) and is put into the new place; what does not fit is sold at half price. Fixtures (structure, doors, bathroom) belong to the
## landlord (owner -1): never in a bill, never carried away. Numbers: data/solo.json "moving".

static var _orig_pos: Dictionary = {}     # lot id -> its [col,row] in data/neighborhood.json as loaded (the first time a role is swapped)

static func cfg() -> Dictionary:
	return SoloCfg.sect("moving")

static func _w():
	return WorldIface.world()

# ------------------------------------------------------------------ ownership
## The landlord's things in a lot: everything the start strip kept (structure, doors, windows, lights, bathroom) except the mailbox.
static func mark_fixtures(lot_id: String) -> int:
	var rc: Rect2i = NeighborhoodLots.rect_of(lot_id)
	var n := 0
	for o in SysUtil.all_world_objects():
		if rc.has_point(o.tile) and StartHome._keeps(str(o.def_id)) and str(o.def_id) != "mailbox":
			Economy.owner[int(o.id)] = -1
			n += 1
	return n

## Everything the household owned in the home lot stays behind for the landlord (an eviction): owner -1.
static func lose_everything_here(hid: int) -> void:
	var rc: Rect2i = NeighborhoodLots.rect_of(Neighborhood.HOME)
	for o in SysUtil.all_world_objects():
		if rc.has_point(o.tile) and int(Economy.owner.get(int(o.id), -1)) == hid:
			Economy.owner[int(o.id)] = -1

## The household's belongings in the home lot, dearest first: [{"id", "def", "value"}] (fixtures and other people's things are not listed).
static func belongings(hid: int) -> Array:
	var rc: Rect2i = NeighborhoodLots.rect_of(Neighborhood.HOME)
	var out: Array = []
	for o in SysUtil.all_world_objects():
		if rc.has_point(o.tile) and int(Economy.owner.get(int(o.id), -1)) == hid:
			out.append({"id": int(o.id), "def": str(o.def_id), "value": Economy.price_of_def(str(o.def_id))})
	out.sort_custom(func(a, b): return int(a["value"]) > int(b["value"]))
	return out

# ------------------------------------------------------------------ people
## Everybody of the household stands on the street outside the home lot (locked out).
static func put_on_street(hid: int) -> void:
	var t: Vector2i = NeighborhoodLots.street_tile(Neighborhood.HOME)
	_place_household(hid, t, true)

static func _place_household(hid: int, tile: Vector2i, street: bool) -> void:
	var i := 0
	for f in SysUtil.residents():
		if int(f.household_id) != hid:
			continue
		f.cancel_current("moved")
		f.clear_queue()
		var spot: Vector2i = tile + Vector2i(i % 3, i / 3)
		if _w() != null and not _w().is_walkable(spot):
			spot = tile
		f.tile = spot
		if "level" in f:
			f.level = 0
		f.set_meta(NeighborhoodLots.IN_LOT, "" if street else NeighborhoodLots.lot_at(spot))
		Neighborhood.refresh_view(int(f.id))
		i += 1

# ------------------------------------------------------------------ role swap
## Exchange the role "home" with `lot_b`. Returns false when either lot is missing.
static func swap_roles(lot_b: String) -> bool:
	var w = _w()
	if w == null or w.get("regions") == null or lot_b == Neighborhood.HOME:
		return false
	var rg: WorldRegions = w.regions
	var ra: Dictionary = rg.by_lot(Neighborhood.HOME)
	var rb: Dictionary = rg.by_lot(lot_b)
	if ra.is_empty() or rb.is_empty():
		return false
	_remember_positions()
	for k in ["lot", "kind", "owner", "label", "venue_type"]:
		var t = ra[k]
		ra[k] = rb[k]
		rb[k] = t
	rg.home_id = int(rb["id"])
	rg._lot_index_valid = false
	w.rooms.invalidate_all()
	# the properties follow their buildings
	var pa: Dictionary = HousingProps.get_prop("map_" + Neighborhood.HOME)
	var pb: Dictionary = HousingProps.get_prop("map_" + lot_b)
	if not pa.is_empty():
		pa["lot"] = lot_b
	if not pb.is_empty():
		pb["lot"] = Neighborhood.HOME
	var ph: String = str(SoloHome.phys.get(Neighborhood.HOME, Neighborhood.HOME))
	SoloHome.phys[Neighborhood.HOME] = str(SoloHome.phys.get(lot_b, lot_b))
	SoloHome.phys[lot_b] = ph
	resync_positions()
	return true

static func _remember_positions() -> void:
	if not _orig_pos.is_empty():
		return
	for l in Neighborhood.lots():
		_orig_pos[str(l["id"])] = (l.get("pos", [0, 0]) as Array).duplicate()

## After a swap or a load: the lot table's map positions follow the physical lots, the home template and spawn tiles follow the home role.
static func resync_positions() -> void:
	_remember_positions()
	for id in SoloHome.phys:
		var row: Dictionary = Neighborhood.lot(str(id))
		var src: String = str(SoloHome.phys[id])
		if not row.is_empty() and _orig_pos.has(src):
			row["pos"] = (_orig_pos[src] as Array).duplicate()
	var w = _w()
	if w == null or w.get("regions") == null or not w.regions.has_regions():
		return
	var home: Dictionary = (w.regions as WorldRegions).home()
	if home.is_empty():
		return
	Neighborhood.home_template = str(home.get("template", Neighborhood.home_template))
	var spawns: Array = []
	var rc: Rect2i = home["rect"]
	for sp in LotLoader.template(Neighborhood.home_template).get("spawn", []):
		spawns.append(Vector2i(int(sp[0]), int(sp[1])) + rc.position)
	if spawns.is_empty():
		spawns.append(NeighborhoodLots.entry_tile(Neighborhood.HOME))
	if "starter_spawn_tiles" in w:
		(w.starter_spawn_tiles as Array).clear()
		for t in spawns:
			(w.starter_spawn_tiles as Array).append(t)

## A new game or a load starts from the file's positions again (the table rows are shared data).
static func reset() -> void:
	for id in _orig_pos:
		var row: Dictionary = Neighborhood.lot(str(id))
		if not row.is_empty():
			row["pos"] = (_orig_pos[id] as Array).duplicate()
