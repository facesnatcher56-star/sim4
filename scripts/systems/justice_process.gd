class_name JusticeProcess
extends RefCounted
## The road from suspicion to a courtroom (task 09): ARREST -> CHARGES -> BAIL or remand -> LAWYER -> a trial date a few days later.
## Used for every person in town: a townie accused is processed with dice and records, a player folk gets prompts and is held away (Away).
## Wrongful arrests are possible (the case record's `accused` differs from the real `culprit`) but rare by construction (CaseEvidence).

static func cfg() -> Dictionary:
	return JusticeState.sect("process")

static func charge_def(charge: String) -> Dictionary:
	return (JusticeState.sect("charges") as Dictionary).get(charge, {})

## Which charge fits the crime (a case with several killings keeps the heaviest).
static func charge_for(c: Dictionary) -> String:
	match str(c["kind"]):
		"serial": return "murder"
		"assault":
			if bool(c.get("domestic", false)):
				return "domestic_violence"
			return "aggravated_assault" if int(c.get("severity", 1)) >= 2 else "assault"
		_:
			if str(c.get("charge_hint", "")) != "" and not charge_def(str(c["charge_hint"])).is_empty():
				return str(c["charge_hint"])
			return str(c["kind"]) if not charge_def(str(c["kind"])).is_empty() else "theft"

## Every charge the incident brings: the main one, a probation violation when the accused is on probation, a breach when a protective order
## covers the victim, plus whatever the crime code listed in c["also"].
static func charges_for(c: Dictionary) -> Array:
	var main: String = charge_for(c)
	var list: Array = [main]
	var pid: int = int(c.get("accused", -1))
	if not bool(charge_def(main).get("petty", false)):
		if JusticeState.probation.has(pid) and int(JusticeState.probation[pid]) >= SysUtil.day() and main != "probation_violation":
			list.append("probation_violation")
		if main != "order_violation" and int(c.get("victim", -1)) >= 0 and not JusticeOrders.between(pid, int(c["victim"])).is_empty() and bool(c.get("domestic", false)):
			list.append("order_violation")
	for extra in (c.get("also", []) as Array):
		if not list.has(str(extra)) and not charge_def(str(extra)).is_empty():
			list.append(str(extra))
	return list

# ------------------------------------------------------------------ arrest
static func arrest(c: Dictionary, pid: int) -> void:
	if not CrimePerson.alive(pid) or CrimePerson.in_custody(pid):
		return
	if CrimeSerial.is_killer(pid):
		CrimeSerial.mark_caught(c)
	var wrongful: bool = pid != int(c["culprit"])
	c["accused"] = pid
	c["wrongful"] = wrongful
	c["state"] = "arrested"
	c["arrest_day"] = SysUtil.day()
	if wrongful:
		JusticeState.count("wrongful_arrests")
	JusticeState.count("arrests")
	JusticeState.count("arrest_" + str(c["kind"]))
	var nm: String = CrimePerson.name_of(pid)
	if CrimePerson.has_trait(pid, "hot_headed") and JusticeState.chance(0.04) and not (c.get("also", []) as Array).has("resisting_arrest"):
		c["also"] = (c.get("also", []) as Array) + ["resisting_arrest"]
	var text: String = CaseText.arrested(c, pid)
	CaseStore.note(c, text, "arrest", 3)
	if CrimePerson.is_player(pid) or CaseStore.household_involved(c):
		SysUtil.notify(text, "bad" if CrimePerson.is_player(pid) else "story")
	SysUtil.game_event("arrested", {"folk_id": pid, "case": int(c["id"]), "wrongful": wrongful})
	var f = CrimePerson.folk(pid)
	JusticeState.inmates[pid] = {"case": int(c["id"]), "kind": "custody", "since": SysUtil.day(), "until": SysUtil.day() + 1, "behaviour": 50, "parole_day": -1}
	if CrimePerson.is_player(pid) and f != null:
		JusticePlayer.hold(f, 6.0 * 60.0, "custody", "In custody")
		JusticePlayer.tell(pid, "Arrested", "%s%s" % [text, " They insist they did nothing wrong." if wrongful else ""])
	if bool(c.get("domestic", false)):
		JusticeOrders.issue(c, int(JusticeState.sect("domestic").get("order_bail_days", 10)))
	file_charges(c)

# ------------------------------------------------------------------ charges, bail, lawyer
static func file_charges(c: Dictionary) -> void:
	var pid: int = int(c["accused"])
	var ch: String = charge_for(c)
	var d: Dictionary = charge_def(ch)
	c["charge"] = ch
	c["charges"] = charges_for(c)
	c["bail"] = int(d.get("bail", 100))
	for extra in c["charges"]:
		c["bail"] = maxi(int(c["bail"]), int(charge_def(str(extra)).get("bail", 0)))
	if bool(d.get("petty", false)):
		JusticeState.inmates.erase(pid)
		JusticePlayer.release(CrimePerson.folk(pid))
		CrimePetty.settle(c)                       # small offences: a fine or service on the spot, no trial
		return
	c["state"] = "charged"
	CaseStore.note(c, CaseText.charged(c, pid), "charged", 3)
	arrange_lawyer(c)
	CrimeUnderFlow.on_charged(c)                 # task 23: a hired killer may name the client
	CrimeLifeSnitch.on_charged(c)               # crew members may talk; the accused may be offered a deal (task 21)
	var tday: int = SysUtil.day() + JusticeState.rng.randi_range(int(cfg().get("trial_delay", [3, 5])[0]), int(cfg().get("trial_delay", [3, 5])[1]))
	c["trial_day"] = tday
	JusticeState.queue({"kind": "trial", "case": int(c["id"]), "due_min": (tday - 1) * 1440 + int(cfg().get("trial_hour", 9)) * 60})
	decide_bail(c)

static func decide_bail(c: Dictionary) -> void:
	var pid: int = int(c["accused"])
	var sev: int = int(charge_def(str(c["charge"])).get("severity", 2))
	var granted: bool = sev <= int(cfg().get("bail_max_severity", 3)) and not (JusticeState.probation.has(pid) and sev >= 3)
	if bool(c.get("domestic", false)) and JusticeGuideline.prior_same(pid, str(c["charge"])) >= int(JusticeState.sect("domestic").get("no_bail_prior", 1)):
		granted = false                        # a repeat domestic offender stays in until the trial
	var amount: int = int(c["bail"])
	if not granted or CrimePerson.coins(pid) < amount:
		_remand(c, "Bail was refused." if not granted else "Bail was set at %d coins, more than they can pay." % amount)
		return
	if CrimePerson.is_player(pid):
		JusticePlayer.ask(pid, "Bail", "%s can go home until the trial if they pay %d coins bail. Otherwise they stay in jail until the trial (day %d)." % [CrimePerson.name_of(pid), amount, int(c["trial_day"]) + 1],
			[{"id": "pay", "label": "Pay bail (%d coins)" % amount}, {"id": "stay", "label": "Stay in jail"}], func(ch): _bail_choice(c, str(ch)), "pay")
	else:
		_bail_choice(c, "pay")

static func _bail_choice(c: Dictionary, choice: String) -> void:
	var pid: int = int(c["accused"])
	if choice == "pay" and CrimePerson.pay(pid, int(c["bail"]), "bail") > 0:
		JusticeState.inmates.erase(pid)
		c["bail_paid"] = int(c["bail"])
		JusticePlayer.release(CrimePerson.folk(pid))
		CaseStore.note(c, "%s paid bail and went home until the trial." % CrimePerson.name_of(pid))
		if CrimePerson.is_player(pid):
			SysUtil.notify("%s paid %d coins bail and is home until the trial on day %d." % [CrimePerson.name_of(pid), int(c["bail"]), int(c["trial_day"]) + 1], "info")
	else:
		_remand(c, "")

static func _remand(c: Dictionary, why: String) -> void:
	var pid: int = int(c["accused"])
	var days: int = maxi(int(c["trial_day"]) - SysUtil.day(), 1) + 1
	JusticeState.inmates[pid] = {"case": int(c["id"]), "kind": "remand", "since": SysUtil.day(), "until": SysUtil.day() + days, "behaviour": 50, "parole_day": -1}
	var f = CrimePerson.folk(pid)
	if CrimePerson.is_player(pid) and f != null:
		JusticePlayer.hold(f, float(days) * 1440.0, "jail", "Held for trial")
		if why != "":
			SysUtil.notify(why + " %s is held until the trial on day %d." % [CrimePerson.name_of(pid), int(c["trial_day"]) + 1], "bad")
	CaseStore.note(c, "%s is held in jail until the trial." % CrimePerson.name_of(pid))

## Public defender (free, weak) or a private lawyer for coins (better). Townies hire what they can afford; the player chooses.
static func arrange_lawyer(c: Dictionary) -> void:
	var pid: int = int(c["accused"])
	var L: Dictionary = JusticeState.sect("lawyers")
	var sev: int = int(charge_def(str(c["charge"])).get("severity", 2))
	c["lawyer_skill"] = float(L.get("public_skill", 0.3))
	c["lawyer_name"] = "a public defender"
	var tiers: Array = L.get("private", [])
	var best: Dictionary = {}
	for t in tiers:
		if CrimePerson.coins(pid) >= int(t["fee"]) * 2 or (CrimePerson.coins(pid) >= int(t["fee"]) and sev >= 4):
			best = t
	if best.is_empty():
		return
	if CrimePerson.is_player(pid):
		JusticePlayer.ask(pid, "A lawyer", "%s needs a lawyer. The public defender is free but overworked. %s costs %d coins." % [CrimePerson.name_of(pid), str(best["label"]), int(best["fee"])],
			[{"id": "private", "label": "Hire %s (%d coins)" % [best["label"], int(best["fee"])]}, {"id": "public", "label": "Public defender (free)"}],
			_lawyer_choice.bind(c, best), "private" if sev >= 3 else "public")
	elif sev >= 2 or CrimePerson.coins(pid) > int(best["fee"]) * 4:
		_hire(c, best)

static func _lawyer_choice(ch, c: Dictionary, tier: Dictionary) -> void:
	if str(ch) == "private":
		_hire(c, tier)

static func _hire(c: Dictionary, tier: Dictionary) -> void:
	CrimePerson.pay(int(c["accused"]), int(tier["fee"]), "lawyer")
	c["lawyer_skill"] = float(tier["skill"])
	c["lawyer_name"] = str(tier["label"])
	# a real townie lawyer lends their own skill when there is one
	for lp in CrimePerson.townies_only():
		if CrimePerson.career(lp) == "lawyer" and lp != int(c["accused"]):
			c["lawyer_skill"] = maxf(float(c["lawyer_skill"]) - 0.1, 0.0) + 0.04 * float(CrimePerson.rec(lp).get("level", 1))
			c["lawyer_name"] = CrimePerson.name_of(lp)
			CrimePerson.add_coins(lp, int(int(tier["fee"]) / 2), "legal fees")
			break

# ------------------------------------------------------------------ plea deal
## Offered on the day of the trial. Returns true when the accused pleads guilty.
static func offer_plea(c: Dictionary) -> bool:
	var pid: int = int(c["accused"])
	if bool(c.get("deal", false)):
		return true                                      # named the crew for a lighter sentence (task 21)
	var strength: float = CaseEvidence.strength(pid, c)
	var guilty: bool = pid == int(c["culprit"])
	var p: float = clampf((strength - 0.4) * 1.5, 0.0, 0.8) if guilty else 0.03
	if CrimePerson.is_player(pid):
		var done: Array = [false]
		var sev_txt: String = "A guilty plea means a lighter sentence. A trial could go either way."
		JusticePlayer.ask(pid, "Plea deal", "%s is offered a deal: plead guilty to %s for a lighter sentence. %s" % [CrimePerson.name_of(pid), str(charge_def(str(c["charge"])).get("label", "the charge")).to_lower(), sev_txt],
			[{"id": "plead", "label": "Plead guilty"}, {"id": "trial", "label": "Go to trial"}], func(ch): done[0] = str(ch) == "plead", "plead" if (guilty and strength > 0.8) else "trial")
		return bool(done[0])
	return JusticeState.chance(p)