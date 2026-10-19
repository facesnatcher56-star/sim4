extends RefCounted
## Case flow details (19b): a defendant who dies before the trial closes the case; "gone cold" is said once; reopened-case toasts follow the notify
## policy; murders are not on a fixed tick (random moments, mostly at night).

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_death(f)
	_cold(f)
	_timing(f)
	_arc(f)
	return f

func _death(f: Array) -> void:
	var w := C.town(8)
	var ids: Array = C.adults()
	var a: int = int(ids[0])
	var v: int = int(ids[1])
	K.set_time(10, 12)
	var c: Dictionary = CaseStore.create("robbery", a, v, "street", {})
	c["accused"] = a
	c["state"] = "charged"
	c["charge"] = "robbery"
	Story.townies[a]["alive"] = false
	CrimeFlow.on_game_event("died", {"folk_id": a})
	K.expect(f, str(c["state"]) == "closed", "a defendant who dies before the trial closes the case")
	var said: bool = false
	for n in c["notes"]:
		if str(n["text"]).find("died before the trial") >= 0 and str(n["text"]).find(CrimePerson.name_of(a)) >= 0:
			said = true
	K.expect(f, said, "with a plain line that names them")
	K.teardown()

func _cold(f: Array) -> void:
	var w := C.town(8)
	var ids: Array = C.adults()
	K.set_time(60, 12)
	var c: Dictionary = CaseStore.create("robbery", int(ids[0]), int(ids[1]), "street", {})
	c["state"] = "open"
	c["disc_day"] = 1
	CaseInvestigation.work(c)
	K.expect(f, str(c["state"]) == "cold", "an old case with nothing new goes cold")
	for i in 3:
		CaseInvestigation.reopen(c, "A new tip came in.")
		c["disc_day"] = 1
		CaseInvestigation.work(c)
	var n_cold: int = 0
	for n in c["notes"]:
		if str(n["text"]).find("gone cold") >= 0:
			n_cold += 1
	K.expect(f, n_cold == 1, "'gone cold' is said once (%d times)" % n_cold)
	K.notes.clear()
	CaseInvestigation.reopen(c, "A detective took a fresh look.")
	var heard: bool = false
	for nn in K.notes:
		if str(nn[0]).find("reopened") >= 0:
			heard = true
	K.expect(f, not heard, "a stranger's reopened case is not toasted to the household")
	var mine: Dictionary = CaseStore.create("burglary", int(ids[0]), -1, "home:1", {})
	mine["state"] = "cold"
	CaseInvestigation.reopen(mine, "A new tip came in.")
	var heard2: bool = false
	for n3 in K.notes:
		if str(n3[0]).find("reopened") >= 0:
			heard2 = true
	K.expect(f, heard2, "a case at the household's own home is")
	K.teardown()

func _timing(f: Array) -> void:
	var w := C.town(10)
	var ids: Array = C.adults()
	var a: int = int(ids[0])
	var b: int = int(ids[1])
	K.set_time(10, 3)
	var seen: Dictionary = {}
	var night: int = 0
	var now: int = SysUtil.now()
	var early: bool = false
	for i in 40:
		JusticeState.pending.clear()
		CrimeMurder._begin(a, b)
		var due: int = int(JusticeState.pending[0]["due_min"])
		seen[due % 1440] = true
		if due <= now:
			early = true
		var mod: int = due % 1440
		if mod >= 1320 or mod < 360:
			night += 1
	K.expect(f, not early and seen.size() >= 25, "the final moment is random, never the tick itself (%d distinct minutes)" % seen.size())
	K.expect(f, night >= 28, "and mostly at night (%d of 40)" % night)
	K.teardown()

## A forced crime still goes the whole way: arrest, trial and a sentence (or a verdict that keeps the case open).
func _arc(f: Array) -> void:
	var done: int = 0
	for seed_i in 6:
		var w := C.town(10)
		JusticeState.seed_rng(300 + seed_i)
		var ids: Array = C.adults()
		var a: int = int(ids[0])
		var b: int = int(ids[1])
		Story.townies[a]["coins"] = 3000
		C.feud(a, b, 90.0)
		K.set_time(5, 2)
		CrimeMurder.execute(a, b)
		for d in 45:
			C.hours(24)
			CrimeFlow.on_day(SysUtil.day())
			for m in 3:
				C.minutes(30)
			if JusticeState.counter("trials") > 0 and JusticeState.pending.is_empty():
				break
		if JusticeState.counter("arrests") > 0 and JusticeState.counter("trials") > 0:
			done += 1
		K.teardown()
	K.expect(f, done >= 1, "a forced murder still goes through arrest and trial (%d of 6 runs)" % done)
