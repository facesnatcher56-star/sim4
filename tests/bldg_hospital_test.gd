extends RefCounted
## The hospital is a real building (task 10 part B): a Folk walks from the entrance to a ward bed and back; Hospital.admit puts a resident
## into a ward bed (full simulation) and discharge / the end of the stay sends them home; far townies and worlds without a hospital keep the
## statistical Away stay; a hospital birth puts mother and baby in the maternity ward.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	var folk: Array = Kit.new_game("small")
	_building()
	_walk_to_a_bed(folk[0])
	_admit_and_discharge(folk[1])
	_stay_ends_by_itself(folk[2])
	_townie_stays_statistical()
	_birth(folk)
	Kit.teardown()
	return fails


func _building() -> void:
	var W: Node = Kit.world()
	_check(HospitalWard.lot_id() == "hospital", "the map has a hospital lot")
	var tpl: Dictionary = LotLoader.template(Neighborhood.template_of("hospital"))
	_check(tpl.has("levels") and str(tpl["venue"]) == "hospital", "it is a multi-floor hospital building")
	var wards: Array = HospitalWard.beds(false)
	var levels: Dictionary = {}
	for b in wards:
		levels[b.level] = int(levels.get(b.level, 0)) + 1
	_check(wards.size() >= 8 and levels.has(0) and levels.has(1), "ER bays on the ground floor and a ward floor: %s" % str(levels))
	var births: Array = HospitalWard.beds(true)
	_check(births.size() >= 2, "a maternity floor with delivery beds (%d)" % births.size())
	var morgue := false
	var surgery := false
	for o in W.all_objects():
		if NeighborhoodLots.lot_at(o.tile) == "hospital":
			morgue = morgue or (o.level < 0)
			surgery = surgery or str(o.def_id) == "operating_table"
	_check(morgue and surgery, "a basement (morgue and stores) and an operating theatre")
	_check(Neighborhood.is_open("hospital") and Venues.status_text("hospital") == "Always open", "the hospital is always open")


## Entrance -> ward bed -> entrance, on foot, through the stairs / lift.
func _walk_to_a_bed(f: Folk) -> void:
	var W: Node = Kit.world()
	var door: Vector2i = NeighborhoodLots.entry_tile("hospital")
	f.tile = door
	f.level = 0
	var bed = HospitalWard.free_bed(false)
	for b in HospitalWard.beds(false):
		if b.level == 1:
			bed = b
			break
	var spot: Vector2i = WorldIface.use_tile(bed, 0)
	_check(W.has_route(Vector3i(door.x, door.y, 0), Vector3i(spot.x, spot.y, bed.level)), "a route from the door to the ward bed on level %d" % bed.level)
	var go := Interaction.create_goto(f, spot, true, int(bed.level))
	_check(go != null and go.start(), "walk to the ward")
	f.current = go
	var guard := 0
	while go.state == "walking" and guard < 300:
		go.tick(0.5)
		guard += 1
	_check(f.tile == spot and f.level == bed.level, "arrived at the bed (%s, level %d)" % [str(f.tile), f.level])
	var back := Interaction.create_goto(f, door, true, 0)
	_check(back != null and back.start(), "walk back")
	f.current = back
	guard = 0
	while back.state == "walking" and guard < 300:
		back.tick(0.5)
		guard += 1
	_check(f.tile == door and f.level == 0, "back at the entrance on the ground floor")
	f.current = null


func _admit_and_discharge(f: Folk) -> void:
	var W: Node = Kit.world()
	f.tile = NeighborhoodLots.entry_tile(Neighborhood.HOME)
	f.level = 0
	_check(Hospital.admit(int(f.id), 2, "test"), "admit a resident")
	var p: Dictionary = Hospital.info(int(f.id))
	_check(bool(p.get("ward", false)) and int(p.get("bed", -1)) >= 0, "the patient lies in a real ward bed")
	var bed = WorldIface.get_object(int(p["bed"]))
	_check(bed != null and f.level == bed.level and NeighborhoodLots.lot_at(f.tile) == "hospital", "on the bed's floor, in the hospital lot (level %d)" % f.level)
	_check(f.has_buff("in_hospital") and not Away.is_away(int(f.id)), "marked in hospital, not hidden by Away")
	_check(HospitalWard.has_stay(f), "resting: the hospital_stay interaction runs")
	_check(HospitalWard.free_bed(false) == null or int(HospitalWard.free_bed(false).id) != int(p["bed"]), "the bed is taken")
	Kit.run(30)
	_check(Hospital.is_in(f) and f.level == bed.level, "still in the bed 30 minutes later")
	var coins_before: int = WorldIface.get_coins(int(f.household_id))
	_check(Hospital.discharge(int(f.id)), "discharge")
	_check(not Hospital.is_in(f) and not f.has_buff("in_hospital"), "no longer a patient")
	_check(NeighborhoodLots.lot_at(f.tile) == Neighborhood.HOME and f.level == 0, "sent home to the ground floor (%s)" % NeighborhoodLots.lot_at(f.tile))
	_check(not HospitalWard.has_stay(f), "the stay interaction is gone")
	_check(WorldIface.get_coins(int(f.household_id)) <= coins_before, "the bill was charged")
	_check(W.is_walkable(f.tile, f.level), "home on a walkable tile")


func _stay_ends_by_itself(f: Folk) -> void:
	f.tile = NeighborhoodLots.entry_tile(Neighborhood.HOME)
	_check(Hospital.admit(int(f.id), 1, "test"), "admit again")
	var p: Dictionary = Hospital.info(int(f.id))
	p["until_min"] = SimEnv.now_min() + 90
	Kit.run(60 * 4)
	_check(not Hospital.is_in(f), "the hourly check discharged the patient after the stay")
	_check(NeighborhoodLots.lot_at(f.tile) == Neighborhood.HOME and f.level == 0, "and they are home")


## Townies on the street (no Folk on the map) keep the statistical stay.
func _townie_stays_statistical() -> void:
	var t: Dictionary = {}
	for tt in Story.alive_townies():
		if SysUtil.folk(int(tt["id"])) == null:          # a townie that is not on the map right now
			t = tt
			break
	if t.is_empty():
		return
	var tid := int(t["id"])
	_check(Hospital.admit(tid, 2, "test"), "admit a townie")
	_check(not bool(Hospital.info(tid).get("ward", false)) and bool(Story.townies[tid].get("in_hospital", false)), "no bed, no Folk: the statistical stay %s %s" % [str(Hospital.info(tid)), str(Story.townies[tid].get("in_hospital", false))])
	Hospital.patients.erase(tid)
	Story.townies[tid].erase("in_hospital")


func _birth(folk: Array) -> void:
	var m: Folk = folk[0]
	var d: Folk = folk[1]
	m.tile = NeighborhoodLots.entry_tile(Neighborhood.HOME)
	var cfg: Dictionary = IncidentDefs.config.get("hospital", {})
	cfg["birth"] = {"chance": 1.0, "stay_hours": 8.0, "bill": 100}
	IncidentDefs.config["hospital"] = cfg
	var before: int = SysUtil.residents().size()
	Aging._birth(int(m.id), int(d.id))
	var baby = null
	for f in SysUtil.residents():
		if str(f.age_stage) == "baby":
			baby = f
	_check(baby != null and SysUtil.residents().size() == before + 1, "a baby was born")
	if baby == null:
		return
	var p: Dictionary = Hospital.info(int(m.id))
	_check(bool(p.get("birth", false)) and bool(p.get("ward", false)), "the mother is admitted for the birth in a ward bed")
	var bed = WorldIface.get_object(int(p.get("bed", -1)))
	_check(bed != null and str(bed.def_id) == "birth_bed" and bed.level == 3, "in a delivery bed on the maternity floor (%s level %d)" % [str(bed.def_id) if bed != null else "?", bed.level if bed != null else -1])
	_check(NeighborhoodLots.lot_at(baby.tile) == "hospital" and baby.level == m.level, "the baby is born on the ward")
	_check(Kit.has_note("at the hospital"), "the birth announcement says where")
	_check(Hospital.discharge(int(m.id)), "discharge after the birth")
	_check(NeighborhoodLots.lot_at(m.tile) == Neighborhood.HOME and NeighborhoodLots.lot_at(baby.tile) == Neighborhood.HOME, "mother and baby go home together")
	_check(m.level == 0 and baby.level == 0, "on the ground floor")
