class_name Fears
extends RefCounted
## Task 55: the fear flaws (creation.json effects.fear). A real trigger where the person is makes them anxious (buff), once per visit:
##   dogs: a lot whose household keeps a dog, or a house with a guard dog (CrimeSecurity profile);
##   heights: any upper floor.
## Said once, as the person feels it. Checked every few minutes, and only for people who have a fear.
##   Fears.on_minute()   Fears.has(pid, fear)

const BUFF := "anxious_jitters"
const EVERY := 5
static var _felt: Dictionary = {}          # "pid|fear|where" -> true while there

static func reset() -> void:
	_felt = {}

static func has(pid: int, fear: String) -> bool:
	for e in Creation._effects(pid):
		if str((e as Dictionary).get("fear", "")) == fear:
			return true
	return false

static func busy() -> bool:
	for pid in Creation.picks:
		if has(int(pid), "dogs") or has(int(pid), "heights"):
			return true
	return false

static func _dog_here(lot: String) -> bool:
	if lot == "":
		return false
	if lot == Neighborhood.HOME or str(Neighborhood.lot(lot).get("type", "")) == "home":
		for hid in Economy.household_ids():
			if PlayerLots.home_of_household(int(hid)) == lot and PetState.of_household(int(hid)).any(func(p): return str(p["species"]) == "dog"):
				return true
		return false
	if str(Neighborhood.lot(lot).get("type", "")) == "townie_home":
		return bool(CrimeSecurity.profile_for(DoorActs.scene_of(lot)).get("dog", false))
	return false

static func on_minute() -> void:
	if SysUtil.now() % EVERY != 0:
		return
	for pid in Creation.picks.keys():
		var f = SysUtil.folk(int(pid))
		if f == null or SysUtil.is_away(f):
			continue
		var lot: String = Neighborhood.lot_of(f)
		_check(f, "dogs", lot, _dog_here(lot), "Somewhere close, a dog barks. Your heart is pounding.")
		_check(f, "heights", "%s#%d" % [lot, int(f.level)], int(f.level) > 0, "You keep well away from the edge.")

static func _check(f, fear: String, where: String, on: bool, line: String) -> void:
	var fid: int = int(f.id)
	if not has(fid, fear):
		return
	var k: String = "%d|%s|%s" % [fid, fear, where]
	if not on:
		for key in _felt.keys():
			if str(key).begins_with("%d|%s|" % [fid, fear]):
				_felt.erase(key)
		return
	if _felt.has(k):
		f.add_buff(BUFF)
		return
	_felt[k] = true
	f.add_buff(BUFF)
	if Pawn.is_pawn(f):
		SysUtil.notify(line, "story")
