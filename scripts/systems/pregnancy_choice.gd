class_name PregnancyChoice
extends RefCounted
## Ending a pregnancy early (task 18 part 4). SENSITIVE: a choice for the pregnant folk, no judgement in any text, no legal penalty.
## Offered only while "Mature life events" is on, and only early (first trimester, `termination.until`):
##   * the PLAYER's folk see a prompt when she learns of the pregnancy: keep it, end it, or decide later (asked again each morning until the
##     early window closes, then the pregnancy simply goes on). The prompt is shown only to the player who controls her;
##   * everybody else decides STATISTICALLY from their circumstances (money, relationship, age, traits, an existing family, planned or not);
##   * townies decide the same way when they conceive (PregnancyTownie.consider).
## Consequences: the partner (if told) and others who find out react by relationship and traits (supportive or upset, never punished);
## it may stay private (secret id 101 in the gossip system, someone may learn it later); she has mixed feelings for a couple of days and a
## memory that softens over time. The clinic visit takes a few hours (she is "at the clinic") and costs a small fee.

const SECRET_ID := 101

static func cfg() -> Dictionary:
	return PregnancyLoss.cfg().get("termination", {})

## Is the choice open to her right now?
static func offered(id: int) -> bool:
	var r: Dictionary = Pregnancy.rec(id)
	return PregnancyLoss.mature_enabled() and not r.is_empty() and bool(r.get("known", false)) and Pregnancy.progress(id) <= float(cfg().get("until", 0.4))

## Called when she learns of the pregnancy, before she tells anyone. True = this file took over (the telling waits for the decision).
static func intercept(id: int) -> bool:
	if not offered(id):
		return false
	var r: Dictionary = Pregnancy.rec(id)
	if CrimePerson.is_player(id):
		ask_player(id)
		return true
	if Pregnancy.rng.randf() < ai_chance(id):
		terminate(id)
		return true
	return false

static func ask_player(id: int) -> void:
	var m = SysUtil.folk(id)
	if m == null:
		return
	var opts: Array = [{"id": "keep", "label": "Keep the baby"}, {"id": "end", "label": "End the pregnancy"}, {"id": "later", "label": "Decide later"}]
	JusticePlayer.ask(id, "A big decision", "%s has found out about the pregnancy. Whatever %s decides is %s own choice." % [m.name, Sexes.they(id), Sexes.their(id)],
		opts, func(choice): _chosen(id, str(choice)), "keep")

static func _chosen(id: int, choice: String) -> void:
	var r: Dictionary = Pregnancy.rec(id)
	if r.is_empty():
		return
	match choice:
		"end":
			if offered(id):
				terminate(id)
			else:
				_keep(id)
		"later":
			r["undecided"] = true
		_:
			_keep(id)

static func _keep(id: int) -> void:
	var r: Dictionary = Pregnancy.rec(id)
	if r.is_empty():
		return
	r["undecided"] = false
	PregnancyTell.open_up(id)

## Morning: someone who decided "later" is asked again until the early window closes, then the pregnancy goes on.
static func on_day(id: int, r: Dictionary) -> void:
	if not bool(r.get("undecided", false)):
		return
	if offered(id):
		if bool(cfg().get("ask_every_day", true)):
			ask_player(id)
	else:
		_keep(id)

# ------------------------------------------------------------------ the statistical decision
## 0..max: how likely she is to end it, from her circumstances. Data: termination.*.
static func ai_chance(id: int) -> float:
	var c: Dictionary = cfg()
	var r: Dictionary = Pregnancy.rec(id)
	var p: float = float(c.get("ai_base", 0.03)) + float(c.get("planned" if bool(r.get("planned", true)) else "unplanned", 0.0))
	var f = SysUtil.folk(id)
	if f != null:
		if WorldIface.get_coins(int(f.household_id)) < int(c.get("poor_coins", 80)):
			p += float(c.get("poor", 0.1))
		for t in f.traits:
			p += float((c.get("trait_add", {}) as Dictionary).get(str(t), 0.0))
		if Family.age_days_of(id) < float(c.get("young_days", 100)):
			p += float(c.get("young", 0.04))
		if Aging.children_of(id).size() >= 2:
			p += float(c.get("kids2", 0.1))
	var fa: int = int(r.get("father", -1))
	if RelationshipBits.has_flag(id, fa, "spouse"):
		p += float(c.get("married", -0.05))
	elif not RelationshipBits.has_flag(id, fa, "partner"):
		p += float(c.get("single", 0.08))
	return clampf(p, 0.0, float(c.get("max", 0.6)))

## The same decision for a townie couple (records), made when they conceive: true = they do not continue.
static func townie_ends(carrier: Dictionary, other: Dictionary, planned: bool) -> bool:
	if not PregnancyLoss.mature_enabled():
		return false
	var c: Dictionary = cfg()
	var p: float = float(c.get("ai_base", 0.03)) + float(c.get("planned" if planned else "unplanned", 0.0))
	if int(carrier.get("coins", 0)) < int(c.get("poor_coins", 80)):
		p += float(c.get("poor", 0.1))
	for t in carrier.get("traits", []):
		p += float((c.get("trait_add", {}) as Dictionary).get(str(t), 0.0))
	if float(carrier.get("age_days", 90.0)) < float(c.get("young_days", 100)):
		p += float(c.get("young", 0.04))
	if int(carrier.get("kids", 0)) + int(other.get("kids", 0)) >= 2:
		p += float(c.get("kids2", 0.1))
	var cid: int = int(carrier["id"])
	var oid: int = int(other["id"])
	if RelationshipBits.has_flag(cid, oid, "spouse"):
		p += float(c.get("married", -0.05))
	elif not RelationshipBits.has_flag(cid, oid, "partner"):
		p += float(c.get("single", 0.08))
	return Pregnancy.rng.randf() < clampf(p, 0.0, float(c.get("max", 0.6)))

# ------------------------------------------------------------------ doing it
static func terminate(id: int) -> void:
	var r: Dictionary = Pregnancy.rec(id)
	var m = SysUtil.folk(id)
	if r.is_empty() or m == null or not PregnancyLoss.mature_enabled():
		return
	var father: int = int(r.get("father", -1))
	var planned: bool = bool(r.get("planned", true))
	var c: Dictionary = cfg()
	var fee: int = int(c.get("cost", 60))
	if WorldIface.get_coins(int(m.household_id)) >= fee:
		WorldIface.add_coins(int(m.household_id), -fee)           # a clinic that cannot be paid for waives the fee
	var knows: bool = (r.get("told", []) as Array).has(father) or RelationshipBits.has_flag(id, father, "spouse") or Pregnancy.rng.randf() < 0.5
	var minutes: float = float(c.get("clinic_minutes", 180))
	PregnancyLoss.end_pregnancy(id)
	if CrimePerson.is_player(id):
		JusticePlayer.hold(m, minutes, "clinic", "At the clinic")
	m.add_buff("mixed_feelings")
	var mem: Dictionary = PregnancyLoss.cfg().get("memory", {})
	PregnancyLoss.add_memory(id, 0, float(mem.get("planned" if planned else "unplanned", -0.15)), "a hard choice")
	PregnancyLoss.add_memory(id, int(mem.get("later_days", 6)), float(mem.get("later_value", 0.1)), "the choice that was made, and the peace that followed")
	SysUtil.notify(Sexes.fill("%s decided to end the pregnancy. It was not an easy decision." % m.name, id), "info")
	var fa = SysUtil.folk(father) if father >= 0 else null
	if knows and fa != null:
		partner_reacts(id, father)
	else:
		_ensure_secret(id)
	ChronicleHook.note("pregnancy_ended", "%s made a private choice." % m.name, [id], "home:%d" % int(m.household_id), 1, false)
	SysUtil.game_event("pregnancy_ended", {"folk_id": id, "target_id": father})

static func _ensure_secret(id: int) -> void:
	for s in RelationshipKnowledge.ensure_secrets(id):
		if int(s["id"]) == SECRET_ID:
			return
	RelationshipKnowledge.ensure_secrets(id).append({"id": SECRET_ID, "kind": "pregnancy_ended", "text": "ended a pregnancy", "severity": 0.3, "known_by": []})

# ------------------------------------------------------------------ others' reactions
## -1..1 how supportive `who` is of `id`'s choice (relationship and traits).
static func support_score(who: int, id: int) -> float:
	var rc: Dictionary = PregnancyLoss.cfg().get("reaction", {})
	var s: float = float(rc.get("base", 0.1)) + 0.004 * (RelationshipService.value(who, id, "friendship") - 40.0)
	var f = SysUtil.folk(who)
	if f != null:
		for t in f.traits:
			s += float((rc.get("supportive_traits", {}) as Dictionary).get(str(t), 0.0))
			s += float((rc.get("upset_traits", {}) as Dictionary).get(str(t), 0.0))
	return clampf(s, -1.0, 1.0)

static func partner_reacts(id: int, father: int) -> void:
	var fa = SysUtil.folk(father)
	if fa == null:
		return
	react(father, id)

static func react(who: int, id: int) -> void:
	var o = SysUtil.folk(who)
	if o == null:
		return
	var rc: Dictionary = PregnancyLoss.cfg().get("reaction", {})
	var s: float = support_score(who, id)
	if s >= 0.0:
		RelationshipService.add_value(who, id, "friendship", float(rc.get("friend_delta", 4.0)))
		o.add_buff("reassured")
	else:
		RelationshipService.add_value(who, id, "friendship", float(rc.get("upset_delta", -4.0)))
		o.add_buff("expecting_worry")
	SysUtil.game_event("pregnancy_choice_reaction", {"folk_id": who, "target_id": id, "supportive": s >= 0.0})

## Somebody learns the private choice through the gossip system: they react by who they are.
static func on_secret_learned(learner: int, owner: int, sid: int) -> void:
	if sid == SECRET_ID:
		react(learner, owner)
