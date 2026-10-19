class_name CrimeLifeMoral
extends RefCounted
## Task 21: the moral weight of a criminal life. Victims are real townies: every crime is written in a LEDGER (who lost what), victims who live in
## the player's home feel violated, a conscience troubles the honest, relatives may FIND OUT (a secret that spreads as gossip and costs friendship),
## and the legacy score has a NOTORIETY side that survives the criminal (Aging.legacy_summary).

static func cfg() -> Dictionary:
	return CrimeLifeState.sect("moral")

static func after_crime(culprit: int, victim: int, kind: String, loss: int, c: Dictionary) -> void:
	var cap: int = int(CrimeLifeState.sect("general").get("ledger_cap", 40))
	var rows: Array = CrimeLifeState.ledger.get(culprit, [])
	rows.append({"victim": victim, "day": SysUtil.day(), "kind": kind, "loss": loss, "case": int(c.get("id", -1))})
	while rows.size() > cap:
		rows.pop_front()
	CrimeLifeState.ledger[culprit] = rows
	var vf = CrimePerson.folk(victim) if victim >= 0 else null
	if vf != null and CrimePerson.is_player(victim) and loss > 0:
		vf.add_buff(str(cfg().get("ledger_victim_buff", "violated")))
	var cf = CrimePerson.folk(culprit)
	if cf != null and (CrimePerson.has_trait(culprit, "honest") or CrimePerson.has_trait(culprit, "generous")):
		cf.add_buff("troubled_conscience")

static func ledger_of(pid: int) -> Array:
	return CrimeLifeState.ledger.get(pid, [])

## Total loss caused and number of different victims.
static func totals(pid: int) -> Dictionary:
	var loss: int = 0
	var seen: Dictionary = {}
	for r in ledger_of(pid):
		loss += int(r.get("loss", 0))
		seen[int(r.get("victim", -1))] = true
	return {"loss": loss, "victims": seen.size(), "crimes": ledger_of(pid).size()}

## One plain line for the ledger view.
static func line(r: Dictionary) -> String:
	var v: int = int(r.get("victim", -1))
	return "Day %d: %s lost %d coins (%s)." % [int(r.get("day", 0)), CrimePerson.name_of(v) if v >= 0 else "A shopkeeper", int(r.get("loss", 0)), CaseStore.kind_label(str(r.get("kind", "theft")))]

# ------------------------------------------------------------------ family finds out
## Daily, for each member: someone close may learn what they do. Returns the number of discoveries (tests).
static func on_day() -> int:
	var n: int = 0
	for pid in CrimeLifeState.members.keys():
		var m: Dictionary = CrimeLifeState.members[pid]
		if int(m.get("jobs", 0)) <= 0 or bool(m.get("found_out", false)):
			continue
		var p: float = float(cfg().get("find_out_daily", 0.01)) * (1.0 + float(m.get("heat", 0.0)) * 0.1 + float(m.get("caught", 0)) * 0.5)
		if CrimeLifeState.chance(p):
			var kin: Array = CrimePerson.close_alive(int(pid))
			if kin.is_empty():
				continue
			n += 1
			find_out(int(pid), int(kin[CrimeLifeState.rng.randi_range(0, kin.size() - 1)]))
			m["found_out"] = true
	return n

static func find_out(culprit: int, kin: int) -> void:
	var k: Dictionary = cfg()
	RelationshipService.add_both(kin, culprit, "friendship", float(k.get("family_friendship", -18)))
	RelationshipKnowledge.add_gossip(kin, culprit, "%s is mixed up in something criminal." % CrimePerson.name_of(culprit), "crime_suspect", -1, culprit)
	var cf = CrimePerson.folk(kin)
	if cf != null:
		cf.add_buff("troubled_conscience")
	if CrimePerson.is_player(culprit) or CrimePerson.is_player(kin):
		SysUtil.notify("%s found out what %s has been up to, and is deeply troubled." % [CrimePerson.name_of(kin), CrimePerson.name_of(culprit)], "warn")
	CrimeLifeState.count("found_out")
	SysUtil.game_event("crime_life_found_out", {"folk_id": culprit, "kin": kin})

# ------------------------------------------------------------------ notoriety (legacy score)
## 0..100 how infamous: street name earned plus convictions. Survives going straight.
static func notoriety(pid: int) -> int:
	var m: Dictionary = CrimeLifePath.member(pid)
	var base: float = float(m.get("notoriety", 0.0))
	base = maxf(base, float(CrimeLifeState.notoriety_kept.get(pid, 0.0)))
	return clampi(int(base + float(JusticeRecords.convictions(pid).size()) * float(cfg().get("notoriety_conviction", 6))), 0, 100)

static func legacy_line(pid: int) -> String:
	var n: int = notoriety(pid)
	if n < 10:
		return ""
	var rank: String = CrimeLifePath.rank_label(pid)
	var tail: String = "was known in the underworld%s" % ((" as a " + rank.to_lower()) if rank != "" else "")
	return "%s%s." % [tail, ", and the town never forgot it" if n >= 50 else ""]
