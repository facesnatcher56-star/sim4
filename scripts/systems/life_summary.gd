class_name LifeSummary
extends RefCounted
## The end-of-life summary (task 44): when the character the player plays dies, the game says plainly what happened, why, and what their choices set in
## motion. Built from the LifeLedger; shown before the heir takes over and kept (`books`) for the heir and the Household window.
##   LifeSummary.build(pid, name) -> {title, name, sections: [{title, lines: [String]}], numbers: {...}}

static var books: Dictionary = {}          # dead person id -> summary (saved with the ledger)
static var last_id: int = -1

static func reset() -> void:
	books = {}
	last_id = -1

static func _day(e: Dictionary) -> String:
	return "Day %d" % int(e["day"])

static func _lc(t: String) -> String:
	return t.trim_suffix(".")

static func _because(e: Dictionary) -> String:
	var ch: Array = LifeLedger.chain(int(e["id"]), 3)
	if ch.is_empty():
		return ""
	var parts: Array = []
	for c in ch:
		parts.append(_lc(str(c["text"])))
	return " Because: " + "; before that, ".join(parts) + "."

static func build(pid: int, nm: String) -> Dictionary:
	var mine: Array = []
	var choices: Array = []
	var hits: Array = []
	var others: Dictionary = {}
	for e in LifeLedger.entries:
		if not (e["who"] as Array).has(pid):
			continue
		mine.append(e)
		if bool(e["choice"]):
			choices.append(e)
		elif int(e["sev"]) >= 3:
			hits.append(e)
		for w in e["who"]:
			if int(w) != pid:
				others[int(w)] = e
	var life: Array = []
	for e in mine:
		if not bool(e["choice"]) and int(e["sev"]) >= 2:
			life.append("%s: %s%s" % [_day(e), str(e["text"]), _because(e)])
	var ranked: Array = []
	for c in choices:
		var eff: Array = LifeLedger.effects_of(int(c["id"]), 4)
		var people: Dictionary = {}
		for x in eff:
			for w in x["who"]:
				if int(w) != pid:
					people[int(w)] = true
		ranked.append({"c": c, "eff": eff, "n": people.size() + eff.size()})
	ranked.sort_custom(func(a, b): return int(a["n"]) > int(b["n"]))
	var motion: Array = []
	for r in ranked.slice(0, 6):
		if (r["eff"] as Array).is_empty():
			continue
		var bits: Array = []
		for x in (r["eff"] as Array).slice(0, 3):
			bits.append(_lc(str(x["text"])))
		motion.append("%s: %s. Then: %s." % [_day(r["c"]), _lc(str(r["c"]["text"])), "; ".join(bits)])
	var happened: Array = []
	for e2 in hits.slice(maxi(hits.size() - 8, 0)):
		happened.append("%s: %s%s" % [_day(e2), str(e2["text"]), _because(e2)])
	var people_lines: Array = []
	for oid in others.keys().slice(0, 8):
		people_lines.append("%s: %s" % [CrimePerson.name_of(int(oid)), str(others[oid]["text"])])
	var friends: int = RelationshipBits.count_bit(pid, "friend", true)
	var kids: int = (Aging.records.get(pid, {}) as Dictionary).get("children", []).size()
	var numbers: Dictionary = {"events": mine.size(), "choices": choices.size(), "lives_touched": others.size(), "children": kids, "friends": friends}
	var sections: Array = [
		{"title": "Your life", "lines": life.slice(maxi(life.size() - 14, 0))},
		{"title": "What you set in motion", "lines": motion},
		{"title": "What happened to you, and why", "lines": happened},
		{"title": "The people in your life", "lines": people_lines},
		{"title": "In numbers", "lines": ["%d moments that mattered, %d choices, %d other lives touched, %d children, %d friends at the end." % [mine.size(), choices.size(), others.size(), kids, friends]]}]
	return {"title": "The life of %s" % nm, "name": nm, "sections": sections, "numbers": numbers}

## Called when the pawn dies (Succession.begin): build, keep, tell the UI.
static func on_pawn_death(pid: int, nm: String) -> void:
	books[pid] = build(pid, nm)
	last_id = pid
	SysUtil.game_event("life_summary", {"folk_id": pid})

static func to_dict() -> Dictionary:
	return {"books": SysUtil.str_keys(books).duplicate(true), "last": last_id}

static func from_dict(d: Dictionary) -> void:
	reset()
	books = SysUtil.int_keys((d.get("books", {}) as Dictionary).duplicate(true))
	last_id = int(d.get("last", -1))
