extends RefCounted
## Task 21 part 1: the criminal path as a hidden career: joining (by choice, by drifting in, through the command layer), the stealth skill, the five
## ranks, street cred that moves opposite to the town record, contacts, and the save round trip.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_join(f)
	_ranks(f)
	_cred_vs_record(f)
	_contacts(f)
	_command(f)
	_drift(f)
	_save(f)
	return f

func _join(f: Array) -> void:
	var w := C.town(8)
	K.expect(f, not CrimeLifePath.is_member(1), "nobody is on the path at the start")
	K.expect(f, CrimeLifePath.join(1, "chose") and CrimeLifePath.rank_id(1) == "petty_thief", "joining starts as a petty thief")
	K.expect(f, not CrimeLifePath.join(1, "chose"), "joining twice does nothing")
	var ada = w.get_folk(1)
	ada.add_skill_xp("stealth", 300.0)
	K.expect(f, ada.skill_level("stealth") >= 2 and CrimeLifePath.skill(1, "stealth") >= 2, "stealth is a real skill that grows with practice (level %d)" % ada.skill_level("stealth"))
	var kid = K.make_folk(w, "Kit", [], 1, Vector2i(14, 12), "child")
	K.expect(f, not CrimeLifePath.join(int(kid.id), "chose"), "children cannot join")
	CrimeLifePath.leave(1)
	K.expect(f, not CrimeLifePath.is_member(1) and CrimeLifePath.going_straight(1), "leaving the path means going straight for a while")
	K.teardown()

func _ranks(f: Array) -> void:
	var w := C.town(8)
	var ada = w.get_folk(1)
	CrimeLifePath.join(1)
	var m: Dictionary = CrimeLifePath.member(1)
	m["cred"] = 19.0
	CrimeLifePath.update_rank(1)
	K.expect(f, CrimeLifePath.rank_id(1) == "petty_thief", "cred and skill alone are not enough for burglar")
	ada.add_skill_xp("stealth", 300.0)
	m["jobs"] = 3
	CrimeLifePath.update_rank(1)
	K.expect(f, CrimeLifePath.rank_id(1) == "burglar", "cred 19, stealth 2 and three jobs make a burglar (got %s)" % CrimeLifePath.rank_id(1))
	CrimeLifePath.add_cred(1, 25.0)
	m["fenced"] = 3
	ada.add_skill_xp("charisma", 700.0)
	CrimeLifePath.update_rank(1)
	K.expect(f, CrimeLifePath.rank_id(1) == "fence", "a fence needs standing, charisma and sold goods (got %s)" % CrimeLifePath.rank_id(1))
	m["cred"] = 70.0
	m["heists"] = 1
	ada.add_skill_xp("stealth", 2000.0)
	ada.add_skill_xp("logic", 700.0)
	CrimeLifePath.update_rank(1)
	K.expect(f, CrimeLifePath.rank_id(1) == "crew_boss", "a first heist and a name make a crew boss (got %s)" % CrimeLifePath.rank_id(1))
	m["cred"] = 90.0
	m["heists"] = 3
	ada.add_skill_xp("logic", 3000.0)
	ada.add_skill_xp("stealth", 4000.0)
	CrimeLifePath.update_rank(1)
	K.expect(f, CrimeLifePath.rank_id(1) == "mastermind", "three heists make a mastermind (got %s)" % CrimeLifePath.rank_id(1))
	m["cred"] = 10.0
	CrimeLifePath.update_rank(1)
	K.expect(f, CrimeLifePath.rank_index(1) < 2, "a lost street name drops the rank")
	K.teardown()

func _cred_vs_record(f: Array) -> void:
	var w := C.town(8)
	CrimeLifePath.join(1)
	var before: float = CrimeLifePath.cred(1)
	# a conviction lowers the town's opinion; keeping quiet raises the street's
	RelationshipKnowledge.add_reputation(1, -6.0)
	CrimeLifePath.add_cred(1, 4.0)
	K.expect(f, CrimeLifePath.cred(1) > before and CrimePerson.reputation(1) < 0.0, "town reputation falls while street cred rises (cred %.1f, rep %.1f)" % [CrimeLifePath.cred(1), CrimePerson.reputation(1)])
	var s: Dictionary = CrimeLifePath.summary(1)
	K.expect(f, bool(s["member"]) and s.has("town_rep") and s.has("cred"), "the summary shows both reputations")
	CrimeLifePath.member(1)["last_job_day"] = SysUtil.day() - 40
	var c0: float = CrimeLifePath.cred(1)
	CrimeLifePath.on_day_member(1)
	K.expect(f, CrimeLifePath.cred(1) < c0, "an idle criminal slowly loses their name")
	K.teardown()

func _contacts(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	var t: int = int(C.adults()[0])
	CrimeLifePath.join(t, "chose")
	CrimeLifeState.talk.clear()
	var met: bool = false
	for i in 40:
		CrimeLifeState.talk.clear()
		var r: Dictionary = CrimeLifeContacts.ask_around(1, t)
		if bool(r.get("ok", false)):
			met = true
			break
	K.expect(f, met and CrimeLifeContacts.has(1, t), "asking around a criminal townie eventually makes a contact")
	var again: Dictionary = CrimeLifeContacts.ask_around(1, t)
	K.expect(f, not bool(again.get("ok", true)), "only one try a day")
	var honest: int = int(C.adults()[1])
	w.get_folk(1)
	Story.townies[honest]["traits"] = ["honest"]
	CrimeLifeState.talk.clear()
	var r2: Dictionary = CrimeLifeContacts.ask_around(1, honest)
	K.expect(f, not bool(r2["ok"]) and not CrimeLifeContacts.has(1, honest), "an honest townie will not talk about it")
	CrimeLifePath.member(t)["snitch"] = true
	CrimeLifeContacts.drop(1, t)
	CrimeLifeState.talk.clear()
	K.expect(f, not bool(CrimeLifeContacts.ask_around(1, t)["ok"]), "nobody deals with a known snitch")
	K.teardown()

func _command(f: Array) -> void:
	var w := C.town(8)
	var r: Dictionary = Commands.run({"player_id": 1, "folk_id": 1, "action": "crimelife", "args": {"action": "join"}})
	K.expect(f, bool(r["ok"]) and CrimeLifePath.is_member(1), "the join arrives as a command")
	var bad: Dictionary = Commands.run({"player_id": 1, "folk_id": 999, "action": "crimelife", "args": {"action": "join"}})
	K.expect(f, not bool(bad["ok"]), "a command for someone else's folk is refused")
	var g: Dictionary = Commands.run({"player_id": 1, "folk_id": 1, "action": "crimelife", "args": {"action": "gear", "gear": "lockpicks"}})
	K.expect(f, bool(g["ok"]) and CrimeLifeRoll.has_gear(1, "lockpicks") and WorldIface.get_coins(1) < 1000, "kit is bought through the command layer")
	K.teardown()

func _drift(f: Array) -> void:
	var w := C.town(8)
	WorldIface.coins[1] = 0
	w.get_folk(1).traits.append("dishonest")
	JusticePlayer.auto = "join"
	var joined: bool = false
	for d in 120:
		CrimeLifeState.offered.erase(1)
		K.set_time(5 + d, 12)
		CrimeLifeFlow._offers()
		if CrimeLifePath.is_member(1):
			joined = true
			break
	JusticePlayer.auto = ""
	K.expect(f, joined and str(CrimeLifePath.member(1).get("why", "")) == "drift", "a desperate player folk is offered shady work and can drift in")
	K.teardown()

func _save(f: Array) -> void:
	var w := C.town(8)
	CrimeLifePath.join(1)
	CrimeLifePath.add_cred(1, 12.0)
	CrimeLifeContacts.add(1, int(C.adults()[0]), "driver", 0.5)
	CrimeLifeHeist.buy_gear(1, "gloves")
	CrimeLifeFence.add_stash(1, "burglary", 120, -1, false)
	CrimeLifeState.cased["1|biz:bank"] = {"amount": 0.4, "day": 3}
	CrimeLifeState.footage["home:1"] = [{"day": 2, "minute": 100, "case": 1, "clarity": 0.5, "gap": false}]
	var a: String = JSON.stringify(JusticeState.to_dict())
	var parsed: Variant = JSON.parse_string(a)
	JusticeState.from_dict(parsed as Dictionary)
	var b: String = JSON.stringify(JusticeState.to_dict())
	var diffs: Array = []
	K.deep_eq(JSON.parse_string(a), JSON.parse_string(b), "", diffs)
	K.expect(f, a == b or diffs.is_empty(), "the criminal-life state survives a JSON round trip unchanged: %s" % str(diffs.slice(0, 4)))
	K.expect(f, CrimeLifePath.is_member(1) and CrimeLifeContacts.has(1, int(C.adults()[0])) and CrimeLifeFence.stash_value(1) == 120, "and still works after loading")
	K.teardown()
