class_name PregnancyTell
extends RefCounted
## Telling people (task 18 part 3). When she finds out (event pregnancy_known):
##   * the PARTNER (father) is told after a few hours and reacts by the relationship, the traits, the money and whether it was planned:
##     joy (a bonding buff, closer), shock (a worry buff), anger (a row, less love) or, rarely, a breakup;
##   * she may keep it SECRET from everybody else for a while (dice by traits / planned; the player's folk get a prompt). A secret uses the
##     secrets-and-gossip system (secret id 100 "is expecting a baby"): housemates and friends notice as she shows, word gets out, and by the
##     third trimester (or when three people know) it is public;
##   * when it is public: a chronicle line, family and friends are glad (friendship up, a happy memory), strangers do not matter.
## Only residents react in full; a father who lives elsewhere (a townie) is told by a note. Data: data/pregnancy.json "tell".

const SECRET_ID := 100

static func cfg() -> Dictionary:
	return Pregnancy.cfg("tell")

## Called when she knows. Decides openness, then schedules telling the partner.
static func on_known(id: int) -> void:
	if PregnancyChoice.intercept(id):                 # the early-pregnancy choice comes first (only with Mature life events on)
		return
	open_up(id)

## She keeps the pregnancy: decide how open she is, then tell the partner.
static func open_up(id: int) -> void:
	var r: Dictionary = Pregnancy.rec(id)
	if r.is_empty():
		return
	var c: Dictionary = cfg()
	var p: float = float(c.get("keep_secret_chance", 0.12)) if bool(r.get("planned", true)) else float(c.get("keep_secret_unplanned", 0.35))
	var f = SysUtil.folk(id)
	if f != null:
		for t in f.traits:
			p += float((c.get("secret_traits", {}) as Dictionary).get(str(t), 0.0))
	var secret: bool = Pregnancy.rng.randf() < p
	r["tell_at_min"] = SysUtil.now() + int(c.get("partner_delay_hours", 6)) * 60
	r["secret"] = secret
	if CrimePerson.is_player(id):
		var opts: Array = [{"id": "tell", "label": "Tell everyone the good news"}, {"id": "secret", "label": "Keep it to ourselves for now"}]
		JusticePlayer.ask(id, "Big news", Sexes.fill("%s is expecting. Who should know?" % SysUtil.folk_name(id), id), opts,
			func(choice): _chosen(id, str(choice)), "secret" if secret else "tell")
	else:
		_apply_openness(id)

static func _chosen(id: int, choice: String) -> void:
	var r: Dictionary = Pregnancy.rec(id)
	if r.is_empty():
		return
	r["secret"] = (choice == "secret")
	_apply_openness(id)

static func _apply_openness(id: int) -> void:
	var r: Dictionary = Pregnancy.rec(id)
	if bool(r.get("secret", false)):
		_ensure_secret(id)
	else:
		make_public(id)

static func _ensure_secret(id: int) -> void:
	var list: Array = RelationshipKnowledge.ensure_secrets(id)
	for s in list:
		if int(s["id"]) == SECRET_ID:
			return
	list.append({"id": SECRET_ID, "kind": "pregnancy", "text": "is expecting a baby", "severity": 0.2, "known_by": []})

static func on_hour(id: int, r: Dictionary) -> void:
	var at: int = int(r.get("tell_at_min", -1))
	if at >= 0 and SysUtil.now() >= at and bool(r.get("known", false)):
		r["tell_at_min"] = -1
		tell_partner(id)

static func on_day(id: int, r: Dictionary) -> void:
	if not bool(r.get("secret", false)) or not bool(r.get("known", false)):
		return
	var c: Dictionary = cfg()
	if Pregnancy.trimester(id) >= int(c.get("public_at_trimester", 3)):
		make_public(id)
		return
	if Pregnancy.trimester(id) < 2:
		return
	var f = SysUtil.folk(id)
	if f == null:
		return
	for o in SysUtil.residents():
		var oid: int = int(o.id)
		if oid == id or SysUtil.is_away(o) or str(o.age_stage) in ["baby", "toddler"]:
			continue
		var close: bool = int(o.household_id) == int(f.household_id) or RelationshipService.value(oid, id, "friendship") >= float(c.get("friend_min", 30))
		if close and Pregnancy.rng.randf() < float(c.get("notice_chance_per_day", 0.35)):
			RelationshipKnowledge.learn_secret(oid, id, SECRET_ID)
	var known_by: int = 0
	for s in RelationshipKnowledge.ensure_secrets(id):
		if int(s["id"]) == SECRET_ID:
			known_by = (s["known_by"] as Array).size()
	if known_by >= 3:
		make_public(id)

# ------------------------------------------------------------------ the partner
static func tell_partner(id: int) -> void:
	var r: Dictionary = Pregnancy.rec(id)
	var fa: int = int(r.get("father", -1))
	var m = SysUtil.folk(id)
	if m == null or fa < 0:
		return
	var told: Array = r.get("told", [])
	if told.has(fa):
		return
	told.append(fa)
	r["told"] = told
	var father = SysUtil.folk(fa)
	if father == null:
		SysUtil.notify(Sexes.fill("%s wrote to tell %s the news." % [m.name, Family.name_of(fa)], id), "relationship")
		return
	if bool(r.get("secret", false)):
		RelationshipKnowledge.learn_secret(fa, id, SECRET_ID)          # the partner is in on it
	var score: float = reaction_score(id, fa, bool(r.get("planned", true)))
	var out: String = "joy" if score >= float(cfg().get("reaction", {}).get("joy_at", 0.45)) else ("anger" if score <= float(cfg().get("reaction", {}).get("anger_below", -0.15)) else "shock")
	var rc: Dictionary = cfg().get("reaction", {})
	if score <= float(rc.get("breakup_below", -0.45)) and Pregnancy.rng.randf() < float(rc.get("breakup_chance", 0.5)):
		out = "breakup"
	r["partner_reaction"] = out
	match out:
		"joy":
			father.add_buff("expecting_joy")
			m.add_buff("expecting_joy")
			RelationshipService.add_both(id, fa, "romance", 4.0)
			RelationshipService.add_both(id, fa, "friendship", 3.0)
			SysUtil.notify("%s is overjoyed to hear it." % father.name, "relationship")
		"shock":
			father.add_buff("expecting_worry")
			SysUtil.notify("%s is quiet for a while. It is a lot to take in." % father.name, "relationship")
		"anger":
			father.add_buff("expecting_worry")
			RelationshipService.add_both(id, fa, "romance", -8.0)
			RelationshipService.add_both(id, fa, "friendship", -5.0)
			SysUtil.notify(Sexes.fill("%s is upset about the news and the two of them argue." % father.name, fa), "relationship")
		"breakup":
			RelationshipRomance.breakup(id, fa, "breakup", 1.0)
			SysUtil.notify("%s could not cope with the news, and the two of them split up." % father.name, "relationship")
	SysUtil.game_event("pregnancy_told", {"folk_id": id, "target_id": fa, "reaction": out})

## -1..1: how well the father takes it.
static func reaction_score(mother: int, father: int, planned: bool) -> float:
	var rc: Dictionary = cfg().get("reaction", {})
	var s: float = float(rc.get("base_joy", 0.4)) + float(rc.get("planned" if planned else "unplanned", 0.0))
	if RelationshipBits.has_flag(mother, father, "spouse"):
		s += float(rc.get("married", 0.3))
	elif RelationshipBits.has_flag(mother, father, "partner"):
		s += float(rc.get("committed", 0.1))
	s += float(rc.get("romance_per_point", 0.004)) * (RelationshipService.value(father, mother, "romance") - 50.0)
	var fa = SysUtil.folk(father)
	if fa != null:
		if WorldIface.get_coins(int(fa.household_id)) < int(rc.get("poor_coins", 80)):
			s += float(rc.get("poor", -0.25))
		for t in fa.traits:
			s += float((rc.get("good_traits", {}) as Dictionary).get(str(t), 0.0))
			s += float((rc.get("bad_traits", {}) as Dictionary).get(str(t), 0.0))
	return clampf(s, -1.0, 1.0)

# ------------------------------------------------------------------ everybody
## The news is out: chronicle, family and friends react.
static func make_public(id: int) -> void:
	var r: Dictionary = Pregnancy.rec(id)
	if r.is_empty() or bool(r.get("public", false)):
		return
	r["public"] = true
	r["secret"] = false
	var m = SysUtil.folk(id)
	if m == null:
		return
	ChronicleHook.note("pregnancy", "%s is expecting a baby." % m.name, [id, int(r.get("father", -1))], "home:%d" % int(m.household_id), 2, true)
	var glad: int = 0
	for o in SysUtil.residents():
		var oid: int = int(o.id)
		if oid == id or str(o.age_stage) in ["baby", "toddler"]:
			continue
		var fam: bool = RelationshipBits.has_flag(oid, id, "family") or FamilyTree.is_kin(oid, id)
		var friend: bool = RelationshipService.value(oid, id, "friendship") >= float(cfg().get("friend_min", 30))
		if fam or friend:
			RelationshipService.add_value(oid, id, "friendship", 3.0)
			o.add_buff("cheered_up")
			glad += 1
	if glad > 0:
		SysUtil.notify("Word is out: %s is expecting. Family and friends are happy for %s." % [m.name, Sexes.them(id)], "relationship")
	SysUtil.game_event("pregnancy_public", {"folk_id": id})

static func on_game_event(ev: String, payload: Dictionary) -> void:
	if ev == "pregnancy_known":
		on_known(int(payload.get("folk_id", -1)))
