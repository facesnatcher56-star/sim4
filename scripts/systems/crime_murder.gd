class_name CrimeMurder
extends RefCounted
## Murder: never random. It needs a MOTIVE built over days (RAGE per ordered pair from tension, grudges, hatred, cheating, money), TRAITS
## (hot-headed, jealous, grudge-holding push it; forgiving, empathic, easy-going almost forbid it) and an OPPORTUNITY (alone together, at night).
## WARNING SIGNS: rage ~45 makes the culprit mutter threats and others gossip ("has been glaring at ..."); a player Folk who is the culprit
## OR the target gets a clear prompt and can step in (talk them down = reconcile). At the vow level a final countdown starts that can still be
## defused. Far townies run the same code statistically (townies can kill townies). Result: a case (hidden or witnessed), see CaseDiscovery.
## Incident `murder` (rate 0) exists only for the force hook / debug panel; the rate comes from this module (measure it with JusticeState.counter).

static func cfg() -> Dictionary:
	return JusticeState.sect("murder")

static func key(a: int, b: int) -> String:
	return "%d>%d" % [a, b]

static func rage_of(a: int, b: int) -> float:
	return float((JusticeState.grudges.get(key(a, b), {}) as Dictionary).get("rage", 0.0))

# ------------------------------------------------------------------ motive
## 0..1.4 how angry `a` is at `b` right now (relationships only; traits come in propensity).
static func anger(a: int, b: int) -> float:
	var k: Dictionary = cfg()
	var s: float = RelationshipRomance.tension(a, b) / 100.0 * float(k.get("tension_w", 0.5))
	s += RelationshipService.grudge(a, b) * float(k.get("grudge_w", 0.45))
	var fr: float = RelationshipService.value(a, b, "friendship")
	if fr < 0.0:
		s += clampf(-fr / 100.0, 0.0, 1.0) * float(k.get("hate_w", 0.4))
	if CrimePerson.is_kin_or_partner(a, b) and CrimePerson.coins(a) < 150 and CrimePerson.coins(b) > 700:
		s += float(k.get("greed_w", 0.15))
	return s

static func propensity(a: int) -> float:
	var k: Dictionary = cfg().get("traits", {})
	var m: float = 1.0
	for t in CrimePerson.traits(a):
		m *= float(k.get(str(t), 1.0))
	return m

# ------------------------------------------------------------------ daily
static func on_day_sched() -> void:
	on_day(DaySlices.enabled())

static func on_day(sliced: bool = false) -> void:
	if not JusticeState.enabled or Incidents.surprise_mult() <= 0.0:
		return
	JusticeState.counters["exposure_hh"] = float(JusticeState.counters.get("exposure_hh", 0.0)) + float(maxi(Economy.household_ids().size(), 1)) / float(IncidentDefs.cfg("year_days", 28))
	var keys: Array = RelationshipService.pairs.keys()
	keys.sort()
	if sliced:                               # one pair per call, spread over the day (DaySlices)
		DaySlices.begin("grudges", keys, Callable(CrimeMurder, "grudge_pair"))
		return
	for pk in keys:
		grudge_pair(pk)

## Is this person in the town and old enough to hold a grudge (adult or teen)?
static func _in_play(p: int) -> bool:
	if SysUtil.folk(p) == null and not bool(Story.townies.get(p, {}).get("alive", false)):
		return false
	return CrimePerson.is_adult(p) or CrimePerson.stage(p) == "teen"

## The daily grudge update of one relationship pair (both directions).
static func grudge_pair(pk) -> void:
	if not RelationshipService.pairs.has(pk):
		return
	var pr: Dictionary = RelationshipService.pairs[pk]
	var lo: int = int(pr["lo"])
	var hi: int = int(pr["hi"])
	if not (_in_play(lo) and _in_play(hi)):
		return
	var k: Dictionary = cfg()
	_update(lo, hi, k)
	_update(hi, lo, k)

static func _update(a: int, b: int, k: Dictionary) -> void:
	if CrimePerson.in_custody(a) or not CrimePerson.is_adult(a):
		return
	var kk: String = key(a, b)
	var g: Dictionary = JusticeState.grudges.get(kk, {})
	var drive: float = anger(a, b) * propensity(a)
	var rage: float = float(g.get("rage", 0.0))
	if drive > float(k.get("start_at", 0.55)):
		rage = minf(rage + (drive - float(k.get("start_at", 0.55))) * float(k.get("build_per_day", 30.0)), 100.0)
		if g.is_empty():
			g = {"rage": rage, "since": SysUtil.day(), "warned": 0, "vow": false}
	else:
		rage *= float(k.get("decay", 0.88))
	if g.is_empty() and rage < 1.0:
		return
	g["rage"] = rage
	if rage < 1.0:
		JusticeState.grudges.erase(kk)
		return
	JusticeState.grudges[kk] = g
	if rage >= float(k.get("warn_at", 45.0)) and int(g.get("warned", 0)) < 1:
		g["warned"] = 1
		_warn(a, b)
	if rage >= float(k.get("vow_at", 75.0)):
		g["vow"] = true
		if SysUtil.day() - int(g.get("since", SysUtil.day())) >= int(k.get("min_days", 6)) and not _queued(a, b):
			if JusticeState.chance(float(k.get("daily_chance", 0.05)) * _opportunity(a, b) * Incidents.surprise_mult() * Storyteller.hard_mult()):
				_begin(a, b)
	elif rage < float(k.get("warn_at", 45.0)) - 15.0:
		g["warned"] = 0

static func _queued(a: int, b: int) -> bool:
	for p in JusticeState.pending:
		if str(p.get("kind", "")) == "murder_due" and int(p["culprit"]) == a and int(p["victim"]) == b:
			return true
	return false

## 0..1 chance weight that the two are alone together at night (far folk: a flat statistical share).
static func _opportunity(a: int, b: int) -> float:
	var fa = CrimePerson.folk(a)
	var fb = CrimePerson.folk(b)
	if fa != null and fb != null:
		var la: String = CrimePlace.where_now(a)
		if la != CrimePlace.where_now(b):
			return 0.1
		var others: int = 0
		for o in WorldIface.all_folk():
			if int(o.id) != a and int(o.id) != b and CrimePlace.where_now(int(o.id)) == la:
				others += 1
		return 1.0 if others == 0 else 0.25
	return float(cfg().get("far_opportunity", 0.5))

# ------------------------------------------------------------------ warning signs
static func _warn(a: int, b: int) -> void:
	var an: String = CrimePerson.name_of(a)
	var bn: String = CrimePerson.name_of(b)
	var fa = CrimePerson.folk(a)
	if fa != null:
		SimEnv.emit("thought", a, "I can't stand %s any more..." % bn)
	# the whisper network: friends of both sides hear about it
	var holders: Array = CrimePerson.friends(a).slice(0, 2) + CrimePerson.friends(b).slice(0, 2)
	for h in holders:
		RelationshipKnowledge.add_gossip(int(h), a, "%s has been glaring at %s lately." % [an, bn], "murder_threat", -1, b)
	JusticeState.count("murder_warning")
	SysUtil.game_event("murder_warning", {"folk_id": a, "target_id": b})
	if CrimePerson.is_player(a) or CrimePerson.is_player(b):
		var pid: int = a if CrimePerson.is_player(a) else b
		var text: String = ("%s is consumed by rage at %s. This could end very badly." % [an, bn]) if CrimePerson.is_player(a) \
			else ("%s has been glaring at %s with real hatred. %s may be in danger." % [an, bn, bn])
		JusticePlayer.ask(pid, "A dangerous grudge", text, [{"id": "step_in", "label": "Step in and calm things down"}, {"id": "ignore", "label": "Let it be"}],
			_step_choice.bind(a, b), "step_in")

static func _step_choice(choice, a: int, b: int) -> void:
	if str(choice) == "step_in":
		defuse(a, b)

## Calm a feud: tension and rage fall (the "step in" action; also fires from apologies via CrimeFlow).
static func defuse(a: int, b: int) -> void:
	SocialConflict.reconcile(a, b, 45.0, "calmed")
	RelationshipRomance.add_tension(a, b, -30.0)
	var kk: String = key(a, b)
	if JusticeState.grudges.has(kk):
		JusticeState.grudges[kk]["rage"] = float(JusticeState.grudges[kk]["rage"]) * 0.35
		JusticeState.grudges[kk]["vow"] = false
		JusticeState.grudges[kk]["warned"] = 0
	var fa = CrimePerson.folk(a)
	if fa != null:
		fa.add_buff("calmed_down")

# ------------------------------------------------------------------ the act
static func _begin(a: int, b: int) -> void:
	var lead: int = int(cfg().get("player_lead_min", 180)) if (CrimePerson.is_player(a) or CrimePerson.is_player(b)) else 0
	if lead > 0:
		var an: String = CrimePerson.name_of(a)
		var bn: String = CrimePerson.name_of(b)
		var pid: int = a if CrimePerson.is_player(a) else b
		JusticePlayer.ask(pid, "Something terrible is about to happen",
			"%s has made up their mind about %s and is going to find them tonight. Step in now, or it will be too late." % [an, bn],
			[{"id": "step_in", "label": "Step in now"}, {"id": "ignore", "label": "Let it happen"}],
			_step_choice.bind(a, b), "ignore")
	JusticeState.queue({"kind": "murder_due", "culprit": a, "victim": b, "due_min": _when(lead)})

## A random moment, never the moment of the daily tick: `lead` minutes from now plus up to four hours, and when that lands in the daytime the
## coming night (22:00 to 05:00) instead, so it is when the two are likely alone together.
static func _when(lead: int) -> int:
	var t: int = SysUtil.now() + maxi(lead, 30) + JusticeState.rng.randi_range(0, 240)
	var mod: int = t % 1440
	if mod >= 360 and mod < 1320:
		t += (1320 - mod) + JusticeState.rng.randi_range(0, 420)
	return t

## The final countdown ended: still enraged and still the chance? Then it happens.
static func due(p: Dictionary) -> void:
	var a: int = int(p["culprit"])
	var b: int = int(p["victim"])
	if not (CrimePerson.alive(a) and CrimePerson.alive(b)) or CrimePerson.in_custody(a):
		return
	if rage_of(a, b) < float(cfg().get("vow_at", 75.0)) - 10.0:
		SysUtil.game_event("murder_averted", {"folk_id": a, "target_id": b})
		if CrimePerson.is_player(a) or CrimePerson.is_player(b):
			SysUtil.notify("The danger passed. %s and %s stepped back from the edge." % [CrimePerson.name_of(a), CrimePerson.name_of(b)], "good")
		return
	execute(a, b)

static func execute(a: int, b: int, forced_scene: String = "") -> Dictionary:
	var scene: String = forced_scene
	if scene == "":
		scene = CrimePlace.where_now(b)
		if scene in ["work", "away", "unknown"]:
			scene = CrimePerson.home_key(b)
	var kk: String = key(a, b)
	JusticeState.grudges.erase(kk)
	return kill(a, b, scene, "murder", {})

## The killing, shared by murder, a mugging gone wrong, serial killers. kind: murder | manslaughter | serial.
static func kill(culprit: int, victim: int, scene: String, kind: String, opts: Dictionary) -> Dictionary:
	var k: Dictionary = cfg()
	var others: Array = []
	for o in CrimePerson.everyone():
		if o != culprit and o != victim and CrimePlace.where_now(o) == scene and scene != "street" and scene != "unknown":
			others.append(o)
	var public_scene: bool = scene == "street" or scene.begins_with("venue:")
	var seen_p: float = float(k.get("witness_public", 0.45)) if public_scene else (float(k.get("witness_home", 0.25)) if not others.is_empty() else float(k.get("witness_alone", 0.04)))
	if kind == "serial":
		seen_p *= float(JusticeState.sect("serial").get("witness_mult", 0.4))
	seen_p *= Police.patrol_factor() * 0.5 + 0.5
	var witnessed: bool = JusticeState.chance(seen_p)
	var witnesses: Array = []
	if witnessed:
		witnesses = [others[0]] if not others.is_empty() else []
	var c: Dictionary
	if opts.has("case") and CaseStore.has_case(int(opts["case"])):
		c = CaseStore.get_case(int(opts["case"]))
		c["kind"] = kind
		c["victim"] = victim
	else:
		c = CaseStore.create(kind, culprit, victim, scene, {})
	c["witnessed"] = witnessed
	c["witnesses"] = witnesses
	c["witness_clarity"] = JusticeState.rng.randf_range(0.5, 0.9) if witnessed else 0.0
	c["trace"] = JusticeState.rng.randf_range(float(k.get("trace_min", 0.25)), float(k.get("trace_max", 0.55)))
	if kind == "serial":
		c["trace"] = float(c["trace"]) * 0.4          # careful: little to find on any single victim
	c["concealed"] = JusticeState.rng.randf_range(0.0, 0.6) if not public_scene else 0.0
	c["missing_mult"] = JusticeState.rng.randf_range(0.7, 1.3)
	c["vhid"] = CrimePerson.hid(victim)
	c["found"] = false
	c["folk_victim"] = CrimePerson.folk(victim) != null
	var cause: String = "murder" if kind in ["murder", "serial"] else "killed_in_fight"
	CrimePlace.place_at_scene(culprit, scene)
	CrimePerson.add_buff_safe(culprit, "troubled_conscience")
	SysUtil.game_event("murder", {"culprit": culprit, "victim": victim, "case": int(c["id"])})
	if witnessed or CrimePerson.folk(victim) != null:
		# seen, or a Folk on the map: the death is known at once
		CrimePerson.hide_death(victim, cause)
		var rep: int = int(witnesses[0]) if not witnesses.is_empty() else -1
		c["state"] = "hidden"
		CaseDiscovery.report(c, rep, "seen" if witnessed else "body")
	else:
		CrimePerson.hide_death(victim, cause)         # townie: gone quietly, found later
	return c