extends RefCounted
## Task 21: moral weight. Victims are real townies in a ledger; victims at home feel violated; honest people are troubled by what they did; kin can
## find out (friendship drops, gossip spreads); the legacy score has a notoriety side that outlives the criminal.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_ledger(f)
	_victims(f)
	_find_out(f)
	_notoriety(f)
	_going_straight(f)
	return f

func _ledger(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	var t: Array = CrimeLifeJobs.targets(1, "pickpocket")
	for i in 3:
		CrimeLifeJobs.run(1, "pickpocket", t[i], {"force": "clean"})
	var tot: Dictionary = CrimeLifeMoral.totals(1)
	K.expect(f, int(tot["crimes"]) == 3 and int(tot["victims"]) == 3 and int(tot["loss"]) > 0, "every victim is written down: %s" % str(tot))
	K.expect(f, CrimeLifeMoral.line(CrimeLifeMoral.ledger_of(1)[0]).contains("lost"), "in plain words: %s" % CrimeLifeMoral.line(CrimeLifeMoral.ledger_of(1)[0]))
	for i in 60:
		CrimeLifeMoral.after_crime(1, int(t[0]["victim"]), "theft", 5, {"id": 1})
	K.expect(f, CrimeLifeMoral.ledger_of(1).size() <= 40, "the ledger is capped")
	K.teardown()

func _victims(f: Array) -> void:
	var w := C.town(8)
	var second = K.make_folk(w, "Bea", [], 1, Vector2i(14, 12))
	CrimeLifePath.join(int(C.adults()[0]), "chose")
	CrimeLifeMoral.after_crime(int(C.adults()[0]), int(second.id), "burglary", 80, {"id": 1})
	K.expect(f, second.has_buff("violated"), "a victim in the player's home feels violated")
	var honest = K.make_folk(w, "Hal", ["honest"], 1, Vector2i(16, 12))
	CrimeLifePath.join(int(honest.id), "chose")
	CrimeLifeMoral.after_crime(int(honest.id), int(C.adults()[1]), "theft", 10, {"id": 2})
	K.expect(f, honest.has_buff("troubled_conscience"), "an honest person is troubled by what they did")
	K.teardown()

func _find_out(f: Array) -> void:
	var w := C.town(10)
	var kin = K.make_folk(w, "Mum", [], 1, Vector2i(14, 12))
	C.set_family(1, int(kin.id))
	CrimeLifePath.join(1)
	CrimeLifePath.member(1)["jobs"] = 4
	CrimeLifePath.member(1)["heat"] = 10.0
	var fr0: float = RelationshipService.value(int(kin.id), 1, "friendship")
	var n: int = 0
	for d in 400:
		n += CrimeLifeMoral.on_day()
		if n > 0:
			break
	K.expect(f, n == 1 and bool(CrimeLifePath.member(1)["found_out"]), "a relative eventually finds out")
	K.expect(f, RelationshipService.value(int(kin.id), 1, "friendship") < fr0 - 10.0, "and it costs the friendship")
	K.expect(f, kin.has_buff("troubled_conscience"), "the relative is troubled")
	K.expect(f, CrimeLifeMoral.on_day() == 0, "it comes out only once")
	K.teardown()

func _notoriety(f: Array) -> void:
	var w := C.town(10)
	CrimeLifePath.join(1)
	K.expect(f, CrimeLifeMoral.legacy_line(1) == "", "an unknown has no notoriety")
	CrimeLifePath.add_cred(1, 40.0)
	var n1: int = CrimeLifeMoral.notoriety(1)
	K.expect(f, n1 >= 20 and CrimeLifeMoral.legacy_line(1).contains("underworld"), "a name in the underworld becomes notoriety: %d, '%s'" % [n1, CrimeLifeMoral.legacy_line(1)])
	var s: Dictionary = Aging.legacy_summary(1)
	K.expect(f, int(s["notoriety"]) == n1 and str(s["summary"]).contains("underworld"), "the legacy summary carries it: %s" % str(s["summary"]))
	JusticeRecords.add(1, "burglary", 1, "guilty")
	K.expect(f, CrimeLifeMoral.notoriety(1) > n1, "a conviction adds to it")
	CrimeLifePath.leave(1)
	K.expect(f, CrimeLifeMoral.notoriety(1) >= n1, "going straight does not clean the legacy")
	K.teardown()

func _going_straight(f: Array) -> void:
	var w := C.town(10)
	CrimeLifePath.join(1)
	CrimeLifePath.leave(1)
	WorldIface.coins[1] = 0
	w.get_folk(1).traits.append("dishonest")
	JusticePlayer.auto = "join"
	for d in 20:
		CrimeLifeState.offered.erase(1)
		K.set_time(5 + d, 12)
		CrimeLifeFlow._offers()
	JusticePlayer.auto = ""
	K.expect(f, not CrimeLifePath.is_member(1), "no shady offers while going straight")
	K.teardown()
