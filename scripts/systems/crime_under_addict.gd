class_name CrimeUnderAddict
extends RefCounted
## Task 23: ADDICTION to the fictional street substances (data/crimeunder.json "deal.substances"). An addict (townie or a player's folk) has a level
## 0..1: it climbs with every dose and falls when doses are missed. Effects: cravings, highs and crashes as moods; a money drain (a dose a day costs
## real coins); a slow frailty; an overdose risk that rises with level and frailty (hospital, sometimes worse); lost work; desperate petty theft
## (townies). REHAB at the clinic (a few days away and a fee) lowers the level, with a relapse risk afterwards, higher when a dealer still has their number.
## Tier: the addicts table is small and tracked; the daily pass loops only it (townies statistically, a player's folk with moods and bills).
## No substance has a recipe or a process: "a supplier", "a dose".

static func cfg() -> Dictionary:
	return CrimeUnderState.sect("addict")

static func substance(id: String) -> Dictionary:
	return (CrimeUnderState.sect("deal").get("substances", {}) as Dictionary).get(id, {})

static func substances() -> Array:
	var out: Array = (CrimeUnderState.sect("deal").get("substances", {}) as Dictionary).keys()
	out.sort()
	return out

static func rec(pid: int) -> Dictionary:
	return CrimeUnderState.addicts.get(pid, {})

static func is_addict(pid: int) -> bool:
	return CrimeUnderState.addicts.has(pid) and str(rec(pid).get("state", "using")) != "clean"

static func level(pid: int) -> float:
	return float(rec(pid).get("level", 0.0))

static func hooked(pid: int) -> bool:
	return is_addict(pid) and level(pid) >= float(cfg().get("hooked_at", 0.45))

static func count_using() -> int:
	var n: int = 0
	for pid in CrimeUnderState.addicts:
		if str(CrimeUnderState.addicts[pid].get("state", "using")) == "using":
			n += 1
	return n

static func adult_townies() -> int:
	var n: int = 0
	for tid in CrimePerson.townies_only():
		if CrimePerson.is_adult(tid):
			n += 1
	return n

# ------------------------------------------------------------------ onset
static func onset_chance(pid: int, sub: String) -> float:
	var k: Dictionary = cfg()
	var p: float = float(substance(sub).get("onset", 0.06))
	for t in (k.get("onset_trait", {}) as Dictionary):
		if CrimePerson.has_trait(pid, str(t)):
			p *= float(k["onset_trait"][t])
	if CrimePerson.coins(pid) < 150:
		p *= float(k.get("onset_poor", 1.4))
	if CrimePressure.pressure(pid) > 0.4:
		p *= float(k.get("onset_stress", 1.3))
	if CrimePerson.in_custody(pid) or str(rec(pid).get("state", "")) == "using":
		return 0.0
	return minf(p, float(k.get("onset_cap", 0.3)))

## One buyer tries a substance. Returns true when they became an addict.
static func try_onset(pid: int, sub: String, dealer: int = -1, forced: bool = false) -> bool:
	if not CrimePerson.alive(pid) or not CrimePerson.is_adult(pid) or CrimeUnderState.addicts.size() >= int(cfg().get("cap", 60)):
		return false
	if not forced and not CrimeUnderState.chance(onset_chance(pid, sub)):
		return false
	var k: Dictionary = cfg()
	var old: Dictionary = rec(pid)
	var lv: float = CrimeUnderState.range_f(k.get("start_level", [0.15, 0.3]))
	CrimeUnderState.addicts[pid] = {"sub": sub, "level": maxf(lv, float(old.get("level", 0.0))), "frail": float(old.get("frail", 0.0)), "since": SysUtil.day(), "last_dose": SysUtil.day(), "state": "using",
		"rehab_until": -1, "clean_days": 0, "relapses": int(old.get("relapses", 0)), "dealer": dealer}
	CrimeUnderState.count("addicted")
	if CrimePerson.is_player(pid):
		SysUtil.notify("%s has started to need it. The cravings come sooner each time." % CrimePerson.name_of(pid), "warn")
	SysUtil.game_event("addiction_started", {"folk_id": pid, "substance": sub})
	return true

# ------------------------------------------------------------------ daily
static func on_day() -> void:
	var ids: Array = CrimeUnderState.addicts.keys()
	ids.sort()
	for pid in ids:
		day_of(int(pid))
	if SysUtil.day() % 7 == 0:
		_town_note()

static func day_of(pid: int) -> void:
	var r: Dictionary = rec(pid)
	if r.is_empty():
		return
	if not CrimePerson.alive(pid):
		CrimeUnderState.addicts.erase(pid)
		return
	var k: Dictionary = cfg()
	var state: String = str(r.get("state", "using"))
	if state == "rehab":
		_rehab_day(pid, r)
	elif state == "clean":
		_clean_day(pid, r)
	else:
		_use_day(pid, r, k)
	if not CrimeUnderState.addicts.has(pid):
		return
	_maybe_rehab_townie(pid, r, k)

static func _use_day(pid: int, r: Dictionary, k: Dictionary) -> void:
	var sub: Dictionary = substance(str(r["sub"]))
	var price: int = int(sub.get("dose_price", 24))
	var lv: float = float(r["level"])
	var wants: bool = CrimeUnderState.chance(float(k.get("dose_chance", 0.85)))
	var dosed: bool = false
	if wants and CrimePerson.coins(pid) >= price:
		var paid: int = CrimePerson.pay(pid, price, "a habit")
		dosed = paid >= price
		if dosed:                                      # the money goes to a supplier somewhere: a dealer on their number gets it
			var dl: int = int(r.get("dealer", -1))
			if dl >= 0 and CrimeUnderState.dealers.has(dl):
				CrimePerson.add_coins(dl, paid, "a sale")
	if dosed:
		r["level"] = minf(lv + float(k.get("level_dose", 0.025)), float(k.get("level_cap", 1.0)))
		r["last_dose"] = SysUtil.day()
		r["frail"] = float(r.get("frail", 0.0)) + float(k.get("frail_day", 0.006)) * float(sub.get("harm", 1.0)) * (0.5 + lv)
	else:
		r["level"] = maxf(lv + float(k.get("level_miss", -0.035)), 0.0)
		r["frail"] = maxf(float(r.get("frail", 0.0)) + float(k.get("frail_heal", -0.004)), 0.0)
		if lv >= float(k.get("desperate_at", 0.5)):
			_desperate(pid, k)
	_moods(pid, dosed, lv, k)
	_overdose(pid, dosed, r, k)
	if not CrimeUnderState.addicts.has(pid):
		return
	if float(r["level"]) < 0.05 and not dosed:
		r["state"] = "clean"                           # drifted off it without help
		r["clean_days"] = 0
	if float(r["level"]) >= float(k.get("job_loss_level", 0.7)) and not CrimePerson.is_player(pid) and CrimePerson.has_job(pid) and CrimeUnderState.chance(float(k.get("job_loss_daily", 0.01))):
		Story.townies[pid].erase("career")
		CrimeUnderState.count("addict_lost_job")

static func _moods(pid: int, dosed: bool, lv: float, k: Dictionary) -> void:
	var f = CrimePerson.folk(pid)
	if f == null or not CrimeUnderState.chance(float(k.get("mood_chance", 0.5))):
		return
	var moods: Array = k.get("mood", ["craving", "high", "crash"])
	if dosed:
		f.add_buff(str(moods[1]) if CrimeUnderState.chance(0.6) else str(moods[2]))
	else:
		f.add_buff("withdrawal" if lv >= 0.6 else str(moods[0]))

static func _desperate(pid: int, k: Dictionary) -> void:
	if CrimePerson.is_player(pid) or not CrimeUnderState.chance(float(k.get("desperate_theft", 0.06))):
		return
	var t: Dictionary = CrimeLifeJobs.pick_target(pid, "pickpocket")
	if not t.is_empty():
		CrimeLifeJobs.run(pid, "pickpocket", t, {"statistical": true})
		CrimeUnderState.count("addict_theft")

static func _overdose(pid: int, dosed: bool, r: Dictionary, k: Dictionary) -> void:
	if not dosed:
		return
	var o: Dictionary = k.get("overdose", {})
	var p: float = (float(o.get("base", 0.0009)) + float(o.get("level", 0.012)) * float(r["level"]) * float(r["level"])) * (1.0 + float(o.get("frail", 0.5)) * float(r.get("frail", 0.0)))
	p *= float(substance(str(r["sub"])).get("harm", 1.0)) * Incidents.surprise_mult()
	if not CrimeUnderState.chance(p):
		return
	CrimeUnderState.count("overdose")
	var dies: bool = CrimeUnderState.chance(float(o.get("death", 0.18)) * (1.0 + float(r.get("frail", 0.0))))
	if dies:
		CrimeUnderState.count("overdose_death")
		CrimeUnderState.addicts.erase(pid)
		Aging.kill(pid, "overdose")
		return
	Hospital.admit(pid, int(o.get("severity", 2)), "overdose")
	r["level"] = maxf(float(r["level"]) - 0.1, 0.0)
	if CrimePerson.is_player(pid):
		SysUtil.notify("%s collapsed and was rushed to hospital. This could have been the end." % CrimePerson.name_of(pid), "bad")
	SysUtil.game_event("overdosed", {"folk_id": pid})

# ------------------------------------------------------------------ rehab
static func rehab_cfg() -> Dictionary:
	return cfg().get("rehab", {})

## Command: the addict goes to the clinic. Folk: away for a few days and a fee; townies: statistical.
static func rehab(pid: int) -> Dictionary:
	var r: Dictionary = rec(pid)
	var rc: Dictionary = rehab_cfg()
	if r.is_empty() or str(r.get("state", "")) != "using":
		return {"ok": false, "msg": "Not needed."}
	var fee: int = int(rc.get("fee", 160))
	if CrimePerson.coins(pid) < fee:
		return {"ok": false, "msg": "The clinic wants %d coins up front." % fee}
	var f = CrimePerson.folk(pid)
	var days: int = int(rc.get("days", 3))
	if f != null and CrimePerson.is_player(pid):
		if SysUtil.is_away(f) or CrimePerson.in_custody(pid):
			return {"ok": false, "msg": "Not right now."}
		if not Away.send(f, float(days) * 1440.0, "rehab", {"label": "At the clinic"}):
			return {"ok": false, "msg": "Not right now."}
	CrimePerson.pay(pid, fee, "the clinic")
	r["state"] = "rehab"
	r["rehab_until"] = SysUtil.day() + days
	CrimeUnderState.count("rehab_started")
	return {"ok": true, "msg": "%s checks in at the clinic." % CrimePerson.name_of(pid)}

static func _rehab_day(pid: int, r: Dictionary) -> void:
	if SysUtil.day() < int(r.get("rehab_until", 0)):
		return
	var rc: Dictionary = rehab_cfg()
	var p: float = float(rc.get("success", 0.45)) + (0.06 if CrimePerson.has_trait(pid, "ambitious") else 0.0)          # willpower is a nature and support, not a skill - float(r["level"]) * 0.3 + (float(rc.get("support", 0.12)) if not CrimePerson.close_alive(pid).is_empty() else 0.0)
	if CrimePerson.has_trait(pid, "stubborn"):
		p += 0.08
	if CrimeUnderState.chance(clampf(p, 0.05, 0.95)):
		r["level"] = float(r["level"]) * (1.0 - float(rc.get("level_cut", 0.55)))
		r["state"] = "clean"
		r["clean_days"] = 0
		CrimeUnderState.count("rehab_success")
		var f = CrimePerson.folk(pid)
		if f != null:
			f.add_buff("in_recovery")
		if CrimePerson.is_player(pid):
			SysUtil.notify("%s leaves the clinic clean, and knows how fragile that is." % CrimePerson.name_of(pid), "good")
	else:
		r["state"] = "using"
		CrimeUnderState.count("rehab_failed")
		if CrimePerson.is_player(pid):
			SysUtil.notify("The stay at the clinic did not take. %s is back where %s started." % [CrimePerson.name_of(pid), "they"], "warn")

static func _clean_day(pid: int, r: Dictionary) -> void:
	var rc: Dictionary = rehab_cfg()
	r["clean_days"] = int(r.get("clean_days", 0)) + 1
	r["frail"] = maxf(float(r.get("frail", 0.0)) + float(cfg().get("frail_heal", -0.004)) * 2.0, 0.0)
	var dealer: bool = _dealer_has_number(pid)
	var p: float = float(rc.get("relapse_daily", 0.012)) * (float(rc.get("relapse_dealer", 2.0)) if dealer else 1.0) * (1.0 + float(r["level"]))
	if CrimeUnderState.chance(p):
		r["state"] = "using"
		r["level"] = maxf(float(r["level"]), 0.3)
		r["relapses"] = int(r.get("relapses", 0)) + 1
		CrimeUnderState.count("relapse")
		if CrimePerson.is_player(pid):
			SysUtil.notify("%s slipped. One dose, and the whole thing starts again." % CrimePerson.name_of(pid), "warn")
	elif int(r["clean_days"]) >= int(rc.get("relapse_days", 30)):
		CrimeUnderState.addicts.erase(pid)             # recovered
		CrimeUnderState.count("recovered")
		if CrimePerson.is_player(pid):
			SysUtil.notify("%s has been clean for a month." % CrimePerson.name_of(pid), "good")
		ChronicleHook.note("recovery", "%s has beaten an addiction." % CrimePerson.name_of(pid), [pid], "", 1, false)

static func _dealer_has_number(pid: int) -> bool:
	for dl in CrimeUnderState.dealers:
		if (CrimeUnderState.dealers[dl].get("customers", []) as Array).has(pid):
			return true
	return false

## Townies go to rehab on their own (friends and family push, money permitting).
static func _maybe_rehab_townie(pid: int, r: Dictionary, k: Dictionary) -> void:
	if CrimePerson.is_player(pid) or str(r.get("state", "")) != "using":
		return
	var rc: Dictionary = rehab_cfg()
	if float(r["level"]) < float(rc.get("townie_min_level", 0.35)) or CrimePerson.coins(pid) < int(rc.get("fee", 160)):
		return
	var push: float = 1.0 + float(CrimePerson.close_alive(pid).size()) * float(k.get("friend_help", 0.05)) * 10.0
	if CrimeUnderState.chance(float(rc.get("townie_daily", 0.03)) * push):
		rehab(pid)

static func _town_note() -> void:
	var share: float = float(count_using()) / float(maxi(adult_townies(), 1))
	if share >= float(cfg().get("town_cap_share", 0.1)):
		ChronicleHook.note("addiction", "Worry grows about how many in town are caught up in the street substances.", [], "", 2, true)

## Daily dice for a far townie: nothing (addicts are handled in on_day). Kept for symmetry with the other modules.
static func summary(pid: int) -> Dictionary:
	var r: Dictionary = rec(pid)
	if r.is_empty():
		return {}
	return {"substance": str(substance(str(r["sub"])).get("label", "")), "level": level(pid), "state": str(r.get("state", "")), "relapses": int(r.get("relapses", 0))}
