class_name CrimeAssault
extends RefCounted
## Assault: a screaming argument (SocialConflict level 3+, game event "argument") between people with very high tension can turn into a
## scuffle. Hot-headed, jealous and drunk folk are more likely. Far townies with a bitter feud get a daily statistical roll.
## Result: an injury (Hospital), a case when the police are called, friendship and trust damage, a reputation hit for the aggressor.

static func cfg() -> Dictionary:
	return JusticeState.sect("assault")

## Game event "argument": {folk_id, target_id, level}.
static func on_argument(a: int, b: int, level: int) -> void:
	var k: Dictionary = cfg()
	if not JusticeState.enabled or level < int(k.get("min_level", 3)):
		return
	var tension: float = maxf(RelationshipRomance.tension(a, b), RelationshipRomance.tension(b, a))
	if tension < float(k.get("min_tension", 45.0)):
		return
	var aggressor: int = a if _hotter(a, b) else b
	var other: int = b if aggressor == a else a
	var p: float = float(k.get("base", 0.06)) * (tension / 50.0)
	p *= _trait_mult(aggressor)
	p *= 1.0 / (1.0 + Police.officers() * 0.05)
	if JusticeState.chance(p):
		fight(aggressor, other)

static func _hotter(a: int, b: int) -> bool:
	return _trait_mult(a) >= _trait_mult(b)

static func _trait_mult(pid: int) -> float:
	var k: Dictionary = cfg().get("traits", {})
	var m: float = 1.0
	for t in CrimePerson.traits(pid):
		m *= float(k.get(str(t), 1.0))
	var f = CrimePerson.folk(pid)
	if f != null:
		for bf in cfg().get("drunk_buffs", []):
			if f.has_buff(str(bf)):
				m *= float(k.get("drunk", 2.0))
	return m

## The scuffle itself. Returns the case (or {} when nobody reported it).
static func fight(aggressor: int, victim: int, severity: int = -1) -> Dictionary:
	var k: Dictionary = cfg()
	if not (CrimePerson.alive(aggressor) and CrimePerson.alive(victim)):
		return {}
	var sev: int = severity if severity > 0 else (1 if JusticeState.chance(float(k.get("minor", 0.75))) else 2)
	var fv = CrimePerson.folk(victim)
	if fv != null:
		Hospital.injure(fv, sev, "a fight")
	elif sev >= 2:
		Hospital.admit(victim, sev, "a fight")
	var fa = CrimePerson.folk(aggressor)
	if fa != null and JusticeState.chance(float(k.get("aggressor_hurt", 0.25))):
		Hospital.injure(fa, 1, "a fight")
	for pr in [[aggressor, victim], [victim, aggressor]]:
		RelationshipService.add_value(pr[0], pr[1], "friendship", -float(k.get("friendship_loss", 25)))
		RelationshipService.add_value(pr[0], pr[1], "trust", -float(k.get("trust_loss", 20)))
	RelationshipService.add_history(aggressor, victim, "assault", -1.0, aggressor)
	RelationshipKnowledge.add_reputation(aggressor, -float(k.get("reputation", 5)))
	SysUtil.game_event("assault", {"folk_id": aggressor, "target_id": victim})
	var text: String = "%s lost their temper and hit %s." % [CrimePerson.name_of(aggressor), CrimePerson.name_of(victim)]
	if not JusticeState.chance(float(k.get("police_called", 0.5))):
		ChronicleHook.note("fight", text, [aggressor, victim], CrimePerson.home_key(victim), 1, false)
		if CrimePerson.is_player(aggressor) or CrimePerson.is_player(victim):
			SysUtil.notify(text, "bad")
		return {}
	var c: Dictionary = CaseStore.create("assault", aggressor, victim, CrimePlace.where_now(victim), {"witnessed": true, "witnesses": [victim],
		"witness_clarity": 0.95, "trace": 0.5})
	CrimePlace.place_at_scene(aggressor, str(c["scene"]))
	c["severity"] = sev
	CaseDiscovery.report(c, victim, "victim")
	CaseStore.note(c, text, "assault", 2)
	if CrimePerson.is_player(aggressor) or CrimePerson.is_player(victim):
		SysUtil.notify(text + " The police were called.", "bad")
	return c

## Daily statistical roll for feuding townie pairs (they are not simulated socially, so the feud itself comes from their records).
static func on_day() -> void:
	if not JusticeState.enabled:
		return
	var k: Dictionary = cfg()
	var ids: Array = CrimePerson.townies_only().filter(func(p): return not CrimePerson.folk(p) and CrimePerson.is_adult(p))
	for a in ids:
		for b in RelationshipBits.all_known(a):
			if int(b) <= a or not ids.has(int(b)):
				continue
			var hot: float = maxf(CrimeMurder.anger(a, int(b)) * CrimeMurder.propensity(a), CrimeMurder.anger(int(b), a) * CrimeMurder.propensity(int(b)))
			if hot >= float(k.get("far_anger", 0.5)) and JusticeState.chance(float(k.get("far_daily", 0.02)) * hot):
				var agg: int = a if CrimeMurder.anger(a, int(b)) >= CrimeMurder.anger(int(b), a) else int(b)
				fight(agg, int(b) if agg == a else a)
