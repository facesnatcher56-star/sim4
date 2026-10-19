class_name EduTownies
extends RefCounted
## Education for the townies (task 14), STATISTICAL: no bodies, one line per townie per day. Adults without a degree sometimes enrol (a major
## close to their career when they have one), earn a credit on some days and graduate after `credits_needed` credits; the chronicle gets a line
## for the graduation. School events pick a child or teen townie as one of the winners. Residents never come through here.

static func on_day(_day: int) -> void:
	var c: Dictionary = EduState.cfg().get("townies", {})
	var need: int = int(EduState.cfg().get("college", {}).get("credits_needed", 12))
	for t in Story.alive_townies():
		var tid: int = int(t["id"])
		if Story.stage_of(t) != "adult" or Hospital.is_in(tid) or JusticeState.inmates.has(tid):
			continue
		var r: Dictionary = EduState.peek(tid)
		var col: Dictionary = r.get("college", {})
		if col.is_empty():
			if (r.get("degrees", []) as Array).size() >= 2 or EduState.rng.randf() >= float(c.get("enrol_chance", 0.015)):
				continue
			var major: String = _major_for(t, r)
			if major == "":
				continue
			EduState.rec(tid)["college"] = {"major": major, "credits": 0, "lectures": 0, "scores": []}
			continue
		if EduState.rng.randf() < float(c.get("credit_chance", 0.4)):
			col["credits"] = int(col["credits"]) + 1
			if int(col["credits"]) >= need:
				_graduate(t, str(col["major"]))

static func _major_for(t: Dictionary, r: Dictionary) -> String:
	var have: Array = r.get("degrees", [])
	var options: Array = []
	for m in LifeDefs.section("majors"):
		if have.has(m):
			continue
		options.append(str(m))
		if (EduCollege.major_def(str(m)).get("careers", []) as Array).has(str(t.get("career", "-"))):
			options.append(str(m))
			options.append(str(m))
	options.sort()
	return "" if options.is_empty() else str(options[EduState.rng.randi_range(0, options.size() - 1)])

static func _graduate(t: Dictionary, major: String) -> void:
	var tid: int = int(t["id"])
	var r: Dictionary = EduState.rec(tid)
	r["college"] = {}
	if not (r["degrees"] as Array).has(major):
		(r["degrees"] as Array).append(major)
	LifeNote.say("graduation", "%s graduated from Fernwood College with a degree in %s." % [t["name"], EduCollege.major_label(major)], [tid], 1, false)

## One child or teen townie takes a prize at a school event (chronicle only).
static func school_event(id: String, e: Dictionary) -> void:
	if id == "parents_evening" or str(e.get("win", "")) == "":
		return
	var kids: Array = Story.alive_townies().filter(func(t): return Story.stage_of(t) in e.get("stages", []))
	if kids.is_empty() or EduState.rng.randf() > 0.6:
		return
	var t: Dictionary = kids[EduState.rng.randi_range(0, kids.size() - 1)]
	LifeNote.say("school_event", str(e["win"]).replace("{name}", str(t["name"])), [int(t["id"])], 1, false)
