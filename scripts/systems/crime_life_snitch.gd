class_name CrimeLifeSnitch
extends RefCounted
## Task 21: loyalty, plea deals and rats. When a crew leader is charged, every crew member the case names may SNITCH for a plea deal (their loyalty,
## their cut and their own record decide); a snitch costs the leader a heavier case but ruins the snitch's name in the underworld (nobody deals with
## them, cred drops). The charged PLAYER is offered a deal to name the crew (lighter sentence, the crew is arrested and hates them) or to stay quiet
## (street respect, loyal crew). RIVALS in the underworld can also tip the police off about a thriving criminal, one anonymous tip at a time.

static func cfg() -> Dictionary:
	return CrimeLifeState.sect("snitch")

## Hook: JusticeProcess.file_charges calls this once a case is charged (not for petty charges).
static func on_charged(c: Dictionary) -> void:
	var pid: int = int(c.get("accused", -1))
	if pid < 0:
		return
	if int(c.get("rat_by", -1)) >= 0 and CrimePerson.is_player(pid):
		SysUtil.notify("Word is that a rival tipped the police off about %s." % CrimePerson.name_of(pid), "warn")
	var crew: Array = SysUtil.to_ints(c.get("crew", []))
	if crew.is_empty() or pid != int(c.get("culprit", -1)):
		return
	for q in crew:
		if CrimePerson.alive(q) and not CrimePerson.in_custody(q) and int(c.get("snitched_by", -1)) < 0 and CrimeLifeState.chance(snitch_chance(q, c)):
			snitch(c, q)
			break                                    # one is enough to break the case open
	if CrimePerson.is_player(pid):
		JusticePlayer.ask(pid, "The detectives' offer", "The police know there were others. Name your crew and %s gets a lighter sentence, but the crew will be picked up and word will get round. Keep quiet and %s keeps respect." % [CrimePerson.name_of(pid), CrimePerson.name_of(pid)],
			[{"id": "name", "label": "Name the crew"}, {"id": "silent", "label": "Say nothing"}], func(ch): decide(c, pid, str(ch)), "silent")
	else:
		var avg: float = 0.0
		for e in _crew_entries(c):
			avg += float(e.get("loyal", 0.5))
		avg /= maxf(float(crew.size()), 1.0)
		decide(c, pid, "name" if CrimeLifeState.chance(clampf(0.3 - avg * 0.25 + (0.2 if CrimePerson.has_record(pid) else 0.0), 0.02, 0.8)) else "silent")

static func _crew_entries(c: Dictionary) -> Array:
	var h: Dictionary = CrimeLifeHeist.get_heist(int(c.get("heist", -1)))
	return h.get("crew", [])

## How likely crew member `q` is to talk about the leader of case `c`.
static func snitch_chance(q: int, c: Dictionary) -> float:
	var k: Dictionary = cfg()
	var loyal: float = 0.5
	var cut: float = 0.15
	for e in _crew_entries(c):
		if int(e["pid"]) == q:
			loyal = float(e["loyal"])
			cut = float(e["cut"])
	var p: float = float(k.get("base", 0.38)) - loyal * float(k.get("loyalty", 0.55)) + (float(k.get("cut_short", 0.2)) if cut < 0.1 else 0.0) \
		+ (float(k.get("record", 0.1)) if CrimePerson.has_record(q) else 0.0)
	if CrimePerson.has_trait(q, "honest"):
		p += 0.1
	return clampf(p, 0.02, 0.9)

## `q` talks. Returns true.
static func snitch(c: Dictionary, q: int) -> bool:
	var k: Dictionary = cfg()
	c["snitched_by"] = q
	c["tips"] = minf(float(c.get("tips", 0.0)) + float(k.get("rat_tip", 0.3)) + 0.2, 0.6)
	var qm: Dictionary = CrimeLifePath.member(q)
	if not qm.is_empty():
		qm["snitch"] = true
		CrimeLifePath.add_cred(q, float(k.get("deal_cred", -30)))
	CaseStore.note(c, "A member of the crew talked to the police.")
	if CrimePerson.is_player(int(c.get("accused", -1))):
		SysUtil.notify("%s has talked to the police." % CrimePerson.name_of(q), "bad")
	var leader: int = int(c.get("accused", -1))
	CrimeLifeContacts.drop(leader, q)
	CrimeLifeState.count("snitches")
	SysUtil.game_event("crew_snitched", {"folk_id": leader, "snitch": q, "case": int(c["id"])})
	return true

## The accused names the crew ("name") or stays quiet ("silent").
static func decide(c: Dictionary, leader: int, choice: String) -> void:
	var k: Dictionary = cfg()
	var lm: Dictionary = CrimeLifePath.member(leader)
	if choice == "name":
		c["deal"] = true
		for q in SysUtil.to_ints(c.get("crew", [])):
			if CrimePerson.alive(q) and not CrimePerson.in_custody(q):
				_crew_case(c, q)
		if not lm.is_empty():
			lm["snitch"] = true
			lm["cred"] = maxf(float(lm["cred"]) + float(k.get("deal_cred", -30)), 0.0)
			CrimeLifePath.update_rank(leader)
		CaseStore.note(c, "%s named the others for a lighter sentence." % CrimePerson.name_of(leader))
		CrimeLifeState.count("deals")
	else:
		if not lm.is_empty():
			CrimeLifePath.add_cred(leader, float(CrimeLifeState.sect("path").get("cred_caught_quiet", 4)))
		for e in _crew_entries(c):
			e["loyal"] = minf(float(e["loyal"]) + float(k.get("refuse_loyalty", 0.1)), 1.0)
		CrimeLifeState.count("stood_up")

## A linked case against a named crew member (same crime, their own arrest and charges).
static func _crew_case(c: Dictionary, q: int) -> void:
	var nc: Dictionary = CaseStore.create(str(c["kind"]), q, int(c.get("victim", -1)), str(c["scene"]), {"witnessed": false, "trace": float(c.get("trace", 0.2)), "stolen_coins": 0, "loot_value": int(c.get("loot_value", 0))})
	nc["charge_hint"] = str(c.get("charge_hint", ""))
	nc["life_job"] = "heist"
	nc["named_in"] = int(c["id"])
	nc["state"] = "open"
	nc["disc_day"] = SysUtil.day()
	nc["tips"] = 0.6
	JusticeProcess.arrest(nc, q)

# ------------------------------------------------------------------ rivals
## Daily: a rival may put the police onto a thriving criminal.
static func rival_tips() -> int:
	var k: Dictionary = cfg()
	var n: int = 0
	for c in CaseStore.in_state(["hidden", "open"]):
		var culprit: int = int(c["culprit"])
		if not CrimeLifePath.is_member(culprit) or int(c.get("rat_by", -1)) >= 0 or CrimeLifePath.cred(culprit) < 15.0:
			continue
		var rivals: Array = []
		for q in CrimeLifeState.members.keys():
			if int(q) != culprit and not SysUtil.to_ints(c.get("crew", [])).has(int(q)) and CrimePerson.alive(int(q)) and not CrimeLifeContacts.has(culprit, int(q)) \
					and absf(CrimeLifePath.cred(int(q)) - CrimeLifePath.cred(culprit)) <= float(k.get("rival_cred_gap", 25)):
				rivals.append(int(q))
		rivals.sort()
		for r in rivals:
			if CrimeLifeState.chance(float(k.get("rival_daily", 0.012))):
				c["rat_by"] = r
				c["tips"] = minf(float(c.get("tips", 0.0)) + float(k.get("rat_tip", 0.3)), 0.6)
				CaseStore.note(c, "An anonymous tip reached the police.")
				if str(c["state"]) == "hidden":
					CaseDiscovery.report(c, -1, "noticed")
				n += 1
				break
	return n
