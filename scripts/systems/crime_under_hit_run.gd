class_name CrimeUnderHitRun
extends RefCounted
## Task 23: the hitman's side of a contract: take or refuse, research the target's routine (CrimePlace whereabouts), pick an opportunity, execute (an
## abstracted event through CrimeMurder.kill: witnesses, cameras, police, the family's revenge), and the ways out: botched, tipped off. The same
## `resolve` serves the player's folk (after timed work through CrimeLifeState.pending) and the townie hitmen (CrimeUnderHit._npc_work).

static func cfg() -> Dictionary:
	return CrimeUnderHit.cfg()

static func ex() -> Dictionary:
	return cfg().get("execute", {})

# ------------------------------------------------------------------ the player's side (commands)
static func take(pid: int, cid: int) -> Dictionary:
	var c: Dictionary = CrimeUnderHit.get_contract(cid)
	if c.is_empty() or str(c["state"]) != "open":
		return {"ok": false, "msg": "That contract is gone."}
	if not CrimeUnderLines.has(pid, "hit"):
		return {"ok": false, "msg": "Nobody hands contracts to an outsider."}
	if CrimePerson.is_player(int(c["target"])) or int(c["target"]) == pid or int(c["client"]) == pid:
		return {"ok": false, "msg": "Not that one."}
	if not CrimePerson.alive(int(c["target"])) or CrimePerson.in_custody(pid):
		return {"ok": false, "msg": "Not right now."}
	c["hitman"] = pid
	c["state"] = "taken"
	c["taken_day"] = SysUtil.day()
	c["npc"] = false
	CrimeUnderState.count("contract_taken_player")
	return {"ok": true, "msg": "%s takes the contract on %s." % [CrimePerson.name_of(pid), CrimePerson.name_of(int(c["target"]))], "contract": cid}

static func refuse(pid: int, cid: int) -> Dictionary:
	var c: Dictionary = CrimeUnderHit.get_contract(cid)
	if c.is_empty() or not str(c["state"]) in ["open", "taken"]:
		return {"ok": false, "msg": "That contract is gone."}
	if str(c["state"]) == "taken" and int(c["hitman"]) != pid:
		return {"ok": false, "msg": "That is not yours."}
	var r: Dictionary = cfg().get("refuse", {})
	if str(c["state"]) == "taken":
		c["state"] = "open"
		c["hitman"] = -1
		c["research"] = 0.0
	var list: Array = SysUtil.to_ints(c.get("refused_by", []))
	if not list.has(pid):
		list.append(pid)
	c["refused_by"] = list
	CrimeLifePath.add_cred(pid, float(r.get("cred", -1.5)), "refused")
	CrimeUnderLines.add_standing(pid, "hit", float(r.get("standing", -0.5)))
	CrimeUnderState.count("contract_refused")
	if CrimePerson.has_trait(pid, "honest") or CrimePerson.has_trait(pid, "empath"):
		CrimeUnderRep.deed(pid, "mercy")
	return {"ok": true, "msg": "%s turns the contract down." % CrimePerson.name_of(pid)}

## Timed research (the folk is out for `minutes`); `session` is the instant version used when it ends and by tests.
static func research(pid: int, cid: int) -> Dictionary:
	var c: Dictionary = CrimeUnderHit.get_contract(cid)
	var f = CrimePerson.folk(pid)
	if c.is_empty() or int(c["hitman"]) != pid or str(c["state"]) != "taken" or f == null or SysUtil.is_away(f) or CrimePerson.in_custody(pid):
		return {"ok": false, "msg": "Not right now."}
	var mins: int = int(cfg().get("research", {}).get("minutes", 120))
	Away.send(f, float(mins), "errand", {"label": "Watching someone"})
	CrimeLifeState.queue({"kind": "hit_research", "pid": pid, "contract": cid, "due_min": SysUtil.now() + mins})
	return {"ok": true, "msg": "%s goes to learn %s's habits." % [f.name, CrimePerson.name_of(int(c["target"]))]}

static func session(pid: int, c: Dictionary) -> Dictionary:
	var k: Dictionary = cfg().get("research", {})
	var gain: float = CrimeUnderState.range_f(k.get("gain", [0.2, 0.34])) + float(k.get("stealth_gain", 0.03)) * float(CrimeLifePath.skill(pid, "stealth"))
	c["research"] = clampf(float(c["research"]) + gain, 0.0, 1.0)
	c["research_day"] = SysUtil.day()
	CrimeLifePath.train(pid, "stealth", 3.0)
	var spotted: bool = CrimeUnderState.chance(float(k.get("spotted", 0.08)) * (1.0 - 0.07 * float(CrimeLifePath.skill(pid, "stealth"))))
	if spotted:
		c["mistakes"] = int(c["mistakes"]) + 1
		var m: Dictionary = CrimeLifePath.member(pid)
		if not m.is_empty():
			m["heat"] = float(m.get("heat", 0.0)) + float(k.get("spotted_heat", 2.0))
	if CrimePerson.is_player(pid):
		SysUtil.notify("%s learned %s's routine: %s.%s" % [CrimePerson.name_of(pid), CrimePerson.name_of(int(c["target"])), word(float(c["research"])), " Somebody may have noticed." if spotted else ""], "warn" if spotted else "info")
	return {"research": float(c["research"]), "spotted": spotted}

static func word(r: float) -> String:
	if r < 0.25:
		return "next to nothing"
	if r < 0.5:
		return "where they are most days"
	if r < 0.8:
		return "when they are alone"
	return "every habit they have"

## Where and when the target can be found, gated by what the research found out. [{scene, label, alone, hour}]
static func opportunities(pid: int, cid: int) -> Array:
	var c: Dictionary = CrimeUnderHit.get_contract(cid)
	if c.is_empty():
		return []
	var t: int = int(c["target"])
	var r: float = float(c["research"])
	var cap: int = 1 if r < 0.25 else (2 if r < 0.5 else 4)
	var seen: Dictionary = {}
	var out: Array = []
	var now: int = SysUtil.now()
	var scenes: Array = [CrimePlace.where_now(t)]
	for h in range(1, 25):
		scenes.append(CrimePlace.where_was(t, now - h * 60))
	for i in scenes.size():
		var s: String = str(scenes[i])
		if s in ["unknown", "away", "work", ""]:
			s = CrimePerson.home_key(t)
		if seen.has(s):
			continue
		seen[s] = true
		var others: int = 0
		for o in CrimePerson.everyone():
			if o != t and o != pid and CrimePlace.where_now(o) == s:
				others += 1
		out.append({"scene": s, "label": CaseStore.house_label(s) if s.begins_with("home:") or s.begins_with("town:") else s, "alone": others == 0 and not s.begins_with("venue:") and s != "street",
			"hour": int(((now - i * 60) % 1440) / 60)})
		if out.size() >= cap:
			break
	return out

static func execute(pid: int, cid: int, scene: String) -> Dictionary:
	var c: Dictionary = CrimeUnderHit.get_contract(cid)
	var f = CrimePerson.folk(pid)
	if c.is_empty() or int(c["hitman"]) != pid or str(c["state"]) != "taken" or f == null or SysUtil.is_away(f) or CrimePerson.in_custody(pid):
		return {"ok": false, "msg": "Not right now."}
	if scene == "":
		var ops: Array = opportunities(pid, cid)
		scene = str(ops[0]["scene"]) if not ops.is_empty() else CrimePerson.home_key(int(c["target"]))
	var mins: int = int(ex().get("minutes", 90))
	Away.send(f, float(mins), "errand", {"label": "Out on a contract"})
	CrimeLifeState.queue({"kind": "hit_exec", "pid": pid, "contract": cid, "scene": scene, "due_min": SysUtil.now() + mins})
	return {"ok": true, "msg": "%s slips out." % f.name}

# ------------------------------------------------------------------ the act
## Odds of pulling it off for this hitman at this contract (0..1) and the parts for the player to read.
static func odds(pid: int, c: Dictionary, scene: String, alone: bool) -> Dictionary:
	var e: Dictionary = ex()
	var skill: float = CrimeLifePath.skill_score(pid, {"stealth": 1.0, "fitness": 0.4, "logic": 0.3})
	var gear: float = 0.0
	for g in ["gloves", "disguise", "burner"]:
		if CrimeLifeRoll.has_gear(pid, str(g)):
			gear += 1.0 / 3.0
	var heat: float = float(CrimeLifePath.member(pid).get("heat", 0.0))
	var r: float = float(c["research"])
	var pull: float = float(e.get("base", 0.5)) + float(e.get("research", 0.34)) * r + float(e.get("skill", 0.18)) * skill + (float(e.get("alone", 0.08)) if alone else 0.0) \
		+ float(e.get("gear", 0.08)) * gear - float(e.get("heat", 0.01)) * heat - 0.04 * float(c["mistakes"])
	if scene.begins_with("biz:") or scene.begins_with("home:") or scene.begins_with("town:"):
		pull -= float(CrimeSecurity.effects(CrimeSecurity.profile_for(scene))["difficulty"]) * 0.5
	return {"pull": clampf(pull, float(e.get("min", 0.08)), float(e.get("max", 0.95))), "research": r, "skill": skill, "gear": gear, "alone": alone}

## Resolve a contract now. opts: protect (0..1 cut to the odds), force ("clean"|"seen"|"botched"), alone. Returns {outcome, case, paid}.
static func resolve(pid: int, c: Dictionary, scene: String, opts: Dictionary = {}) -> Dictionary:
	var e: Dictionary = ex()
	var target: int = int(c["target"])
	var res: Dictionary = {"outcome": "none", "case": -1, "paid": 0}
	if not CrimePerson.alive(target) or not CrimePerson.alive(pid):
		c["state"] = "failed"
		return res
	var alone: bool = bool(opts.get("alone", false))
	var o: Dictionary = odds(pid, c, scene, alone)
	var pull: float = float(o["pull"]) * (1.0 - float(opts.get("protect", 0.0)))
	var outcome: String = str(opts.get("force", ""))
	if outcome == "":
		outcome = "botched" if not CrimeUnderState.chance(pull) else ("seen" if CrimeUnderState.chance(float(e.get("seen_extra", 0.18)) * (1.0 - float(c["research"]) * 0.7)) else "clean")
	res["outcome"] = outcome
	res["odds"] = o
	var m: Dictionary = CrimeLifePath.member(pid)
	CrimeLifePath.train(pid, "stealth", float(e.get("xp", 18)) * (1.0 if outcome != "botched" else 0.4))
	if outcome == "botched":
		_botched(pid, c, scene, res, bool(opts.get("police", false)))
		return res
	var cs: Dictionary = _kill(pid, c, scene, outcome == "seen")
	res["case"] = int(cs.get("id", -1))
	c["case"] = int(cs.get("id", -1))
	c["state"] = "done"
	c["seen"] = bool(cs.get("witnessed", false))
	var fee: int = int(c["fee"])
	if bool(c["cond"]["quiet"]) and bool(cs.get("witnessed", false)):
		fee = fee / 2                                    # the client wanted it quiet
	res["paid"] = _pay(pid, int(c["client"]), fee)
	CrimeUnderState.count("contract_done")
	if not m.is_empty():
		m["heat"] = float(m.get("heat", 0.0)) + 6.0 * (1.5 if outcome == "seen" else 0.8)
		m["jobs"] = int(m.get("jobs", 0)) + 1
		m["last_job_day"] = SysUtil.day()
		CrimeLifePath.add_cred(pid, float(e.get("cred", 6.0)) * (0.7 if outcome == "seen" else 1.0), "contract")
	CrimeUnderLines.add_standing(pid, "hit", float(e.get("standing", 4.0)))
	CrimeLifeMoral.after_crime(pid, target, "murder", 0, cs)
	CrimeUnderRep.deed(pid, "kill")
	_family_revenge(pid, c, cs)
	SysUtil.game_event("contract_done", {"folk_id": pid, "target_id": target, "contract": int(c["id"]), "case": int(cs.get("id", -1))})
	return res

## The killing through 04's flow. Research quiets the scene (fewer witnesses); mistakes and a thin disguise leave traces.
static func _kill(pid: int, c: Dictionary, scene: String, seen_forced: bool) -> Dictionary:
	var e: Dictionary = ex()
	var mcfg: Dictionary = JusticeState.sect("murder")
	var old: Dictionary = {}
	var cut: float = 1.0 - float(e.get("witness_cut", 0.7)) * float(c["research"])
	for kk in ["witness_public", "witness_home", "witness_alone"]:
		old[kk] = mcfg.get(kk, 0.0)
		mcfg[kk] = float(mcfg.get(kk, 0.0)) * cut + (0.9 if seen_forced else 0.0)
	var cs: Dictionary = CrimeMurder.kill(pid, int(c["target"]), scene, "murder", {})
	for kk2 in old:
		mcfg[kk2] = old[kk2]
	cs["contract"] = int(c["id"])
	cs["hired_by"] = int(c["client"])
	cs["charge_hint"] = "murder"
	var tm: float = clampf(float(e.get("trace_base", 1.0)) - float(e.get("trace_research", 0.55)) * float(c["research"]) + float(e.get("trace_mistake", 0.3)) * float(c["mistakes"]), 0.2, 2.2)
	cs["trace"] = clampf(float(cs.get("trace", 0.3)) * tm, 0.02, 0.95)
	if scene.begins_with("biz:") or scene.begins_with("town:") or scene.begins_with("home:"):
		CrimeSecurityFootage.capture(cs, scene, pid, CrimeLifeRoll.has_gear(pid, "disguise"), CrimeLifeRoll.has_gear(pid, "tools"))
	return cs

static func _pay(hitman: int, client: int, fee: int) -> int:
	var paid: int = CrimePerson.pay(client, fee, "a contract") if client >= 0 else fee
	if paid > 0:
		CrimePerson.add_coins(hitman, paid, "a contract")
	return paid

static func _botched(pid: int, c: Dictionary, scene: String, res: Dictionary, police: bool) -> void:
	var e: Dictionary = ex()
	var target: int = int(c["target"])
	c["state"] = "botched"
	c["mistakes"] = int(c["mistakes"]) + 2
	CrimeUnderState.count("contract_botched")
	var m: Dictionary = CrimeLifePath.member(pid)
	if not m.is_empty():
		m["heat"] = float(m.get("heat", 0.0)) + 4.0
	CrimeUnderLines.add_standing(pid, "hit", float(e.get("botch_standing", -2.0)))
	CrimeLifePath.add_cred(pid, -2.0, "botched")
	var f = CrimePerson.folk(target)
	if f != null and CrimeUnderState.chance(float(e.get("botch_hurt", 0.5))):
		Health.injure(f, int(cfg().get("attack", {}).get("hurt_severity", 2)), "an attack")
	if CrimePerson.is_player(target):
		SysUtil.notify("Someone tried to kill %s and failed. The police are being called." % CrimePerson.name_of(target), "bad")
	# a failed attempt is still a crime: an assault case, charged as attempted murder
	var cs: Dictionary = CaseStore.create("assault", pid, target, scene, {"witnessed": true, "witnesses": [target], "witness_clarity": 0.4 * (1.0 - float(c["research"])), "trace": 0.5})
	cs["severity"] = 2
	cs["charge_hint"] = "attempted_murder"
	cs["contract"] = int(c["id"])
	cs["hired_by"] = int(c["client"])
	cs["state"] = "open"
	cs["disc_day"] = SysUtil.day()
	res["case"] = int(cs["id"])
	c["case"] = int(cs["id"])
	if police and CrimeUnderState.chance(0.5):
		JusticeProcess.arrest(cs, pid)
	elif CrimePerson.is_player(target):
		Police.respond(cs, 10)

static func _family_revenge(pid: int, c: Dictionary, cs: Dictionary) -> void:
	var p: float = float(cfg().get("family_revenge", 0.5))
	var victim: int = int(c["target"])
	var kin: Array = CrimePerson.close_alive(victim)
	var against: int = -1
	if bool(cs.get("witnessed", false)) and float(cs.get("witness_clarity", 0.0)) >= 0.5:
		against = pid
	elif CrimeUnderState.chance(float(cfg().get("rumour_client", 0.35))) and int(c["client"]) >= 0 and CrimeMurder.rage_of(int(c["client"]), victim) >= 30.0:
		against = int(c["client"])
	if against < 0:
		return
	for a in kin:
		var av: int = int(a)
		if av == against or CrimePerson.is_player(av) or not CrimePerson.is_adult(av):
			continue
		if CrimeUnderState.chance(p * 0.3) and not CrimeRevenge._exists(av, against):
			CrimeRevenge.start(av, against, int(cs["id"]))
			CrimeUnderState.count("hit_family_revenge")
			return

# ------------------------------------------------------------------ townies
## A townie hitman acts on the day the research is done.
static func npc_act(c: Dictionary) -> void:
	var pid: int = int(c["hitman"])
	var target: int = int(c["target"])
	var scene: String = CrimePlace.where_now(target)
	if scene in ["work", "away", "unknown"]:
		scene = CrimePerson.home_key(target)
	if CrimePerson.is_player(target):
		_attack_player(c, pid, scene)
		return
	if CrimePerson.in_custody(target) or Hospital.is_in(target):
		c["due_day"] = SysUtil.day() + 1            # wait for an opening
		return
	var res: Dictionary = resolve(pid, c, scene, {"alone": CrimeUnderState.chance(0.35)})
	if str(res["outcome"]) == "none":
		return

## The target is a player's folk: warning, counterplay (police, lie low, buy them off), then the odds with the protections.
static func _attack_player(c: Dictionary, pid: int, scene: String) -> void:
	var a: Dictionary = cfg().get("attack", {})
	var t: int = int(c["target"])
	if bool(c.get("choosing", false)):
		return
	c["choosing"] = true
	var price: int = int(float(c["fee"]) * float(a.get("bribe_mult", 1.2)))
	var text: String = "The person hired to hurt %s is close now. There is not much time." % CrimePerson.name_of(t)
	JusticePlayer.ask(t, "Someone is coming for you", text,
		[{"id": "police", "label": "Go to the police"}, {"id": "lie_low", "label": "Lie low at home"}, {"id": "pay", "label": "Pay them off (%d coins)" % price}, {"id": "ignore", "label": "Carry on as normal"}],
		func(ch): _attack_choice(str(ch), c, pid, scene, price), "ignore")

static func _attack_choice(ch: String, c: Dictionary, pid: int, scene: String, price: int) -> void:
	var a: Dictionary = cfg().get("attack", {})
	var t: int = int(c["target"])
	c["choosing"] = false
	var protect: float = 0.0
	var police: bool = false
	var guard: float = float(a.get("protect_guard", 0.25)) if int(CrimeLifeState.home_sec.get(CrimePerson.hid(t), {}).get("guard", 0)) > 0 else 0.0
	match ch:
		"police":
			protect = float(a.get("protect_police", 0.45))
			police = true
		"lie_low":
			protect = float(a.get("protect_lie_low", 0.3))
		"pay":
			if CrimePerson.coins(t) >= price:
				CrimePerson.pay(t, price, "paying off a contract")
				CrimePerson.add_coins(pid, price, "a pay-off")
				c["state"] = "bought_off"
				CrimeUnderState.count("contract_bought_off")
				SysUtil.notify("The money changed hands. The danger has gone away, for now.", "good")
				return
	protect = 1.0 - (1.0 - protect) * (1.0 - guard)
	var res: Dictionary = resolve(pid, c, scene, {"protect": protect, "police": police, "alone": ch == "ignore"})
	if str(res["outcome"]) == "none":
		c["state"] = "failed"

# ------------------------------------------------------------------ tipping the target off
static func tip(pid: int, cid: int) -> Dictionary:
	var c: Dictionary = CrimeUnderHit.get_contract(cid)
	if c.is_empty() or not str(c["state"]) in ["taken", "open"]:
		return {"ok": false, "msg": "Too late."}
	if str(c["state"]) == "taken" and int(c["hitman"]) != pid:
		return {"ok": false, "msg": "That is not yours."}
	var k: Dictionary = cfg().get("tip", {})
	var t: int = int(c["target"])
	var reward: int = mini(CrimeUnderState.range_i(k.get("reward", [120, 420])) + int(float(CrimePerson.coins(t)) * float(k.get("reward_wealth", 0.1))), CrimePerson.coins(t))
	c["state"] = "tipped"
	c["tipped_by"] = pid
	var paid: int = CrimePerson.pay(t, reward, "a warning") if CrimePerson.alive(t) else 0
	if paid > 0:
		CrimePerson.add_coins(pid, paid, "a reward")
	CrimePerson.add_buff_safe(t, str(k.get("friend_buff", "relieved")))
	CrimeLifePath.add_cred(pid, float(cfg().get("tip_cred", -14.0)) * (0.3 if not CrimeUnderState.chance(float(k.get("client_finds_out", 0.5))) else 1.0), "tipped")
	CrimeUnderRep.deed(pid, "mercy")
	if CrimeUnderState.chance(float(k.get("client_finds_out", 0.5)) * float(k.get("price_on_tipster", 0.25)) * 2.0) and int(c["client"]) >= 0 and CrimePerson.alive(int(c["client"])):
		var back: Dictionary = CrimeUnderHit.post(int(c["client"]), pid, "tipster")   # the client wants the tipster gone
		if not back.is_empty():
			c["tipster_contract"] = int(back["id"])
	CrimeUnderState.count("contract_tipped")
	if CrimePerson.is_player(t):
		SysUtil.notify("Someone slipped %s a warning: a contract was out on them. It has been dropped." % CrimePerson.name_of(t), "good")
	return {"ok": true, "msg": "%s warns %s and takes a reward (%d coins)." % [CrimePerson.name_of(pid), CrimePerson.name_of(t), paid], "paid": paid}

# ------------------------------------------------------------------ discovery reaches the client
## A hitman was charged: the client may be named (a conspiracy case follows). Called from JusticeProcess.file_charges via CrimeUnderFlow.
static func on_charged(c: Dictionary) -> void:
	var cid: int = int(c.get("contract", -1))
	if cid < 0 or bool(c.get("client_named", false)):
		return
	var con: Dictionary = CrimeUnderHit.get_contract(cid)
	var client: int = int(c.get("hired_by", -1))
	var pid: int = int(c.get("accused", -1))
	if con.is_empty() or client < 0 or pid != int(c["culprit"]) or not CrimePerson.alive(client) or CrimePerson.in_custody(client) or CrimePerson.is_player(client):
		return
	var p: float = float(cfg().get("conspiracy_link", 0.45)) * (0.5 if CrimePerson.has_trait(pid, "honest") else 1.0)
	if CrimePerson.is_player(pid):
		JusticePlayer.ask(pid, "The detectives' offer", "The police want to know who paid. Give them the client and %s's sentence gets lighter, but word will get round." % CrimePerson.name_of(pid),
			[{"id": "name", "label": "Name the client"}, {"id": "silent", "label": "Say nothing"}], func(ch): _name_client(c, pid, client, str(ch) == "name"), "silent")
	else:
		_name_client(c, pid, client, CrimeUnderState.chance(p))

static func _name_client(c: Dictionary, pid: int, client: int, named: bool) -> void:
	c["client_named"] = true
	if not named:
		CrimeLifePath.add_cred(pid, float(CrimeLifeState.sect("path").get("cred_caught_quiet", 4)), "silent")
		return
	c["deal"] = true
	var nc: Dictionary = CaseStore.create("conspiracy", client, int(c.get("victim", -1)), str(c["scene"]), {"witnessed": false, "trace": 0.5})
	nc["charge_hint"] = "conspiracy"
	nc["named_in"] = int(c["id"])
	nc["state"] = "open"
	nc["disc_day"] = SysUtil.day()
	nc["tips"] = 0.6
	CaseStore.note(c, "%s named the person who paid." % CrimePerson.name_of(pid))
	CrimeLifePath.add_cred(pid, float(CrimeLifeState.sect("snitch").get("deal_cred", -30)), "named_client")
	var m: Dictionary = CrimeLifePath.member(pid)
	if not m.is_empty():
		m["snitch"] = true
	CrimeUnderState.count("client_named")
	JusticeProcess.arrest(nc, client)
