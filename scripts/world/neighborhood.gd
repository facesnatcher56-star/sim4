class_name Neighborhood
extends RefCounted
## The neighbourhood REGISTRY: ~11 lots (the player's home, 3 townie homes, community venues) that all exist at once on the
## one continuous map (World + World.regions; MapLots places them). There is no lot swapping any more: where a folk is follows
## from its tile (`where` / `lot_of`), travel is a real walk (NeighborhoodTravel) and the venue entry rules run when a folk
## walks into a lot (NeighborhoodLots.on_minute). Folk are never parked or hidden because of where they are.
##
## Public API (all static):
##   Neighborhood.start_game(template_id)            fresh game: build the map with every lot, home = template_id
##   Neighborhood.lots() / lot(id) / lot_ids() / is_open(id) / label_of(id) / residents_of(id) / travel_minutes(a, b)
##   Neighborhood.where(folk_id) / lot_of(folk) / lot_of_selected() / folk_at(lot_id)     location, derived from the tile
##   Neighborhood.travel(ids, lot, opts) / can_travel / go_home / movable                 see NeighborhoodTravel
##   Neighborhood.entry_tile(lot_id) / spawns_of(lot_id)                                  tiles on the map
##   Neighborhood.to_dict() / from_dict(d)           pantry / visits / meetups / loc / walks (the lots live in the World save)

const HOME := "home"
const TRAVEL := "travel"                 # Away reason of fast travel
const HELD_REASONS := ["work", "school", "party"]    # away reasons we never interrupt
const SAVE_VERSION := 2

static var home_template: String = LotLoader.CLASSIC
static var loc: Dictionary = {}          # folk_id -> lot_id the folk is walking to / was sent to
static var pantry: int = 0               # grocery units bought at the market, delivered to the home fridge
static var visits: Dictionary = {}       # lot_id -> number of times a resident went there
static var last_report: Dictionary = {}
static var meetups: Array = []           # invitations to hang out at a venue
static var world_seed: int = 0          # per-game seed of the lot layout draw (LotPicker); saved
static var selected: int = -1            # folk id the HUD has selected (lot_of_selected)

# ------------------------------------------------------------------ data
static func cfg() -> Dictionary:
	return SysUtil.table("neighborhood")

static func lots() -> Array:
	return cfg().get("lots", [])

static func lot_ids() -> Array:
	var out: Array = []
	for l in lots():
		out.append(str(l["id"]))
	return out

static func lot(lot_id: String) -> Dictionary:
	for l in lots():
		if str(l["id"]) == lot_id:
			return l
	return {}

static func starts() -> Array:
	return cfg().get("starts", [])

static func start_def(start_id: String) -> Dictionary:
	for s in starts():
		if str(s["id"]) == start_id:
			return s
	return {}

## Template id that builds this lot (home -> the chosen home template).
static func template_of(lot_id: String) -> String:
	if lot_id == HOME:
		return home_template
	var w = WorldIface.world()
	if w != null and w.get("regions") != null:
		var t := str((w.regions as WorldRegions).by_lot(lot_id).get("template", ""))
		if t != "":
			return t          # the template this game's map was built with (saved in the regions)
	return str(lot(lot_id).get("template", ""))

static func label_of(lot_id: String) -> String:
	if lot_id == "":
		return "the street"
	var l: Dictionary = lot(lot_id)
	if l.is_empty() and WorldIface.world() != null and WorldIface.world().get("regions") != null:      # task 22: holiday zones are lots that exist only on a trip
		return str((WorldIface.world().regions as WorldRegions).by_lot(lot_id).get("label", lot_id))
	return str(l.get("label", lot_id))

static func venue_type(lot_id: String) -> String:
	return Venues.type_of_lot(lot_id)

static func is_home(lot_id: String) -> bool:
	return lot_id == HOME

static func is_open(lot_id: String) -> bool:
	return Venues.is_open(lot_id)

static func pos_of(lot_id: String) -> Vector2:
	var p: Array = lot(lot_id).get("pos", [0, 0])
	return Vector2(float(p[0]), float(p[1]))

static func distance(a: String, b: String) -> int:
	if a == b:
		return 0
	var pa := pos_of(a)
	var pb := pos_of(b)
	return int(absf(pa.x - pb.x) + absf(pa.y - pb.y))

## Fast-travel time between two lots (block distance on the neighbourhood grid).
static func travel_minutes(a: String, b: String) -> int:
	if a == b:
		return 0
	var t: Dictionary = cfg().get("travel", {})
	if a == "":          # from the street: the base time
		return int(t.get("base_min", 5))
	var m: int = int(t.get("base_min", 5)) + int(t.get("per_block_min", 4)) * distance(a, b)
	return clampi(m, int(t.get("base_min", 5)), int(t.get("max_min", 40)))

## Townies living at a townie-home lot (Story townies are spread over the three homes by their `lot` number).
static func residents_of(lot_id: String) -> Array:
	var homes: Array = []
	for l in lots():
		if str(l.get("type", "")) == "townie_home" and not PlayerLots.is_claimed(str(l["id"])):      # a co-op player lives there now: its townies moved to the other homes
			homes.append(str(l["id"]))
	var idx: int = homes.find(lot_id)
	var out: Array = []
	if idx < 0:
		return out
	for t in Story.alive_townies():
		if (int(t.get("lot", 1)) - 1) % homes.size() == idx and Story.stage_of(t) != "baby":
			out.append(t)
	return out

static func home_of_townie(townie_id: int) -> String:
	for l in lots():
		if str(l.get("type", "")) == "townie_home":
			for t in residents_of(str(l["id"])):
				if int(t["id"]) == townie_id:
					return str(l["id"])
	return ""

# ------------------------------------------------------------------ map positions
static func entry_tile(lot_id: String) -> Vector2i:
	return NeighborhoodLots.entry_tile(lot_id)

static func spawns_of(lot_id: String) -> Array:
	return NeighborhoodLots.spawns_of(lot_id)

static func rect_of(lot_id: String) -> Rect2i:
	return NeighborhoodLots.rect_of(lot_id)

# ------------------------------------------------------------------ state
static func reset() -> void:
	home_template = LotLoader.CLASSIC
	loc.clear()
	pantry = 0
	visits.clear()
	meetups.clear()
	last_report = {}
	selected = -1
	Crowd.reset()

# ------------------------------------------------------------------ who is where (derived from tiles)
## Lot id of a tile's region ("" on streets / parks).
static func lot_at(tile: Vector2i) -> String:
	return NeighborhoodLots.lot_at(tile)

static func lot_of_folk(f) -> String:
	return "" if f == null else NeighborhoodLots.lot_at(f.tile)

static func lot_of(f) -> String:
	return lot_of_folk(f)

static func where(folk_id: int) -> String:
	return lot_of_folk(SysUtil.folk(folk_id))

## Lot of the folk the HUD has selected (first resident when nothing is selected); "" on the street.
static func lot_of_selected() -> String:
	var f = SysUtil.folk(selected)
	if f == null:
		var res: Array = SysUtil.residents()
		f = res[0] if not res.is_empty() else null
	return lot_of_folk(f)

## Resident folk ids standing in a lot.
static func folk_at(lot_id: String) -> Array:
	var out: Array = []
	for f in SysUtil.residents():
		if lot_of_folk(f) == lot_id:
			out.append(int(f.id))
	return out

## Lot a folk is walking to ("" when not travelling).
static func heading_to(folk_id: int) -> String:
	return NeighborhoodLots.walking_to(SysUtil.folk(folk_id))

static func traveling(folk_id: int) -> bool:
	return str(Away.info(folk_id).get("reason", "")) == TRAVEL or str((Away.pending.get(folk_id, {}) as Dictionary).get("reason", "")) == TRAVEL \
		or heading_to(folk_id) != ""

## Everybody of the household is in the home lot (or away at work / school): nobody is out and about.
static func everyone_home() -> bool:
	for f in SysUtil.residents():
		if not SysUtil.is_away(f) and lot_of_folk(f) != HOME:
			return false
	return true

# ------------------------------------------------------------------ new game
## Build the whole map: roads, every lot with its template, `template_id` on the home lot. Forgets everything else.
## Every other lot draws its own layout from its pool (LotPicker) with `p_seed` (default 1; new games pass a random one).
static func start_game(template_id: String = LotLoader.CLASSIC, p_seed: int = 1) -> bool:
	reset()
	home_template = template_id
	world_seed = p_seed
	NeighborhoodContent.install()
	var w = WorldIface.world()
	var picks: Dictionary = LotPicker.pick(p_seed, "", template_id)
	var res: Dictionary = MapLots.build(w, template_id, picks)
	last_report = (res["reports"] as Dictionary).get(HOME, {})
	for lid in (res["reports"] as Dictionary):
		var fails: Array = (res["reports"][lid] as Dictionary).get("failed", [])
		if not fails.is_empty():
			push_warning("Neighborhood: lot %s built with problems: %s" % [lid, str(fails)])
	return bool(res["ok"])

## Call after SystemsManager.new_game (which resets this class): remember the chosen home, scale the starting funds.
## `funds` >= 0 overrides the start's own number (the new-game flow passes scenario funds x difficulty).
static func finish_new_game(start_id: String, funds: int = -1) -> void:
	var sd: Dictionary = start_def(start_id)
	var hr: Dictionary = WorldIface.world().regions.home()
	home_template = str(hr.get("template", "")) if str(hr.get("template", "")) != "" else str(sd.get("template", LotLoader.CLASSIC))
	if funds < 0 and sd.has("funds"):
		funds = int(sd["funds"])
	if funds >= 0:
		var hid: int = Economy.primary_household()
		WorldIface.coins[hid] = 0
		Economy.deposit(hid, funds, "starting funds")

# ------------------------------------------------------------------ travel (see NeighborhoodTravel)
static func movable(folk_ids: Array) -> Array:
	return NeighborhoodTravel.movable(folk_ids)

static func can_travel(folk_ids: Array, lot_id: String) -> Dictionary:
	return NeighborhoodTravel.can_travel(folk_ids, lot_id)

static func travel(folk_ids: Array, lot_id: String, opts: Dictionary = {}) -> Dictionary:
	return NeighborhoodTravel.travel(folk_ids, lot_id, opts)

static func go_home(folk_ids: Array = [], opts: Dictionary = {}) -> Dictionary:
	return NeighborhoodTravel.go_home(folk_ids, opts)

static func walk_minutes(folk_id: int, lot_id: String) -> int:
	return NeighborhoodTravel.walk_minutes(folk_id, lot_id)

static func focus_camera(t: Vector2i) -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var lv = (ml as SceneTree).get_first_node_in_group("lot_view")      # no LotView reference: keeps this script headless-safe
		if lv != null and lv.has_method("focus_tile"):
			lv.call("focus_tile", t)

## Move the camera to the middle of a lot.
static func focus_lot(lot_id: String) -> void:
	var rc := rect_of(lot_id)
	if rc.size != Vector2i.ZERO:
		focus_camera(rc.position + rc.size / 2)

static func refresh_view(fid: int) -> void:
	var ev = SimEnv.events()
	ev.emit_signal("folk_removed", fid)
	ev.emit_signal("folk_added", fid)

# ------------------------------------------------------------------ pantry (market -> home fridge)
static func add_pantry(units: int) -> void:
	pantry += units

static func apply_pantry() -> int:
	if pantry <= 0:
		return 0
	var cap: int = int(cfg().get("pantry", {}).get("fridge_max", 10))
	var added := 0
	for o in WorldIface.world().objects_of_def("fridge"):
		if NeighborhoodLots.lot_at(o.tile) != HOME:
			continue
		var cur: int = int(float(WorldIface.state_get(o, "stock", 0.0)))
		var add: int = mini(pantry - added, maxi(cap - cur, 0))
		if add > 0:
			WorldIface.world().add_object_state(o.id, "stock", float(add))
			added += add
	if added > 0:
		pantry -= added
		SysUtil.notify("Groceries from the market stocked the fridge (+%d)." % added, "good")
	return added

# ------------------------------------------------------------------ persistence
## Only the bookkeeping: the lots themselves are in the World save (objects, floors, regions).
static func to_dict() -> Dictionary:
	var walks: Dictionary = {}
	for f in SysUtil.residents():
		var to: String = NeighborhoodLots.walking_to(f)
		if to != "":
			walks[str(f.id)] = {"lot": to, "dest": [entry_tile(to).x, entry_tile(to).y]}
	return {"home_template": home_template, "world_seed": world_seed, "loc": SysUtil.str_keys(loc), "pantry": pantry, "visits": visits.duplicate(),
		"meetups": meetups.duplicate(true), "npc_ids": Crowd.npc_ids(), "walks": walks, "version": SAVE_VERSION}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	home_template = str(d.get("home_template", LotLoader.CLASSIC))
	world_seed = int(d.get("world_seed", 0))
	var lc: Dictionary = SysUtil.int_keys(d.get("loc", {}))
	for k2 in lc:
		loc[int(k2)] = str(lc[k2])
	pantry = int(d.get("pantry", 0))
	visits = (d.get("visits", {}) as Dictionary).duplicate()
	meetups = (d.get("meetups", []) as Array).duplicate(true)
	# crowd / staff NPCs are not restored: remove the ones SaveLoad re-created, they respawn from the venue rules
	for nid in d.get("npc_ids", []):
		if SysUtil.folk(int(nid)) != null:
			SysUtil.world_remove_folk(int(nid))
	for f in SysUtil.residents():          # nobody is "entering" a lot just because the game was loaded
		f.set_meta(NeighborhoodLots.IN_LOT, lot_of_folk(f))
	var walks: Dictionary = d.get("walks", {})
	for k in walks:
		var f2 = SysUtil.folk(int(k))
		if f2 == null or SysUtil.is_away(f2):
			continue
		var w: Dictionary = walks[k]
		f2.set_meta("walk_to", str(w["lot"]))
		NeighborhoodLots.walk_to(f2, Vector2i(int(w["dest"][0]), int(w["dest"][1])), str(w["lot"]))
