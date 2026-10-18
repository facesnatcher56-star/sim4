class_name Workplace
extends RefCounted
## Where a career (or school) happens on the map. Data: career.workplace = lot id in data/careers.json (school = the "school" lot),
## career.visible_work = interaction id of a job done ON the lot (data/commute.json, see VisibleWork).
##   Workplace.lot_for(career_id) / lot_of_folk(f)     lot id, "" when the map has no such lot (tests on a bare stub world: no commute)
##   Workplace.entry_tile(career_id)                   {"tile": Vector2i, "level": int} - the door; `level` is the multi-floor hook
##                                                     (office jobs get a floor in the tower once task 10 lands)
##   Workplace.desk_tile(lot_id, f)                    where a hidden worker "is" inside (staff post / a desk / the door)
##   Workplace.commute_minutes(f, tile)                planned walk (route x walk minutes x weather x injury) in game minutes
##   Workplace.coworkers(f)                            residents + present townies sharing the workplace
## Config: data/commute.json.

const MARK := "_commute_content"
const SCHOOL := "school"

static func install() -> void:
	ContentMerge.install(cfg().get("content", {}), MARK, {"_sys_gate": true})

static func cfg() -> Dictionary:
	return SimEnv.data().get_table("commute")

static func num(key: String, default: float) -> float:
	return float(cfg().get(key, default))

# ------------------------------------------------------------------ lookups
static func map_ready() -> bool:
	var w = WorldIface.world()
	return w != null and "regions" in w and w.regions != null and w.regions.has_regions()

## Lot of a career ("" = none / not on this map).
static func lot_for(career_id: String) -> String:
	var lot: String = str(Careers.career_def(career_id).get("workplace", ""))
	if lot == "" or not map_ready() or Neighborhood.lot(lot).is_empty():
		return ""
	return lot

static func lot_of_folk(f) -> String:
	if f == null:
		return ""
	var fid: int = int(f.id)
	if Careers.jobs.has(fid):
		return lot_for(str(Careers.jobs[fid]["career"]))
	if Careers.school.has(fid):
		return SCHOOL if (map_ready() and not Neighborhood.lot(SCHOOL).is_empty()) else ""
	return ""

static func entry_tile(career_id: String) -> Dictionary:
	var lot: String = lot_for(career_id)
	if lot == "":
		return {"tile": Vector2i(-1, -1), "level": 0}
	return {"tile": NeighborhoodLots.entry_tile(lot), "level": 0}

static func visible_job(career_id: String) -> String:
	return str(Careers.career_def(career_id).get("visible_work", ""))

## The staff post of a lot (template staff tile moved to the lot), else Vector2i(-1, -1).
static func staff_tile(lot_id: String) -> Vector2i:
	var staff: Array = LotLoader.template(Neighborhood.template_of(lot_id)).get("staff", [])
	if staff.is_empty():
		return Vector2i(-1, -1)
	var t: Array = staff[0]["tile"]
	return Vector2i(int(t[0]), int(t[1])) + NeighborhoodLots.rect_of(lot_id).position

## Where a hidden worker stands inside the building: a desk of the lot (different folk, different desks), else the staff post, else the door.
static func desk_tile(lot_id: String, f) -> Vector2i:
	var w = WorldIface.world()
	var desks: Array = []
	if w != null:
		for o in w.all_objects():
			if (o.def_id == "computer" or o.def_id == "desk") and NeighborhoodLots.lot_at(o.tile) == lot_id:
				desks.append(o)
	if not desks.is_empty():
		desks.sort_custom(func(a, b): return a.id < b.id)
		var o2 = desks[int(f.id) % desks.size()]
		var t: Vector2i = WorldIface.use_tile(o2, 0)
		if w.is_walkable(t):
			return t
	var st: Vector2i = staff_tile(lot_id)
	return st if st.x >= 0 else NeighborhoodLots.entry_tile(lot_id)

# ------------------------------------------------------------------ time
## Speed factor the folk walks at right now (injury x weather).
static func speed_factor(f) -> float:
	return maxf(Health.speed_mult(f) * Weather.walk_speed_mult_at(f.tile), 0.2)

## Planned minutes to walk from the folk's tile to `to`: -1 when there is no route.
static func commute_minutes(f, to: Vector2i) -> float:
	var n: int = WorldIface.path_length(f.tile, to)
	if n < 0:
		return -1.0
	return float(n) * Interaction.WALK_MIN_PER_TILE / speed_factor(f)

## Extra wait on the way (placeholder for real traffic): every busy road crossing on the route costs a little. 0 without Traffic.provider.
static func traffic_delay(f, to: Vector2i) -> float:
	if not Traffic.provider.is_valid():
		return 0.0
	var hour: float = SysUtil.hour_f()
	var wait: float = 0.0
	for t in WorldIface.find_path(f.tile, to):
		if Traffic.road_kind(t) == "crosswalk":
			wait += Traffic.risk_at(t, hour) * num("traffic_wait_min", 1.5)
	return wait

# ------------------------------------------------------------------ coworkers
## Everybody who works (or studies) at the same lot as `f`: residents with that workplace and townies with a career there.
static func coworkers(f) -> Array:
	var lot: String = lot_of_folk(f)
	var out: Array = []
	if lot == "":
		return out
	for r in SysUtil.residents():
		if r != f and lot_of_folk(r) == lot and not Careers.school.has(int(r.id)):
			out.append(int(r.id))
	for t in Story.alive_townies():
		if lot_for_townie(t) == lot:
			out.append(int(t["id"]))
	return out

static func lot_for_townie(t: Dictionary) -> String:
	var cid: String = str(t.get("career", ""))
	return "" if cid == "" else lot_for(cid)

## A small first-meeting / friendship bonus between a resident arriving at work and the coworkers standing near the door.
static func greet_coworkers(f, lot_id: String) -> void:
	var rid: int = int(f.id)
	var bonus: float = num("coworker_friendship", 1.5)
	for n in Crowd.crowd_folk(lot_id):
		if not n.has_meta("coworker") or n.has_meta("leaving") or not n.has_meta("townie_id"):
			continue
		if absi(n.tile.x - f.tile.x) + absi(n.tile.y - f.tile.y) > 12:
			continue
		var tid: int = int(n.get_meta("townie_id"))
		if not RelationshipService.knows(rid, tid):
			RelationshipService.add_both(rid, tid, "friendship", bonus * 2.0)
			RelationshipService.add_history(rid, tid, "met", 0.3, tid)
			SysUtil.notify("%s met a coworker, %s." % [f.name, n.name], "relationship")
			SysUtil.game_event("met_townie", {"folk_id": rid, "townie_id": tid, "lot_id": lot_id})
		else:
			RelationshipService.add_both(rid, tid, "friendship", bonus)
			RelationshipService.touch(rid, tid)
		return
	for o in SysUtil.residents():          # household coworkers who are already inside: they know each other, a little warmer
		if o != f and Commute.on_shift(int(o.id)) and lot_of_folk(o) == lot_id:
			RelationshipService.add_both(rid, int(o.id), "friendship", bonus * 0.5)
