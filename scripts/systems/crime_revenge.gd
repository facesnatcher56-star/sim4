class_name CrimeRevenge
extends RefCounted
## Task 09c section 6: revenge chains. Victims and their families remember. When the culprit got off (not guilty, a very light sentence, or the
## case went cold for good), a vengeful or hot-headed relative starts a grudge chain that escalates: vandalism -> a fight -> (rarely) a murderous
## rage that the murder system then handles with its usual warnings. VIGILANTES (rare) go after convicted criminals in town.
## The chain ENDS by forgiveness (forgiving folk drop it fast), an apology, a later conviction, or when either side is gone.

static func cfg() -> Dictionary:
	return JusticeState.sect("revenge")

static func chains_for(avenger: int) -> Array:
	return JusticeState.revenge.filter(func(r): return int(r["avenger"]) == avenger)

static func active() -> Array:
	return JusticeState.revenge.filter(func(r): return str(r.get("state", "active")) == "active")

# ------------------------------------------------------------------ start
## The culprit of `c` escaped justice: relatives of the victim may start a chain.
static func on_escaped(c: Dictionary) -> int:
	var culprit: int = int(c["culprit"])
	var victim: int = int(c.get("victim", -1))
	if culprit < 0 or victim < 0 or not CrimePerson.alive(culprit):
		return 0
	var k: Dictionary = cfg()
	var started: int = 0
	var kin: Array = CrimePerson.close_ones(victim)
	if CrimePerson.alive(victim):
		kin.append(victim)                             # the victim themself may want payback
	for a in kin:
		var av: int = int(a)
		if av == culprit or not CrimePerson.alive(av) or CrimePerson.is_player(av) or not CrimePerson.is_adult(av):
			continue
		var p: float = float(k.get("base", 0.08))
		for t in k.get("traits", {}):
			if CrimePerson.has_trait(av, str(t)):
				p *= float(k["traits"][t])
		p *= 1.0 + float(int(JusticeProcess.charge_def(str(c.get("charge", c["kind"]))).get("severity", 1))) * 0.4
		if JusticeState.chance(minf(p, 0.95) * Incidents.surprise_mult()) and not _exists(av, culprit):
			start(av, culprit, int(c["id"]))
			started += 1
	return started

static func _exists(a: int, t: int) -> bool:
	for r in JusticeState.revenge:
		if int(r["avenger"]) == a and int(r["target"]) == t and str(r.get("state", "active")) == "active":
			return true
	return false

static func start(avenger: int, target: int, case_id: int) -> Dictionary:
	var id: int = 1
	for o in JusticeState.revenge:
		id = maxi(id, int(o["id"]) + 1)
	var r: Dictionary = {"id": id, "avenger": avenger, "target": target, "case": case_id, "level": 0, "since": SysUtil.day(), "state": "active"}
	JusticeState.revenge.append(r)
	while JusticeState.revenge.size() > 60:
		JusticeState.revenge.pop_front()
	JusticeState.count("revenge_chains")
	RelationshipService.add_value(avenger, target, "friendship", -20.0)
	RelationshipService.add_history(avenger, target, "wronged_family", -1.0, target)
	return r

# ------------------------------------------------------------------ daily
static func on_day() -> void:
	if not JusticeState.enabled:
		return
	var k: Dictionary = cfg()
	for r in JusticeState.revenge:
		if str(r.get("state", "active")) != "active":
			continue
		var a: int = int(r["avenger"])
		var t: int = int(r["target"])
		if not (CrimePerson.alive(a) and CrimePerson.alive(t)) or CrimePerson.in_custody(a):
			r["state"] = "ended"
			continue
		if Prison.is_inside(t):
			continue                                    # the target is locked away: the grudge waits
		# forgiveness
		var forgive: float = float(k.get("forgive_base", 0.004))
		if CrimePerson.has_trait(a, "forgiving"):
			forgive = float(k.get("forgive_forgiving", 0.08))
		if CrimePerson.has_trait(a, "empath") or CrimePerson.has_trait(a, "easygoing"):
			forgive *= 3.0
		if CrimePerson.has_trait(a, "vengeful"):
			forgive *= 0.1
		if JusticeState.chance(forgive):
			end(r, "forgave")
			continue
		r["level"] = int(r["level"]) + (2 if CrimePerson.has_trait(a, "vengeful") else 1)
		var lv: int = int(r["level"])
		if lv >= int(k.get("whisper_at", 4)) and not bool(r.get("whispered", false)):
			r["whispered"] = true
			for h in CrimePerson.friends(a).slice(0, 2) + CrimePerson.friends(t).slice(0, 2):
				RelationshipKnowledge.add_gossip(int(h), a, "%s has not forgiven %s." % [CrimePerson.name_of(a), CrimePerson.name_of(t)], "murder_threat", int(r["case"]), t)
			if CrimePerson.is_player(t):
				SysUtil.notify("%s has not forgotten what happened and still blames %s." % [CrimePerson.name_of(a), CrimePerson.name_of(t)], "warn")
		if lv >= int(k.get("vandal_at", 6)) and not bool(r.get("vandalised", false)):
			r["vandalised"] = true
			CrimePetty.commit("vandalism", a, CrimePerson.home_key(t), {"seen": false})
		elif lv >= int(k.get("fight_at", 11)) and not bool(r.get("fought", false)):
			r["fought"] = true
			CrimeAssault.fight(a, t)
			r["level"] = int(k.get("after_fight", 5))
		elif lv >= int(k.get("rage_at", 16)) and CrimePerson.has_trait(a, "vengeful"):
			var kk: String = CrimeMurder.key(a, t)
			var g: Dictionary = JusticeState.grudges.get(kk, {"rage": 0.0, "since": SysUtil.day() - 6, "warned": 0, "vow": false})
			g["rage"] = minf(float(g["rage"]) + float(k.get("rage_push", 25.0)), 100.0)
			JusticeState.grudges[kk] = g
			r["level"] = int(k.get("after_rage", 10))
	_vigilantes(k)

static func _vigilantes(k: Dictionary) -> void:
	if not JusticeState.chance(float(k.get("vigilante_daily", 0.002)) * Incidents.surprise_mult()):
		return
	var targets: Array = []
	for pid in JusticeState.records:
		for rec in JusticeState.records[pid]:
			if str(rec.get("result", "")) in ["guilty", "plea"] and int(JusticeProcess.charge_def(str(rec.get("charge", ""))).get("severity", 1)) >= 3 and CrimePerson.alive(int(pid)) and not Prison.is_inside(int(pid)):
				targets.append(int(pid))
				break
	var cands: Array = CrimePerson.townies_only().filter(func(x): return CrimePerson.has_trait(int(x), "vengeful") or (CrimePerson.has_trait(int(x), "hot_headed") and CrimePerson.has_trait(int(x), "active")))
	if targets.is_empty() or cands.is_empty():
		return
	var vig: int = int(cands[JusticeState.rng.randi_range(0, cands.size() - 1)])
	var tgt: int = int(targets[JusticeState.rng.randi_range(0, targets.size() - 1)])
	if vig == tgt:
		return
	JusticeState.count("vigilante")
	ChronicleHook.note("vigilante", "%s took the law into their own hands against %s." % [CrimePerson.name_of(vig), CrimePerson.name_of(tgt)], [vig, tgt], "", 3, true)
	CrimeAssault.fight(vig, tgt)

# ------------------------------------------------------------------ ending
static func end(r: Dictionary, how: String) -> void:
	r["state"] = "ended"
	r["how"] = how
	JusticeState.count("revenge_ended_" + how)
	var a: int = int(r["avenger"])
	var t: int = int(r["target"])
	if how in ["forgave", "apology"]:
		RelationshipService.add_both(a, t, "friendship", 8.0)
		RelationshipRomance.add_tension(a, t, -30.0)
		var g: String = CrimeMurder.key(a, t)
		if JusticeState.grudges.has(g):
			JusticeState.grudges[g]["rage"] = float(JusticeState.grudges[g]["rage"]) * 0.3
		var text: String = "%s let go of the grudge against %s." % [CrimePerson.name_of(a), CrimePerson.name_of(t)]
		ChronicleHook.note("forgiveness", text, [a, t], "", 1, false)
		if CrimePerson.is_player(t):
			SysUtil.notify(text, "good")

## A later conviction ends the chains that were built on that case.
static func end_for_case(case_id: int) -> void:
	for r in JusticeState.revenge:
		if int(r["case"]) == case_id and str(r.get("state", "active")) == "active":
			end(r, "convicted")

## An apology from the target to the avenger (game event "apologize" {folk_id = apologizer, target_id}).
static func on_apology(apologizer: int, to: int) -> void:
	for r in JusticeState.revenge:
		if str(r.get("state", "active")) == "active" and int(r["target"]) == apologizer and int(r["avenger"]) == to:
			var p: float = float(cfg().get("apology_chance", 0.6)) * (0.2 if CrimePerson.has_trait(to, "vengeful") else 1.0) * (1.5 if CrimePerson.has_trait(to, "forgiving") else 1.0)
			if JusticeState.chance(minf(p, 0.95)):
				end(r, "apology")
