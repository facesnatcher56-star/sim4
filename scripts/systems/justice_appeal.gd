class_name JusticeAppeal
extends RefCounted
## Appeals, exonerations and pardons. Every day a convicted person may get new evidence: an innocent one far more often than a guilty one.
## A successful appeal for an innocent person is an EXONERATION (freed, compensated, in the news). Model prisoners are rarely pardoned.
## A player can also file an appeal for a convicted folk (Case board): costs coins, lowers a sentence or, if they are innocent, overturns it.

static func cfg() -> Dictionary:
	return JusticeState.sect("appeal")

static func on_day() -> void:
	var k: Dictionary = cfg()
	for c in CaseStore.in_state(["closed"]):
		var pid: int = int(c.get("accused", -1))
		if pid < 0 or str(c["verdict"]) not in ["guilty", "plea"] or bool(c.get("overturned", false)):
			continue
		var s: Dictionary = c.get("sentence", {})
		if str(s.get("type", "")) not in ["jail", "prison"] or not JusticeState.inmates.has(pid):
			continue
		var p: float = float(k.get("new_evidence_innocent", 0.012)) if bool(c["wrongful"]) else float(k.get("new_evidence_guilty", 0.0008))
		if JusticeState.chance(p):
			resolve(c, true)
			continue
		var ins: Dictionary = JusticeState.inmates[pid]
		if float(ins.get("behaviour", 0)) >= float(k.get("pardon_behaviour", 90)) and JusticeState.chance(float(k.get("pardon_chance", 0.002))):
			pardon(c)

## Appeal outcome. `new_evidence` = true when the appeal rests on something new (it does when started by the daily roll).
static func resolve(c: Dictionary, new_evidence: bool) -> String:
	var pid: int = int(c["accused"])
	var k: Dictionary = cfg()
	if bool(c["wrongful"]) and (new_evidence or JusticeState.chance(float(k.get("player_overturn", 0.5)))):
		c["overturned"] = true
		JusticeState.inmates.erase(pid)
		JusticePlayer.release(CrimePerson.folk(pid))
		if Story.townies.has(pid):
			Story.townies[pid].erase("in_prison")
		JusticeState.count("exonerations")
		CrimePerson.add_coins(pid, int(k.get("compensation", 300)), "compensation")
		RelationshipKnowledge.add_reputation(pid, 12.0)
		var recs: Array = JusticeState.records.get(pid, [])
		for r in recs.duplicate():
			if int(r.get("case", -1)) == int(c["id"]):
				recs.erase(r)
		JusticeState.records[pid] = recs
		var text: String = "%s was cleared of %s. The court admitted it had the wrong person." % [CrimePerson.name_of(pid), CaseText.neutral(c)]
		CaseStore.note(c, text, "exonerated", 4)
		if CrimePerson.is_player(pid) or CaseStore.household_involved(c):
			SysUtil.notify(text, "good")
		# the real culprit is still out there
		c["accused"] = -1
		c["wrongful"] = false
		c["state"] = "open"
		c["disc_day"] = SysUtil.day() - 1
		c["tips"] = minf(float(c["tips"]) + 0.15, 0.6)
		return "exonerated"
	if not bool(c["wrongful"]) and JusticeState.chance(float(k.get("sentence_cut", 0.25))) and JusticeState.inmates.has(pid):
		var ins: Dictionary = JusticeState.inmates[pid]
		if int(ins["until"]) < 100000:
			ins["until"] = SysUtil.day() + maxi(int((int(ins["until"]) - SysUtil.day()) * 0.7), 1)
		c["overturned"] = true
		CaseStore.note(c, "%s's sentence was shortened on appeal." % CrimePerson.name_of(pid))
		return "reduced"
	c["overturned"] = true          # one appeal per case
	CaseStore.note(c, "The appeal of %s was rejected." % CrimePerson.name_of(pid))
	return "rejected"

## The player files an appeal for a convicted folk (costs coins).
static func file(case_id: int) -> String:
	var c: Dictionary = CaseStore.get_case(case_id)
	if c.is_empty() or bool(c.get("overturned", false)) or int(c.get("accused", -1)) < 0:
		return "none"
	var pid: int = int(c["accused"])
	var fee: int = int(cfg().get("fee", 200))
	if CrimePerson.is_player(pid) and not Economy.spend(CrimePerson.hid(pid), fee, "appeal"):
		return "poor"
	return resolve(c, false)

static func pardon(c: Dictionary) -> void:
	var pid: int = int(c["accused"])
	JusticeState.inmates.erase(pid)
	JusticePlayer.release(CrimePerson.folk(pid))
	c["overturned"] = true
	JusticeState.count("pardons")
	var text: String = "%s was pardoned after years of exemplary behaviour." % CrimePerson.name_of(pid)
	CaseStore.note(c, text, "pardon", 3)
	if CrimePerson.is_player(pid):
		SysUtil.notify(text, "good")