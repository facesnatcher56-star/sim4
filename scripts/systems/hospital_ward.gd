class_name HospitalWard
extends RefCounted
## The hospital as a real place (task 10 part B). When the map has a hospital lot (a multi-floor building with `hospital_bed` / `birth_bed`
## objects), Hospital.admit puts a RESIDENT patient into a free ward bed of that building (full simulation: the folk lies in the bed on its
## floor, visible when the player looks at the ward) and Hospital.discharge / the end of the stay sends them home. Far townies (no Folk on
## the map), worlds without a hospital lot and full wards keep the statistical Away stay of Hospital.
##   HospitalWard.lot_id()                    id of the hospital lot ("" when the map has none)
##   HospitalWard.ready()                     true when a patient can be placed in a real bed right now
##   HospitalWard.place(f, rec, maternity)    teleport `f` into a free bed and queue the `hospital_stay` interaction; false = use Away
##   HospitalWard.release(f, rec)             end of the stay: cancel the interaction, send the folk (and a newborn) home
##   HospitalWard.birth(mother, baby)         a hospital birth: mother and baby are placed in the maternity ward; true when it happened
##   HospitalWard.beds(maternity) / free_bed(maternity) / ward_of(f)   queries for tests and the UI

const BED := "hospital_bed"
const BIRTH_BED := "birth_bed"
const STAY := "hospital_stay"


static func lot_id() -> String:
	if not Workplace.map_ready():
		return ""
	for l in Neighborhood.lots():
		if str(l.get("type", "")) == "hospital":
			return str(l["id"])
	return ""


static func beds(maternity: bool = false) -> Array:
	var out: Array = []
	var lot := lot_id()
	if lot == "":
		return out
	var rc := NeighborhoodLots.rect_of(lot)
	for o in SysUtil.all_world_objects():
		if (str(o.def_id) == (BIRTH_BED if maternity else BED)) and rc.has_point(o.tile) and not bool(WorldIface.state_get(o, "broken", false)):
			out.append(o)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


## Ids of the beds taken by patients right now.
static func taken() -> Dictionary:
	var out: Dictionary = {}
	for id in Hospital.patients:
		var p: Dictionary = Hospital.patients[id]
		if int(p.get("bed", -1)) >= 0:
			out[int(p["bed"])] = true
	return out


## A free bed: wards (level >= 1) before the emergency bays, the lowest id first.
static func free_bed(maternity: bool = false):
	var used := taken()
	var best = null
	for o in beds(maternity):
		if used.has(int(o.id)):
			continue
		if best == null or (best.level == 0 and o.level != 0):
			best = o
	return best


static func ready() -> bool:
	return free_bed(false) != null


static func ward_of(f) -> Dictionary:
	var p: Dictionary = Hospital.patients.get(int(f.id), {})
	return p if int(p.get("bed", -1)) >= 0 else {}


static func place(f, rec: Dictionary, maternity: bool = false, minutes: float = 0.0) -> bool:
	if not SysUtil.is_resident(f):
		return false                  # townies / visitors keep the statistical stay (they have no home on the player's lot to be sent back to)
	var bed = free_bed(maternity)
	if bed == null and maternity:
		bed = free_bed(false)
	if bed == null:
		return false
	_move(f, bed)
	rec["bed"] = int(bed.id)
	rec["ward"] = true
	_queue_stay(f, bed, minutes if minutes > 0.0 else float(int(rec["until_min"]) - SysUtil.now()))
	return true


static func _move(f, bed) -> void:
	f.cancel_current("admitted")
	f.clear_queue()
	f.tile = WorldIface.use_tile(bed, 0)
	f.level = int(bed.level)
	NeighborhoodLots.mark_inside(f, lot_id())
	Neighborhood.refresh_view(int(f.id))


static func _queue_stay(f, bed, minutes: float) -> void:
	var ir := Interaction.create(STAY, f, int(bed.id), false)
	if ir == null:
		return
	ir.def = ir.def.duplicate(true)
	ir.def["duration_min"] = maxf(minutes, 30.0) + 90.0           # the discharge (hourly check) ends it
	f.enqueue(ir)


static func has_stay(f) -> bool:
	if f.current != null and f.current.def_id == STAY:
		return true
	for q in f.queue:
		if (q as Interaction).def_id == STAY:
			return true
	return false


## The stay is over: leave the bed and go home (instantly: an ambulance / taxi), a newborn with its mother.
static func release(f, rec: Dictionary) -> void:
	if f.current != null and f.current.def_id == STAY:
		f.current.cancel("discharged")
	for q in f.queue.duplicate():
		if (q as Interaction).def_id == STAY:
			f.queue.erase(q)
	_home(f)
	var baby = SysUtil.folk(int(rec.get("baby", -1)))
	if baby != null:
		_home(baby)


static func _home(f) -> void:
	f.cancel_current("discharged")
	f.clear_queue()
	if SoloHome.locked_out(f):          # one-character play: evicted, so there is no home to go to: they leave by the hospital door onto the street
		f.tile = NeighborhoodLots.street_tile(lot_id())
		f.level = 0
		NeighborhoodLots.mark_inside(f, "")
		Neighborhood.refresh_view(int(f.id))
		return
	var hl: String = PlayerLots.home_of(f)          # their own home (a co-op guest's lot), else the home lot
	NeighborhoodTravel.travel([int(f.id)], hl, {"instant": true, "free": true, "quiet": true})
	if NeighborhoodLots.lot_at(f.tile) != hl:         # not movable (should not happen): put them at the home door by hand
		f.tile = NeighborhoodLots.entry_tile(hl)
		f.level = 0
		NeighborhoodLots.mark_inside(f, hl)
		Neighborhood.refresh_view(int(f.id))


## Hospital birth: `mother` (a resident) is admitted for the birth stay and both are placed in the maternity ward. Called by Aging._birth.
static func birth(mother, baby) -> bool:
	if not Workplace.map_ready() or lot_id() == "" or not SysUtil.is_resident(mother):
		return false
	var bc: Dictionary = Hospital.cfg().get("birth", {})
	if free_bed(true) == null and free_bed(false) == null:
		return false
	var hours: float = float(bc.get("stay_hours", 10.0))
	var rec: Dictionary = {"severity": 1, "reason": "giving birth", "admitted_min": SysUtil.now(), "until_min": SysUtil.now() + int(hours * 60.0),
		"bill": int(bc.get("bill", 220)), "townie": false, "hid": int(mother.household_id), "baby": int(baby.id), "birth": true}
	if Away.is_away(int(mother.id)):
		Away.recall(int(mother.id), "hospital")
	Hospital.patients[int(mother.id)] = rec
	mother.add_buff("in_hospital")
	if not place(mother, rec, true, hours * 60.0):
		Hospital.patients.erase(int(mother.id))
		mother.remove_buff("in_hospital")
		return false
	var bed = WorldIface.get_object(int(rec["bed"]))
	baby.tile = mother.tile
	baby.level = mother.level
	NeighborhoodLots.mark_inside(baby, lot_id())
	Neighborhood.refresh_view(int(baby.id))
	SysUtil.game_event("admitted", {"folk_id": int(mother.id), "severity": 1, "reason": "giving birth"})
	return bed != null
