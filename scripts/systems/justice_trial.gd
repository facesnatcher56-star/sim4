class_name JusticeTrial
extends RefCounted
## The trial: a SCORED verdict, not a coin flip. z = k * (evidence + testimony + jury - doubt - defence); P(guilty) = logistic(z).
##   evidence   CaseEvidence.strength(accused): hard evidence only the culprit leaves + a share of motive/alibi/record
##   testimony  witnesses and folk who know the accused: friends defend, enemies accuse (relationships matter); player witnesses add their
##              own weight; a lie on the stand can be exposed (perjury)
##   defence    the lawyer's skill, the accused's charisma and reputation
##   jury       six townies: how they feel about the accused
## Outcomes: guilty / not_guilty / mistrial (a hung jury when it is very close: a new trial follows). Tuned so a guilty person with strong
## evidence is convicted ~85% of the time and an innocent one < 5% (see tests/justice_longrun_test.gd).

static func cfg() -> Dictionary:
	return JusticeState.sect("trial")

# ------------------------------------------------------------------ pieces of the score
static func testimony(c: Dictionary, pid: int) -> float:
	var k: Dictionary = cfg()
	var t: float = 0.0
	var seen: Array = (c["witnesses"] as Array).duplicate()
	if int(c["victim"]) >= 0 and CrimePerson.alive(int(c["victim"])) and not seen.has(int(c["victim"])):
		seen.append(int(c["victim"]))
	for w in seen:
		var rel: float = RelationshipService.value(int(w), pid, "friendship")
		var against: float = float(k.get("witness_against", 0.1)) if rel < 20.0 else -float(k.get("witness_for", 0.12)) * clampf(rel / 60.0, 0.2, 1.0)
		t += against
	for f in CrimePerson.friends(pid).slice(0, 3):          # friends and family speak for the accused
		t -= float(k.get("friend_for", 0.04))
	for e in (c.get("testimony", []) as Array):
		var sign: float = 1.0 if str(e["side"]) == "against" else -1.0
		var w2: float = float(k.get("player_weight", 0.14))
		if bool(e.get("exposed", false)):
			w2 = -w2 * 0.5                                   # exposed liars sway the court the other way
		elif bool(e.get("lie", false)):
			w2 *= float(k.get("lie_weight", 1.4))
		t += sign * w2
	return clampf(t, -0.5, 0.5)

static func defence(c: Dictionary, pid: int) -> float:
	var k: Dictionary = cfg()
	var d: float = float(c.get("lawyer_skill", 0.3)) * float(k.get("lawyer_weight", 0.55))
	d += CrimePerson.charisma(pid) * float(k.get("charisma_weight", 0.08))
	d += clampf(CrimePerson.reputation(pid) / 100.0, -1.0, 1.0) * float(k.get("reputation_weight", 0.1))
	d -= minf(float(CrimePerson.record_count(pid)), 3.0) * float(k.get("record_penalty", 0.04))
	return d

static func jury(pid: int, c: Dictionary = {}) -> float:
	var total: float = 0.0
	var pool: Array = CrimePerson.everyone().filter(func(p): return p != pid and CrimePerson.is_adult(p) and not CrimePerson.in_custody(p))
	var seated: Array = (c.get("jurors", []) as Array).duplicate()          # the six who sat in the courtroom (CourtScene) are the ones who decide
	var n: int = seated.size() if not seated.is_empty() else mini(int(cfg().get("jurors", 6)), pool.size())
	for i in n:
		var j: int = int(seated[i]) if not seated.is_empty() else int(pool[JusticeState.rng.randi_range(0, pool.size() - 1)])
		pool.erase(j)
		var op: float = RelationshipService.value(j, pid, "friendship") / 100.0 + CrimePerson.reputation(pid) / 200.0
		total += op
	if n == 0:
		return 0.0
	return -(total / float(n)) * float(cfg().get("jury_weight", 0.25))     # a liked defendant lowers the guilt score

## The z-score and its pieces, for the case board and the tests.
static func breakdown(c: Dictionary, pid: int, with_jury: bool = true) -> Dictionary:
	var k: Dictionary = cfg()
	var e: float = CaseEvidence.strength(pid, c)
	var t: float = testimony(c, pid)
	var d: float = defence(c, pid)
	var j: float = jury(pid, c) if with_jury else 0.0
	var z: float = float(k.get("k", 9.0)) * (e + t + j - float(k.get("doubt", 0.58)) - (0.04 if bool(c.get("reviewed", false)) else 0.0) - d)
	return {"evidence": e, "testimony": t, "defence": d, "jury": j, "z": z, "p_guilty": 1.0 / (1.0 + exp(-z))}

# ------------------------------------------------------------------ the trial day
static func run(c: Dictionary) -> String:
	var pid: int = int(c["accused"])
	var k: Dictionary = cfg()
	if not CrimePerson.alive(pid) or str(c["state"]) in ["closed"]:
		return ""
	c["state"] = "trial"
	_perjury_check(c)
	var plea: bool = JusticeProcess.offer_plea(c)
	var bd: Dictionary = breakdown(c, pid)
	c["trial"] = {"day": SysUtil.day(), "p_guilty": snappedf(float(bd["p_guilty"]), 0.001), "evidence": snappedf(float(bd["evidence"]), 0.01),
		"testimony": snappedf(float(bd["testimony"]), 0.01), "defence": snappedf(float(bd["defence"]), 0.01), "jury": snappedf(float(bd["jury"]), 0.01)}
	var verdict: String
	if plea:
		verdict = "plea"
		c["plea"] = true
	elif absf(float(bd["z"])) < float(k.get("hung_z", 0.35)) and JusticeState.chance(float(k.get("hung_chance", 0.4))):
		verdict = "mistrial"
	else:
		verdict = "guilty" if JusticeState.rng.randf() < float(bd["p_guilty"]) else "not_guilty"
	c["verdict"] = verdict
	JusticeState.count("trials")
	JusticeState.count("verdict_" + verdict)
	if bool(c["wrongful"]):
		JusticeState.count("innocent_tried")
		if verdict in ["guilty", "plea"]:
			JusticeState.count("innocent_convicted")
	else:
		JusticeState.count("guilty_tried")
		if verdict in ["guilty", "plea"]:
			JusticeState.count("guilty_convicted")
	_announce(c, verdict)
	match verdict:
		"guilty", "plea":
			JusticeSentence.impose(c)
		"not_guilty":
			_acquit(c)
		"mistrial":
			_mistrial(c)
	return verdict

static func _announce(c: Dictionary, verdict: String) -> void:
	if verdict in ["guilty", "plea"]:
		return                                  # one notice with charge, victim and sentence: JusticeSentence.impose
	var pid: int = int(c["accused"])
	var text: String = CaseText.acquitted(c, pid) if verdict == "not_guilty" else CaseText.mistrial(c, pid)
	CaseStore.note(c, text, "verdict", 4 if verdict != "mistrial" else 3)
	if CaseStore.household_involved(c):
		SysUtil.notify(text, "story")
		if CrimePerson.is_player(pid):
			JusticePlayer.tell(pid, "The verdict", text)

static func _acquit(c: Dictionary) -> void:
	var pid: int = int(c["accused"])
	JusticeOrders.lift(c)
	var acq: Array = SysUtil.to_ints(c.get("acquitted", []))
	acq.append(pid)
	c["acquitted"] = acq
	JusticeState.inmates.erase(pid)
	JusticePlayer.release(CrimePerson.folk(pid))
	c["state"] = "closed" if bool(c["wrongful"]) else "cold"
	c["closed_day"] = SysUtil.day()
	if not bool(c["wrongful"]):
		# the real culprit walked free: the case stays open for new evidence
		CrimeRevenge.on_escaped(c)                  # the family saw the culprit walk free
		c["accused"] = -1
		c["state"] = "cold"
		c["progress"] = maxf(float(c["progress"]) - 0.3, 0.0)
		c["disc_day"] = SysUtil.day()
		CaseStore.note(c, "The case is open again: the police are still looking.")
	else:
		RelationshipKnowledge.add_reputation(pid, 4.0)
		# the innocent are free; the real culprit is still out there
		c["accused"] = -1
		c["wrongful"] = false
		c["state"] = "open"
		c["disc_day"] = SysUtil.day() - 1
		c["tips"] = minf(float(c["tips"]) + 0.1, 0.6)
	if bool(c.get("bail_paid", 0)):
		CrimePerson.add_coins(pid, int(c["bail"]), "bail returned")

static func _mistrial(c: Dictionary) -> void:
	var tday: int = SysUtil.day() + JusticeState.rng.randi_range(5, 8)
	c["trial_day"] = tday
	c["state"] = "charged"
	JusticeState.queue({"kind": "trial", "case": int(c["id"]), "due_min": (tday - 1) * 1440 + 540})

## Lies on the stand can be exposed: a fine, a record and a reputation hit for the witness.
static func _perjury_check(c: Dictionary) -> void:
	for e in (c.get("testimony", []) as Array):
		if bool(e.get("lie", false)) and not bool(e.get("exposed", false)):
			var p: float = float(cfg().get("perjury_chance", 0.3))
			var truth_against: bool = int(c["accused"]) == int(c["culprit"])
			if (str(e["side"]) == "for" and not truth_against) or (str(e["side"]) == "against" and truth_against):
				p *= 0.25                      # a lie that happens to match the truth is hard to expose
			if JusticeState.chance(p):
				e["exposed"] = true
				var w: int = int(e["pid"])
				CrimePerson.pay(w, int(cfg().get("perjury_fine", 150)), "perjury")
				RelationshipKnowledge.add_reputation(w, -10.0)
				var recs: Array = JusticeState.records.get(w, [])
				recs.append({"day": SysUtil.day(), "charge": "perjury", "case": int(c["id"]), "result": "guilty"})
				JusticeState.records[w] = recs
				var text: String = "%s was caught lying on the stand." % CrimePerson.name_of(w)
				CaseStore.note(c, text, "perjury", 3)
				if CrimePerson.is_player(w):
					SysUtil.notify(text + " A fine and a record for perjury.", "bad")