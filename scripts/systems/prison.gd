class_name Prison
extends RefCounted
## Jail (short) and prison (long): a rabbit hole like the hospital. A player folk is away (Away reason "jail"/"prison") with a status chip; a
## townie is simply marked in JusticeState.inmates. Behaviour decides early PAROLE (good) or extra time (fights). Friends and family can VISIT,
## which keeps the relationship from fading. On RELEASE: a criminal record stays, some jobs refuse them, their reputation drops, and a
## "fresh start" goal begins.
##   Prison.admit(pid, case, days, kind) / release(pid, early) / visit(visitor, inmate) / job_ok(pid, career) / on_day()

static func cfg() -> Dictionary:
	return JusticeState.sect("prison")

static func admit(pid: int, c: Dictionary, days: int, kind: String) -> void:
	var until: int = SysUtil.day() + days if days < 99999 else 100000
	JusticeState.inmates[pid] = {"case": int(c["id"]), "kind": kind, "since": SysUtil.day(), "until": until, "behaviour": 50, "parole_day": -1, "visits": 0, "life": days >= 99999}
	var f = CrimePerson.folk(pid)
	if f != null and CrimePerson.is_player(pid):
		var minutes: float = float(mini(days, 3000)) * 1440.0
		JusticePlayer.hold(f, minutes, kind, "In prison" if kind == "prison" else "In jail")
	elif Story.townies.has(pid):
		Story.townies[pid]["in_prison"] = true
	var text: String = "%s was taken to %s." % [CrimePerson.name_of(pid), "prison" if kind == "prison" else "jail"]
	ChronicleHook.note("jailed", text, [pid], CrimePerson.home_key(pid), 3, true)

static func is_inside(pid: int) -> bool:
	return str((JusticeState.inmates.get(pid, {}) as Dictionary).get("kind", "")) in ["jail", "prison"]

# ------------------------------------------------------------------ daily
static func on_day() -> void:
	var k: Dictionary = cfg()
	for pid in JusticeState.inmates.keys():
		var ins: Dictionary = JusticeState.inmates[pid]
		if not CrimePerson.alive(int(pid)):
			JusticeState.inmates.erase(pid)
			continue
		var kind: String = str(ins["kind"])
		if kind not in ["jail", "prison"]:
			continue
		# behaviour: calm folk earn trust, hot-headed ones get into fights that add time
		var b: float = float(ins["behaviour"])
		var fight_p: float = float(k.get("fight_chance", 0.03)) * (3.0 if CrimePerson.has_trait(int(pid), "hot_headed") else 1.0)
		if JusticeState.chance(fight_p):
			b -= float(k.get("fight_penalty", 25))
			if int(ins["until"]) < 100000:
				ins["until"] = int(ins["until"]) + int(k.get("fight_days", 3))
			if CrimePerson.is_player(int(pid)):
				SysUtil.notify("%s got into a fight inside. 3 days were added." % CrimePerson.name_of(int(pid)), "bad")
		else:
			b += float(k.get("good_per_day", 1.5)) * (1.5 if CrimePerson.has_trait(int(pid), "easygoing") or CrimePerson.has_trait(int(pid), "forgiving") else 1.0)
		ins["behaviour"] = clampf(b, 0.0, 100.0)
		# townie relatives visit now and then
		for rel in CrimePerson.close_alive(int(pid)).slice(0, 2):
			if not CrimePerson.is_player(int(rel)) and JusticeState.chance(float(k.get("townie_visit", 0.12))):
				visit(int(rel), int(pid))
		# parole: after a share of the sentence, good behaviour can end it early
		var served: int = SysUtil.day() - int(ins["since"])
		var total: int = int(ins["until"]) - int(ins["since"])
		if kind == "prison" and not bool(ins.get("life", false)) and float(served) >= float(total) * float(k.get("parole_after", 0.5)) and float(ins["behaviour"]) >= float(k.get("parole_behaviour", 65)):
			if JusticeState.chance(float(k.get("parole_chance", 0.12))):
				release(int(pid), true)
				continue
		if SysUtil.day() >= int(ins["until"]):
			release(int(pid), false)

static func release(pid: int, early: bool) -> void:
	var ins: Dictionary = JusticeState.inmates.get(pid, {})
	if ins.is_empty():
		return
	JusticeRecords.note_served(pid, SysUtil.day() - int(ins.get("since", SysUtil.day())))
	JusticeState.inmates.erase(pid)
	var f = CrimePerson.folk(pid)
	JusticePlayer.release(f)
	if Story.townies.has(pid):
		Story.townies[pid].erase("in_prison")
	var k: Dictionary = cfg()
	RelationshipKnowledge.add_reputation(pid, -float(k.get("release_reputation", 6)))
	JusticeState.fresh_start[pid] = SysUtil.day()
	CrimeAssault.calm_for(pid, int(JusticeState.sect("assault").get("release_calm_days", 14)))
	JusticeOrders.on_released(pid)
	if f != null:
		f.add_buff("fresh_start")
		f.remove_buff("in_custody")
	var nm: String = CrimePerson.name_of(pid)
	var text: String = "%s was released on parole." % nm if early else "%s was released after serving their sentence." % nm
	ChronicleHook.note("released", text, [pid], CrimePerson.home_key(pid), 2, true)
	if CrimePerson.is_player(pid):
		SysUtil.notify(text + " The record stays, and some jobs will not hire them, but it is a fresh start.", "story")
	SysUtil.game_event("released", {"folk_id": pid, "early": early})

# ------------------------------------------------------------------ visits
## `visitor` goes to see `inmate`. A player visitor is away for two hours. Keeps the bond from fading.
static func visit(visitor: int, inmate: int) -> bool:
	var ins: Dictionary = JusticeState.inmates.get(inmate, {})
	if ins.is_empty() or str(ins["kind"]) not in ["jail", "prison"] or not CrimePerson.alive(visitor):
		return false
	var fv = CrimePerson.folk(visitor)
	if fv != null and CrimePerson.is_player(visitor):
		if not JusticePlayer.hold(fv, 120.0, "prison_visit", "Visiting %s" % CrimePerson.name_of(inmate)):
			return false
	RelationshipService.add_both(visitor, inmate, "friendship", float(cfg().get("visit_friendship", 3)))
	RelationshipService.touch(visitor, inmate)
	ins["visits"] = int(ins.get("visits", 0)) + 1
	ins["behaviour"] = minf(float(ins["behaviour"]) + 2.0, 100.0)
	var fi = CrimePerson.folk(inmate)
	if fi != null:
		fi.add_buff("visited_inside")
	return true

# ------------------------------------------------------------------ records and jobs
## Jobs that refuse anyone with a conviction (data: prison.record_blocks). Short sentences and old convictions are forgiven.
static func job_ok(pid: int, career: String) -> bool:
	if not (cfg().get("record_blocks", []) as Array).has(career):
		return true
	return not JusticeRecords.bans(pid, career)

static func on_returned(f, _rec: Dictionary) -> void:
	f.remove_buff("in_custody")