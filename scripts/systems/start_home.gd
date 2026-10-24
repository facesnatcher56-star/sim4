class_name StartHome
extends RefCounted
## New-game home state (task 32d, data/start_home.json): 'empty' (default) or 'furnished'.
##   StartHome.default_id() / ids() / option(id)    the choices shown on the New Game screen
##   StartHome.apply(w, id, start_id) -> int         after the lot is built: strips the home of furniture when `id` == empty (returns objects removed)
##   StartHome.next_basic(hid) -> Dictionary         the first basic the household still lacks {id, text} or {} when all are bought
##   StartHome.is_bare(hid)                          the household owns no bed at all (the 'empty start' state)
## Pure function of the choice and the world; the host's choice is part of the saved world, so co-op clients see the same home.

static func cfg() -> Dictionary:
	return SysUtil.table("start_home")

static func ids() -> Array:
	var out: Array = []
	for o in cfg().get("options", []):
		out.append(str(o["id"]))
	return out

static func default_id() -> String:
	return str(cfg().get("default", "empty"))

static func option(id: String) -> Dictionary:
	for o in cfg().get("options", []):
		if str(o["id"]) == id:
			return o
	return {}

static func normalize(id: String) -> String:
	return id if id in ids() else default_id()

static func _keeps(def_id: String) -> bool:
	var c: Dictionary = cfg()
	if def_id in (c.get("keep_defs", []) as Array):
		return true
	var d: Dictionary = WorldIface.world().get_def(def_id)
	for t in d.get("tags", []):
		if str(t) in (c.get("keep_tags", []) as Array):
			return true
	return false

## Remove everything the player can buy from the home lot (all floors). Call right after the map is built.
static func apply(w, id: String) -> int:
	if normalize(id) != "empty":
		return 0
	var rc: Rect2i = w.regions.home().get("rect", Rect2i())
	var gone: Array = []
	for o in w.all_objects():
		if rc.has_point(o.tile) and not _keeps(str(o.def_id)):
			gone.append(int(o.id))
	gone.sort()
	for oid in gone:
		w.remove_object(oid)
	w.clear_undo()
	w.rooms.invalidate_all()
	return gone.size()

static func _count(hid: int, defs: Array) -> int:
	var n: int = 0
	for o in Economy.objects_of(hid):
		if str(o.def_id) in defs:
			n += 1
	if n == 0 and hid == Economy.primary_household() and defs.any(func(d): return d in (cfg().get("keep_defs", []) as Array)):
		for o2 in SysUtil.all_world_objects():          # task 64: the landlord's fixtures (toilet, shower) stay in the studio and count, though the tenant does not own them
			if str(o2.def_id) in defs and NeighborhoodLots.lot_at(o2.tile) == Neighborhood.HOME:
				n += 1
	return n

static func _residents(hid: int) -> int:
	var n: int = 0
	for f in SysUtil.residents():
		if int(f.household_id) == hid and str(f.age_stage) != "baby":
			n += 1
	return maxi(n, 1)

## First basic still missing (data order: bed, toilet, fridge, shower, stove, seats).
static func next_basic(hid: int) -> Dictionary:
	for b in cfg().get("basics", []):
		var need: int = _residents(hid) if bool(b.get("per_folk", false)) else 1
		if _count(hid, b["defs"]) < need:
			return {"id": str(b["id"]), "text": str(b["text"])}
	return {}

static func is_bare(hid: int) -> bool:
	return _count(hid, (cfg()["basics"][0]["defs"] as Array)) == 0

## The welcome tips for a fresh game: the buy-the-basics walkthrough when the home is bare, else the scenario's own.
static func tips_for(scenario_def: Dictionary) -> Array:
	if is_bare(Economy.primary_household()) and not (cfg().get("empty_tips", []) as Array).is_empty():
		return cfg()["empty_tips"]
	return Scenario.tips_text(scenario_def)
