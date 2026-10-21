class_name CrimeUnderGood
extends RefCounted
## Task 23, part 2: the good side, just as deep. COPS (a player's police officer or detective, or a townie one): CORRUPTION offers (take the bribe or
## not; a taken bribe protects the briber from stings and raids but grows the risk of INTERNAL AFFAIRS: an investigation that can clear, suspend, fire
## or charge them), STINGS on known dealers, UNDERCOVER work inside a gang (trust grows, evidence piles up, then a bust), and the HERO: stepping in to
## stop a crime in progress (risk of injury) or helping with a rescue; hero standing and the town's regard follow (CrimeUnderRep).
## Tier: the `cops` table only holds officers who ever took an offer; townie cops roll one dice a day (person_day). Everything else is a command.

static func cfg() -> Dictionary:
	return CrimeUnderState.sect("good")

static func is_cop(pid: int) -> bool:
	return CrimePerson.career(pid) in (cfg().get("bribe", {}).get("careers", ["police_officer", "detective"]) as Array)

static func rec(pid: int) -> Dictionary:
	return CrimeUnderState.cops.get(pid, {})

static func suspended(pid: int) -> bool:
	return int(rec(pid).get("suspended_until", -1)) >= SysUtil.day()

## 0..0.7: how much of the police attention a criminal dodges because of corrupt cops on the payroll (and a short informant immunity).
static func protection(pid: int) -> float:
	var cut: float = 0.0
	var b: float = float(cfg().get("bribe", {}).get("protects_dealer", 0.5))
	for cop in CrimeUnderState.cops:
		var c: Dictionary = CrimeUnderState.cops[cop]
		if (c.get("protecting", []) as Array).has(pid) and CrimePerson.alive(int(cop)) and not suspended(int(cop)) and not CrimePerson.in_custody(int(cop)):
			cut += b
	var inf: Dictionary = CrimeUnderState.informant.get(pid, {})
	if not inf.is_empty() and SysUtil.day() - int(inf.get("day", -999)) <= int(CrimeUnderState.sect("gang").get("informant", {}).get("immunity_days", 20)):
		cut += 0.6
	return clampf(cut, 0.0, 0.8)

# ------------------------------------------------------------------ bribes
## Who would pay a cop: dealers, gang bosses, racketeers (underworld people with something to protect).
static func clients() -> Array:
	var out: Array = []
	for pid in CrimeUnderState.dealers:
		out.append(int(pid))
	for gid in CrimeUnderState.gangs:
		out.append(int(CrimeUnderState.gangs[gid]["boss"]))
	for pid in CrimeUnderState.lines:
		if CrimeUnderLines.has(int(pid), "racket"):
			out.append(int(pid))
	var seen: Dictionary = {}
	var uniq: Array = []
	for p in out:
		if not seen.has(p) and CrimePerson.alive(p):
			seen[p] = true
			uniq.append(p)
	uniq.sort()
	return uniq

## An offer: the player's cop is asked; a townie cop decides by nature.
static func offer(cop: int, client: int, amount: int = -1) -> Dictionary:
	var b: Dictionary = cfg().get("bribe", {})
	if not CrimePerson.alive(cop) or not is_cop(cop) or suspended(cop) or CrimePerson.alive(client) == false or client == cop:
		return {"ok": false, "msg": "Not possible."}
	if amount < 0:
		amount = CrimeUnderState.range_i(b.get("amount", [90, 400]))
	if CrimePerson.is_player(cop):
		JusticePlayer.ask(cop, "A quiet offer", "%s slips an envelope across the table: %d coins, to look the other way when the time comes." % [CrimePerson.name_of(client), amount],
			[{"id": "take", "label": "Take it"}, {"id": "refuse", "label": "Turn it down"}], func(ch): decide(cop, client, amount, str(ch) == "take"), "refuse")
		return {"ok": true, "msg": "asked"}
	var p: float = float(b.get("townie_take", 0.45)) * (0.2 if CrimePerson.has_trait(cop, "honest") else 1.0) * (1.8 if CrimePerson.has_trait(cop, "dishonest") else 1.0) * (1.0 + CrimePressure.risk(cop))
	return decide(cop, client, amount, CrimeUnderState.chance(clampf(p, 0.01, 0.9)))

static func decide(cop: int, client: int, amount: int, take: bool) -> Dictionary:
	var b: Dictionary = cfg().get("bribe", {})
	if not take:
		var r0: Dictionary = CrimeUnderState.cops.get(cop, {"taken": 0, "corruption": 0.0, "protecting": [], "refused": 0})
		r0["refused"] = int(r0.get("refused", 0)) + 1
		CrimeUnderState.cops[cop] = r0
		CrimeUnderRep.deed(cop, "mercy")
		CrimeUnderRep.add_hero(cop, float(b.get("pride_refuse", 1.0)) * 0.5)
		CrimeUnderState.count("bribe_refused")
		return {"ok": true, "msg": "refused", "taken": false}
	var paid: int = CrimePerson.pay(client, amount, "a bribe")
	CrimePerson.add_coins(cop, paid, "a bribe")
	var r: Dictionary = CrimeUnderState.cops.get(cop, {"taken": 0, "corruption": 0.0, "protecting": [], "refused": 0})
	r["taken"] = int(r.get("taken", 0)) + 1
	r["corruption"] = float(r.get("corruption", 0.0)) + float(b.get("take_corruption", 1.0))
	var prot: Array = SysUtil.to_ints(r.get("protecting", []))
	if not prot.has(client):
		prot.append(client)
	r["protecting"] = prot
	CrimeUnderState.cops[cop] = r
	CrimeLifePath.add_cred(client, float(b.get("client_cred", 1.0)), "bought a cop")
	CrimeUnderRep.deed(cop, "betray")
	CrimeUnderState.count("bribe_taken")
	return {"ok": true, "msg": "taken", "taken": true, "paid": paid}

# ------------------------------------------------------------------ internal affairs
static func ia_risk(cop: int) -> float:
	var ia: Dictionary = cfg().get("ia", {})
	var r: Dictionary = rec(cop)
	return float(ia.get("base", 0.0)) + float(ia.get("per_bribe", 0.012)) * float(r.get("taken", 0)) * (1.0 + float(r.get("tips", 0.0)) * float(ia.get("tip_ia", 0.05)) * 20.0) + float(ia.get("rival_tip", 0.01)) * float(r.get("tips", 0.0))

static func on_day() -> void:
	var ia: Dictionary = cfg().get("ia", {})
	var ids: Array = CrimeUnderState.cops.keys()
	ids.sort()
	for pid in ids:
		var cop: int = int(pid)
		var r: Dictionary = CrimeUnderState.cops[pid]
		if not CrimePerson.alive(cop):
			CrimeUnderState.cops.erase(pid)
			continue
		if not r.get("ia", {}).is_empty() and str(r["ia"].get("state", "")) == "investigating":
			if SysUtil.day() - int(r["ia"].get("since", 0)) >= 5:
				_ia_verdict(cop, r, ia)
			continue
		r["corruption"] = maxf(float(r.get("corruption", 0.0)) - float(ia.get("decay_day", 0.0015)), 0.0)
		# a protected client who is arrested is a loose end that talks
		for cl in SysUtil.to_ints(r.get("protecting", [])):
			if CrimePerson.in_custody(cl) and CrimeUnderState.chance(0.05):
				r["tips"] = float(r.get("tips", 0.0)) + 1.0
		if int(r.get("taken", 0)) >= int(cfg().get("bribe", {}).get("min_taken_for_ia", 1)) and CrimeUnderState.chance(ia_risk(cop)):
			start_ia(cop)
	_cop_offers()

static func start_ia(cop: int) -> void:
	var r: Dictionary = CrimeUnderState.cops.get(cop, {})
	if r.is_empty() or not (r.get("ia", {}) as Dictionary).is_empty() and str(r["ia"].get("state", "")) == "investigating":
		return
	r["ia"] = {"since": SysUtil.day(), "state": "investigating"}
	CrimeUnderState.cops[cop] = r
	CrimeUnderState.count("ia_started")
	if CrimePerson.is_player(cop):
		JusticePlayer.tell(cop, "Internal Affairs", "Two officers from Internal Affairs want a word with %s about some money. It is going to be a long week." % CrimePerson.name_of(cop))

static func _ia_verdict(cop: int, r: Dictionary, ia: Dictionary) -> void:
	r["ia"] = {"since": SysUtil.day(), "state": "closed"}
	if CrimeUnderState.chance(float(ia.get("cleared", 0.2))):
		CrimeUnderState.count("ia_cleared")
		if CrimePerson.is_player(cop):
			SysUtil.notify("Internal Affairs found nothing they could prove. This time.", "info")
		return
	CrimeUnderState.count("ia_guilty")
	r["suspended_until"] = SysUtil.day() + int(ia.get("suspend_days", 10))
	var f = CrimePerson.folk(cop)
	if f != null and CrimePerson.is_player(cop):
		Careers.fire(f)
		SysUtil.notify("%s has been dismissed from the force." % CrimePerson.name_of(cop), "bad")
	elif Story.townies.has(cop):
		Story.townies[cop].erase("career")
	ChronicleHook.note("corruption", "%s was thrown off the force over bribes." % CrimePerson.name_of(cop), [cop], "", 3, true)
	if CrimeUnderState.chance(float(ia.get("convict", 0.5))):
		var c: Dictionary = CaseStore.create("racket", cop, -1, "street", {"witnessed": true, "trace": 0.8})
		c["charge_hint"] = str(ia.get("charge", "bribery"))
		c["state"] = "open"
		c["disc_day"] = SysUtil.day()
		CaseStore.note(c, "%s took bribes while on the force." % CrimePerson.name_of(cop), "arrest", 3)
		JusticeProcess.arrest(c, cop)
	r["protecting"] = []                                 # the protection is gone

## Daily for the player's cops: the underworld comes calling now and then.
static func _cop_offers() -> void:
	var b: Dictionary = cfg().get("bribe", {})
	var cl: Array = clients()
	if cl.is_empty():
		return
	for f in SysUtil.residents():
		var pid: int = int(f.id)
		if not is_cop(pid) or suspended(pid) or not CrimeUnderState.chance(float(b.get("daily", 0.015))):
			continue
		offer(pid, int(cl[CrimeUnderState.rng.randi_range(0, cl.size() - 1)]))

## A townie cop's daily dice (bucketed with the other per-person jobs).
static func person_day(pid: int) -> void:
	if CrimePerson.is_player(pid) or not is_cop(pid) or suspended(pid):
		return
	var b: Dictionary = cfg().get("bribe", {})
	if not CrimeUnderState.chance(float(b.get("townie_daily", 0.002))):
		return
	var cl: Array = clients()
	if not cl.is_empty():
		offer(pid, int(cl[CrimeUnderState.rng.randi_range(0, cl.size() - 1)]))

# ------------------------------------------------------------------ stings and undercover
## A police officer sets up a sting on a known dealer (needs a customer's tip: tips >= 1, or the dealer is a known seller).
static func sting(cop: int, dealer: int) -> Dictionary:
	var k: Dictionary = cfg().get("sting", {})
	if not is_cop(cop) or suspended(cop) or not CrimePerson.alive(dealer) or CrimePerson.in_custody(dealer) or CrimePerson.is_player(dealer):
		return {"ok": false, "msg": "Not possible."}
	var d: Dictionary = CrimeUnderDeal.rec(dealer)
	if d.is_empty() or CrimeUnderDeal.stock_total(dealer) <= 0:
		return {"ok": false, "msg": "That person is not selling right now."}
	var skill: float = CrimeLifePath.skill_score(cop, {"perception": 0.6, "manipulation": 0.4})          # task 54: playing a buyer
	var p: float = float(k.get("base", 0.35)) * (float(k.get("detective", 1.4)) if CrimePerson.career(cop) == "detective" else 1.0) + float(k.get("skill", 0.3)) * skill + float(d.get("tips", 0.0)) * 0.05 \
		- CrimeLifePath.skill_score(dealer, {"perception": 0.6, "manipulation": 0.4}) * 10.0 * 0.03 - CrimeUnderGood.protection(dealer) * 0.3
	if not CrimeUnderState.chance(clampf(p, 0.05, float(k.get("cap", 0.9)))):
		d["tips"] = float(d.get("tips", 0.0)) + 0.3
		return {"ok": true, "msg": "The dealer didn't bite.", "caught": false}
	CrimeUnderState.count("cop_sting")
	CrimeUnderDeal.arrest_for(dealer, "sting")
	CrimePerson.add_coins(cop, int(k.get("reward", 120)), "a commendation bonus")
	CrimeUnderRep.add_hero(cop, 1.5, "")
	return {"ok": true, "msg": "%s was arrested in the sting." % CrimePerson.name_of(dealer), "caught": true}

static func go_undercover(cop: int, gid: int) -> Dictionary:
	if not is_cop(cop) or suspended(cop) or CrimeUnderGang.get_gang(gid).is_empty() or CrimeUnderState.undercover.has(cop):
		return {"ok": false, "msg": "Not possible."}
	CrimeUnderState.undercover[cop] = {"gang": gid, "trust": 0.0, "evidence": 0.0, "day": SysUtil.day()}
	CrimeUnderGang.add_member(gid, cop, 0.0)             # inside as an associate
	return {"ok": true, "msg": "%s goes under, a new name and an old coat." % CrimePerson.name_of(cop)}

## The daily pass of every undercover officer: trust and evidence grow, cover can be blown, the bust follows enough evidence.
static func undercover_day() -> void:
	var u: Dictionary = cfg().get("undercover", {})
	var ids: Array = CrimeUnderState.undercover.keys()
	ids.sort()
	for pid in ids:
		var cop: int = int(pid)
		var r: Dictionary = CrimeUnderState.undercover[pid]
		var gid: int = int(r["gang"])
		if not CrimePerson.alive(cop) or CrimeUnderGang.get_gang(gid).is_empty():
			end_undercover(cop, "gone")
			continue
		r["trust"] = minf(float(r["trust"]) + float(u.get("trust_day", 0.07)), 1.0)
		r["evidence"] = minf(float(r["evidence"]) + float(u.get("evidence_day", 0.08)) * (0.4 + float(r["trust"])), 1.0)
		if CrimeUnderState.chance(float(u.get("exposed_daily", 0.02)) * (1.0 - float(r["trust"]) * 0.5)):
			var f = CrimePerson.folk(cop)
			if f != null:
				Health.injure(f, int(u.get("exposed_hurt", 2)), "a beating")
			if CrimePerson.is_player(cop):
				SysUtil.notify("%s's cover has been blown." % CrimePerson.name_of(cop), "bad")
			end_undercover(cop, "exposed")
			continue
		if float(r["evidence"]) >= float(u.get("bust_evidence", 0.7)) and not CrimePerson.is_player(cop):
			bust_from_cover(cop)

static func bust_from_cover(cop: int) -> int:
	var r: Dictionary = CrimeUnderState.undercover.get(cop, {})
	if r.is_empty():
		return 0
	var gid: int = int(r["gang"])
	CrimeUnderGang.remove(cop)
	var n: int = CrimeUnderGang.bust(gid)
	CrimePerson.add_coins(cop, int(cfg().get("undercover", {}).get("reward", 350)), "an undercover bonus")
	CrimeUnderRep.add_hero(cop, 3.0, "%s brought down a gang from the inside." % CrimePerson.name_of(cop))
	CrimeUnderState.undercover.erase(cop)
	CrimeUnderState.count("undercover_bust")
	return n

## The officer ends the operation: enough evidence = the arrests begin, else they pull out.
static func end_cover(cop: int) -> Dictionary:
	var r: Dictionary = CrimeUnderState.undercover.get(cop, {})
	if r.is_empty():
		return {"ok": false, "msg": "Not undercover."}
	if float(r["evidence"]) >= float(cfg().get("undercover", {}).get("bust_evidence", 0.7)):
		return {"ok": true, "msg": "The arrests begin before dawn.", "arrests": bust_from_cover(cop)}
	end_undercover(cop, "withdrawn")
	return {"ok": true, "msg": "%s pulls out. Not enough to act on." % CrimePerson.name_of(cop)}

static func end_undercover(cop: int, _why: String) -> void:
	CrimeUnderGang.remove(cop)
	CrimeUnderState.undercover.erase(cop)

# ------------------------------------------------------------------ the hero
## Step in on a crime in progress (a burglar still inside). Returns {ok, msg, won}.
static func intervene(pid: int, case_id: int) -> Dictionary:
	var h: Dictionary = cfg().get("hero", {})
	var c: Dictionary = CaseStore.get_case(case_id)
	var f = CrimePerson.folk(pid)
	if c.is_empty() or f == null or CrimePerson.in_custody(pid) or SysUtil.is_away(f) or not bool(c.get("on_scene", false)):
		return {"ok": false, "msg": "There is nothing to step into."}
	var culprit: int = int(c["culprit"])
	var fit: float = clampf(float(CrimePerson.skill(pid, "fitness")) / 10.0, 0.0, 1.0)
	var p: float = float(h.get("intervene_base", 0.45)) + float(h.get("fitness", 0.35)) * fit - 0.3 * CrimeLifePath.skill_score(culprit, {"fitness": 0.6, "stealth": 0.4})
	CrimeUnderState.count("hero_try")
	if CrimeUnderState.chance(clampf(p, 0.1, 0.9)):
		c["on_scene"] = false
		CrimeBurglary.end_scene(c, true)
		CrimeBurglary.restore_loot(c)
		c["recovered"] = true
		JusticeProcess.arrest(c, culprit)
		CrimeUnderRep.deed(pid, "heroic")
		CrimeUnderRep.add_hero(pid, float(h.get("rep", 3.0)), "%s stopped a crime in progress." % CrimePerson.name_of(pid))
		CrimeUnderState.count("hero_win")
		return {"ok": true, "msg": "%s held the intruder until the police came." % CrimePerson.name_of(pid), "won": true}
	if CrimeUnderState.chance(float(h.get("hurt", 0.3))):
		Health.injure(f, 1, "a scuffle")
	CrimeUnderRep.add_hero(pid, float(h.get("rep_fail", 0.5)))
	return {"ok": true, "msg": "%s tried to stop them but they got away." % CrimePerson.name_of(pid), "won": false}

static func on_rescue(helper: int) -> void:
	if helper >= 0 and CrimePerson.alive(helper):
		CrimeUnderRep.deed(helper, "heroic")
		CrimeUnderRep.add_hero(helper, float(cfg().get("hero", {}).get("rescue_rep", 4.0)), "%s pulled someone out of danger." % CrimePerson.name_of(helper))
		CrimeUnderState.count("hero_rescue")
