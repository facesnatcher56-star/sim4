class_name CaseEvidence
extends RefCounted
## What the police (and later the court) can know about a suspect. Two kinds of evidence:
##   HARD (only the real culprit leaves it): physical trace revealed by investigation work, an eyewitness who saw them, tips from new leads,
##   stolen goods recovered from them.
##   SOFT (anybody can have it): motive from relationships and grudges, no alibi from where the sim really had them, a criminal record,
##   bad reputation, gossip. Soft evidence is capped well below the arrest threshold, so an innocent person is arrested only when
##   motive, opportunity, record and gossip all line up (rare = a wrongful arrest).

static func cfg() -> Dictionary:
	return JusticeState.sect("evidence")

# ------------------------------------------------------------------ motive
## 0..1 how strongly `p` wanted to do this to the victim (or to rob this house).
static func motive(p: int, c: Dictionary) -> float:
	var v: int = int(c.get("victim", -1))
	var m: float = 0.0
	if v >= 0 and p != v:
		m += clampf(RelationshipRomance.tension(p, v) / 100.0, 0.0, 1.0) * 0.45
		m += RelationshipService.grudge(p, v) * 0.35
		var fr: float = RelationshipService.value(p, v, "friendship")
		if fr < -10.0:
			m += clampf(-fr / 100.0, 0.0, 0.3)
		for ev in RelationshipService.history_for(p, v):
			if str(ev.get("kind", "")) == "cheated" and int(ev.get("by", -1)) == v:
				m += 0.25
		if CrimePerson.is_kin_or_partner(p, v) and CrimePerson.coins(p) < 150 and CrimePerson.coins(v) > 600:
			m += 0.2                                   # money motive: an heir who is short of coins
		if CrimePerson.has_trait(p, "jealous") and RelationshipService.value(p, v, "romance") > 20.0 and RelationshipRomance.tension(p, v) > 20.0:
			m += 0.1
	else:
		if CrimePerson.coins(p) < 120:
			m += 0.3
		if not CrimePerson.has_job(p) and CrimePerson.is_adult(p):
			m += 0.15
		if CrimePerson.has_record(p):
			m += 0.1
	return clampf(m, 0.0, 1.0)

# ------------------------------------------------------------------ alibi
## 0..0.9 how well `p` can show they were somewhere else when it happened.
static func alibi(p: int, c: Dictionary) -> float:
	var loc: String = CrimePlace.where_was(p, int(c["minute"]))
	if loc == "unknown":
		return 0.0
	var scene: String = str(c["scene"])
	if loc == scene or (scene == "street" and loc == "street"):
		return 0.0
	if loc == "work":
		return 0.9
	if loc == "away":
		return 0.8
	# elsewhere: stronger if someone else was there too
	var company: int = _company_at(p, loc, int(c["minute"]))
	var home_like: bool = loc.begins_with("home:") or loc.begins_with("town:")
	if loc == "street":
		return 0.1
	return 0.7 if company > 0 else (0.4 if home_like else 0.5)

## How many OTHER tracked people were at `loc` at `minute`. Inside a suspects() scan the whole table is counted once (O(n) per case, not per suspect: a
## 200-person scan was 40,000 where_was calls, 100+ ms per open case); outside a scan it is counted directly.
static var _scan: Dictionary = {}          # loc -> people tracked there at _scan_minute
static var _scan_minute: int = -1
static var _scanning: bool = false
static var _scan_case: int = -1
static var _scan_gossip: Dictionary = {}   # person -> gossip items about them that count for the scanned case (one walk of the table, not one per suspect)

static func _company_at(p: int, loc: String, minute: int) -> int:
	if _scanning and minute == _scan_minute:
		return int(_scan.get(loc, 0)) - (1 if JusticeState.whereabouts.has(p) else 0)
	var company: int = 0
	for q in JusticeState.whereabouts:
		if int(q) != p and CrimePlace.where_was(int(q), minute) == loc:
			company += 1
	return company

static func _begin_scan(c: Dictionary) -> void:
	var minute: int = int(c["minute"])
	_scan_case = int(c["id"])
	_scan_gossip = {}
	for holder in RelationshipService.gossip_items:
		for it in RelationshipService.gossip_items[holder]:
			if _gossip_hit(it, c):
				var about: int = int(it.get("about", -1))
				_scan_gossip[about] = int(_scan_gossip.get(about, 0)) + 1
	_scan = {}
	for q in JusticeState.whereabouts:
		var l: String = CrimePlace.where_was(int(q), minute)
		_scan[l] = int(_scan.get(l, 0)) + 1
	_scan_minute = minute
	_scanning = true

static func _end_scan() -> void:
	_scanning = false
	_scan = {}
	_scan_gossip = {}
	_scan_case = -1

# ------------------------------------------------------------------ gossip and reputation
static func gossip(p: int, c: Dictionary) -> float:
	if _scanning and int(c["id"]) == _scan_case:
		return clampf(float(_scan_gossip.get(p, 0)) * 0.4, 0.0, 1.0)
	return clampf(float(_gossip_count(p, c)) * 0.4, 0.0, 1.0)

static func _gossip_hit(it: Dictionary, c: Dictionary) -> bool:
	return str(it.get("kind", "")) in ["murder_threat", "grudge", "crime_suspect"] and (int(it.get("sid", -1)) == int(c["id"]) or int(it.get("other", -1)) == int(c.get("victim", -2)) or int(it.get("sid", -1)) < 0)

static func _gossip_count(p: int, c: Dictionary) -> int:
	var n: int = 0
	for holder in RelationshipService.gossip_items:
		for it in RelationshipService.gossip_items[holder]:
			if int(it.get("about", -1)) == p and _gossip_hit(it, c):
				n += 1
	return n

# ------------------------------------------------------------------ scores
static func reveal(c: Dictionary) -> float:
	return clampf(float(c.get("progress", 0.0)), 0.0, 1.0)

## Evidence only the culprit can have. 0..~1.3
static func hard(p: int, c: Dictionary) -> float:
	if p != int(c["culprit"]):
		return 0.0
	var h: float = float(c.get("trace", 0.0)) * reveal(c)
	if bool(c.get("witnessed", false)):
		h += float(c.get("witness_clarity", 0.0)) * float(cfg().get("witness_weight", 0.7))
	h += float(c.get("tips", 0.0))
	if bool(c.get("recovered", false)):
		h += float(cfg().get("recovered_weight", 0.5))
	return h

## Evidence anybody can have, capped by data (default 0.5).
static func soft(p: int, c: Dictionary) -> float:
	if p == int(c.get("victim", -2)):
		return 0.0
	var e: Dictionary = cfg()
	var s: float = motive(p, c) * float(e.get("motive_weight", 0.3))
	s += (1.0 - alibi(p, c)) * float(e.get("opportunity_weight", 0.12))
	if CrimePerson.has_record(p):
		s += float(e.get("record_weight", 0.08))
	s += clampf(-CrimePerson.reputation(p) / 100.0, 0.0, 1.0) * float(e.get("reputation_weight", 0.06))
	s += gossip(p, c) * float(e.get("gossip_weight", 0.06))
	return minf(s, float(e.get("soft_cap", 0.52)))

## What the police think of this person for this case (used to pick who to arrest).
static func suspicion(p: int, c: Dictionary) -> float:
	return hard(p, c) + soft(p, c)

## What a court sees (before testimony): hard evidence plus a share of the soft evidence.
static func strength(p: int, c: Dictionary) -> float:
	return clampf(hard(p, c) + soft(p, c) * float(cfg().get("court_soft_share", 0.6)), 0.0, 1.3)

## Everyone worth looking at, best first: [{pid, score}] (top n).
static func suspects(c: Dictionary, n: int = 4) -> Array:
	var rows: Array = []
	_begin_scan(c)
	for p in CrimePerson.everyone():
		if p == int(c.get("victim", -2)) or not CrimePerson.is_adult(p) or CrimePerson.in_custody(p):
			continue
		var s: float = suspicion(p, c)
		if s > 0.05:
			rows.append({"pid": p, "score": s})
	_end_scan()
	rows.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]) or (float(a["score"]) == float(b["score"]) and int(a["pid"]) < int(b["pid"])))
	return rows.slice(0, n)
