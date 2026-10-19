extends RefCounted
## Task 23: the dealer (fictional substances). Joining needs a contact or a record, buying has a price and a cap by rank, selling pays and hooks townies,
## customers inform and raids follow tips, rivals take corners, and an undercover STING catches a dealer at the rate the data and the police presence say.
## A corrupt cop on the payroll cuts it. Dealing writes crime points into the town crime rate.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_buy(f)
	_sell(f)
	_sting_rate(f)
	_corrupt_cop(f)
	_raid(f)
	_corner(f)
	_command(f)
	return f

func _dealer(pid: int) -> void:
	CrimeLifePath.join(pid, "chose")
	CrimeLifePath.member(pid)["cred"] = 30.0
	CrimeLifeContacts.add(pid, int(C.adults()[0]), "fence", 0.5)
	CrimeUnderLines.join(pid, "deal")

func _buy(f: Array) -> void:
	var w := C.town(14)
	CrimeLifePath.join(1)
	CrimeLifePath.member(1)["cred"] = 30.0
	K.expect(f, not bool(CrimeUnderDeal.buy(1, "glow", 3)["ok"]), "no supplier deals with someone outside the trade")
	_dealer(1)
	WorldIface.coins[1] = 1000
	var r: Dictionary = CrimeUnderDeal.buy(1, "glow", 5)
	K.expect(f, bool(r["ok"]) and CrimeUnderDeal.stock_total(1) == 5 and CrimePerson.coins(1) < 1000, "buying costs coins and fills the stash")
	var over: Dictionary = CrimeUnderDeal.buy(1, "glow", 50)
	K.expect(f, CrimeUnderDeal.stock_total(1) == 8, "a runner can only keep 8 doses (%d)" % CrimeUnderDeal.stock_total(1))
	K.expect(f, not bool(CrimeUnderDeal.buy(1, "glow", 1)["ok"]), "no more room")
	K.expect(f, not bool(CrimeUnderDeal.buy(1, "not_a_thing", 1)["ok"]), "only the listed fictional substances exist")
	K.teardown()

func _sell(f: Array) -> void:
	var w := C.town(20)
	_dealer(1)
	WorldIface.coins[1] = 1000
	CrimeUnderDeal.buy(1, "glow", 8)
	for tid in C.adults():
		Story.townies[tid]["coins"] = 500
	CrimeUnderState.sect("addict")["onset_cap"] = 1.0
	CrimeUnderState.sect("deal")["substances"]["glow"]["onset"] = 1.0
	var rate_before: float = CrimeRate.recent_points()
	var coins: int = CrimePerson.coins(1)
	var res: Dictionary = {}
	for i in 4:
		res = CrimeUnderDeal.session(1, "c1", {"no_sting": true})
		CrimeUnderState.dealers[1]["stock"]["glow"] = 8
		if int(res["sold"]) > 0:
			break
	K.expect(f, int(res["sold"]) > 0 and CrimePerson.coins(1) > coins, "a session on a corner sells doses and pays (%d sold)" % int(res["sold"]))
	K.expect(f, CrimeUnderAddict.count_using() >= 1 and int(res["hooked"]) >= 1, "first-time buyers get hooked (%d)" % CrimeUnderAddict.count_using())
	K.expect(f, CrimeRate.recent_points() > rate_before, "dealing raises the town crime rate")
	K.expect(f, CrimeUnderLines.standing(1, "deal") > 0.0 and float(CrimeLifePath.member(1)["heat"]) > 0.0, "standing and heat grow")
	K.expect(f, int(CrimeUnderState.corners["c1"]["owner"]) == 1, "the corner is theirs now")
	K.expect(f, (CrimeUnderState.dealers[1]["customers"] as Array).size() >= 1, "regulars are remembered")
	K.teardown()

## The sting rate over many sessions equals the computed chance (heat and tips reset each time so the chance is constant).
func _sting_rate(f: Array) -> void:
	var w := C.town(20)
	_dealer(1)
	for tid in C.adults():
		Story.townies[tid]["coins"] = 500
	CrimeUnderState.sect("deal")["sting"]["base"] = 0.2
	var n: int = 240
	var stings: int = 0
	var expected: float = 0.0
	var sessions: int = 0
	for i in n:
		CrimeUnderState.dealers.erase(1)
		CrimeUnderDeal.ensure(1)["stock"] = {"glow": 8}
		CrimeLifePath.member(1)["heat"] = 0.0
		for tid in C.adults():
			Story.townies[tid]["coins"] = 500
		JusticeState.inmates.clear()
		JusticeState.cases.clear()
		var d: Dictionary = CrimeUnderDeal.rec(1)
		var p: float = CrimeUnderDeal.sting_chance(1, d)
		var r: Dictionary = CrimeUnderDeal.session(1, "c1", {})
		if int(r["sold"]) > 0:
			sessions += 1
			expected += p
			if bool(r["sting"]):
				stings += 1
		CrimeUnderState.corners.clear()
	var measured: float = float(stings) / float(maxi(sessions, 1))
	var want: float = expected / float(maxi(sessions, 1))
	K.expect(f, sessions >= 120, "enough sessions sold something (%d)" % sessions)
	K.expect(f, absf(measured - want) <= 0.08, "the dealer is caught in a sting at the expected rate (measured %.3f vs %.3f over %d sessions)" % [measured, want, sessions])
	K.expect(f, want > 0.03, "and it is not nothing (%.3f)" % want)
	K.teardown()

func _corrupt_cop(f: Array) -> void:
	var w := C.town(20)
	_dealer(1)
	CrimeUnderDeal.ensure(1)
	var cop: int = int(C.adults()[2])
	Story.townies[cop]["career"] = "police_officer"
	CrimeUnderState.cops[cop] = {"taken": 1, "corruption": 1.0, "protecting": [], "refused": 0}
	var plain: float = CrimeUnderDeal.sting_chance(1, CrimeUnderDeal.rec(1))
	CrimeUnderState.cops[cop]["protecting"] = [1]
	var bought: float = CrimeUnderDeal.sting_chance(1, CrimeUnderDeal.rec(1))
	K.expect(f, bought < plain * 0.75, "a cop on the payroll cuts the sting chance (%.3f -> %.3f)" % [plain, bought])
	K.teardown()

func _raid(f: Array) -> void:
	var w := C.town(14)
	_dealer(1)
	CrimeUnderDeal.ensure(1)["stock"] = {"glow": 6}
	CrimeUnderDeal.rec(1)["tips"] = 12.0
	CrimeUnderState.sect("deal")["informant"]["raid_cap"] = 1.0
	CrimeUnderState.sect("deal")["informant"]["raid_per_tip"] = 1.0
	CrimeUnderDeal.on_day()
	K.expect(f, CrimeUnderState.counter("raid") == 1, "customers' tips bring a raid with a search warrant")
	K.expect(f, CrimeUnderDeal.stock_total(1) == 0 and (CrimePerson.in_custody(1) or not CaseStore.cases_of_culprit(1).is_empty()), "the stock is seized and a case is made")
	var c: Dictionary = CaseStore.cases_of_culprit(1)[0]
	K.expect(f, str(c.get("charge_hint", "")) == "drug_dealing" and not JusticeProcess.charge_def("drug_dealing").is_empty(), "charged with dealing")
	K.teardown()

func _corner(f: Array) -> void:
	var w := C.town(20)
	var ids: Array = C.adults()
	var rival: int = int(ids[1])
	CrimeLifePath.join(rival, "chose")
	CrimeLifePath.member(rival)["cred"] = 60.0
	var l: Dictionary = {"deal": {"standing": 60.0, "since": 0, "acts": 0, "via": "contact"}}
	CrimeUnderState.lines[rival] = l
	CrimeUnderState.corners["c2"] = {"owner": rival, "hold": 0.9, "day": SysUtil.day()}
	_dealer(1)
	WorldIface.coins[1] = 1000
	CrimeUnderDeal.buy(1, "glow", 8)
	var beaten: int = 0
	var took: int = 0
	for i in 40:
		CrimeUnderState.corners["c2"] = {"owner": rival, "hold": 0.9, "day": SysUtil.day()}
		CrimeUnderDeal.ensure(1)["stock"] = {"glow": 8}
		JusticeState.inmates.clear()
		var r: Dictionary = CrimeUnderDeal.session(1, "c2", {"no_sting": true})
		if bool(r.get("beaten", false)):
			beaten += 1
		elif int(CrimeUnderState.corners["c2"]["owner"]) == 1:
			took += 1
	K.expect(f, beaten > 0 and took >= 0 and beaten + took >= 30, "working a rival's corner is a fight: run off %d, took it %d" % [beaten, took])
	K.expect(f, beaten > took, "a weak newcomer mostly loses to an established dealer")
	K.teardown()

func _command(f: Array) -> void:
	var w := C.town(14)
	_dealer(1)
	WorldIface.coins[1] = 1000
	var b: Dictionary = Commands.run({"player_id": 1, "folk_id": 1, "action": "crimeunder", "args": {"action": "deal_buy", "substance": "slumber", "qty": 4}})
	K.expect(f, bool(b["ok"]) and CrimeUnderDeal.stock_total(1) == 4, "buy through the command layer")
	K.set_time(3, 14, 0)
	var s: Dictionary = Commands.run({"player_id": 1, "folk_id": 1, "action": "crimeunder", "args": {"action": "deal_sell", "corner": "c3"}})
	K.expect(f, bool(s["ok"]) and CrimeLifeState.pending.size() == 1, "selling takes an hour away from home")
	C.minutes(70)
	K.expect(f, CrimeLifeState.pending.is_empty() and str(CrimeUnderDeal.rec(1)["corner"]) == "c3", "and is played out when the time is up")
	K.teardown()
