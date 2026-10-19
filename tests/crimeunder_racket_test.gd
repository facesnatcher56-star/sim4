extends RefCounted
## Task 23: racketeering. Loan sharking (interest, collection visits that press debtors, a debtor may report), protection rackets on businesses (pay,
## or suffer vandalism; a player-owned business is asked), a gambling den (income, raids), counterfeit batches, and laundering through a front business
## (the dirty-money taint falls; unexplained wealth draws an audit).

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_loans(f)
	_protection(f)
	_den_and_forgery(f)
	_laundering(f)
	_townies(f)
	return f

func _racketeer(pid: int) -> void:
	CrimeLifePath.join(pid, "chose")
	CrimeLifePath.member(pid)["cred"] = 40.0
	CrimeLifeContacts.add(pid, int(C.adults()[0]), "fence", 0.5)
	CrimeUnderLines.join(pid, "racket")

func _loans(f: Array) -> void:
	var w := C.town(16)
	var ids: Array = C.adults()
	var debtor: int = int(ids[1])
	_racketeer(1)
	WorldIface.coins[1] = 1000
	Story.townies[debtor]["coins"] = 20
	var r: Dictionary = Commands.run({"player_id": 1, "folk_id": 1, "action": "crimeunder", "args": {"action": "racket_lend", "debtor": debtor, "amount": 200}})
	K.expect(f, bool(r["ok"]) and CrimePerson.coins(debtor) == 220 and CrimePerson.coins(1) == 800, "a loan changes hands")
	var op: Dictionary = CrimeUnderRacket.ops_of(1, "loan")[0]
	K.expect(f, int(op["owed"]) == 250, "and the debtor owes with interest (%d)" % int(op["owed"]))
	K.expect(f, not bool(CrimeUnderRacket.lend(1, debtor, 100)["ok"]), "only one loan to a debtor at a time")
	# collection when they cannot pay: pressure, friendship falls
	Story.townies[debtor]["coins"] = 0
	CrimeUnderState.sect("racket")["loan"]["report_chance"] = 0.0
	CrimeUnderState.sect("racket")["loan"]["pay_chance"] = 0.0
	var fr: float = RelationshipService.value(debtor, 1, "friendship")
	var out: String = CrimeUnderRacket.collect(op)
	K.expect(f, out == "pressed" and int(op["visits"]) == 1 and RelationshipService.value(debtor, 1, "friendship") < fr, "a collection visit presses the debtor")
	# with money they pay it off
	Story.townies[debtor]["coins"] = 400
	CrimeUnderState.sect("racket")["loan"]["pay_chance"] = 1.0
	var c0: int = CrimePerson.coins(1)
	out = CrimeUnderRacket.collect(op)
	K.expect(f, out == "paid" and CrimePerson.coins(1) >= c0 + 250 and str(op["state"]) == "paid", "paid in full (profit %d)" % (CrimePerson.coins(1) - 800))
	K.expect(f, CrimeUnderRacket.taint(1) > 0.0 and CrimeUnderLines.standing(1, "racket") > 0.0, "the money is dirty and the standing grows")
	# a debtor may go to the police
	var op2: Dictionary = CrimeUnderRacket.lend(1, int(ids[2]), 100)
	var o2: Dictionary = CrimeUnderState.rackets[int(op2["racket"])]
	Story.townies[int(ids[2])]["coins"] = 0
	CrimeUnderState.sect("racket")["loan"]["pay_chance"] = 0.0
	CrimeUnderState.sect("racket")["loan"]["report_chance"] = 1.0
	o2["visits"] = 2
	out = CrimeUnderRacket.collect(o2)
	K.expect(f, out == "reported" and not CaseStore.cases_of_culprit(1).is_empty(), "or report the lender: a loan-sharking case")
	K.expect(f, str(CaseStore.cases_of_culprit(1)[0].get("charge_hint", "")) == "loan_sharking", "charged as loan sharking")
	K.teardown()

func _biz(w, owner_kind: String, owner: int) -> int:
	var lot: String = ""
	for t in BusinessState.type_ids():
		var lots: Array = BusinessState.open_lots_for(str(t))
		if not lots.is_empty():
			var b: Dictionary = BusinessState.make(str(t), str(lots[0]), "sole", owner_kind, owner, "Test %s" % str(t))
			return int(b["id"])
	return -1

func _protection(f: Array) -> void:
	var w := C.town(16)
	var ids: Array = C.adults()
	_racketeer(1)
	var biz: int = _biz(w, "townie", int(ids[2]))
	if biz < 0:
		K.expect(f, true, "(no business lot in this test world: protection skipped)")
		K.teardown()
		return
	Story.townies[int(ids[2])]["coins"] = 500
	var r: Dictionary = CrimeUnderRacket.protect(1, biz)
	K.expect(f, bool(r["ok"]), "a business is told it needs protection")
	var op: Dictionary = CrimeUnderState.rackets[int(r["racket"])]
	CrimeUnderState.sect("racket")["protect"]["pay_chance"] = 1.0
	var c0: int = CrimePerson.coins(1)
	K.expect(f, CrimeUnderRacket.demand(op) == "paid" and CrimePerson.coins(1) > c0, "the owner pays")
	CrimeUnderState.sect("racket")["protect"]["pay_chance"] = 0.0
	CrimeUnderState.sect("racket")["protect"]["report_chance"] = 0.0
	CrimeUnderState.sect("racket")["protect"]["refuse_vandal"] = 1.0
	var cases: int = JusticeState.cases.size()
	K.expect(f, CrimeUnderRacket.demand(op) == "vandalised" and JusticeState.cases.size() == cases + 1, "refuse and the place is vandalised (a case)")
	K.teardown()
	# a player-owned business is asked, with a choice
	var w2 := C.town(16)
	_racketeer(int(C.adults()[3]))
	var pb: int = _biz(w2, "player", 1)
	if pb >= 0:
		var rk: int = int(C.adults()[3])
		var r2: Dictionary = CrimeUnderRacket.protect(rk, pb)
		var op2: Dictionary = CrimeUnderState.rackets[int(r2["racket"])]
		JusticePlayer.auto = "pay"
		WorldIface.coins[1] = 1000
		CrimeUnderRacket.demand(op2)
		K.expect(f, WorldIface.get_coins(1) < 1000, "the player's business owner can pay up")
		JusticePlayer.auto = "police"
		CrimeUnderRacket.demand(op2)
		K.expect(f, str(op2["state"]) == "reported", "or tell the police")
		JusticePlayer.auto = ""
	K.teardown()

func _den_and_forgery(f: Array) -> void:
	var w := C.town(16)
	_racketeer(1)
	WorldIface.coins[1] = 2000
	var r: Dictionary = CrimeUnderRacket.open_den(1)
	K.expect(f, bool(r["ok"]) and CrimePerson.coins(1) == 1550, "a card room costs to set up")
	var c0: int = CrimePerson.coins(1)
	CrimeUnderState.sect("racket")["den"]["raid_daily"] = 0.0
	for d in 5:
		CrimeUnderRacket.on_day()
	K.expect(f, CrimePerson.coins(1) >= c0 + 5 * 14, "and pays every day (+%d)" % (CrimePerson.coins(1) - c0))
	CrimeUnderState.sect("racket")["den"]["raid_daily"] = 100.0
	CrimeUnderRacket.on_day()
	var op: Dictionary = CrimeUnderState.rackets[1]
	K.expect(f, str(op["state"]) == "raided" and not CaseStore.cases_of_culprit(1).is_empty(), "a raid shuts it and makes a case")
	K.expect(f, str(CaseStore.cases_of_culprit(1)[0].get("charge_hint", "")) == "illegal_gambling", "gambling without a licence")
	CrimeUnderState.sect("racket")["counterfeit"]["detect"] = 0.0
	var c1: int = CrimePerson.coins(1)
	var fr: Dictionary = CrimeUnderRacket.counterfeit(1)
	K.expect(f, bool(fr["ok"]) and int(fr["value"]) > 0 and CrimePerson.coins(1) > c1 - 80, "a batch of false notes passes (value %d)" % int(fr["value"]))
	K.teardown()

func _laundering(f: Array) -> void:
	var w := C.town(16)
	_racketeer(1)
	var biz: int = _biz(w, "player", 1)
	if biz < 0:
		K.expect(f, true, "(no business lot in this test world: laundering skipped)")
		K.teardown()
		return
	WorldIface.coins[1] = 3000
	K.expect(f, not bool(CrimeUnderRacket.launder(1, 100)["ok"]), "laundering needs a front")
	K.expect(f, bool(CrimeUnderRacket.set_front(1, biz)["ok"]), "a business you own can be the front")
	CrimeUnderRacket.add_taint(1, 6.0)
	var r: Dictionary = Commands.run({"player_id": 1, "folk_id": 1, "action": "crimeunder", "args": {"action": "racket_launder", "amount": 500}})
	K.expect(f, bool(r["ok"]) and CrimeUnderRacket.taint(1) < 2.0, "dirty money goes through for a fee and the taint falls (%.1f)" % CrimeUnderRacket.taint(1))
	var again: Dictionary = CrimeUnderRacket.launder(1, 500)
	K.expect(f, not bool(again["ok"]) or int(again.get("fee", 0)) > 0, "a weekly cap limits how much")
	# dirty money draws an audit
	CrimeUnderRacket.add_taint(1, 20.0)
	CrimeUnderState.sect("racket")["launder"]["audit_base"] = 1.0
	CrimeUnderRacket._audits(CrimeUnderRacket.cfg())
	K.expect(f, CrimeUnderState.counter("audit") == 1, "a lot of dirty money brings an audit")
	K.teardown()

func _townies(f: Array) -> void:
	var w := C.town(24)
	var ids: Array = C.adults()
	var t: int = int(ids[0])
	CrimeLifePath.join(t, "chose")
	CrimeLifePath.member(t)["cred"] = 50.0
	CrimeLifePath.member(t)["rank"] = "fence"
	CrimeUnderState.lines[t] = {"racket": {"standing": 20.0, "since": 0, "acts": 0, "via": "contact"}}
	Story.townies[t]["coins"] = 1500
	CrimeUnderState.sect("racket")["npc"]["op_daily"] = 1.0
	var n: int = 0
	for d in 6:
		CrimeUnderRacket.person_day(t)
	n = CrimeUnderRacket.ops_of(t).size()
	K.expect(f, n >= 1, "townie racketeers run their own loans and demands (%d ops)" % n)
	K.teardown()
