class_name CrimeUnderFlow
extends RefCounted
## The one door of task 23 (the underworld lines, gangs, the good side and the two reputations) into the rest of the game. CrimeLifeFlow calls
## on_day (one line); CrimeFlow.person_day calls person_day (bucketed daily dice per person); CrimeLifeJobs.on_minute hands the timed pending
## resolutions (research, an execution, a sale) to on_pending; CrimeFlow.on_game_event hands the events; JusticeProcess.file_charges calls on_charged.
## Tier: nothing per minute. ACTIVE (the player's folk): commands and pending resolutions. NEAR / TOWN / STATISTICAL: the same dice once a day per
## townie (no walking, no scenes). Caps: contracts 8 open, 60 addicts, 3 gangs, 7 members a gang, 12 racket ops per boss.

## `sliced`: the per-person dice already run in the bucketed CrimeFlow.person_day job.
static func on_day(sliced: bool) -> void:
	CrimeUnderHit.on_day()
	CrimeUnderDeal.on_day()
	CrimeUnderAddict.on_day()
	CrimeUnderGang.on_day()
	CrimeUnderRacket.on_day()
	CrimeUnderGood.on_day()
	CrimeUnderGood.undercover_day()
	CrimeUnderRedeem.on_day()
	CrimeUnderRep.on_day()
	if not sliced:
		for tid in CrimePerson.townies_only():
			person_day(int(tid))

static func person_day(pid: int) -> void:
	if not CrimePerson.alive(pid):
		return
	CrimeUnderHit.person_day(pid)
	CrimeUnderDeal.person_day(pid)
	CrimeUnderRacket.person_day(pid)
	CrimeUnderGood.person_day(pid)
	CrimeUnderRedeem.person_day(pid)

## Timed work of the player's folk that ended (queued in CrimeLifeState.pending).
static func on_pending(p: Dictionary) -> void:
	var pid: int = int(p.get("pid", -1))
	if pid < 0 or not CrimePerson.alive(pid) or CrimePerson.in_custody(pid):
		return
	match str(p.get("kind", "")):
		"hit_research":
			var c: Dictionary = CrimeUnderHit.get_contract(int(p.get("contract", -1)))
			if not c.is_empty() and str(c["state"]) == "taken":
				CrimeUnderHitRun.session(pid, c)
		"hit_exec":
			var c2: Dictionary = CrimeUnderHit.get_contract(int(p.get("contract", -1)))
			if not c2.is_empty() and str(c2["state"]) == "taken":
				var scene: String = str(p.get("scene", ""))
				var alone: bool = false
				for o in CrimeUnderHitRun.opportunities(pid, int(c2["id"])):
					if str(o["scene"]) == scene:
						alone = bool(o["alone"])
				var res: Dictionary = CrimeUnderHitRun.resolve(pid, c2, scene, {"alone": alone, "police": false})
				if CrimePerson.is_player(pid):
					SysUtil.notify({"clean": "It is done. Nobody saw.", "seen": "It is done, but somebody saw.", "botched": "It went wrong.", "none": ""}.get(str(res.get("outcome", "none")), ""), "warn")
		"deal_sell":
			var r: Dictionary = CrimeUnderDeal.session(pid, str(p.get("corner", "")))
			if CrimePerson.is_player(pid) and int(r.get("sold", 0)) > 0:
				SysUtil.notify("%s sold %d doses (%d coins)%s." % [CrimePerson.name_of(pid), int(r["sold"]), int(r["earned"]), "; a customer was an undercover officer" if bool(r.get("sting", false)) else ""], "bad" if bool(r.get("sting", false)) else "info")

static func on_event(ev: String, p: Dictionary) -> void:
	match ev:
		"accident_rescued":
			CrimeUnderGood.on_rescue(int(p.get("folk_id", -1)))

static func on_charged(c: Dictionary) -> void:
	if int(c.get("contract", -1)) >= 0:
		CrimeUnderHitRun.on_charged(c)

## A snapshot of what a person is in underworld terms (UI, tests, the case board).
static func overview(pid: int) -> Dictionary:
	var lines: Dictionary = {}
	for line in CrimeUnderLines.ids():
		if CrimeUnderLines.has(pid, line):
			lines[line] = {"rank": CrimeUnderLines.rank_label(pid, line), "standing": CrimeUnderLines.standing(pid, line)}
	var gid: int = CrimeUnderGang.of(pid)
	return {"lines": lines, "gang": str(CrimeUnderGang.get_gang(gid).get("name", "")) if gid >= 0 else "", "gang_rank": CrimeUnderGang.rank_label(pid), "reputation": CrimeUnderRep.summary(pid),
		"addiction": CrimeUnderAddict.summary(pid), "redeeming": CrimeUnderRedeem.active(pid), "progress": CrimeUnderRedeem.progress(pid), "taint": CrimeUnderRacket.taint(pid)}
