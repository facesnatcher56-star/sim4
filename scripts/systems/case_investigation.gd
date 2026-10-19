class_name CaseInvestigation
extends RefCounted
## The daily detective work on every open case (09b section 2). Work (`progress`) reveals the physical trace; connections (grudges, alibis from
## where folk really were, record, reputation, gossip) are looked at through CaseEvidence. The best suspect over the arrest threshold is
## arrested (usually the real culprit, rarely somebody else = a wrongful arrest). Cases with weak evidence go cold but the police keep
## checking: a new tip (or a gossip) can reopen them. Works for every case in town, statistical or not (it is all records).

static func cfg() -> Dictionary:
	return JusticeState.sect("investigation")

static func on_day() -> void:
	for c in CaseStore.in_state(["open", "cold"]):
		work(c)

## One day of work on a case. Returns the arrested person id or -1. Public so the tests can step cases.
static func work(c: Dictionary) -> int:
	if bool(c.get("ship_hold", false)):
		return -1                          # task 22: a case held by a ship at sea (the ship's security works it, CruiseCrime)
	var k: Dictionary = cfg()
	var cold: bool = str(c["state"]) == "cold"
	var found: bool = bool(c.get("found", true))
	var power: float = Police.strength() * (float(k.get("cold_power", 0.15)) if cold else 1.0)
	if not found:
		power *= float(k.get("missing_power", 0.25))
	if bool(c.get("assist", false)):
		power += float(k.get("detective_assist", 0.4))       # a player or townie detective is on the case
		c["assist"] = false
	c["progress"] = minf(float(c["progress"]) + power * JusticeState.rng.randf_range(float(k.get("work_min", 0.09)), float(k.get("work_max", 0.17))), 1.0)
	# tips: a witness remembers something, a pawnshop turns up an item, gossip points somewhere
	var tip_p: float = float(k.get("tip_per_day", 0.05)) * (1.0 + float(Police.strength())) * (0.08 if int(c.get("serial", -1)) >= 0 else 1.0)
	if found and JusticeState.chance(tip_p):
		var culprit_free: bool = int(c["culprit"]) >= 0 and CrimePerson.alive(int(c["culprit"])) and not CrimePerson.in_custody(int(c["culprit"]))
		if culprit_free:
			c["tips"] = minf(float(c["tips"]) + JusticeState.rng.randf_range(0.1, 0.25), 0.6)
			if cold:
				reopen(c, "A new tip came in.")
	if cold:
		return -1
	var age: int = SysUtil.day() - int(c["disc_day"])
	var rows: Array = CaseEvidence.suspects(c, 3)
	c["suspect_ids"] = rows.map(func(r): return int(r["pid"]))
	if not found:
		return -1
	if not rows.is_empty() and age >= int(k.get("min_days", 1)):
		var top: Dictionary = rows[0]
		var thr: float = float(k.get("arrest_threshold", 0.62))
		var score: float = float(top["score"]) + JusticeState.rng.randf_range(0.0, float(k.get("noise", 0.05)))
		if score >= thr and not SysUtil.to_ints(c.get("acquitted", [])).has(int(top["pid"])):      # no second trial for the same case
			JusticeProcess.arrest(c, int(top["pid"]))
			return int(top["pid"])
	if age >= int(k.get("cold_after_days", 30)):
		c["state"] = "cold"
		if not bool(c.get("cold_noted", false)):                 # said once; a case that is reopened and cools again stays quiet
			c["cold_noted"] = true
			var big: bool = str(c["kind"]) in ["murder", "serial", "manslaughter"] or CaseStore.household_involved(c)
			CaseStore.note(c, "The case has gone cold. The police are still checking new leads.", "cold_case" if big else "", 3 if big else 1)
	return -1

static func reopen(c: Dictionary, why: String) -> void:
	if str(c["state"]) in ["cold", "closed"]:
		c["state"] = "open"
		c["reopened"] = int(c["reopened"]) + 1
		c["disc_day"] = SysUtil.day() - 2
		CaseStore.note(c, "%s The case was reopened." % why, "case_reopened" if CaseStore.household_involved(c) else "", 3)
		if CaseStore.household_involved(c):                       # notify policy: only cases that touch the household
			SysUtil.notify("The police reopened the case: %s" % CaseStore.title(c), "warn")

## Gossip and rumours feed the investigation: somebody is whispering about a person with a grudge.
static func feed_gossip(c: Dictionary) -> void:
	var v: int = int(c.get("victim", -1))
	if v < 0:
		return
	for p in CrimePerson.everyone():
		if p != v and RelationshipService.grudge(p, v) > 0.5:
			for holder in CrimePerson.friends(v).slice(0, 2):
				RelationshipKnowledge.add_gossip(int(holder), p, "%s had been on bad terms with %s." % [CrimePerson.name_of(p), CrimePerson.name_of(v)], "crime_suspect", int(c["id"]), v)

## A detective (player or townie) works the case today.
static func assist(case_id: int) -> void:
	var c: Dictionary = CaseStore.get_case(case_id)
	if not c.is_empty():
		c["assist"] = true