class_name ThoughtContext
extends RefCounted
## Context for ThoughtVoice (view / flavour only): who a folk misses, likes and talks about, where they are and what just happened in town.
## Game events are noted from SimEnv.emit("game_event") into a short view-local list (never saved, never touches sim state or rng); the folk it
## concerns react once (rate-limited) and may recall it for a few days. All wording is in data/thought_voice.json (context / events / topics).

static var recent: Array = []     # [{ev: index into events, day, vars: {}, ids: Array (empty = anyone)}]

static func reset() -> void:
	recent.clear()

static func _events() -> Array:
	return ThoughtVoice.cfg().get("events", [])

static func _name(id: int) -> String:
	return "" if id < 0 else SysUtil.folk_name(id)

# ------------------------------------------------------------------ events
static func note(ev_name: String, p: Dictionary) -> void:
	var evs := _events()
	for i in evs.size():
		var e: Dictionary = evs[i]
		if str(e.get("event", "")) != ev_name:
			continue
		var ok := true
		for k in (e.get("filter", {}) as Dictionary):
			if str(p.get(k, "")) != str((e["filter"] as Dictionary)[k]):
				ok = false
		if not ok:
			continue
		var subj := int(p.get("folk_id", -1))
		var vars := {"subject": _name(subj), "other": _name(int(p.get("target_id", -1))), "baby": _name(int(p.get("baby_id", -1)))}
		var ids := _who(str(e.get("who", "all")), subj)
		var day := SysUtil.day()
		recent.append({"ev": i, "day": day, "vars": vars, "ids": ids})
		while recent.size() > 24:
			recent.pop_front()
		_react(e, vars, ids, subj, day)

static func _who(kind: String, subj: int) -> Array:
	var out: Array = []
	if kind == "all" or subj < 0:
		return out
	var sf = SysUtil.folk(subj)
	for r in SysUtil.residents():
		var rid := int(r.id)
		if rid == subj:
			continue
		if kind == "household" and sf != null and int(r.household_id) == int(sf.household_id):
			out.append(rid)
		elif kind == "kin" and (FamilyTree.is_kin(rid, subj) or RelationshipService.value(rid, subj, "friendship") >= 50.0 or (sf != null and int(r.household_id) == int(sf.household_id))):
			out.append(rid)
	return out

static func _react(e: Dictionary, vars: Dictionary, ids: Array, subj: int, day: int) -> void:
	var lines := ThoughtVoice._fill_pool(e.get("react", []), vars)
	if lines.is_empty():
		return
	var who: Array = ids.duplicate()
	if who.is_empty():
		for r in SysUtil.residents():
			who.append(int(r.id))
	who.sort_custom(func(a, b): return hash([a, day, subj]) < hash([b, day, subj]))
	var shown := 0
	var now := SimEnv.now_min()
	for w in who:
		if shown >= int(ThoughtVoice.conf().get("event_react_max", 2)):
			break
		var st := ThoughtVoice._state(int(w), now, day)
		var line := ThoughtVoice.pick_fresh(lines, st, day, hash([now, w, subj]))
		if ThoughtVoice.say(int(w), line, float(ThoughtVoice.conf().get("event_gap_frac", 0.25))):
			shown += 1

# ------------------------------------------------------------------ ambient context lines
## A line naming a person, place or recent event for `f`, or "" (then the normal line is used).
## No template is used more than template_max_per_day times a day and nobody is named more than name_max_per_day times (events excepted).
static func line(f, st: Dictionary, day: int, roll: int) -> String:
	var opts: Array = _options(f, day)
	if opts.is_empty():
		return ""
	var c: Dictionary = ThoughtVoice.conf()
	var tmax := int(c.get("template_max_per_day", 2))
	var nmax := int(c.get("name_max_per_day", 2))
	var look := int(c.get("lookback_days", 2))
	var start := absi(hash([roll, int(f.id), day])) % opts.size()
	for i in opts.size():
		var o: Dictionary = opts[(start + i) % opts.size()]
		var names: Array = o.get("names", [])
		var over := false
		for n in names:
			if not bool(o.get("event", false)) and int((st["named"] as Dictionary).get(n, 0)) >= nmax:
				over = true
		if over:
			continue
		var pool: Array = o["pool"]
		var ps := absi(hash([roll, i, int(f.id)])) % maxi(1, pool.size())
		for j in pool.size():
			var tmpl := str(pool[(ps + j) % pool.size()])
			if int((st["tmpl"] as Dictionary).get(tmpl, 0)) >= tmax:
				continue
			var got := ThoughtVoice.fill_one(tmpl, o["vars"])
			if got == "" or day - int((st["used"] as Dictionary).get(got, -99)) < look:
				continue
			(st["tmpl"] as Dictionary)[tmpl] = int((st["tmpl"] as Dictionary).get(tmpl, 0)) + 1
			for n in names:
				(st["named"] as Dictionary)[n] = int((st["named"] as Dictionary).get(n, 0)) + 1
			return got
	return ""

static func _options(f, day: int) -> Array:
	var c: Dictionary = ThoughtVoice.cfg()
	var ctx: Dictionary = c.get("context", {})
	var evs := _events()
	var out: Array = []
	var fid := int(f.id)
	for r in recent:
		var e: Dictionary = evs[int(r["ev"])]
		if day - int(r["day"]) > int(e.get("days", 3)):
			continue
		var ids: Array = r["ids"]
		if not ids.is_empty() and not ids.has(fid):
			continue
		for k in 2:       # recent news is weighted up
			out.append({"pool": e.get("recall", []), "vars": r["vars"], "event": true})
	for fr in _friends(fid, 4):
		out.append({"pool": ctx.get("friend", []), "vars": {"friend": _name(fr)}, "names": [_name(fr)]})
	var sp: int = FamilyTree.spouse_of(fid)
	if sp >= 0 and SysUtil.folk(sp) != null:
		out.append({"pool": ctx.get("partner", []), "vars": {"partner": _name(sp)}, "names": [_name(sp)]})
	var kid := _relative(FamilyTree.children_of(fid))
	if kid >= 0 and str(f.age_stage) not in ["baby", "toddler", "child"]:
		out.append({"pool": ctx.get("child", []), "vars": {"child": _name(kid)}, "names": [_name(kid)]})
	var par := _relative(FamilyTree.parents_of(fid))
	if par >= 0 and str(f.age_stage) not in ["baby", "toddler"]:
		out.append({"pool": ctx.get("parent", []), "vars": {"parent": _name(par)}, "names": [_name(par)]})
	if Careers.has_job(fid):
		out.append({"pool": ctx.get("work", []), "vars": {}})
	var lot: String = Neighborhood.lot_of_folk(f)
	if lot != "" and Venues.type_of_lot(lot) != "home" and (Venues.type_of_lot(lot) == "park" or not WeatherFolk.is_outside(f)):          # place thoughts only from inside the place, not its doorstep
		var pv := {"place": Neighborhood.label_of(lot)}
		var spec: Array = (c.get("venue_types", {}) as Dictionary).get(Venues.type_of_lot(lot), [])
		if not spec.is_empty():
			out.append({"pool": spec, "vars": pv})
			out.append({"pool": spec, "vars": pv})
		if (fid + day) % 3 == 0:
			out.append({"pool": ctx.get("venue", []), "vars": pv})
	if CityElection.phase == "campaign" and str(f.age_stage) not in ["baby", "toddler", "child"]:
		out.append({"pool": ctx.get("election", []), "vars": {}})
	return out

## Up to n living, known people this folk is fond of (friendship >= 30), most recently in touch first, ties by warmth.
static func _friends(fid: int, n: int) -> Array:
	var scored: Array = []
	for key in RelationshipService.keys_of(fid):
		var p: Dictionary = RelationshipService.pairs.get(key, {})
		if p.is_empty():
			continue
		var o := int(p["hi"]) if int(p["lo"]) == fid else int(p["lo"])
		var v := RelationshipService.value(fid, o, "friendship")
		if v >= 30.0 and (SysUtil.folk(o) != null or Story.is_townie(o)):
			scored.append([int(p.get("last_contact", 0)), v, o])
	scored.sort_custom(func(x, y): return x[0] > y[0] or (x[0] == y[0] and x[1] > y[1]))
	var out: Array = []
	for s in scored.slice(0, n):
		out.append(int(s[2]))
	return out

static func _relative(ids: Array) -> int:
	for i in ids:
		if SysUtil.folk(int(i)) != null:
			return int(i)
	return -1

# ------------------------------------------------------------------ chat helpers
## Sometimes steer a chat to the election or to the kids (topics that social.json does not list).
static func chat_override(actor: int, other: int, now: int) -> String:
	var r := ThoughtVoice.pick_index(actor, now, "override", 100)
	if r < 15 and CityElection.phase == "campaign":
		return "election"
	if r >= 85 and not FamilyTree.children_of(actor).is_empty() and not FamilyTree.children_of(other).is_empty():
		return "kids"
	return ""

## Someone both of them could gossip about (a mutual acquaintance or just someone the speaker knows), or -1.
static func third_party(actor: int, other: int, now: int) -> int:
	var cands: Array = []
	for key in RelationshipService.keys_of(actor):
		var p: Dictionary = RelationshipService.pairs.get(key, {})
		if p.is_empty():
			continue
		var o := int(p["hi"]) if int(p["lo"]) == actor else int(p["lo"])
		if o != other and o != actor and (SysUtil.folk(o) != null or Story.is_townie(o)):
			cands.append(o)
	if cands.is_empty():
		return -1
	cands.sort()
	return int(cands[absi(hash([now, actor, other])) % cands.size()])

static func child_name(actor: int, other: int) -> String:
	var k := _relative(FamilyTree.children_of(actor))
	if k < 0:
		k = _relative(FamilyTree.children_of(other))
	return _name(k)
