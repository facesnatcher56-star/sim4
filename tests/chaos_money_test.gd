extends RefCounted
## Household chaos (task 07b), money trouble: identity theft (adults with savings only, coins drain until reported, the police sort it out and the bank pays
## most of it back, unreported cases are reviewed later) and the eviction notice (only after overdue bills AND a repossession; a warning with two days to pay;
## paying cancels it; otherwise the bailiffs take things).

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/chaos_kit.gd")

func run() -> Array:
	var f: Array = []
	_theft(f)
	_unreported(f)
	_eviction(f)
	return f

func _theft(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	var kid := K.make_folk(h["w"], "Kit Voss", [], 1, Vector2i(15, 12), "child")
	K.expect(f, Incidents.effective_rate("identity_theft", IncidentSubject.of_folk(kid)) == 0.0, "a child can never be a victim")
	var rate: float = Incidents.effective_rate("identity_theft", IncidentSubject.of_folk(ada))
	K.expect(f, rate > 0.025 and rate < 0.08, "an adult with savings can (%.3f a year, more with a computer)" % rate)
	WorldIface.coins[1] = 100
	K.expect(f, Incidents.effective_rate("identity_theft", IncidentSubject.of_folk(ada)) == 0.0, "with next to nothing there is nothing to steal")
	WorldIface.coins[1] = 2000
	var r: Dictionary = Incidents.force("identity_theft", {"folk_id": ada.id, "outcome": 0})
	K.expect(f, bool(r["ok"]) and Economy.balance(1) == 1500 and ada.has_buff("identity_theft"), "a quarter of the savings vanish (%d left)" % Economy.balance(1))
	K.expect(f, ChaosState.theft.has(1) and str(r["text"]).contains("Report it"), "the player is told to report it")
	K.expect(f, Incidents.effective_rate("identity_theft", IncidentSubject.of_folk(h["bo"])) == 0.0, "no second theft while one is open")
	C.days(2)
	K.expect(f, Economy.balance(1) == 1500 - 30, "unreported, a little more goes every day (%d)" % Economy.balance(1))
	C.ev("report_identity_theft", ada)
	K.expect(f, bool(ChaosState.theft[1]["reported"]) and K.has_note("police"), "reporting it starts the police work")
	var bal: int = Economy.balance(1)
	C.days(1)
	K.expect(f, Economy.balance(1) == bal, "no more money goes once it is reported")
	C.days(7)
	K.expect(f, not ChaosState.theft.has(1) and not ada.has_buff("identity_theft"), "the police sort it out")
	K.expect(f, Economy.balance(1) > bal + 400 and K.has_note("returned"), "and the bank pays most of it back (%d -> %d)" % [bal, Economy.balance(1)])
	K.teardown()

func _unreported(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	Incidents.force("identity_theft", {"folk_id": ada.id, "outcome": 0})
	C.days(25)
	K.expect(f, not ChaosState.theft.has(1) and not ada.has_buff("identity_theft"), "never reported: the bank reviews it after three weeks")
	K.teardown()

func _eviction(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	var subj := IncidentSubject.of_household(1)
	K.expect(f, Incidents.effective_rate("eviction_notice", subj) == 0.0, "a household that pays its bills never gets a notice")
	WorldIface.coins[1] = 0
	var bl: Dictionary = Economy.issue_bill(1)
	bl["late"] = true
	bl["amount"] = int(bl["amount"]) + 10
	K.expect(f, Incidents.effective_rate("eviction_notice", subj) == 0.0, "late bills alone are not enough")
	Economy.repossessed.append({"day": SysUtil.day(), "hid": 1, "def_id": "tv", "value": 100})
	K.expect(f, Incidents.effective_rate("eviction_notice", subj) > 1.0, "late bills AND a repossession can lead to a notice")
	var objs0: int = Economy.objects_of(1).size()
	K.expect(f, objs0 > 3, "test setup: furnished home (%d objects)" % objs0)
	var w: Dictionary = Incidents.force("eviction_notice", {"lot": "home:1", "warn": false})
	K.expect(f, bool(w["ok"]) and K.has_note("bailiffs"), "forced: the bailiffs come (%s)" % str(w["text"]))
	K.expect(f, Economy.repossessed.size() > 1 and Economy.objects_of(1).size() < objs0, "the bailiffs took things (%d -> %d objects)" % [objs0, Economy.objects_of(1).size()])
	K.expect(f, Economy.owed(1) == 0 and ada.has_buff("eviction_scare"), "the overdue bills were settled with them")
	K.teardown()
	# the warned route: pay in time and it is cancelled
	var h2: Dictionary = C.setup()
	WorldIface.coins[1] = 0
	var bl2: Dictionary = Economy.issue_bill(1)
	bl2["late"] = true
	Economy.repossessed.append({"day": SysUtil.day(), "hid": 1, "def_id": "tv", "value": 100})
	var objs1: int = Economy.objects_of(1).size()
	var s := IncidentSubject.of_household(1)
	var res: Dictionary = IncidentFlow.start("eviction_notice", s)
	K.expect(f, str(res["mode"]) == "warned" and K.has_note("eviction notice"), "the notice comes with two days to pay")
	WorldIface.coins[1] = 5000
	Economy.pay_bill(1)
	C.minutes(2900)
	K.expect(f, Economy.objects_of(1).size() == objs1 and K.has_note("withdrew the notice"), "paying in time cancels it")
	K.teardown()
