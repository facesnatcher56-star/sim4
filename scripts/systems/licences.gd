class_name Licences
extends RefCounted
## Task 55: the driving licence. A background or perk can start with it (creation.json effects.licence); otherwise it is earned with the
## driving test at City Hall: ask the receptionist there, pay the fee, and the test is a SkillCheck on driving ("driving_test"). A car dealer
## will not sell a car to someone without one (TransportCars.buy).
##   Licences.has(pid, id)   Licences.person_entries(f, staff)

const TEST_FEE := 40
static var held: Dictionary = {}          # "pid|id" -> day earned

static func reset() -> void:
	held = {}

static func has(pid: int, id: String) -> bool:
	return Creation.has_licence(pid, id) or held.has("%d|%s" % [pid, id])

## The receptionist at City Hall offers the test to someone without a licence.
static func person_entries(f, staff) -> Array:
	if f == null or staff == null or not Pawn.is_pawn(f) or not staff.has_meta("staff"):
		return []
	if Venues.type_of_lot(str(staff.get_meta("staff_lot", ""))) != "city_hall" or str(staff.get_meta("staff", "")) != "receptionist":
		return []
	if has(int(f.id), "driving"):
		return []
	return [{"id": "driving_test", "label": "Take the driving test (%d coins)" % TEST_FEE, "category": "Ask", "enabled": true, "reason": "",
		"action": func(): take_test(f, staff)}]

static func take_test(f, staff) -> void:
	var fid: int = int(f.id)
	var nm: String = str(staff.name).get_slice(" (", 0)
	if not Economy.spend(int(f.household_id), TEST_FEE, "driving test"):
		SysUtil.notify("\"The test is %d coins,\" says %s." % [TEST_FEE, nm], "story")
		return
	var r: Dictionary = SkillCheck.attempt(fid, "driving_test", {})
	if bool(r["ok"]):
		held["%d|driving" % fid] = SysUtil.day()
		SysUtil.notify("You pass the driving test. %s hands over the licence." % nm, "good")
	else:
		SysUtil.notify("The examiner shakes their head: a fail this time.", "story")

static func to_dict() -> Dictionary:
	return held.duplicate()

static func from_dict(d: Dictionary) -> void:
	held = d.duplicate()
