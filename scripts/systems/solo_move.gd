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

## The pawn's things leave the old place: removed from the lot, up to the cap, dearest first. Returns the store [{"def", "value"}].
static func take_belongings(hid: int) -> Array:
	var w = _w()
	var out: Array = []
	var cap: int = int(cfg().get("max_objects", 40))
	for b in belongings(hid):
		if out.size() >= cap:
			break
		if w != null and w.remove_object(int(b["id"])):
			out.append({"def": str(b["def"]), "value": int(b["value"])})
	return out

## A property record for a lot that had none (the Elm Court rooms): valued from the rung's rent.
static func make_prop(lot_label: String, r: Dictionary) -> Dictionary:
	var rent: int = SoloCfg.rung_rent(r)
	var p: Dictionary = HousingProps.make("map_" + lot_label + "_" + str(r.get("id", "")), str(r.get("label", lot_label)), "flat", maxi(int(float(rent) / 0.012), 1000), 0.3, 70.0, lot_label)
	HousingProps.props[str(p["id"])] = p
	return p

## The household walks into the new home; the movers put the belongings in; what does not fit is sold at half price; a furnished rung gets its bed.
static func move_in() -> void:
	var hid: int = Economy.primary_household()
	var w = _w()
	var rc: Rect2i = NeighborhoodLots.rect_of(Neighborhood.HOME)
	var spawn: Vector2i = NeighborhoodLots.entry_tile(Neighborhood.HOME)
	if w != null and "starter_spawn_tiles" in w and not (w.starter_spawn_tiles as Array).is_empty():
		spawn = (w.starter_spawn_tiles as Array)[0]
	_place_household(hid, spawn, false)
	var rooms: Array = [] if w == null else AutoFurnish._rooms(w, rc)
	var placed: Array = []
	var sold := 0
	var furnished: String = str(SoloHome.rung_def().get("furnished", ""))
	if furnished == "cot" and not rooms.is_empty():
		_put(w, hid, "single_bed", rooms, rc, placed, -1)
	for it in SoloHome.stored:
		if rooms.is_empty() or _put(w, hid, str(it["def"]), rooms, rc, placed, hid) < 0:
			var back: int = int(int(it["value"]) / 2)
			sold += back
			Economy.deposit(hid, back, "sold: no room in the new place")
	if sold > 0:
		SysUtil.notify("Some of your things did not fit and were sold for %d coins." % sold, "info")
	SoloHome.stored = []
	Neighborhood.focus_lot(Neighborhood.HOME)

static func _put(w, hid: int, def_id: String, rooms: Array, rc: Rect2i, placed: Array, owner_hid: int) -> int:
	for room in AutoFurnish._rooms_by_preference(rooms, "largest"):
		var oid: int = AutoFurnish._place_one(w, hid, def_id, room, rc, placed)
		if oid >= 0:
			placed.append(oid)
			Economy.owner[oid] = owner_hid
			Economy.placed_day[oid] = SysUtil.day()
			return oid
	return -1

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
	var pa: Dictionary = prop_at(Neighborhood.HOME)
	var pb: Dictionary = prop_at(lot_b)
	if not pa.is_empty():
		pa["lot"] = lot_b
	if not pb.is_empty():
		pb["lot"] = Neighborhood.HOME
	var ph: String = str(SoloHome.phys.get(Neighborhood.HOME, Neighborhood.HOME))
	SoloHome.phys[Neighborhood.HOME] = str(SoloHome.phys.get(lot_b, lot_b))
	SoloHome.phys[lot_b] = ph
	resync_positions()
	return true

## The housing property standing on the lot with this label ({} for a lot without one).
static func prop_at(lot_label: String) -> Dictionary:
	for id in HousingProps.props:
		if str(HousingProps.props[id].get("lot", "")) == lot_label:
			return HousingProps.props[id]
	return {}

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
