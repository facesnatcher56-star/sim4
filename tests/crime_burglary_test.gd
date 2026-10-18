extends RefCounted
## Burglary upgrade: a visible townie burglar enters at night, takes an object or coins and flees; confront / call police / alarm / lamps;
## the police catch him and recover the goods; hidden thefts are noticed when the owner looks; statistical version for a far townie lot;
## guest theft; the old coin-only burglar of Story is switched off.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_scene(f)
	_confront(f)
	_police(f)
	_alarm(f)
	_unseen(f)
	_far(f)
	_guest(f)
	return f

func _home_with_tv(w: StubWorld) -> void:
	w.add_object("tv", Vector2i(14, 12))
	w.add_object("door", Vector2i(10, 10))
	Economy.refresh_objects()

func _scene(f: Array) -> void:
	var w := C.town()
	_home_with_tv(w)
	K.set_time(3, 2, 0)
	var res: Dictionary = CrimeBurglary.attempt("home:1", false, true)
	var c: Dictionary = CaseStore.get_case(int(res.get("case", -1)))
	K.expect(f, not c.is_empty() and str(c["kind"]) == "burglary" and bool(c["on_scene"]), "a burglary scene starts")
	var b = SysUtil.folk(int(c["culprit"]))
	K.expect(f, b != null and b.has_meta("burglar") and b.has_buff("intruder"), "the burglar is a visible townie Folk on the lot")
	var ada = w.get_folk(1)
	K.expect(f, ada.has_buff("intruder_alert") and (c["witnesses"] as Array).has(1), "an awake resident notices the intruder")
	C.minutes(30)
	K.expect(f, not bool(c["on_scene"]) and SysUtil.folk(int(c["culprit"])) == null, "the burglar leaves the map again")
	K.expect(f, (c["loot"] as Array).size() == 1 or int(c["stolen_coins"]) > 0, "something was stolen (object or coins)")
	K.expect(f, str(c["state"]) == "open" and K.has_note("police"), "a witnessed burglary is reported straight away (state %s)" % str(c["state"]))
	K.expect(f, not ada.has_buff("intruder_alert"), "the alert ends when the burglar is gone")
	Story.burglaries = 0
	Story.on_hour(3)
	K.expect(f, Story.burglaries == 0, "the old coin-only burglar is switched off")
	K.teardown()

func _confront(f: Array) -> void:
	var w := C.town()
	_home_with_tv(w)
	K.set_time(3, 2, 0)
	var res: Dictionary = CrimeBurglary.attempt("home:1", false, true)
	var c: Dictionary = CaseStore.get_case(int(res["case"]))
	var out: Dictionary = CrimeBurglary.on_confront(1, int(c["culprit"]))
	K.expect(f, out.has("fled") and not bool(c["on_scene"]), "confronting ends the scene: %s" % str(out))
	K.expect(f, str(c["state"]) == "open" and bool(c["witnessed"]), "the confrontation makes the break-in known")
	K.teardown()

func _police(f: Array) -> void:
	var w := C.town()
	_home_with_tv(w)
	K.set_time(3, 2, 0)
	var caught: int = 0
	for i in 12:
		var res: Dictionary = CrimeBurglary.attempt("home:1", false, true)
		var c: Dictionary = CaseStore.get_case(int(res["case"]))
		Police.call_police(1)
		var before: int = int(c["id"])
		C.minutes(2)                                    # the scene is still on
		K.expect(f, bool(c["on_scene"]), "the burglar is still there after 2 minutes")
		# police arrive while the burglar is still inside (delay forced short)
		for p in JusticeState.pending:
			if str(p["kind"]) == "police_arrive":
				p["due_min"] = SysUtil.now()
		JusticeState.chance(0.0)
		C.minutes(1)
		if str(c["state"]) in ["arrested", "charged", "trial", "closed"] and bool(c["recovered"]):
			caught += 1
		C.minutes(30)
		K.expect(f, before == int(c["id"]), "same case")
		JusticeState.pending.clear()
		for pid in JusticeState.inmates.keys():
			JusticeState.inmates.erase(pid)
		K.set_time(3 + i, 2, 0)
	K.expect(f, caught >= 2, "police catch the burglar and recover the goods sometimes (%d of 12)" % caught)
	K.teardown()

func _alarm(f: Array) -> void:
	var w := C.town()
	_home_with_tv(w)
	w.add_object("burglar_alarm", Vector2i(12, 12))
	Economy.refresh_objects()
	K.set_time(3, 2, 0)
	var res: Dictionary = CrimeBurglary.attempt("home:1", false, true)
	var c: Dictionary = CaseStore.get_case(int(res["case"]))
	K.expect(f, bool(c["called"]) and K.has_note("alarm"), "the alarm rings and calls the police")
	# prevention: lamps / alarm / someone awake abort most attempts when not forced
	var made: int = 0
	var tries: int = 60
	JusticeState.cases.clear()
	for i in tries:
		var r2: Dictionary = CrimeBurglary.attempt("home:1", false, false)
		if r2.has("case"):
			made += 1
			CrimeBurglary.end_scene(CaseStore.get_case(int(r2["case"])), false)
	K.expect(f, made < tries * 0.5, "alarm + someone awake stop most attempts (%d of %d got through)" % [made, tries])
	K.teardown()

func _unseen(f: Array) -> void:
	var w := C.town()
	_home_with_tv(w)
	var ada = w.get_folk(1)
	ada.current = null
	K.set_time(3, 2, 0)
	WorldIface.coins[1] = 1000
	# nobody is home: Ada is away at work
	Away.active[1] = {"reason": "work", "minutes": 600.0, "data": {}, "start_min": 0, "until_min": 99999}
	ada.set_meta("away", "work")
	var res: Dictionary = CrimeBurglary.attempt("home:1", false, true)
	var c: Dictionary = CaseStore.get_case(int(res["case"]))
	C.minutes(30)
	K.expect(f, str(c["state"]) == "hidden" and not bool(c["on_scene"]), "an unseen burglary stays hidden until the owner looks")
	ada.remove_meta("away")
	Away.active.erase(1)
	var found_after: int = -1
	for h in 24:
		K.set_time(3 + h / 24, (7 + h) % 24, 0)
		CaseDiscovery.on_hour()
		if str(c["state"]) == "open":
			found_after = h
			break
	K.expect(f, found_after >= 0 and found_after < 12, "noticed soon after the owner is home and awake (after %d h)" % found_after)
	K.teardown()

func _far(f: Array) -> void:
	var w := C.town(8)
	var lot: String = ""
	for tid in C.ids():
		lot = CrimePerson.home_key(int(tid))
		break
	var n: int = 0
	for i in 40:
		var r: Dictionary = CrimeBurglary.attempt(lot, true, true)
		if r.has("case"):
			n += 1
	K.expect(f, n > 20, "far lots get statistical burglaries with a case record (%d)" % n)
	var c: Dictionary = JusticeState.cases[JusticeState.cases.keys()[0]]
	K.expect(f, str(c["kind"]) == "burglary" and int(c["culprit"]) >= 1000 and str(c["scene"]) == lot, "case names a townie burglar and the lot")
	K.teardown()

func _guest(f: Array) -> void:
	var w := C.town()
	_home_with_tv(w)
	var tid: int = int(C.ids()[0])
	var g := Folk.create("Guest", [])
	g.household_id = -1
	g.set_meta("visitor", true)
	g.set_meta("townie_id", tid)
	w.add_folk(g, Vector2i(12, 12))
	RelationshipKnowledge.add_reputation(tid, -60.0)
	var res: Dictionary = {}
	for i in 30:
		res = CrimeBurglary.on_guest_theft({"statistical": false, "household_id": 1, "forced": true}, {})
		if res.has("case"):
			break
	var c: Dictionary = CaseStore.get_case(int(res.get("case", -1)))
	K.expect(f, not c.is_empty() and str(c["kind"]) == "theft" and str(c["state"]) == "hidden", "a low-reputation guest can pocket something (hidden theft)")
	K.teardown()
