class_name CrimeUnderLines
extends RefCounted
## Task 23, part 1: the underworld LINES (hired gun, dealer, racketeer). Hidden careers on top of the criminal path (CrimeLifePath member): a line has
## ranks from STANDING (earned by acts, lost by failures). Joined through a CONTACT, a RECORD or DESPERATION; nobody vouches for a stranger.
## Players and townies are the same record (CrimeUnderState.lines). Everything arrives from the command layer (CrimeUnderCmd) or the daily dice.

static func cfg() -> Dictionary:
	return CrimeUnderState.sect("lines")

static func def(line: String) -> Dictionary:
	return cfg().get(line, {})

static func ids() -> Array:
	var out: Array = []
	for k in cfg():
		if (cfg()[k] as Dictionary).has("ranks"):
			out.append(k)
	out.sort()
	return out

static func has(pid: int, line: String) -> bool:
	return (CrimeUnderState.lines.get(pid, {}) as Dictionary).has(line)

static func rec(pid: int, line: String) -> Dictionary:
	return (CrimeUnderState.lines.get(pid, {}) as Dictionary).get(line, {})

static func standing(pid: int, line: String) -> float:
	return float(rec(pid, line).get("standing", 0.0))

static func rank_index(pid: int, line: String) -> int:
	if not has(pid, line):
		return -1
	var best: int = 0
	var rs: Array = def(line).get("ranks", [])
	for i in rs.size():
		if standing(pid, line) >= float(rs[i].get("standing", 0)):
			best = i
	return best

static func rank_data(pid: int, line: String) -> Dictionary:
	var i: int = rank_index(pid, line)
	return (def(line).get("ranks", []) as Array)[i] if i >= 0 else {}

static func rank_label(pid: int, line: String) -> String:
	return str(rank_data(pid, line).get("label", ""))

## Why the person cannot join (empty = fine) and how they would get in.
static func entry(pid: int, line: String) -> Dictionary:
	var d: Dictionary = def(line)
	var via: Dictionary = cfg().get("via", {})
	if d.is_empty() or not CrimePerson.alive(pid) or not CrimePerson.is_adult(pid) or CrimePerson.in_custody(pid):
		return {"ok": false, "msg": "Not right now."}
	if has(pid, line):
		return {"ok": false, "msg": "Already in."}
	if CrimeLifePath.cred(pid) < float(d.get("min_cred", 10)):
		return {"ok": false, "msg": "Nobody in the underworld knows %s well enough yet." % CrimePerson.name_of(pid)}
	if CrimeUnderState.protected.get(pid, -1) >= SysUtil.day():
		return {"ok": false, "msg": "That door is shut to someone in protection."}
	var how: String = ""
	if not CrimeLifeContacts.list(pid).is_empty():
		how = "contact"
	elif CrimePerson.record_count(pid) >= int(via.get("record_convictions", 1)):
		how = "record"
	elif CrimePressure.risk(pid) >= float(via.get("desperate_risk", 0.5)):
		how = "desperate"
	if how == "":
		return {"ok": false, "msg": "Nobody will vouch for %s: no contacts, no record, and not desperate enough." % CrimePerson.name_of(pid)}
	return {"ok": true, "via": how}

static func join(pid: int, line: String) -> Dictionary:
	var e: Dictionary = entry(pid, line)
	if not bool(e["ok"]):
		return e
	if not CrimeLifePath.is_member(pid):
		CrimeLifePath.join(pid, "chose")
	var l: Dictionary = CrimeUnderState.lines.get(pid, {})
	l[line] = {"standing": 0.0, "since": SysUtil.day(), "acts": 0, "via": str(e["via"])}
	CrimeUnderState.lines[pid] = l
	CrimeUnderState.count("join_" + line)
	if CrimePerson.is_player(pid):
		SysUtil.notify("%s joins the %s trade (through %s)." % [CrimePerson.name_of(pid), str(def(line).get("label", line)).to_lower(), {"contact": "a contact", "record": "the name a record brings", "desperate": "sheer need"}[str(e["via"])]], "story")
	SysUtil.game_event("underworld_line_joined", {"folk_id": pid, "line": line})
	return {"ok": true, "msg": "", "via": str(e["via"])}

static func leave(pid: int, line: String) -> void:
	var l: Dictionary = CrimeUnderState.lines.get(pid, {})
	l.erase(line)
	if l.is_empty():
		CrimeUnderState.lines.erase(pid)
	else:
		CrimeUnderState.lines[pid] = l

## Standing up or down; the rank follows and a promotion is told.
static func add_standing(pid: int, line: String, amount: float) -> void:
	if not has(pid, line):
		return
	var before: int = rank_index(pid, line)
	var r: Dictionary = rec(pid, line)
	r["standing"] = clampf(float(r.get("standing", 0.0)) + amount, 0.0, 100.0)
	if amount > 0.0:
		r["acts"] = int(r.get("acts", 0)) + 1
	var after: int = rank_index(pid, line)
	if after > before and CrimePerson.is_player(pid):
		SysUtil.notify("%s is now a %s." % [CrimePerson.name_of(pid), rank_label(pid, line).to_lower()], "story")
	if after != before:
		SysUtil.game_event("underworld_rank", {"folk_id": pid, "line": line, "rank": str(rank_data(pid, line).get("id", ""))})

## Members of a line that are townies (statistical actors), sorted.
static func townie_members(line: String) -> Array:
	var out: Array = []
	for pid in CrimeUnderState.lines:
		if has(int(pid), line) and not CrimePerson.is_player(int(pid)) and CrimePerson.alive(int(pid)):
			out.append(int(pid))
	out.sort()
	return out

## Share of adult townies in a line (statistical joiners stay a small share).
static func townie_share(line: String) -> float:
	var adults: int = 0
	for tid in CrimePerson.townies_only():
		if CrimePerson.is_adult(tid):
			adults += 1
	return float(townie_members(line).size()) / float(maxi(adults, 1))

## Pull a townie into a line (daily dice): members of the criminal path with the right nature, never a player.
static func townie_join_dice(pid: int, line: String, daily: float, traits: Array) -> bool:
	if CrimePerson.is_player(pid) or has(pid, line) or not CrimeLifePath.is_member(pid) or CrimePerson.in_custody(pid):
		return false
	var p: float = daily
	var t_mult: float = 1.0
	for t in traits:
		if CrimePerson.has_trait(pid, str(t)):
			t_mult += 0.8
	p *= t_mult * (1.0 + CrimePressure.risk(pid))
	if CrimeLifePath.cred(pid) < float(def(line).get("min_cred", 10)) or not CrimeUnderState.chance(p):
		return false
	var l: Dictionary = CrimeUnderState.lines.get(pid, {})
	l[line] = {"standing": float(CrimeLifePath.cred(pid)) * 0.3, "since": SysUtil.day(), "acts": 0, "via": "contact"}
	CrimeUnderState.lines[pid] = l
	CrimeUnderState.count("join_" + line)
	return true
