extends RefCounted
## Task 22 review fixes (the owner's cruise report): distinct crew names; job offers and jobs only for adults (teens in part-time careers), never
## for crew; a charged killer is held and never turns up as a visitor / guest / crowd NPC and the case reaches trial; names in the justice text
## (crew victim, capitalised); one death toast; no "Boarding opened" after boarding; relationship news only when it concerns the household; an
## unseen shipboard affair becomes a secret.

const K = preload("res://tests/vacation_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	_names_and_jobs()
	_rel_notify()
	_arrested_killer()
	_affair()
	K.teardown()
	return fails

func _board(seed_value: int, days: int = 5) -> Dictionary:
	K.new_game("small", 9000, false, seed_value)
	var res: Dictionary = Vacation.book_and_go(1, "cruise", {"length_days": days, "cabin_class": "inside", "seed": seed_value})
	K.run(40)
	return Vacation.trip(int(res["trip"]))

func _names_and_jobs() -> void:
	var t: Dictionary = _board(5, 3)
	var seen: Dictionary = {}
	var crew: Array = CruiseCrew.crew(t)
	_check(crew.size() >= 8, "crew aboard (%d)" % crew.size())
	for c in crew:
		var first: String = str(c.name).split(" ")[0]
		_check(not seen.has(first) or str(c.name).begins_with("Captain"), "crew first names differ: %s twice" % first)
		_check(not str(c.name).begins_with("Sam Reed"), "no Sam Reed (%s)" % c.name)
		seen[first] = true
		_check(Careers.make_offer(c).is_empty() and not Careers.hire(c, "cook", 1), "%s: crew get no job offers and cannot be hired" % c.name)
	# stage gating
	var kid := Folk.create("Pip", [])
	kid.household_id = 1
	kid.age_stage = "child"
	WorldIface.world().add_folk(kid, Vector2i(5, 5))
	_check(Careers.make_offer(kid).is_empty() and not Careers.hire(kid, "cook", 1), "a child gets no offer and cannot take the Dishwasher job")
	Careers.offers[int(kid.id)] = {"career": "cook", "level": 1, "expires_day": 99}
	_check(not Careers.accept_offer(int(kid.id)) and not Careers.jobs.has(int(kid.id)), "a stale offer cannot be accepted by a child")
	var teen := Folk.create("Rex", [])
	teen.household_id = 1
	teen.age_stage = "teen"
	WorldIface.world().add_folk(teen, Vector2i(6, 5))
	_check(not Careers.hire(teen, "scientist", 1) and Careers.hire(teen, "barista", 1), "a teen: part-time careers only")
	var adult: Folk = VacationCost.household_folk(1)[0]
	_check(Careers.hire(adult, "cook", 1), "an adult can work")
	K.teardown()

func _rel_notify() -> void:
	K.new_game("small")
	K.Kit.notes.clear()
	RelNotify.say([9001, 9002], "Stranger A and Stranger B made up.", "relationship")
	_check(K.Kit.notes.is_empty(), "news between strangers stays out of the feed")
	var mira: Folk = VacationCost.household_folk(1)[0]
	RelNotify.say([int(mira.id), 9002], "Mira and Stranger B made up.", "relationship")
	_check(K.Kit.notes.size() == 1, "news about the household is shown")
	K.teardown()

## Returns true when the killer was arrested at a port (some seeds end otherwise: try a few).
func _arrested_killer() -> void:
	var done := false
	for seed_value in [8, 31, 12, 44, 3, 77]:
		if done:
			break
		var t: Dictionary = _board(seed_value, 5)
		var sail1: int = 0
		for e in t["cruise"]["timeline"]:
			if str(e["kind"]) == "sail" and int(e["day"]) == 1:
				sail1 = int(e["min"])
		K.warp(sail1 - K.now() + 40)
		K.Kit.notes.clear()
		Incidents.force("serial_killer_aboard", {"ship": int(t["id"]), "delay_hours": 3, "spare_party": true})
		var k: Dictionary = t["cruise"]["killer"]
		var guard: int = 0
		while guard < 140 and str(k.get("phase", "")) in ["hunting", "detained"] and str(t.get("state", "")) == "there":
			K.warp(60)
			guard += 1
		if str(k.get("phase", "")) != "caught":
			K.teardown()
			continue
		done = true
		var killer: int = int(k["pid"])
		_check(JusticeState.inmates.has(killer), "the arrested killer is held (%s)" % str(JusticeState.inmates.get(killer, {})))
		_check(Story.free_townies().all(func(x): return int(x["id"]) != killer), "a held suspect is not among the free townies")
		var main: Dictionary = {}
		for cid in k["cases"]:
			if int(CaseStore.get_case(int(cid)).get("accused", -1)) == killer:
				main = CaseStore.get_case(int(cid))
		_check(not main.is_empty() and str(main["state"]) in ["charged", "arrested", "trial"], "charged, trial pending (%s)" % str(main.get("state", "?")))
		# names in the text: never "Someone", names capitalised
		for e2 in VacationLog.entries():
			var txt: String = str(e2["text"])
			_check(not txt.contains("death of someone") and not txt.contains("Someone"), "no 'someone' in: %s" % txt)
			var rx := RegEx.create_from_string("death of [a-z]")
			_check(rx.search(txt) == null, "names are capitalised: %s" % txt)
		# one death toast per victim
		for v in k["victims"]:
			var nm: String = CrimePerson.name_of(int(v))
			var n_death := 0
			for nt in K.Kit.notes:
				if str(nt[1]) == "death" and str(nt[0]).contains(nm):
					n_death += 1
			_check(n_death <= 1, "%s: the death is announced once (%d)" % [nm, n_death])
		# the rest of the cruise, then days at home: the killer never visits, is never a crowd NPC, and the trial happens
		K.warp(int(t["return_min"]) - K.now() + 120)
		var verdict_by: int = SysUtil.day() + 9
		var visited := false
		while SysUtil.day() < verdict_by:
			K.warp(180)
			if SysUtil.hour_f() < 3.0:
				StoryVisits._visits_and_invites(SysUtil.day())
			for sit in Story.situations:
				if (sit["guest_ids"] as Array).has(killer) and str(sit["state"]) in ["arrive", "mingle", "scheduled"] and JusticeState.inmates.has(killer):
					visited = true
			if SysUtil.folk(killer) != null and JusticeState.inmates.has(killer):
				visited = true
			if str(main["state"]) in ["closed"] or str(main.get("verdict", "")) != "":
				break
		_check(not visited, "the held killer never turned up as a visitor, guest or crowd NPC")
		_check(str(main.get("verdict", "")) != "" or str(main["state"]) in ["trial", "closed"], "the case reached trial within days (%s / %s)" % [str(main["state"]), str(main.get("verdict", ""))])
		K.teardown()
	_check(done, "at least one seed ends with the killer arrested at a port")

func _affair() -> void:
	var t: Dictionary = _board(6, 3)
	var pax: Array = CruiseCrew.passengers(t)
	_check(pax.size() >= 2, "passengers")
	var a = pax[0]
	var b = pax[1]
	var spouse: int = -1
	for tid in Story.townies:
		if int(tid) != int(a.id) and int(tid) != int(b.id) and SysUtil.folk(int(tid)) == null and RomanceRules.allowed(int(a.id), int(tid)):
			spouse = int(tid)
			break
	RelationshipBits.set_flag(int(a.id), spouse, "partner", true, false)
	CruiseLife._affair(t, a, b, Vacation.rng_for(t))
	var secrets: Array = RelationshipKnowledge.ensure_secrets(int(a.id))
	var found := false
	for s in secrets:
		if str(s["kind"]) == "affair":
			found = true
	_check(found and (t["cruise"].get("affairs", []) as Array).size() == 1, "the unseen fling is a secret of the married passenger")
	var p_before: Array = RelationshipKnowledge.secrets_known_by(spouse)
	for _i in 12:
		t["cruise"]["affairs"] = [{"owner": int(a.id), "other": int(b.id), "sid": int(secrets[secrets.size() - 1]["id"])}]
		CruiseLife.surface_secrets(t)
	_check(RelationshipKnowledge.secrets_known_by(spouse).size() > p_before.size(), "it can surface: the partner learns it")
	K.teardown()
