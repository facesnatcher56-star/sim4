class_name StoryThreads
extends RefCounted
## Long-running story threads: follow-ups to earlier events, from the small table in data/story_pacing.json "threads"
## (trigger event, conditions, delay in days, action). Examples: the cheated partner takes revenge or forgives; an ex turns up at the
## door; a townie who fell ill comes round to say thanks. Pending follow-ups are not saved (they are days long).

static var pending: Array = []      # [{thread, due, a, b}]

static func reset() -> void:
	pending.clear()

static func _threads(on: String) -> Array:
	var out: Array = []
	for t in StoryPacing.cfg().get("threads", []):
		if str(t["on"]) == on:
			out.append(t)
	return out

static func _is_resident(id: int) -> bool:
	return SysUtil.is_resident(SysUtil.folk(id))

static func _is_townie(id: int) -> bool:
	return Story.is_townie(id) and bool(Story.townies[id]["alive"]) and not _is_resident(id)

static func _schedule(t: Dictionary, a: int, b: int) -> void:
	var dd: Array = t.get("delay_days", [1, 3])
	pending.append({"thread": str(t["id"]), "due": SysUtil.day() + SysUtil.rng.randi_range(int(dd[0]), int(dd[1])), "a": a, "b": b})

static func on_event(ev: String, p: Dictionary) -> void:
	for t in _threads(ev):
		var w: Dictionary = t.get("when", {})
		var a: int = int(p.get("folk_id", -1))
		var b: int = int(p.get("target_id", -1))
		if w.has("cause") and str(p.get("cause", "")) != str(w["cause"]):
			continue
		if bool(w.get("other_is_townie", false)):
			if _is_resident(a) and _is_townie(b):
				_schedule(t, a, b)
			elif _is_resident(b) and _is_townie(a):
				_schedule(t, b, a)
			continue
		if _is_resident(a) or _is_resident(b):
			_schedule(t, a, b)

static func on_chronicle(p: Dictionary) -> void:
	for t in _threads("chronicle"):
		var w: Dictionary = t.get("when", {})
		if not (w.get("kinds", []) as Array).has(str(p.get("kind", ""))):
			continue
		for s in p.get("subjects", []):
			if not _is_townie(int(s)):
				continue
			var host := -1
			for r in SysUtil.residents():
				if RelationshipService.knows(int(r.id), int(s)):
					host = int(r.id)
					break
			if host >= 0 or not bool(w.get("known", false)):
				_schedule(t, host, int(s))
			break

static func on_day(day: int) -> void:
	var keep: Array = []
	for e in pending:
		if int(e["due"]) > day:
			keep.append(e)
			continue
		_run(e)
	pending = keep

static func _def(id: String) -> Dictionary:
	for t in StoryPacing.cfg().get("threads", []):
		if str(t["id"]) == id:
			return t
	return {}

static func _run(e: Dictionary) -> void:
	var t: Dictionary = _def(str(e["thread"]))
	if t.is_empty():
		return
	var a: int = int(e["a"])
	var b: int = int(e["b"])
	match str(t.get("action", "")):
		"revenge_or_forgive":
			_revenge_or_forgive(t, a, b)
		"visit_from_other", "visit_from_subject":
			_visit(t, a, b)

static func _revenge_or_forgive(t: Dictionary, victim: int, cheater: int) -> void:
	var fv = SysUtil.folk(victim)
	var fc = SysUtil.folk(cheater)
	if fv == null or fc == null:
		return
	var p: float = float(t.get("forgive", 0.4))
	if fv.has_trait("forgiving"):
		p += 0.25
	if fv.has_trait("grudgeholder"):
		p -= 0.3
	if fv.has_trait("jealous"):
		p -= 0.1
	if SysUtil.chance(p):
		RelationshipService.add_both(victim, cheater, "friendship", 15.0)
		fv.add_buff("cheered_up")
		SysUtil.notify("%s decided to forgive %s." % [fv.name, fc.name], "relationship")
		ChronicleHook.note("forgiveness", "%s forgave %s." % [fv.name, fc.name], [victim, cheater], "home:%d" % int(fv.household_id), 2, false)
	else:
		fc.add_buff("embarrassed")
		RelationshipService.add_value(cheater, victim, "friendship", -6.0)
		SysUtil.notify("%s got back at %s with a prank everyone heard about." % [fv.name, fc.name], "relationship")
		ChronicleHook.note("revenge", "%s got back at %s." % [fv.name, fc.name], [victim, cheater], "home:%d" % int(fv.household_id), 2, false)

static func _visit(t: Dictionary, host: int, guest: int) -> void:
	if host < 0 or SysUtil.folk(host) == null or not Story.townies.has(guest) or not bool(Story.townies[guest]["alive"]):
		return
	var arrive: int = StoryVisits.daytime(SysUtil.now() + 60)
	StoryVisits.schedule_visit([guest], host, arrive, 120, "visit")
	var txt: String = str(t.get("text", "{other} came by.")).replace("{other}", Story.name_of(guest)).replace("{subject}", Story.name_of(guest))
	SysUtil.notify(txt, "visit")
