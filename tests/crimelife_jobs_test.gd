extends RefCounted
## Task 21 part 1: the jobs of a criminal life. Each job rolls skill, security, casing and gear (CrimeLifeRoll), takes loot, writes a case record for
## discovery and trial, and moves cred, heat and the moral ledger. Forced outcomes make single steps deterministic; the odds comparisons use the
## real numbers.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_odds(f)
	_pickpocket(f)
	_shoplift(f)
	_burglary(f)
	_robbery_scam(f)
	_car(f)
	_caught(f)
	_timed(f)
	_rank_gate(f)
	return f

func _target(jid: String, pid: int = 1) -> Dictionary:
	var t: Array = CrimeLifeJobs.targets(pid, jid)
	return t[0] if not t.is_empty() else {}

func _odds(f: Array) -> void:
	var w := C.town(12)
	var ada = w.get_folk(1)
	CrimeLifePath.join(1)
	var tgt: Dictionary = _target("burglary")
	var base: Dictionary = CrimeLifeRoll.odds(1, "burglary", str(tgt["scene"]), {"night": true})
	ada.add_skill_xp("stealth", 3000.0)
	ada.add_skill_xp("handiness", 1000.0)
	var skilled: Dictionary = CrimeLifeRoll.odds(1, "burglary", str(tgt["scene"]), {"night": true})
	K.expect(f, float(skilled["pull_off"]) > float(base["pull_off"]) and float(skilled["detect"]) < float(base["detect"]), "skill makes the job work more often and noticed less (%.2f -> %.2f, %.2f -> %.2f)" % [base["pull_off"], skilled["pull_off"], base["detect"], skilled["detect"]])
	var cased: Dictionary = CrimeLifeRoll.odds(1, "burglary", str(tgt["scene"]), {"night": true, "cased": 1.0})
	K.expect(f, float(cased["pull_off"]) > float(skilled["pull_off"]) and float(cased["detect"]) < float(skilled["detect"]), "a cased target is easier")
	CrimeLifeHeist.buy_gear(1, "lockpicks")
	CrimeLifeHeist.buy_gear(1, "gloves")
	var geared: Dictionary = CrimeLifeRoll.odds(1, "burglary", str(tgt["scene"]), {"night": true})
	K.expect(f, float(geared["pull_off"]) > float(skilled["pull_off"]) and float(geared["trace"]) < float(skilled["trace"]), "kit helps (lockpicks) and leaves less trace (gloves)")
	var day: Dictionary = CrimeLifeRoll.odds(1, "pickpocket", "street", {"night": false})
	var night: Dictionary = CrimeLifeRoll.odds(1, "pickpocket", "street", {"night": true})
	K.expect(f, float(night["detect"]) < float(day["detect"]), "the dark helps")
	K.teardown()

func _pickpocket(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	var t: Dictionary = _target("pickpocket")
	K.expect(f, not t.is_empty(), "there is somebody to pick a pocket of")
	var victim: int = int(t["victim"])
	var vcoins: int = CrimePerson.coins(victim)
	var mine: int = WorldIface.get_coins(1)
	var res: Dictionary = CrimeLifeJobs.run(1, "pickpocket", t, {"force": "clean"})
	K.expect(f, res["outcome"] == "clean" and int(res["loot"]) > 0, "a clean pickpocket takes coins")
	K.expect(f, CrimePerson.coins(victim) == vcoins - int(res["loot"]) and WorldIface.get_coins(1) == mine + int(res["loot"]), "the coins move from the victim to the thief")
	var c: Dictionary = CaseStore.get_case(int(res["case"]))
	K.expect(f, str(c["kind"]) == "theft" and int(c["culprit"]) == 1 and str(c["state"]) == "hidden", "an unseen theft is a hidden case against the real thief")
	K.expect(f, CrimeLifePath.member(1)["jobs"] == 1 and CrimeLifePath.cred(1) > 2.0 and CrimeLifePath.skill(1, "stealth") >= 0, "the job counts: jobs and cred go up")
	K.expect(f, CrimeLifeMoral.totals(1)["crimes"] == 1, "the victim is in the thief's ledger")
	var seen: Dictionary = CrimeLifeJobs.run(1, "pickpocket", _target("pickpocket"), {"force": "seen"})
	var c2: Dictionary = CaseStore.get_case(int(seen["case"]))
	K.expect(f, str(c2["state"]) == "open" and bool(c2["witnessed"]), "a noticed theft is reported at once")
	K.expect(f, float(CrimeLifePath.member(1)["heat"]) > 1.0, "being seen raises heat")
	K.teardown()

func _shoplift(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	var t: Dictionary = _target("shoplift")
	var res: Dictionary = CrimeLifeJobs.run(1, "shoplift", t, {"force": "clean"})
	K.expect(f, int(res["goods"]) > 0 and CrimeLifeFence.stash_value(1) > 0, "shoplifted goods go into the stash, not into coins")
	var c: Dictionary = CaseStore.get_case(int(res["case"]))
	K.expect(f, str(c["state"]) == "closed", "an unseen shoplifting leaves no open case")
	var seen: Dictionary = CrimeLifeJobs.run(1, "shoplift", t, {"force": "seen"})
	var c2: Dictionary = CaseStore.get_case(int(seen["case"]))
	K.expect(f, str(c2["state"]) == "closed" and str(c2["verdict"]) == "petty" and not (JusticeState.records.get(1, []) as Array).is_empty(), "a seen shoplifting is settled as a petty offence with a fine or service, and goes on the record")
	K.teardown()

func _burglary(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	CrimeLifePath.member(1)["rank"] = "burglar"
	K.set_time(3, 2, 0)
	var t: Dictionary = _target("burglary")
	var res: Dictionary = CrimeLifeJobs.run(1, "burglary", t, {"force": "clean", "night": true})
	var c: Dictionary = CaseStore.get_case(int(res["case"]))
	K.expect(f, str(c["kind"]) == "burglary" and int(c["culprit"]) == 1 and float(c["trace"]) > 0.0, "a burglary case with a trace of the thief")
	K.expect(f, int(res["loot"]) + int(res["goods"]) >= 60, "the take is real money plus goods")
	var fail: Dictionary = CrimeLifeJobs.run(1, "burglary", t, {"force": "fail", "night": true})
	K.expect(f, fail["outcome"] == "fail" and int(fail["case"]) == -1, "a failed break-in takes nothing and leaves no case")
	K.teardown()

func _robbery_scam(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	CrimeLifePath.member(1)["rank"] = "burglar"
	var rt: Dictionary = _target("store_robbery")
	var r: Dictionary = CrimeLifeJobs.run(1, "store_robbery", rt, {"force": "seen"})
	var rc: Dictionary = CaseStore.get_case(int(r["case"]))
	K.expect(f, str(rc["kind"]) == "robbery" and int(r["loot"]) > 0 and str(rc["state"]) == "open", "a seen shop robbery is a reported robbery with a witness (the shopkeeper)")
	var st: Dictionary = _target("scam")
	var s: Dictionary = CrimeLifeJobs.run(1, "scam", st, {"force": "clean"})
	var sc: Dictionary = CaseStore.get_case(int(s["case"]))
	K.expect(f, str(sc["kind"]) == "fraud" and str(sc["state"]) == "hidden", "a con is a hidden fraud until the victim works it out")
	K.expect(f, CrimeLifePath.skill(1, "charisma") >= 0 and CrimeLifeJobs.job("scam")["xp_skill"] == "charisma", "a con trains charisma, not stealth")
	K.teardown()

func _car(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	CrimeLifePath.member(1)["rank"] = "burglar"
	K.set_time(3, 1, 0)
	var res: Dictionary = CrimeLifeJobs.run(1, "car_theft", _target("car_theft"), {"force": "clean", "night": true})
	var items: Array = CrimeLifeFence.items_of(1)
	K.expect(f, items.size() == 1 and bool(items[0]["car"]), "a stolen car goes into the stash (and can be a getaway car)")
	var c: Dictionary = CaseStore.get_case(int(res["case"]))
	K.expect(f, str(c.get("charge_hint", "")) == "car_theft", "the charge is car theft")
	K.teardown()

func _caught(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	CrimeLifePath.member(1)["rank"] = "burglar"
	var res: Dictionary = CrimeLifeJobs.run(1, "store_robbery", _target("store_robbery"), {"force": "caught"})
	var c: Dictionary = CaseStore.get_case(int(res["case"]))
	K.expect(f, str(c["state"]) in ["charged", "arrested", "trial"] and int(c["accused"]) == 1, "caught in the act leads to arrest and charges (state %s)" % str(c["state"]))
	K.expect(f, (JusticeState.inmates.has(1) and CrimePerson.in_custody(1)) or int(c.get("bail_paid", 0)) > 0, "the thief is held, or out on bail")
	K.expect(f, int(CrimeLifePath.member(1)["caught"]) == 1, "the path keeps count of arrests")
	K.teardown()

func _timed(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	K.set_time(3, 12, 0)
	var r: Dictionary = Commands.run({"player_id": 1, "folk_id": 1, "action": "crimelife", "args": {"action": "job", "job": "pickpocket", "target": _target("pickpocket")}})
	K.expect(f, bool(r["ok"]) and CrimeLifeState.pending.size() == 1, "a job through the command layer is queued and takes time")
	K.expect(f, JusticeState.cases.is_empty(), "nothing has happened yet")
	C.minutes(40)
	K.expect(f, CrimeLifeState.pending.is_empty() and CrimeLifePath.member(1)["jobs"] == 1, "when the time is up the job is rolled")
	var late: Dictionary = Commands.run({"player_id": 1, "folk_id": 1, "action": "crimelife", "args": {"action": "job", "job": "burglary", "target": _target("burglary")}})
	K.expect(f, not bool(late["ok"]), "a break-in needs the dark")
	K.teardown()

func _rank_gate(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	var r: Dictionary = CrimeLifeJobs.start(1, "store_robbery", _target("store_robbery"))
	K.expect(f, not bool(r["ok"]), "a petty thief is not trusted with a shop robbery")
	CrimeLifePath.member(1)["rank"] = "burglar"
	K.expect(f, CrimeLifeJobs.unlocked(1, "store_robbery") and CrimeLifeJobs.unlocked(1, "pickpocket"), "burglars can do both")
	K.teardown()
