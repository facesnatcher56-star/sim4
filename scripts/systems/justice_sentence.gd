class_name JusticeSentence
extends RefCounted
## Sentences: a fine, community service, probation, jail (short, up to `jail_max_days`) or prison (the longest stretch). Picked from the charge's
## weighted options in data/justice.json; a plea deal lightens it, a record or probation makes it harsher, a serial killer gets life.
## A murder sentence can outlast the rest of a playthrough (a folk lives ~200 days): the player is warned in the plea and sentence prompts.

static func cfg() -> Dictionary:
	return JusticeState.sect("sentences")

static func options_for(charge: String) -> Array:
	return (JusticeProcess.charge_def(charge).get("sentences", []) as Array)

## "from 70 to 160 days in prison, or for life" - used by the plea prompt so the player knows what is at stake.
static func describe_range(charge: String) -> String:
	var worst: Dictionary = {}
	var worst_days: int = -1
	for o in options_for(charge):
		var d: int = int(o.get("max", 0)) if str(o["type"]) in ["jail", "prison"] else -1
		if bool(o.get("life", false)):
			d = 99999
		if d > worst_days:
			worst_days = d
			worst = o
	if worst_days < 0:
		return "a fine or community service"
	if worst_days >= 99999:
		return "up to life in prison"
	return "up to %d days in %s" % [worst_days, str(worst["type"])]

static func pick(c: Dictionary, plea: bool) -> Dictionary:
	var pid: int = int(c["accused"])
	var opts: Array = options_for(str(c["charge"]))
	var w: Array = []
	var record: int = CrimePerson.record_count(pid)
	var probation: bool = JusticeState.probation.has(pid) and int(JusticeState.probation[pid]) >= SysUtil.day()
	var heavy: bool = int(c.get("counts", 1)) >= 2
	for o in opts:
		var weight: float = float(o.get("weight", 1.0))
		var t: String = str(o["type"])
		if t in ["jail", "prison"]:
			weight *= 1.0 + 0.5 * float(mini(record, 3)) + (1.0 if probation else 0.0)
		elif t in ["fine", "service"] and (record > 0 or probation):
			weight *= 0.5
		if plea and t in ["jail", "prison"]:
			weight *= 0.7
		if heavy:
			weight *= 6.0 if bool(o.get("life", false)) else (0.0 if t not in ["prison"] else 1.0)
		elif bool(o.get("life", false)):
			weight *= 1.0 if not plea else 0.3
		w.append(weight)
	var i: int = JusticeState.pick_index(w)
	if i < 0:
		return {"type": "fine", "fine": 50, "days": 0}
	var o2: Dictionary = opts[i]
	var days: int = JusticeState.rng.randi_range(int(o2.get("min", 0)), maxi(int(o2.get("max", 0)), int(o2.get("min", 0))))
	var mult: float = (float(cfg().get("plea_mult", 0.6)) if plea else 1.0) * (float(cfg().get("probation_mult", 1.5)) if probation else 1.0)
	var out: Dictionary = {"type": str(o2["type"]), "days": int(round(float(days) * mult)), "fine": int(round(float(o2.get("fine", 0)) * mult)), "life": bool(o2.get("life", false))}
	if str(out["type"]) in ["jail", "prison"] and not bool(out["life"]):
		out["type"] = "jail" if int(out["days"]) <= int(cfg().get("jail_max_days", 10)) else "prison"
	if bool(out["life"]):
		out["days"] = 99999
	return out

static func impose(c: Dictionary) -> void:
	var pid: int = int(c["accused"])
	var plea: bool = str(c["verdict"]) == "plea"
	var s: Dictionary = pick(c, plea)
	c["sentence"] = s
	c["state"] = "closed"
	c["closed_day"] = SysUtil.day()
	CaseStore.mark_solved(c)
	JusticeState.count("convictions")
	var recs: Array = JusticeState.records.get(pid, [])
	recs.append({"day": SysUtil.day(), "charge": str(c["charge"]), "case": int(c["id"]), "result": "plea" if plea else "guilty"})
	JusticeState.records[pid] = recs
	RelationshipKnowledge.add_reputation(pid, -8.0 * float(int(JusticeProcess.charge_def(str(c["charge"])).get("severity", 2))) / 2.0)
	for oid in (c.get("joined", []) as Array):
		var o: Dictionary = CaseStore.get_case(int(oid))
		if not o.is_empty():
			o["state"] = "closed"
			o["accused"] = pid
			o["verdict"] = c["verdict"]
			CaseStore.mark_solved(o)
	if str(c["kind"]) in ["murder", "serial"]:
		Police.stir_town(c)
		JusticeState.uneasy_until = SysUtil.day()          # the town breathes again
		for r in SysUtil.residents():
			r.remove_buff("uneasy_at_night")
	_apply(c, pid, s)
	CrimeRevenge.end_for_case(int(c["id"]))
	if str(s["type"]) in ["fine", "service", "probation"] or (str(s["type"]) == "jail" and int(s["days"]) <= 3):
		CrimeRevenge.on_escaped(c)             # a very light sentence: the family may not accept it
	var txt: String = describe(s)
	CaseStore.note(c, "%s: %s" % [CrimePerson.name_of(pid), txt], "sentence", 3)
	if CrimePerson.is_player(pid):
		var warn: String = ""
		if bool(s.get("life", false)) or (str(s["type"]) == "prison" and int(s["days"]) >= int(cfg().get("long_warning_days", 80))):
			warn = " This sentence may outlast the rest of their life."
		JusticePlayer.tell(pid, "Sentence", "%s: %s.%s" % [CrimePerson.name_of(pid), txt, warn])
	SysUtil.game_event("sentenced", {"folk_id": pid, "case": int(c["id"]), "type": str(s["type"]), "days": int(s["days"])})

static func describe(s: Dictionary) -> String:
	match str(s["type"]):
		"fine": return "a fine of %d coins" % int(s["fine"])
		"service": return "%d days of community service" % int(s["days"])
		"probation": return "%d days of probation" % int(s["days"])
		"jail": return "%d days in jail" % int(s["days"])
		"prison": return "life in prison" if bool(s.get("life", false)) else "%d days in prison" % int(s["days"])
	return "a sentence"

static func _apply(c: Dictionary, pid: int, s: Dictionary) -> void:
	JusticeState.inmates.erase(pid)
	JusticePlayer.release(CrimePerson.folk(pid))
	match str(s["type"]):
		"fine":
			_fine(pid, int(s["fine"]))
		"service":
			JusticeState.service[pid] = {"days_left": int(s["days"]), "last_day": -1}
			JusticeState.probation[pid] = SysUtil.day() + int(s["days"]) + 7
		"probation":
			JusticeState.probation[pid] = SysUtil.day() + int(s["days"])
		"jail", "prison":
			if int(s["days"]) >= 4:
				_lose_job(pid)
			Prison.admit(pid, c, int(s["days"]), str(s["type"]))
	if int(s.get("fine", 0)) > 0 and str(s["type"]) != "fine":
		_fine(pid, int(s["fine"]))

static func _fine(pid: int, amount: int) -> void:
	if amount <= 0:
		return
	if CrimePerson.is_player(pid):
		var hid: int = CrimePerson.hid(pid)
		if not Economy.spend(hid, amount, "court fine"):
			Economy.bills.append({"id": Economy._seq, "hid": hid, "amount": amount, "base": amount, "issued": SysUtil.day(), "due": SysUtil.day() + 3,
				"paid": false, "late": false, "fee": 0, "reason": "court fine"})
			Economy._seq += 1
			SysUtil.notify("A court fine of %d coins is waiting to be paid." % amount, "bill")
	else:
		CrimePerson.pay(pid, amount, "fine")

static func _lose_job(pid: int) -> void:
	var f = CrimePerson.folk(pid)
	if f != null and Careers.has_job(pid):
		Careers.quit_job(f, "jailed")
	elif Story.townies.has(pid) and str(Story.townies[pid].get("career", "")) != "":
		Story.townies[pid]["career"] = ""
		Story.townies[pid]["level"] = 1

# ------------------------------------------------------------------ community service (daily)
static func on_day() -> void:
	for pid in JusticeState.service.keys():
		var sv: Dictionary = JusticeState.service[pid]
		if int(sv["last_day"]) == SysUtil.day():
			continue
		sv["last_day"] = SysUtil.day()
		var f = CrimePerson.folk(int(pid))
		if f != null and CrimePerson.is_player(int(pid)) and not SysUtil.is_away(f):
			f.add_buff("community_service")
			JusticePlayer.hold(f, 240.0, "service", "Community service")
		sv["days_left"] = int(sv["days_left"]) - 1
		if int(sv["days_left"]) <= 0:
			JusticeState.service.erase(pid)
			if CrimePerson.is_player(int(pid)):
				SysUtil.notify("%s finished their community service." % CrimePerson.name_of(int(pid)), "good")
	for pid2 in JusticeState.probation.keys():
		if int(JusticeState.probation[pid2]) < SysUtil.day():
			JusticeState.probation.erase(pid2)
