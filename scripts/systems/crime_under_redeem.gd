class_name CrimeUnderRedeem
extends RefCounted
## Task 23: REDEMPTION. A reformed criminal goes straight (leaves the path, the lines and the crew) and works up a progress score: days of clean living,
## an honest job (some careers hire people with records), a MENTOR (a clean friend or relative who sticks by them), and resisting the OLD CONTACTS who call
## and may pull them back. As progress grows, old convictions are EXPUNGED one by one (never the gravest charges); at the end the town's regard recovers
## and a Chronicle line says so. A fall resets part of it. The legacy keeps the notoriety. Townies who left the path run the same dice statistically.
## Tier: the `redeem` table is tiny; one daily pass, no per-minute work.

static func cfg() -> Dictionary:
	return CrimeUnderState.sect("redeem")

static func rec(pid: int) -> Dictionary:
	return CrimeUnderState.redeem.get(pid, {})

static func active(pid: int) -> bool:
	return CrimeUnderState.redeem.has(pid)

static func progress(pid: int) -> float:
	return float(rec(pid).get("progress", 0.0))

## Begin the way back. Leaves every underworld tie behind.
static func begin(pid: int) -> Dictionary:
	if active(pid) or not CrimePerson.alive(pid) or CrimePerson.in_custody(pid) or not CrimePerson.is_adult(pid):
		return {"ok": false, "msg": "Not right now."}
	if CrimeLifePath.is_member(pid):
		CrimeLifePath.leave(pid, "redeem")
	else:
		CrimeLifeState.straight[pid] = SysUtil.day() + int(CrimeLifeState.sect("path").get("going_straight_days", 28))
	CrimeUnderState.lines.erase(pid)
	CrimeUnderGang.remove(pid)
	CrimeUnderState.redeem[pid] = {"start": SysUtil.day(), "progress": 0.0, "mentor": -1, "resisted": 0, "falls": 0, "last_tempt": -99}
	CrimeUnderState.count("redeem_begin")
	_find_mentor(pid)
	return {"ok": true, "msg": "%s is going straight." % CrimePerson.name_of(pid)}

static func _find_mentor(pid: int) -> void:
	var r: Dictionary = rec(pid)
	if int(r.get("mentor", -1)) >= 0 and CrimePerson.alive(int(r["mentor"])):
		return
	for c in CrimePerson.close_alive(pid) + CrimePerson.friends(pid):
		var m: int = int(c)
		if m != pid and CrimePerson.alive(m) and CrimePerson.is_adult(m) and not CrimeLifePath.is_member(m) and not CrimePerson.has_record(m) and RelationshipService.value(m, pid, "friendship") >= 30.0:
			if CrimePerson.has_trait(m, "honest") or CrimePerson.has_trait(m, "empath") or CrimePerson.has_trait(m, "forgiving") or CrimeUnderState.chance(float(cfg().get("mentor_chance", 0.1)) * 3.0):
				r["mentor"] = m
				if CrimePerson.is_player(pid):
					SysUtil.notify("%s offers to stand by %s." % [CrimePerson.name_of(m), CrimePerson.name_of(pid)], "good")
				return

## Take the first honest job that hires people with a record (a command; the folk must qualify).
static func find_job(pid: int) -> Dictionary:
	var f = CrimePerson.folk(pid)
	if f == null or not CrimePerson.is_player(pid) or CrimePerson.has_job(pid):
		return {"ok": false, "msg": "Not possible."}
	for cid in cfg().get("second_chance", []):
		if Careers.why_not_work(f, str(cid), 1) == "" and Careers.hire(f, str(cid), 1):
			return {"ok": true, "msg": "%s gets a start as a %s. Someone was willing to look past the past." % [f.name, str(cid)]}
	return {"ok": false, "msg": "Nobody is hiring someone with that record just now."}

# ------------------------------------------------------------------ daily
static func on_day() -> void:
	var ids: Array = CrimeUnderState.redeem.keys()
	ids.sort()
	for pid in ids:
		day_of(int(pid))

static func day_of(pid: int) -> void:
	var r: Dictionary = rec(pid)
	if r.is_empty():
		return
	if not CrimePerson.alive(pid):
		CrimeUnderState.redeem.erase(pid)
		return
	if CrimePerson.in_custody(pid):
		return
	if CrimeLifePath.is_member(pid):                       # drifted back in without help
		_fall(pid, r, "back in")
		return
	var k: Dictionary = cfg()
	var mentor: int = int(r.get("mentor", -1))
	if mentor >= 0 and (not CrimePerson.alive(mentor) or RelationshipService.value(mentor, pid, "friendship") < 10.0):
		r["mentor"] = -1
		mentor = -1
	if mentor < 0:
		_find_mentor(pid)
		mentor = int(r.get("mentor", -1))
	var gain: float = float(k.get("base_day", 0.8)) * (1.0 + (float(k.get("job", 0.6)) if CrimePerson.has_job(pid) else 0.0) + (float(k.get("mentor", 0.7)) if mentor >= 0 else 0.0))
	gain += float(k.get("streak", 0.002)) * float(SysUtil.day() - int(r["start"]))
	r["progress"] = minf(float(r["progress"]) + gain, float(k.get("pardon_at", 100.0)))
	_expunge_step(pid, r)
	_temptation(pid, r, k)
	if CrimeUnderState.redeem.has(pid) and float(r["progress"]) >= float(k.get("pardon_at", 100.0)):
		finish(pid)

## Old convictions come off the record as the progress grows (never the gravest charges).
static func _expunge_step(pid: int, r: Dictionary) -> void:
	var k: Dictionary = cfg()
	var eligible: Array = []
	for e in JusticeRecords.visible(pid):
		var cd: Dictionary = JusticeProcess.charge_def(str(e.get("charge", "")))
		if not (k.get("never", []) as Array).has(str(e.get("charge", ""))) and (k.get("expunge_classes", []) as Array).has(str(cd.get("class", ""))):
			eligible.append(e)
	var total: int = eligible.size() + int(r.get("cleared", 0))
	var want: int = int(floor(float(r["progress"]) / float(k.get("pardon_at", 100.0)) * float(total) + 0.001))
	var todo: int = want - int(r.get("cleared", 0))
	for i in mini(todo, eligible.size()):
		eligible[i]["expunged"] = true
		eligible[i]["expunged_by"] = "redemption"
		r["cleared"] = int(r.get("cleared", 0)) + 1
		CrimeUnderState.count("record_cleared")
		if CrimePerson.is_player(pid):
			SysUtil.notify("An old conviction no longer counts against %s." % CrimePerson.name_of(pid), "good")

static func _temptation(pid: int, r: Dictionary, k: Dictionary) -> void:
	if SysUtil.day() - int(r.get("last_tempt", -99)) < int(k.get("tempt_gap", 7)) or CrimeLifeContacts.list(pid).is_empty():
		return
	if not CrimeUnderState.chance(float(k.get("tempt_daily", 0.03))):
		return
	r["last_tempt"] = SysUtil.day()
	if CrimePerson.is_player(pid):
		JusticePlayer.ask(pid, "An old contact calls", "A voice from the old days: there is a job, easy money, nobody would ever know. %s could use it." % CrimePerson.name_of(pid),
			[{"id": "resist", "label": "Hang up"}, {"id": "go", "label": "Hear them out"}], _tempt_choice.bind(pid), "resist")
		return
	var strength: float = 0.55 + (0.25 if CrimePerson.has_trait(pid, "honest") else 0.0) + (0.1 if int(r.get("mentor", -1)) >= 0 else 0.0) - 0.3 * CrimePressure.risk(pid) \
		- (0.2 if CrimePerson.has_trait(pid, "dishonest") else 0.0)
	_tempt_choice("resist" if CrimeUnderState.chance(clampf(strength, 0.05, 0.95) * float(k.get("pull_back", 0.5)) + (1.0 - float(k.get("pull_back", 0.5)))) else "go", pid)

static func _tempt_choice(ch, pid: int) -> void:
	var r: Dictionary = rec(pid)
	if r.is_empty():
		return
	if str(ch) == "resist":
		r["resisted"] = int(r.get("resisted", 0)) + 1
		r["progress"] = minf(float(r["progress"]) + float(cfg().get("resist", 4.0)), float(cfg().get("pardon_at", 100.0)))
		CrimeUnderRep.deed(pid, "mercy")
		CrimeUnderState.count("redeem_resist")
	else:
		_fall(pid, r, "went back")

static func _fall(pid: int, r: Dictionary, _why: String) -> void:
	r["falls"] = int(r.get("falls", 0)) + 1
	r["progress"] = maxf(float(r["progress"]) + float(cfg().get("fall", -20.0)), 0.0)
	CrimeUnderState.count("redeem_fall")
	if not CrimeLifePath.is_member(pid):
		CrimeLifeState.straight.erase(pid)
		CrimeLifePath.join(pid, "chose")
	if CrimePerson.is_player(pid):
		SysUtil.notify("%s has gone back to the old ways. The road back is longer now." % CrimePerson.name_of(pid), "warn")
	CrimeUnderState.redeem.erase(pid)                      # the attempt is over; they may begin again

static func finish(pid: int) -> void:
	var k: Dictionary = cfg()
	for e in JusticeRecords.visible(pid):                   # whatever is left and allowed
		if not (k.get("never", []) as Array).has(str(e.get("charge", ""))) and (k.get("expunge_classes", []) as Array).has(str(JusticeProcess.charge_def(str(e.get("charge", ""))).get("class", ""))):
			e["expunged"] = true
			e["expunged_by"] = "redemption"
	RelationshipKnowledge.add_reputation(pid, float(k.get("rep_gain", 10.0)))
	CrimePerson.add_buff_safe(pid, "turned_my_life")
	CrimeUnderState.redeem.erase(pid)
	var rr: Dictionary = CrimeUnderRep.rec(pid)
	rr["redeemed"] = SysUtil.day()
	rr["honour"] = float(rr.get("honour", 0.0)) + 3.0
	CrimeUnderState.rep[pid] = rr
	CrimeUnderState.count("redeemed")
	ChronicleHook.note("redemption", "%s has turned their life around." % CrimePerson.name_of(pid), [pid], "", 2, true)
	if CrimePerson.is_player(pid):
		SysUtil.notify("%s has turned their life around. The town is beginning to believe it." % CrimePerson.name_of(pid), "good")

# ------------------------------------------------------------------ townies
## A townie who left the path and has a record may take the way back (daily dice).
static func person_day(pid: int) -> void:
	if CrimePerson.is_player(pid) or active(pid) or not CrimePerson.is_adult(pid) or CrimePerson.in_custody(pid) or CrimeLifePath.is_member(pid):
		return
	var until: int = int(CrimeLifeState.straight.get(pid, -1))
	if until < 0 or CrimePerson.record_count(pid) == 0:
		return
	if SysUtil.day() - (until - int(CrimeLifeState.sect("path").get("going_straight_days", 28))) < int(cfg().get("townie_min_straight", 10)):
		return
	if CrimeUnderState.chance(float(cfg().get("townie_daily", 0.01)) * (2.0 if CrimePerson.has_trait(pid, "honest") else 1.0)):
		begin(pid)
