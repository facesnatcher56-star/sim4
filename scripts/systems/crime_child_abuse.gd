class_name CrimeChildAbuse
extends RefCounted
## Child abuse (task 20.4): a RARE path of its own, never part of the "lost their temper" fight loop (CrimeAssault never targets children).
## A carer's RISK builds from stress (money pressure, no job, grief, drink), temper (hot-headed, vengeful ...), having been abused as a child, tension
## with the child and having nobody around; support (relatives, friends, therapy, calm traits, a parenting course, being watched by child services)
## lowers it. The hidden SCORE builds only while the risk stays high for days; at `warn_at` the child is visibly fearful and the player's own
## folk get a prompt to step in; at `act_at` there is a small daily chance of an incident: an EVENT ONLY (the child is hurt and frightened, a hidden
## case is opened; nothing is shown or described). Then ChildServices: discovery, home visit, placement, police. Data: justice.json "child_abuse".
## Townies use the same code with records only (the statistical version): outcomes reach the Chronicle and gossip.

static func cfg() -> Dictionary:
	return JusticeState.sect("child_abuse")

static func ab() -> Dictionary:
	return JusticeState.abuse

static func is_minor(pid: int) -> bool:
	return CrimePerson.stage(pid) in ["baby", "toddler", "child"]

## Adults who look after the child: parents and the adults of the same household.
static func carers_of(child: int) -> Array:
	var out: Array = []
	for p in FamilyTree.parents_of(child):
		if CrimePerson.alive(int(p)) and CrimePerson.is_adult(int(p)) and not out.has(int(p)):
			out.append(int(p))
	var h: int = CrimePerson.hid(child)
	if h > 0:
		for r in SysUtil.residents():
			if int(r.household_id) == h and CrimePerson.is_adult(int(r.id)) and not out.has(int(r.id)):
				out.append(int(r.id))
	out.sort()
	return out

static func dependents_of(carer: int) -> Array:
	var out: Array = []
	for p in CrimePerson.everyone():
		if is_minor(int(p)) and carers_of(int(p)).has(carer):
			out.append(int(p))
	return out

# ------------------------------------------------------------------ the risk
## People outside the carer's home who are close to them (relatives, friends): the support around.
static func support_count(carer: int) -> int:
	var h: int = CrimePerson.hid(carer)
	var n: int = 0
	var seen: Dictionary = {}
	for o in CrimePerson.close_alive(carer) + CrimePerson.friends(carer):
		var oid: int = int(o)
		if seen.has(oid) or not CrimePerson.alive(oid) or not CrimePerson.is_adult(oid):
			continue
		seen[oid] = true
		if (h > 0 and CrimePerson.hid(oid) == h) or RelationshipService.value(oid, carer, "friendship") < 35.0:
			continue
		n += 1
	return n

static func _has_buff(pid: int, ids: Array) -> bool:
	var f = CrimePerson.folk(pid)
	if f == null:
		return false
	for b in ids:
		if f.has_buff(str(b)):
			return true
	return false

## {"raw": 0..1.2, "risk": {name: amount}, "protect": {name: amount}} for a carer and the child they are most strained with.
static func assess(carer: int, child: int) -> Dictionary:
	var K: Dictionary = cfg()
	var R: Dictionary = K.get("risk", {})
	var P: Dictionary = K.get("protect", {})
	var risk: Dictionary = {}
	var prot: Dictionary = {}
	var pressure: float = CrimePressure.pressure(carer)
	if pressure >= 0.3:
		risk["money"] = float(R.get("money", 0.25)) * pressure
	if not CrimePerson.has_job(carer) and CrimePerson.stage(carer) != "elder":
		risk["jobless"] = float(R.get("jobless", 0.08))
	if _has_buff(carer, ["grieving", "bereaved", "widowed"]):
		risk["grief"] = float(R.get("grief", 0.12))
	for t in ["hot_headed", "vengeful", "grudgeholder", "stubborn", "pessimist"]:
		if CrimePerson.has_trait(carer, t):
			risk[t] = float(R.get(t, 0.05))
	if _has_buff(carer, JusticeState.sect("assault").get("drunk_buffs", [])):
		risk["drunk"] = float(R.get("drunk", 0.12))
	if ab()["hist"].has(carer):
		risk["abused_as_child"] = float(R.get("abused_as_child", 0.22))
	if child >= 0:
		var tn: float = maxf(RelationshipRomance.tension(carer, child), RelationshipRomance.tension(child, carer))
		if tn > 10.0:
			risk["child_tension"] = float(R.get("child_tension", 0.2)) * minf(tn / 100.0, 1.0)
	var sup: int = support_count(carer)
	if sup == 0:
		risk["no_support"] = float(R.get("no_support", 0.15))
	elif sup >= 3:
		prot["support"] = float(P.get("support_many", 0.22))
	else:
		prot["support"] = float(P.get("support_one", 0.12))
	if _has_buff(carer, ["in_therapy"]):
		prot["therapy"] = float(P.get("therapy", 0.3))
	var calm: float = 0.0
	for t2 in ["easygoing", "empath", "forgiving", "optimist", "generous"]:
		if CrimePerson.has_trait(carer, t2):
			calm += float(P.get(t2, 0.05))
	if calm > 0.0:
		prot["calm_nature"] = minf(calm, float(P.get("calm_cap", 0.3)))
	if SysUtil.day() - int(ab()["parenting"].get(carer, -9999)) <= int(P.get("parenting_days", 56)):
		prot["parenting_course"] = float(P.get("parenting_course", 0.3))
	if int(ab()["watched"].get(carer, -1)) >= SysUtil.day():
		prot["watched"] = float(P.get("watched", 0.2))
	if _has_buff(carer, ["calm_mind"]):
		prot["calm_mind"] = 0.1
	var raw: float = 0.0
	for k in risk:
		raw += float(risk[k])
	for k2 in prot:
		raw -= float(prot[k2])
	return {"raw": clampf(raw, 0.0, 1.2), "risk": risk, "protect": prot}

static func trauma_of(pid: int) -> float:
	return float((ab()["kids"].get(pid, {}) as Dictionary).get("trauma", 0.0))

static func score_of(carer: int) -> float:
	return float((ab()["carers"].get(carer, {}) as Dictionary).get("score", 0.0))

# ------------------------------------------------------------------ the daily tick
static func on_day() -> void:
	if not JusticeState.enabled:
		return
	var K: Dictionary = cfg()
	var by_carer: Dictionary = {}
	for p in CrimePerson.everyone():
		if is_minor(int(p)):
			for c in carers_of(int(p)):
				var l: Array = by_carer.get(c, [])
				l.append(int(p))
				by_carer[c] = l
	var carers: Array = by_carer.keys()
	carers.sort()
	for carer in carers:
		if CrimePerson.in_custody(int(carer)):
			continue
		_update(int(carer), by_carer[carer], K)
	_trauma_day(K)

static func _update(carer: int, kids: Array, K: Dictionary) -> void:
	var rec: Dictionary = ab()["carers"].get(carer, {"score": 0.0, "warned": -99, "last": -99})
	var worst: int = -1
	var worst_t: float = -1.0
	for k in kids:
		var tn: float = maxf(RelationshipRomance.tension(carer, int(k)), RelationshipRomance.tension(int(k), carer))
		if tn > worst_t:
			worst_t = tn
			worst = int(k)
	var a: Dictionary = assess(carer, worst)
	var score: float = float(rec["score"])
	var min_raw: float = float(K.get("min_raw", 0.35))
	if float(a["raw"]) > min_raw:
		score = minf(score + float(K.get("build_per_day", 0.1)) * (float(a["raw"]) - min_raw), float(K.get("score_cap", 1.5)))
	else:
		score *= float(K.get("decay", 0.9))
	rec["score"] = score
	ab()["carers"][carer] = rec
	if score >= float(K.get("warn_at", 0.55)) and SysUtil.day() - int(rec["warned"]) >= int(K.get("warn_cooldown", 7)):
		rec["warned"] = SysUtil.day()
		warn(carer, worst, score)
	if score >= float(K.get("act_at", 0.9)) and SysUtil.day() - int(rec["last"]) >= int(K.get("incident_cooldown", 10)) \
			and JusticeState.chance(float(K.get("daily_chance", 0.04)) * score):
		rec["last"] = SysUtil.day()
		rec["score"] = score * float(K.get("relief_after_incident", 0.5))
		incident(carer, worst)

# ------------------------------------------------------------------ warning signs
static func warn(carer: int, child: int, score: float) -> void:
	var fc = CrimePerson.folk(child)
	if fc != null:
		fc.add_buff("afraid_at_home")
	var f = CrimePerson.folk(carer)
	if f != null:
		f.add_buff("at_the_end_of_rope")
	JusticeState.count("abuse_warnings")
	var cn: String = CrimePerson.name_of(carer)
	var kn: String = CrimePerson.name_of(child)
	if CrimePerson.is_player(carer):
		var text: String = "Things are very tense between %s and %s. %s is worn out and short-tempered, and %s has gone quiet and wary. It is time to step in before something goes wrong." % [cn, kn, cn, kn]
		JusticePlayer.ask(carer, "Tension at home", text, [{"id": "break", "label": "Take a break"}, {"id": "help", "label": "Ask family and friends for help"}, {"id": "ignore", "label": "Carry on"}],
			func(ch): _warn_choice(str(ch), carer), "break")
	elif not CrimePerson.is_player(child) and JusticeState.chance(0.5):
		ChronicleHook.note("worry", "Neighbours have noticed a lot of shouting at the %s house." % CaseStore.house_label(CrimePerson.home_key(child)).trim_prefix("the ").trim_suffix(" house"), [carer, child], CrimePerson.home_key(child), 1, true)

static func _warn_choice(ch: String, carer: int) -> void:
	var rec: Dictionary = ab()["carers"].get(carer, {})
	var f = CrimePerson.folk(carer)
	match ch:
		"break":
			rec["score"] = float(rec.get("score", 0.0)) * 0.4
			if f != null:
				f.add_buff("calm_mind")
				f.remove_buff("at_the_end_of_rope")
		"help":
			rec["score"] = float(rec.get("score", 0.0)) * 0.6
			CrimePressure.help(carer, "family")
			if f != null:
				f.add_buff("calm_mind")
	ab()["carers"][carer] = rec

# ------------------------------------------------------------------ the incident (event only)
static func incident(carer: int, child: int) -> Dictionary:
	if child < 0 or not CrimePerson.alive(child) or not CrimePerson.alive(carer):
		return {}
	var K: Dictionary = cfg()
	var T: Dictionary = K.get("trauma", {})
	var kid: Dictionary = ab()["kids"].get(child, {"incidents": 0, "trauma": 0.0, "reported": false, "case": -1, "serious": false})
	var serious: bool = JusticeState.chance(float(K.get("serious", 0.3))) or (int(kid.get("incidents", 0)) >= 1 and JusticeState.chance(0.4))
	var sev: int = 2 if serious else 1
	kid["carer"] = carer
	kid["incidents"] = int(kid["incidents"]) + 1
	kid["last_day"] = SysUtil.day()
	kid["serious"] = bool(kid["serious"]) or serious
	kid["trauma"] = minf(float(kid["trauma"]) + float(T.get("per_incident", 0.5)), 1.0)
	kid.erase("safe_noted")
	ab()["hist"][child] = true
	ab()["kids"][child] = kid
	var fc = CrimePerson.folk(child)
	if fc != null:
		Health.injure(fc, sev, "an injury at home")
		fc.add_buff("afraid_at_home")
		fc.remember("folk:%d" % carer, -1.0)
		if Careers.school.has(child):
			Careers.school[child]["grade"] = maxf(float(Careers.school[child]["grade"]) - float(T.get("school_penalty", 8)), 0.0)
	_trait_roll(child, T)
	var c: Dictionary = CaseStore.get_case(int(kid.get("case", -1)))
	if c.is_empty() or str(c["state"]) not in ["hidden", "open"]:
		c = CaseStore.create("child_abuse", carer, child, CrimePerson.home_key(child), {"witnessed": false, "trace": 0.2, "vhid": CrimePerson.hid(child)})
		c["charge_hint"] = "child_abuse"
		c["domestic"] = true
		c["found"] = true
	c["severity"] = maxi(int(c.get("severity", 1)), sev)
	c["injury"] = bool(c.get("injury", false)) or serious
	c["cruelty"] = int(kid["incidents"]) >= 3
	c["trace"] = minf(float(c["trace"]) + 0.1, 0.8)
	kid["case"] = int(c["id"])
	JusticeState.count("child_abuse_incident")
	SysUtil.game_event("child_hurt", {"folk_id": child, "target_id": carer, "case": int(c["id"])})
	if CrimePerson.is_player(child):
		SysUtil.notify("%s was hurt at home and is frightened." % CrimePerson.name_of(child), "bad")
	return c

## Lasting effects: a chance of an anxious or mistrustful nature, lower with support around.
static func _trait_roll(child: int, T: Dictionary) -> void:
	var p: float = float(T.get("trait_chance", 0.3)) * (0.5 if support_count(child) > 0 else 1.0)
	if not JusticeState.chance(p):
		return
	var t: String = "anxious" if JusticeState.chance(0.5) else "mistrustful"
	var f = CrimePerson.folk(child)
	var list: Array = f.traits if f != null else CrimePerson.rec(child).get("traits", [])
	if list.has("anxious") or list.has("mistrustful"):
		return
	list.append(t)
	if f == null and Story.townies.has(child):
		Story.townies[child]["traits"] = list

## Trauma fades faster in a safe home, with supportive adults and therapy; the fear buff follows it.
static func _trauma_day(K: Dictionary) -> void:
	var T: Dictionary = K.get("trauma", {})
	for child in ab()["kids"].keys():
		var kid: Dictionary = ab()["kids"][child]
		var rate: float = float(T.get("decay", 0.01))
		var safe: bool = not (kid.get("placed", {}) as Dictionary).is_empty() or CrimePerson.in_custody(int(kid.get("carer", -1)))
		if safe:
			rate *= float(T.get("safe_mult", 3.0))
		if support_count(int(child)) > 0:
			rate *= 1.5
		if _has_buff(int(child), ["in_therapy"]):
			rate *= float(T.get("therapy_mult", 4.0))
		kid["trauma"] = maxf(float(kid["trauma"]) - rate, 0.0)
		var f = CrimePerson.folk(int(child))
		if f != null and float(kid["trauma"]) < float(T.get("afraid_at", 0.2)):
			if f.has_buff("afraid_at_home") and not bool(kid.get("safe_noted", false)):
				f.remove_buff("afraid_at_home")
				if safe:
					f.add_buff("safe_again")
				kid["safe_noted"] = true

# ------------------------------------------------------------------ justice hooks
## A conviction with loss of custody: the child is placed away from the carer until a parenting course is done.
static func on_custody_loss(c: Dictionary, carer: int) -> void:
	var child: int = int(c.get("victim", -1))
	if child < 0:
		return
	var kid: Dictionary = ab()["kids"].get(child, {})
	kid["carer"] = carer
	kid["custody_lost"] = true
	ab()["kids"][child] = kid
	ChildServices.place(child, carer, "custody")

static func on_parenting_done(pid: int) -> void:
	ab()["parenting"][pid] = SysUtil.day()
	var f = CrimePerson.folk(pid)
	if f != null:
		f.add_buff("calm_mind")
	if CrimePerson.is_player(pid):
		SysUtil.notify("%s finished a parenting course." % CrimePerson.name_of(pid), "good")
