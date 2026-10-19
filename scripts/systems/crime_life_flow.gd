class_name CrimeLifeFlow
extends RefCounted
## The one door of task 21 (criminal life and security) into the rest of the game. CrimeFlow calls install / uninstall / on_minute / on_hour / on_day /
## on_game_event, one line each; everything else is routed from here. Townie dice are per person (CrimeLifeTownie.person_day, bucketed by CrimeFlow).

static func install() -> void:
	CrimeSecurityGuards.install()

static func uninstall() -> void:
	CrimeSecurityGuards.uninstall()

static func on_minute() -> void:
	if not CrimeLifeState.pending.is_empty():
		CrimeLifeJobs.on_minute()

static func on_hour() -> void:
	CrimeSecurityGuards.on_hour()

## `sliced`: the townie dice already run in the bucketed CrimeFlow.person_day job.
static func on_day(sliced: bool) -> void:
	CrimeSecurityGuards.on_day()
	CrimeSecurityAlarm.on_day()
	CrimeSecurityUpgrade.on_day()
	CrimeLifeFence.on_day()
	CrimeLifeSnitch.rival_tips()
	CrimeLifeMoral.on_day()
	CrimeLifeContacts.on_day()
	_offers()
	_forget_old_casing()
	for pid in CrimeLifeState.members.keys():
		if not CrimePerson.alive(int(pid)):
			CrimeLifeState.notoriety_kept[int(pid)] = float(CrimeLifeState.members[pid].get("notoriety", 0.0))
			CrimeLifeState.members.erase(pid)                  # the dead leave the underworld (their legacy keeps the name)
		elif CrimePerson.is_player(int(pid)):
			CrimeLifePath.on_day_member(int(pid))
	if not sliced:
		CrimeLifeTownie.on_day_all()
	CrimeUnderFlow.on_day(sliced)                              # task 23: the underworld lines, gangs, the good side

## A desperate PLAYER folk is offered shady work now and then (09c pressure): join, or say no thanks.
static func _offers() -> void:
	var k: Dictionary = CrimeLifeState.sect("path")
	var gap: int = int(CrimeLifeState.sect("townie").get("offer_gap_days", 14))
	for f in SysUtil.residents():
		var pid: int = int(f.id)
		if CrimeLifePath.is_member(pid) or CrimeLifePath.going_straight(pid) or not CrimePerson.is_adult(pid) or CrimePerson.in_custody(pid):
			continue
		if SysUtil.day() - int(CrimeLifeState.offered.get(pid, -999)) < gap:
			continue
		var r: float = CrimePressure.risk(pid)
		if r < float(k.get("drift_pressure", 0.55)) or not CrimeLifeState.chance(float(k.get("drift_daily", 0.04))):
			continue
		CrimeLifeState.offered[pid] = SysUtil.day()
		JusticePlayer.ask(pid, "A shady offer", "Money is desperately tight. An acquaintance says there is quick cash for someone who can keep quiet. Does %s take it?" % f.name,
			[{"id": "join", "label": "Hear them out"}, {"id": "no", "label": "No thanks"}], func(ch): if str(ch) == "join": CrimeLifePath.join(pid, "drift"), "no")

static func _forget_old_casing() -> void:
	if SysUtil.day() % 7 != 0:
		return
	for key in CrimeLifeState.cased.keys():
		if SysUtil.day() - int(CrimeLifeState.cased[key].get("day", 0)) > 60:
			CrimeLifeState.cased.erase(key)

# ------------------------------------------------------------------ game events
static func on_event(ev: String, p: Dictionary) -> void:
	var fid: int = int(p.get("folk_id", -1))
	match ev:
		"crime_pickpocket":
			var t: int = int(p.get("target_id", -1))
			if t >= 0 and CrimePerson.alive(t):
				if not CrimeLifePath.is_member(fid):
					CrimeLifePath.join(fid, "chose")
				var res: Dictionary = CrimeLifeJobs.run(fid, "pickpocket", {"scene": "street", "case_scene": "street", "victim": t, "label": CrimePerson.name_of(t)}, {})
				if res.get("outcome", "") == "clean":
					SysUtil.notify("%s's pocket was light and nobody noticed." % CrimePerson.name_of(fid), "good")
		"crime_ask_around":
			var r: Dictionary = CrimeLifeContacts.ask_around(fid, int(p.get("target_id", -1)))
			if str(r.get("msg", "")) != "":
				SysUtil.notify(str(r["msg"]), "story" if bool(r.get("ok", false)) else "info")
		"crime_case_here":
			var f = CrimePerson.folk(fid)
			var lot: String = Neighborhood.lot_of(f) if f != null else ""
			if lot != "" and lot != Neighborhood.HOME:
				CrimeLifeCasing.session(fid, "biz:%s" % lot)
		"crime_review_footage":
			CrimeSecurityFootage.on_review(fid)
		"guard_round":
			CrimeSecurityGuards.on_round(fid)
		"released":
			CrimeLifeContacts.on_released(fid)
