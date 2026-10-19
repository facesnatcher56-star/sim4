class_name CrimeAssault
extends RefCounted
## Assault, task 19.1: violence is RARE and escalates in steps. Arguments come first (SocialConflict). Only a screaming argument (level
## `min_level`) between people with very high tension can turn physical: usually a shove, and a hit only rarely (more likely after earlier
## incidents of the same pair). Every incident starts a long cooldown for the pair (days), a released aggressor stays calm for a while, and an
## anger-management course dampens the temper. Aftermath (prompt, leaving, divorce, protective order): CrimeDomestic and JusticeOrders.
## CHILD SAFETY: this "lost their temper" mechanic NEVER targets babies, toddlers or children (nor starts from one). Harm to a child is
## child services' domain (neglect, BabyCare) and the separate child-abuse path (CrimeChildAbuse), not a routine fight.

static func cfg() -> Dictionary:
	return JusticeState.sect("assault")

## Teens and grown-ups only. Child safety: a child is never an aggressor or a victim of a fight.
static func can_fight(pid: int) -> bool:
	return CrimePerson.stage(pid) in ["teen", "adult", "elder"]

## Game event "argument": {folk_id, target_id, level}.
static func on_argument(a: int, b: int, level: int) -> void:
	var k: Dictionary = cfg()
	if not JusticeState.enabled or level < int(k.get("min_level", 4)):
		return
	if not (can_fight(a) and can_fight(b)):
		return
	var tension: float = maxf(RelationshipRomance.tension(a, b), RelationshipRomance.tension(b, a))
	if tension < float(k.get("min_tension", 70.0)):
		return
	var aggressor: int = a if _hotter(a, b) else b
	var other: int = b if aggressor == a else a
	if CrimePerson.in_custody(aggressor) or CrimePerson.in_custody(other) or is_calm(aggressor) or in_cooldown(aggressor, other):
		return
	var p: float = float(k.get("base", 0.012)) * (tension / 50.0) * temper(aggressor)
	p *= 1.0 / (1.0 + Police.officers() * 0.05)
	if JusticeState.chance(p):
		escalate(aggressor, other)

## One step up the ladder: usually a shove, rarely a hit.
static func escalate(aggressor: int, victim: int) -> Dictionary:
	var k: Dictionary = cfg()
	var prior: int = incidents(aggressor, victim)
	var hit_p: float = minf(float(k.get("hit_base", 0.12)) * (1.0 + float(k.get("hit_per_prior", 0.5)) * float(prior)), float(k.get("hit_cap", 0.45)))
	return fight(aggressor, victim, -1, "hit" if JusticeState.chance(hit_p) else "shove")

# ------------------------------------------------------------------ temper, cooldowns
static func _hotter(a: int, b: int) -> bool:
	return temper(a) >= temper(b)

## Multiplier of the aggressor's temper: traits, drink, and a recent anger-management course.
static func temper(pid: int) -> float:
	var k: Dictionary = cfg().get("traits", {})
	var m: float = 1.0
	for t in CrimePerson.traits(pid):
		m *= float(k.get(str(t), 1.0))
	var f = CrimePerson.folk(pid)
	if f != null:
		for bf in cfg().get("drunk_buffs", []):
			if f.has_buff(str(bf)):
				m *= float(k.get("drunk", 2.0))
	m = minf(m, float(cfg().get("trait_cap", 3.0)))
	if int(JusticeState.coursed.get(pid, -1)) >= SysUtil.day():
		m *= float(cfg().get("course_mult", 0.25))
	return m

static func is_calm(pid: int) -> bool:
	return int(JusticeState.calm.get(pid, -1)) >= SysUtil.day()

## The person starts no fights for `days` days (after release, after a course).
static func calm_for(pid: int, days: int) -> void:
	JusticeState.calm[pid] = maxi(int(JusticeState.calm.get(pid, -1)), SysUtil.day() + days)

static func pair_key(a: int, b: int) -> String:
	return "%d>%d" % [mini(a, b), maxi(a, b)]

static func in_cooldown(a: int, b: int) -> bool:
	return int((JusticeState.violence.get(pair_key(a, b), {}) as Dictionary).get("until", -1)) >= SysUtil.day()

## Earlier incidents of the pair within memory_days.
static func incidents(a: int, b: int) -> int:
	var v: Dictionary = JusticeState.violence.get(pair_key(a, b), {})
	if v.is_empty() or SysUtil.day() - int(v.get("last", -999)) > int(cfg().get("memory_days", 28)):
		return 0
	return int(v.get("n", 0))

static func _record(a: int, b: int, kind: String) -> void:
	var key: String = pair_key(a, b)
	var v: Dictionary = JusticeState.violence.get(key, {"n": 0, "last": -999, "until": -1, "hits": 0})
	v["n"] = (int(v.get("n", 0)) + 1) if SysUtil.day() - int(v.get("last", -999)) <= int(cfg().get("memory_days", 28)) else 1
	v["last"] = SysUtil.day()
	v["until"] = SysUtil.day() + int(cfg().get("cooldown_hit" if kind == "hit" else "cooldown_shove", 7))
	if kind == "hit":
		v["hits"] = int(v.get("hits", 0)) + 1
	JusticeState.violence[key] = v

## An anger-management course (sentence or the voluntary class) finished.
static func on_course_done(pid: int) -> void:
	var days: int = int(cfg().get("course_days", 28))
	JusticeState.coursed[pid] = SysUtil.day() + days
	calm_for(pid, int(days / 2))
	var f = CrimePerson.folk(pid)
	if f != null:
		f.add_buff("calm_mind")
		if CrimePerson.is_player(pid):
			SysUtil.notify("%s finished an anger-management course and feels calmer." % f.name, "good")

# ------------------------------------------------------------------ the incident
## The shove or hit itself. `kind` "hit" | "shove". Returns the case (or {} when nobody reported it). Never for children (see header).
static func fight(aggressor: int, victim: int, severity: int = -1, kind: String = "hit") -> Dictionary:
	var k: Dictionary = cfg()
	if not (CrimePerson.alive(aggressor) and CrimePerson.alive(victim)):
		return {}
	if not (can_fight(aggressor) and can_fight(victim)):
		return {}                      # child safety: see the header comment (hook for child services / CrimeChildAbuse)
	var shove: bool = kind == "shove"
	var sev: int = severity if severity > 0 else (1 if shove or JusticeState.chance(float(k.get("minor", 0.75))) else 2)
	var mult: float = float(k.get("shove_loss_mult", 0.5)) if shove else 1.0
	if not shove:
		var fv = CrimePerson.folk(victim)
		if fv != null:
			Hospital.injure(fv, sev, "a fight")
		elif sev >= 2:
			Hospital.admit(victim, sev, "a fight")
		var fa = CrimePerson.folk(aggressor)
		if fa != null and JusticeState.chance(float(k.get("aggressor_hurt", 0.25))):
			Hospital.injure(fa, 1, "a fight")
	for pr in [[aggressor, victim], [victim, aggressor]]:
		RelationshipService.add_value(pr[0], pr[1], "friendship", -float(k.get("friendship_loss", 25)) * mult)
		RelationshipService.add_value(pr[0], pr[1], "trust", -float(k.get("trust_loss", 20)) * mult)
	RelationshipService.add_history(aggressor, victim, "assault", -1.0, aggressor)
	RelationshipKnowledge.add_reputation(aggressor, -float(k.get("reputation", 5)) * mult)
	_record(aggressor, victim, kind)
	JusticeState.count("shove" if shove else "hit")
	SysUtil.game_event("assault", {"folk_id": aggressor, "target_id": victim, "kind": kind})
	var text: String = Sexes.fill("%s lost {their} temper and %s %s." % [CrimePerson.name_of(aggressor), "shoved" if shove else "hit", CrimePerson.name_of(victim)], aggressor)
	var out: Dictionary = {}
	CrimeDomestic.after(aggressor, victim, kind, sev, text, out)
	return out.get("case", {})

## Used by CrimeDomestic when the incident is reported: the case, the scene and the notice.
static func report(aggressor: int, victim: int, sev: int, text: String, domestic: bool, kind: String) -> Dictionary:
	var c: Dictionary = CaseStore.create("assault", aggressor, victim, CrimePlace.where_now(victim), {"witnessed": true, "witnesses": [victim],
		"witness_clarity": 0.95, "trace": 0.5})
	CrimePlace.place_at_scene(aggressor, str(c["scene"]))
	c["severity"] = sev
	c["domestic"] = domestic
	c["act"] = kind
	CaseDiscovery.report(c, victim, "victim")
	CaseStore.note(c, text, "assault", 2)
	if CrimePerson.is_player(aggressor) or CrimePerson.is_player(victim):
		SysUtil.notify(text + " The police were called.", "bad")
	return c

## Daily statistical roll for feuding townie pairs (they are not simulated socially, so the feud itself comes from their records).
static func on_day() -> void:
	if not JusticeState.enabled:
		return
	for a in CrimePerson.townies_only():
		person_day(int(a))

static func _far_adult(p: int) -> bool:
	return bool(Story.townies.get(p, {}).get("alive", false)) and not CrimePerson.folk(p) and CrimePerson.is_adult(p)

## One far townie's feud rolls (the body of the old loop over the far adults; CrimeFlow.person_day calls it from the bucketed daily job).
static func person_day(a: int) -> void:
	if not JusticeState.enabled or not _far_adult(a):
		return
	var k: Dictionary = cfg()
	if true:
		for b in RelationshipBits.all_known(a):
			if int(b) <= a or not _far_adult(int(b)):
				continue
			var hot: float = maxf(CrimeMurder.anger(a, int(b)) * CrimeMurder.propensity(a), CrimeMurder.anger(int(b), a) * CrimeMurder.propensity(int(b)))
			if hot >= float(k.get("far_anger", 0.5)) and JusticeState.chance(float(k.get("far_daily", 0.004)) * hot):
				var agg: int = a if CrimeMurder.anger(a, int(b)) >= CrimeMurder.anger(int(b), a) else int(b)
				var vic: int = int(b) if agg == a else a
				if not is_calm(agg) and not in_cooldown(agg, vic) and not CrimePerson.in_custody(agg):
					escalate(agg, vic)