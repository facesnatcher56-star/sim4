extends RefCounted
## Task 21 part 1: loyalty and betrayal. A crew member snitches under a plea offer (loyalty, cut and record decide), a charged player may name the crew for
## a lighter sentence or stay quiet, and rivals can rat out a thriving criminal. Snitching ruins a name in the underworld.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_snitches(f)
	_rates(f)
	_effects(f)
	_player_deal(f)
	_player_silent(f)
	_townie_leader(f)
	_rivals(f)
	return f

## A heist case against `leader` (accused) with a crew of the given loyalties.
func _heist_case(leader: int, loyalties: Array) -> Dictionary:
	var crew: Array = []
	var ids: Array = C.adults()
	var n: int = 0
	for i in ids.size():
		var pid: int = int(ids[i])
		if pid == leader:
			continue
		if n >= loyalties.size():
			break
		CrimeLifePath.join(pid, "recruited")
		crew.append({"pid": pid, "role": "lookout", "cut": 0.15, "loyal": float(loyalties[n])})
		n += 1
	var hid: int = CrimeLifeState.next_heist
	CrimeLifeState.next_heist += 1
	CrimeLifeState.heists[hid] = {"id": hid, "leader": leader, "target": "jeweller", "scene": "biz:jeweller", "stage": "failed", "day": 0, "crew": crew, "getaway": false}
	var c: Dictionary = CaseStore.create("robbery", leader, -1, "street", {"witnessed": true, "witness_clarity": 0.6, "trace": 0.3})
	c["heist"] = hid
	c["crew"] = crew.map(func(e): return int(e["pid"]))
	c["charge_hint"] = "grand_theft"
	c["also"] = ["conspiracy"]
	c["state"] = "open"
	c["disc_day"] = SysUtil.day()
	return c

func _snitches(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	CrimeLifePath.member(1)["cred"] = 40.0
	var c: Dictionary = _heist_case(1, [0.05, 0.05])
	var crew0: int = int((c["crew"] as Array)[0])
	CrimeLifeContacts.add(1, crew0, "driver", 0.5)
	var sn: Dictionary = {}
	for i in 30:
		var cc: Dictionary = _heist_case(1, [0.05, 0.05])
		JusticeState.inmates.clear()
		JusticeProcess.arrest(cc, 1)
		if int(cc.get("snitched_by", -1)) >= 0:
			sn = cc
			break
	K.expect(f, not sn.is_empty(), "disloyal crew members talk to the police once the leader is charged")
	var q: int = int(sn["snitched_by"])
	K.expect(f, float(sn["tips"]) >= 0.4, "a snitch hands the police a lot of evidence (tips %.2f)" % float(sn["tips"]))
	K.expect(f, bool(CrimeLifePath.member(q)["snitch"]) and CrimeLifePath.cred(q) < 5.0, "the snitch's name is ruined in the underworld")
	K.expect(f, not CrimeLifeContacts.has(1, q), "and the leader drops them as a contact")
	var again: Dictionary = CrimeLifeContacts.ask_around(q, int(C.adults()[0]))
	K.teardown()

func _rates(f: Array) -> void:
	var w := C.town(14)
	CrimeLifePath.join(1)
	var c_loyal: Dictionary = _heist_case(1, [0.95])
	var c_rat: Dictionary = _heist_case(1, [0.05])
	var q_loyal: int = int((c_loyal["crew"] as Array)[0])
	var q_rat: int = int((c_rat["crew"] as Array)[0])
	var p_loyal: float = CrimeLifeSnitch.snitch_chance(q_loyal, c_loyal)
	var p_rat: float = CrimeLifeSnitch.snitch_chance(q_rat, c_rat)
	K.expect(f, p_rat > p_loyal + 0.2, "loyalty protects the leader (%.2f vs %.2f)" % [p_loyal, p_rat])
	var n: int = 600
	var talks: int = 0
	for i in n:
		if CrimeLifeState.chance(p_rat):
			talks += 1
	K.expect(f, absf(float(talks) - p_rat * n) < 4.0 * sqrt(p_rat * n), "snitching follows its chance (%d of %d at %.2f)" % [talks, n, p_rat])
	var rec: Dictionary = {"pid": q_rat, "role": "lookout", "cut": 0.05, "loyal": 0.05}
	CrimeLifeState.heists[int(c_rat["heist"])]["crew"] = [rec]
	var small: float = CrimeLifeSnitch.snitch_chance(q_rat, c_rat)
	rec["cut"] = 0.3
	K.expect(f, CrimeLifeSnitch.snitch_chance(q_rat, c_rat) < small, "a fat cut keeps people quiet")
	K.teardown()

func _effects(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	var c: Dictionary = _heist_case(1, [0.5])
	var q: int = int((c["crew"] as Array)[0])
	c["accused"] = 1
	var before: float = float(JusticeTrial.breakdown(c, 1, false)["p_guilty"])
	CrimeLifeSnitch.snitch(c, q)
	var after: float = float(JusticeTrial.breakdown(c, 1, false)["p_guilty"])
	K.expect(f, after > before + 0.05, "a snitch makes a conviction far likelier (%.2f -> %.2f)" % [before, after])
	K.expect(f, int(c["snitched_by"]) == q, "the case remembers who talked")
	K.teardown()

func _player_deal(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	CrimeLifePath.member(1)["cred"] = 50.0
	var c: Dictionary = _heist_case(1, [0.99, 0.99])
	JusticePlayer.auto = "name"
	JusticeState.inmates.clear()
	JusticeProcess.arrest(c, 1)
	JusticePlayer.auto = ""
	K.expect(f, bool(c.get("deal", false)), "the charged player takes the deal")
	var arrested: int = 0
	for q in (c["crew"] as Array):
		if CrimePerson.in_custody(int(q)) or not CrimeStore_cases_of(int(q)).is_empty():
			arrested += 1
	K.expect(f, arrested == 2, "the named crew are picked up, each with their own case")
	K.expect(f, bool(CrimeLifePath.member(1)["snitch"]) and CrimeLifePath.cred(1) < 30.0, "and the player's name takes a beating")
	K.expect(f, JusticeProcess.offer_plea(c), "a deal means a guilty plea (a lighter sentence)")
	K.teardown()

func CrimeStore_cases_of(pid: int) -> Array:
	return CaseStore.cases_of_culprit(pid).filter(func(x): return int(x.get("named_in", -1)) >= 0)

func _player_silent(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	CrimeLifePath.member(1)["cred"] = 50.0
	var c: Dictionary = _heist_case(1, [0.5, 0.5])
	c["crew"] = []                 # nobody to snitch: isolate the player's choice
	var crew: Array = CrimeLifeHeist.get_heist(int(c["heist"]))["crew"]
	c["crew"] = crew.map(func(e): return int(e["pid"]))
	JusticePlayer.auto = "silent"
	CrimeLifeSnitch.decide(c, 1, "silent")
	JusticePlayer.auto = ""
	K.expect(f, not bool(c.get("deal", false)) and CrimeLifePath.cred(1) > 50.0, "keeping quiet earns respect")
	K.expect(f, float(crew[0]["loyal"]) > 0.55, "and the crew's loyalty grows")
	K.expect(f, not bool(CrimeLifePath.member(1)["snitch"]), "no stain")
	K.teardown()

func _townie_leader(f: Array) -> void:
	var w := C.town(12)
	var leader: int = int(C.adults()[0])
	CrimeLifePath.join(leader, "chose")
	var named: int = 0
	var quiet: int = 0
	for i in 60:
		var c: Dictionary = _heist_case(leader, [0.1])
		JusticeState.inmates.clear()
		CrimeLifeSnitch.decide(c, leader, "name" if CrimeLifeState.chance(0.5) else "silent")
		if bool(c.get("deal", false)):
			named += 1
		else:
			quiet += 1
	K.expect(f, named > 5 and quiet > 5, "both choices are possible for townies (%d named, %d quiet)" % [named, quiet])
	K.teardown()

func _rivals(f: Array) -> void:
	var w := C.town(14)
	CrimeLifePath.join(1)
	CrimeLifePath.member(1)["cred"] = 40.0
	var rival: int = int(C.adults()[0])
	CrimeLifePath.join(rival, "chose")
	CrimeLifePath.member(rival)["cred"] = 45.0
	var tipped: int = 0
	for i in 150:
		var c: Dictionary = CaseStore.create("burglary", 1, -1, "town:2", {})
		var n: int = CrimeLifeSnitch.rival_tips()
		if int(c.get("rat_by", -1)) == rival:
			tipped += 1
		JusticeState.cases.erase(int(c["id"]))
	K.expect(f, tipped >= 1 and tipped < 40, "a rival now and then tips the police about a thriving criminal (%d of 150 days)" % tipped)
	var c2: Dictionary = CaseStore.create("burglary", 1, -1, "town:2", {})
	c2["rat_by"] = rival
	var friend: int = int(C.adults()[1])
	CrimeLifePath.join(friend, "chose")
	CrimeLifePath.member(friend)["cred"] = 41.0
	CrimeLifeContacts.add(1, friend, "driver", 0.5)
	K.teardown()
