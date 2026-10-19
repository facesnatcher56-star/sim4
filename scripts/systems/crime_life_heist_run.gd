class_name CrimeLifeHeistRun
extends RefCounted
## Task 21: carrying out a planned heist. Three phases, each a roll shaped by the crew's ROLES, the gear, the getaway car and how well the target was
## CASED: ENTRY (get in past locks, cameras, alarm and guards), VAULT (open what holds the money), ESCAPE (get away before the response arrives).
## The takings are split by the crew's cuts. A case is created like for any robbery (trace, witnesses, camera footage, alarm) and flows into discovery,
## arrest and trial; a crew member who is later arrested may snitch (CrimeLifeSnitch). Outcome words: getaway | partial | aborted | caught.

static func _best(h: Dictionary, effect: String) -> float:
	var roles: Dictionary = CrimeLifeHeist.cfg().get("roles", {})
	var best: float = 0.0
	var leader: int = int(h["leader"])
	for e in h["crew"]:
		var r: Dictionary = roles.get(str(e["role"]), {})
		if str(r.get("effect", "")) == effect:
			best = maxf(best, CrimeLifePath.skill_score(int(e["pid"]), r.get("skills", {})))
	if best <= 0.0:
		for rid in roles:
			if str(roles[rid].get("effect", "")) == effect:
				best = CrimeLifePath.skill_score(leader, roles[rid].get("skills", {})) * 0.6       # the leader does it alone, worse
	return best

## Chances of the three phases (also shown as words in the planning screen and compared by tests).
static func phases(h: Dictionary) -> Dictionary:
	var k: Dictionary = CrimeLifeHeist.cfg()
	var leader: int = int(h["leader"])
	var td: Dictionary = CrimeLifeHeist.target_def(str(h["target"]))
	var scene: String = str(h["scene"])
	var base_diff: float = float(CrimeLifeRoll.job("heist").get("difficulty", 0.3))
	var o: Dictionary = CrimeLifeRoll.odds(leader, "heist", scene, {"night": true, "diff_add": float(td.get("difficulty", 0.5)) - base_diff})
	var cased: float = float(o["cased"])
	var entry: float = clampf(float(o["pull_off"]) + 0.12 * _best(h, "alarm") + 0.08 * _best(h, "detect"), 0.05, 0.97)
	var noticed: float = clampf(float(o["detect"]) * (1.0 - 0.35 * _best(h, "detect")), 0.02, 0.97)
	var vault: float = clampf(0.4 + 0.5 * _best(h, "vault") + CrimeLifeRoll.gear_effect(leader, "vault") + float(k.get("cased_bonus", 0.3)) * 0.4 * cased - 0.1 * float(td.get("vault", 1)), 0.05, 0.95)
	var fit: float = clampf(float(CrimeLifePath.skill(leader, "fitness")) / 10.0, 0.0, 1.0)
	var escape: float = clampf(0.45 + 0.3 * _best(h, "escape") + (float(k.get("getaway_bonus", 0.12)) if bool(h["getaway"]) else 0.0) + 0.15 * _best(h, "guards") + 0.2 * fit \
		+ float(k.get("cased_bonus", 0.3)) * 0.4 * cased - float(td.get("heat", 8.0)) / 80.0, 0.05, 0.95)
	return {"entry": entry, "noticed": noticed, "vault": vault, "escape": escape, "odds": o}

static func run(h: Dictionary) -> Dictionary:
	var leader: int = int(h["leader"])
	var td: Dictionary = CrimeLifeHeist.target_def(str(h["target"]))
	var ph: Dictionary = phases(h)
	var o: Dictionary = ph["odds"]
	var scene: String = str(h["scene"])
	var jdef: Dictionary = CrimeLifeRoll.job("heist")
	var result: String = "getaway"
	var share: float = 1.0
	if not CrimeLifeState.chance(float(ph["entry"])):
		result = "aborted"
		share = 0.0
	elif not CrimeLifeState.chance(float(ph["vault"])):
		result = "partial"
		share = float(CrimeLifeHeist.cfg().get("partial_loot", 0.45))
	var caught: bool = false
	if result != "aborted" and not CrimeLifeState.chance(float(ph["escape"])):
		caught = true
		result = "caught"
	var base: int = CrimeLifeState.range_i(td.get("loot", [900, 2400]))
	var loot: int = 0 if caught else int(float(base) * share)           # caught on the way out: the takings are recovered
	var seen: bool = result != "aborted" and (caught or CrimeLifeState.chance(float(ph["noticed"])))
	h["result"] = result
	h["loot"] = loot
	h["stage"] = "failed" if result in ["aborted", "caught"] else "done"
	var victim: int = CrimeLifeJobs._shop_victim(str(h["target"]))
	var crew_ids: Array = (h["crew"] as Array).map(func(e): return int(e["pid"]))
	var c: Dictionary = {}
	if result != "aborted":
		c = CaseStore.create("robbery", leader, victim, "street", {"witnessed": seen, "witnesses": [victim] if seen and victim >= 0 else [], "witness_clarity": CrimeLifeState.rng.randf_range(0.35, 0.8) if seen else 0.0,
			"trace": float(o["trace"]), "stolen_coins": loot, "loot_value": base})
		c["heist"] = int(h["id"])
		c["crew"] = crew_ids
		c["charge_hint"] = "grand_theft"
		c["life_job"] = "heist"
		if not crew_ids.is_empty():
			c["also"] = ["conspiracy"]
		CrimePlace.place_at_scene(leader, "street")
		for cid in crew_ids:
			CrimePlace.place_at_scene(int(cid), "street")
		CrimeSecurityFootage.capture(c, scene, leader, CrimeLifeRoll.has_gear(leader, "disguise"), CrimeLifeRoll.has_gear(leader, "tools"))
		h["case"] = int(c["id"])
		if bool(o["profile"].get("alarm", false)):
			c["alarm_rang"] = true
		_pay_out(h, loot)
		CaseDiscovery.report(c, victim, "noticed")             # an emptied vault is noticed at once
		if bool(o["profile"].get("alarm", false)) and not caught:
			Police.respond(c, int(td.get("response_min", 8)) + 6)
	_record(h, jdef, result, seen)
	if caught and not c.is_empty():
		c["recovered"] = true
		JusticeProcess.arrest(c, leader)
	_announce(h, td, result, loot)
	SysUtil.game_event("heist_done", {"folk_id": leader, "result": result, "loot": loot})
	return {"result": result, "loot": loot, "case": int(c.get("id", -1)), "phases": {"entry": ph["entry"], "vault": ph["vault"], "escape": ph["escape"]}}

static func _pay_out(h: Dictionary, loot: int) -> void:
	var leader: int = int(h["leader"])
	var left: int = loot
	for e in h["crew"]:
		var cut: int = int(float(loot) * float(e["cut"]))
		left -= cut
		CrimePerson.add_coins(int(e["pid"]), cut, "heist cut")
		e["paid"] = cut
	CrimePerson.add_coins(leader, maxi(left, 0), "heist takings")
	h["leader_share"] = maxi(left, 0)

static func _record(h: Dictionary, jdef: Dictionary, result: String, seen: bool) -> void:
	var leader: int = int(h["leader"])
	var m: Dictionary = CrimeLifePath.member(leader)
	var td: Dictionary = CrimeLifeHeist.target_def(str(h["target"]))
	if not m.is_empty():
		m["jobs"] = int(m.get("jobs", 0)) + 1
		m["last_job_day"] = SysUtil.day()
		if result in ["getaway", "partial"]:
			m["heists"] = int(m.get("heists", 0)) + 1
		m["heat"] = float(m.get("heat", 0.0)) + float(td.get("heat", 8.0)) * (1.0 if seen else 0.6)
		CrimeLifePath.add_cred(leader, float(jdef.get("cred", 9.0)) * (1.0 if result == "getaway" else (0.5 if result == "partial" else 0.1)), "heist")
	CrimeLifePath.train(leader, "stealth", float(jdef.get("xp", 20)))
	CrimeLifePath.train(leader, "logic", 8.0)
	for e in h["crew"]:
		var q: int = int(e["pid"])
		var qm: Dictionary = CrimeLifePath.member(q)
		if not qm.is_empty():
			qm["jobs"] = int(qm.get("jobs", 0)) + 1
			qm["heat"] = float(qm.get("heat", 0.0)) + float(td.get("heat", 8.0)) * 0.5
			if result in ["getaway", "partial"]:
				qm["heists"] = int(qm.get("heists", 0)) + 1
				CrimeLifePath.add_cred(q, 3.0, "heist")
		CrimeLifeContacts.add_trust(leader, q, 0.15 if result in ["getaway", "partial"] else 0.02)
	CrimeLifeMoral.after_crime(leader, CrimeLifeJobs._shop_victim(str(h["target"])), "robbery", int(h.get("loot", 0)), CaseStore.get_case(int(h.get("case", -1))) if h.has("case") else {})
	var f = CrimePerson.folk(leader)
	if f != null and CrimePerson.is_player(leader):
		f.add_buff("on_the_run" if seen else "easy_money")

static func _announce(h: Dictionary, td: Dictionary, result: String, loot: int) -> void:
	var leader: int = int(h["leader"])
	var label: String = str(td.get("label", "the place"))
	var text: String
	match result:
		"getaway":
			text = "The job on %s went off without a hitch: %d coins." % [label, loot]
		"partial":
			text = "The vault would not give in time. The crew got away with only %d coins from %s." % [loot, label]
		"aborted":
			text = "The crew could not get past the defences at %s and pulled out empty-handed." % label
		_:
			text = "The job on %s went wrong. The police were waiting." % label
	if CrimePerson.is_player(leader):
		SysUtil.notify(text, "good" if result == "getaway" else ("warn" if result != "caught" else "bad"))
	if result in ["getaway", "partial", "caught"]:
		ChronicleHook.note("heist", "%s was raided." % label.capitalize(), [], "", 4, true)
