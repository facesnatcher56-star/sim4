extends RefCounted
## Task 21 part 1: planned heists. Planning needs a name (burglar rank), time and a cased target; the crew (townies with roles, loyalty and a cut), gear
## and a stolen getaway car shape three phases (entry, vault, escape); the takings are split; the case flows into discovery and trial.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_casing(f)
	_planning(f)
	_crew(f)
	_phases(f)
	_runs(f)
	_commands(f)
	_townie_heist(f)
	return f

func _boss(w: StubWorld) -> void:
	var ada = w.get_folk(1)
	CrimeLifePath.join(1)
	CrimeLifePath.member(1)["rank"] = "burglar"
	CrimeLifePath.member(1)["cred"] = 30.0
	CrimeLifePath.member(1)["jobs"] = 6
	ada.add_skill_xp("stealth", 1500.0)
	ada.add_skill_xp("logic", 700.0)
	ada.add_skill_xp("handiness", 700.0)

func _crew_member(i: int, skills: Dictionary) -> int:
	var pid: int = int(C.adults()[i])
	CrimeLifePath.join(pid, "recruited")
	CrimeLifePath.member(pid)["skills"] = skills
	return pid

func _casing(f: Array) -> void:
	var w := C.town(12)
	_boss(w)
	K.expect(f, CrimeLifeCasing.amount(1, "biz:bank") == 0.0, "an unknown place is unknown")
	var r: Dictionary = CrimeLifeCasing.session(1, "biz:bank")
	K.expect(f, float(r["amount"]) >= 0.18 and CrimeLifeCasing.amount(1, "biz:bank") > 0.0, "a session of watching builds knowledge (%.2f)" % r["amount"])
	for i in 4:
		CrimeLifeCasing.session(1, "biz:bank")
	K.expect(f, CrimeLifeCasing.amount(1, "biz:bank") == 1.0, "a few sessions give a complete picture")
	var lines: Array = CrimeLifeCasing.report(1, "biz:bank")
	K.expect(f, lines.size() >= 4 and str(lines).contains("Guards"), "and the report says what was learned: %s" % str(lines))
	K.expect(f, CrimeLifeCasing.report(1, "biz:museum").is_empty(), "nothing is known about a place never watched")
	K.set_time(40, 12)
	var fresh: float = CrimeLifeCasing.amount(1, "biz:bank")
	K.set_time(100, 12)
	K.expect(f, CrimeLifeCasing.amount(1, "biz:bank") < fresh, "old knowledge fades")
	var heat0: float = float(CrimeLifePath.member(1).get("heat", 0.0))
	var spotted: bool = false
	for i in 80:
		if bool(CrimeLifeCasing.session(1, "biz:jeweller")["spotted"]):
			spotted = true
	K.expect(f, spotted and float(CrimeLifePath.member(1)["heat"]) > heat0, "watching a place can get noticed, which adds heat")
	var q: Dictionary = CrimeLifeCasing.start(1, "biz:bank")
	K.expect(f, bool(q["ok"]) and CrimeLifeState.pending.size() == 1, "casing as a player takes time away from home")
	K.teardown()

func _planning(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	var no: Dictionary = CrimeLifeHeist.plan(1, "bank")
	K.expect(f, not bool(no["ok"]), "an unproven thief cannot plan a bank job")
	_boss(w)
	K.expect(f, not bool(CrimeLifeHeist.plan(1, "castle")["ok"]), "no such target")
	var p: Dictionary = CrimeLifeHeist.plan(1, "jeweller")
	K.expect(f, bool(p["ok"]), "a burglar can plan a job")
	K.expect(f, not bool(CrimeLifeHeist.plan(1, "bank")["ok"]), "one plan at a time")
	var h: Dictionary = CrimeLifeHeist.get_heist(int(p["heist"]))
	K.expect(f, CrimeLifeHeist.missing(h) != "", "not ready straight away: %s" % CrimeLifeHeist.missing(h))
	K.set_time(5, 12)
	K.expect(f, CrimeLifeHeist.missing(h).contains("Watch"), "then it needs casing: %s" % CrimeLifeHeist.missing(h))
	CrimeLifeCasing.session(1, "biz:jeweller")
	CrimeLifeCasing.session(1, "biz:jeweller")
	K.expect(f, CrimeLifeHeist.missing(h) == "", "plan, time and knowledge make it ready")
	K.expect(f, CrimeLifeHeist.abort(1) and CrimeLifeHeist.plan_of(1).is_empty(), "a plan can be dropped")
	K.teardown()

func _crew(f: Array) -> void:
	var w := C.town(14)
	_boss(w)
	var p: Dictionary = CrimeLifeHeist.plan(1, "jeweller")
	var hid: int = int(p["heist"])
	var driver: int = _crew_member(0, {"handiness": 8, "fitness": 6})
	CrimeLifeContacts.add(1, driver, "driver", 0.8)
	var ok: bool = false
	for i in 30:
		var r: Dictionary = CrimeLifeHeist.recruit(1, hid, driver, "driver", 0.3)
		if bool(r["ok"]):
			ok = true
			break
	K.expect(f, ok, "a contact with the right skills joins for a good cut")
	K.expect(f, not bool(CrimeLifeHeist.recruit(1, hid, driver, "driver")["ok"]), "no double joining")
	var e: Dictionary = CrimeLifeHeist.crew_entry(CrimeLifeHeist.get_heist(hid), driver)
	K.expect(f, e != null and float(e["loyal"]) > 0.4, "loyalty comes from the cut and the contact's trust (%.2f)" % float(e["loyal"]))
	var cheap: int = _crew_member(1, {})
	var rich: int = _crew_member(2, {})
	var p_cheap: int = 0
	var p_rich: int = 0
	for i in 60:
		var hh: Dictionary = CrimeLifeHeist.get_heist(hid)
		hh["crew"] = []
		if bool(CrimeLifeHeist.recruit(1, hid, cheap, "lookout", 0.05)["ok"]):
			p_cheap += 1
		hh["crew"] = []
		if bool(CrimeLifeHeist.recruit(1, hid, rich, "lookout", 0.35)["ok"]):
			p_rich += 1
	K.expect(f, p_rich > p_cheap, "a bigger cut recruits more easily (%d vs %d of 60)" % [p_rich, p_cheap])
	var honest: int = int(C.adults()[5])
	Story.townies[honest]["traits"] = ["honest"]
	var yes: int = 0
	for i in 40:
		CrimeLifeHeist.get_heist(hid)["crew"] = []
		if bool(CrimeLifeHeist.recruit(1, hid, honest, "muscle")["ok"]):
			yes += 1
	K.expect(f, yes <= 2, "an honest townie almost never says yes (%d of 40)" % yes)
	var h: Dictionary = CrimeLifeHeist.get_heist(hid)
	h["crew"] = []
	for i in 6:
		CrimeLifeHeist.recruit(1, hid, int(C.adults()[6 + i]), "muscle", 0.35)
	K.expect(f, (h["crew"] as Array).size() <= 4, "the crew has a size limit")
	K.teardown()

func _phases(f: Array) -> void:
	var w := C.town(14)
	_boss(w)
	var make: Callable = func(target: String) -> Dictionary:
		var p: Dictionary = CrimeLifeHeist.plan(1, target)
		return CrimeLifeHeist.get_heist(int(p["heist"]))
	var h: Dictionary = make.call("jeweller")
	var solo: Dictionary = CrimeLifeHeistRun.phases(h)
	var driver: int = _crew_member(0, {"handiness": 9, "fitness": 8})
	var safe: int = _crew_member(1, {"handiness": 9, "logic": 8})
	var look: int = _crew_member(2, {"stealth": 9, "logic": 7})
	var hack: int = _crew_member(3, {"logic": 9, "handiness": 6})
	h["crew"] = [{"pid": driver, "role": "driver", "cut": 0.1, "loyal": 0.6}, {"pid": safe, "role": "safecracker", "cut": 0.1, "loyal": 0.6},
		{"pid": look, "role": "lookout", "cut": 0.1, "loyal": 0.6}, {"pid": hack, "role": "hacker", "cut": 0.1, "loyal": 0.6}]
	var crewed: Dictionary = CrimeLifeHeistRun.phases(h)
	K.expect(f, float(crewed["entry"]) > float(solo["entry"]) and float(crewed["vault"]) > float(solo["vault"]) and float(crewed["escape"]) > float(solo["escape"]) and float(crewed["noticed"]) < float(solo["noticed"]),
		"a full crew improves every phase: entry %.2f->%.2f vault %.2f->%.2f escape %.2f->%.2f" % [solo["entry"], crewed["entry"], solo["vault"], crewed["vault"], solo["escape"], crewed["escape"]])
	h["getaway"] = true
	var car: Dictionary = CrimeLifeHeistRun.phases(h)
	K.expect(f, float(car["escape"]) > float(crewed["escape"]), "a getaway car helps the escape")
	CrimeLifeState.cased["1|biz:jeweller"] = {"amount": 1.0, "day": SysUtil.day()}
	var known: Dictionary = CrimeLifeHeistRun.phases(h)
	K.expect(f, float(known["entry"]) > float(car["entry"]) and float(known["noticed"]) < float(car["noticed"]) and float(known["vault"]) > float(car["vault"]), "a well-cased target is easier in every way")
	CrimeLifeState.cased.clear()
	var bank: Dictionary = make.call("bank") if false else {}
	var hb: Dictionary = {"id": 99, "leader": 1, "target": "bank", "scene": "biz:bank", "stage": "planning", "day": 0, "crew": h["crew"], "getaway": true}
	var vs_bank: Dictionary = CrimeLifeHeistRun.phases(hb)
	K.expect(f, float(vs_bank["entry"]) < float(car["entry"]), "the bank is harder than the jeweller")
	K.teardown()

func _runs(f: Array) -> void:
	var w := C.town(14)
	_boss(w)
	var results: Dictionary = {}
	var loots: Array = []
	var cases_ok: bool = true
	var cut_paid: bool = false
	for i in 50:
		CrimeLifeState.heists.clear()
		CrimeLifeState.cased["1|biz:jeweller"] = {"amount": 0.7, "day": SysUtil.day()}
		var crew_pid: int = _crew_member(0, {"handiness": 6})
		var p: Dictionary = CrimeLifeHeist.plan(1, "jeweller")
		var h: Dictionary = CrimeLifeHeist.get_heist(int(p["heist"]))
		h["crew"] = [{"pid": crew_pid, "role": "safecracker", "cut": 0.2, "loyal": 0.7}]
		h["day"] = -10
		h["stage"] = "ready"
		JusticeState.inmates.clear()
		CrimePerson.add_coins(crew_pid, -CrimePerson.coins(crew_pid))
		var before: int = CrimePerson.coins(1)
		var r: Dictionary = CrimeLifeHeistRun.run(h)
		results[r["result"]] = int(results.get(r["result"], 0)) + 1
		if r["result"] in ["getaway", "partial"]:
			loots.append(int(r["loot"]))
			var c: Dictionary = CaseStore.get_case(int(r["case"]))
			if str(c["kind"]) != "robbery" or str(c["charge_hint"]) != "grand_theft" or not (c["also"] as Array).has("conspiracy") or (c["crew"] as Array).size() != 1:
				cases_ok = false
			if CrimePerson.coins(crew_pid) == int(float(r["loot"]) * 0.2):
				cut_paid = true
			if CrimePerson.coins(1) - before != int(r["loot"]) - int(float(r["loot"]) * 0.2):
				cases_ok = false
		JusticeState.inmates.erase(1)
		CrimeLifeState.guards.clear()
		JusticeState.pending.clear()
	K.expect(f, results.has("getaway") and (results.has("caught") or results.has("aborted") or results.has("partial")), "heists succeed and fail: %s" % str(results))
	K.expect(f, cases_ok and cut_paid, "every raid is a robbery case with a grand-theft charge and a conspiracy count, and the takings are split by the crew's cut")
	var td: Dictionary = CrimeLifeHeist.target_def("jeweller")
	var in_range: bool = true
	for l in loots:
		if int(l) < int(float((td["loot"] as Array)[0]) * 0.4) or int(l) > int((td["loot"] as Array)[1]):
			in_range = false
	K.expect(f, in_range and not loots.is_empty(), "the haul is in the target's range")
	# cased targets succeed more often
	var rate: Callable = func(amount: float) -> int:
		var ok: int = 0
		for i in 60:
			CrimeLifeState.heists.clear()
			CrimeLifeState.cased["1|biz:jeweller"] = {"amount": amount, "day": SysUtil.day()}
			var p2: Dictionary = CrimeLifeHeist.plan(1, "jeweller")
			var h2: Dictionary = CrimeLifeHeist.get_heist(int(p2["heist"]))
			h2["stage"] = "ready"
			var r2: Dictionary = CrimeLifeHeistRun.run(h2)
			if r2["result"] == "getaway":
				ok += 1
			JusticeState.inmates.erase(1)
			JusticeState.pending.clear()
		return ok
	var cold: int = rate.call(0.0)
	var warm: int = rate.call(1.0)
	K.expect(f, warm > cold, "a cased target is robbed cleanly more often (%d vs %d of 60)" % [warm, cold])
	K.teardown()

func _commands(f: Array) -> void:
	var w := C.town(14)
	_boss(w)
	var run: Callable = func(a: Dictionary) -> Dictionary:
		return Commands.run({"player_id": 1, "folk_id": 1, "action": "crimelife", "args": a})
	var p: Dictionary = run.call({"action": "plan", "target": "museum"})
	K.expect(f, bool(p["ok"]), "planning is a command")
	var hid: int = int(p["heist"])
	var early: Dictionary = run.call({"action": "go", "heist": hid})
	K.expect(f, not bool(early["ok"]) and str(early["msg"]) != "", "going too early is refused with a plain reason: %s" % str(early["msg"]))
	K.set_time(6, 20)
	CrimeLifeCasing.session(1, "biz:museum")
	CrimeLifeCasing.session(1, "biz:museum")
	CrimeLifeFence.add_stash(1, "car_theft", 400, -1, true)
	var g: Dictionary = run.call({"action": "getaway", "heist": hid})
	K.expect(f, bool(g["ok"]) and bool(CrimeLifeHeist.get_heist(hid)["getaway"]) and CrimeLifeFence.items_of(1).is_empty(), "a stolen car becomes the getaway car")
	var go: Dictionary = run.call({"action": "go", "heist": hid})
	K.expect(f, bool(go["ok"]) and not CrimeLifeState.pending.is_empty(), "when ready the crew sets off and the run waits for its time")
	C.minutes(200)
	var h: Dictionary = CrimeLifeHeist.get_heist(hid)
	K.expect(f, str(h["stage"]) in ["done", "failed"] and h.has("result"), "the raid is played out when the time is up (%s)" % str(h.get("result", "?")))
	K.teardown()

func _townie_heist(f: Array) -> void:
	var w := C.town(14)
	var boss: int = _crew_member(0, {"stealth": 6, "logic": 6, "handiness": 5})
	CrimeLifePath.member(boss)["rank"] = "crew_boss"
	_crew_member(1, {"handiness": 5})
	_crew_member(2, {"fitness": 5})
	var res: Dictionary = CrimeLifeTownie.heist(boss)
	K.expect(f, res.has("result"), "a townie crew boss can run a heist statistically (%s)" % str(res.get("result", "?")))
	K.teardown()
