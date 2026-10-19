class_name CaseStore
extends RefCounted
## The shared CASE RECORD. One dictionary per crime, JSON safe, kept in JusticeState.cases:
##   id, kind (burglary | robbery | assault | murder | theft | arson | manslaughter | serial), scene ("home:1" | "town:3" | "street"), day, minute,
##   culprit (the TRUTH), victim (-1 for a house), vhid (household id of the victim lot or person, 0 = none), witnessed (bool), witnesses [ids],
##   witness_clarity (0..1 how well they could identify), trace (0..1 physical evidence left), loot [{def, tile, rot, value}], stolen_coins,
##   state (hidden | open | arrested | charged | trial | closed | cold), disc_day, reporter, progress (investigation work done),
##   tips (extra evidence from new leads 0..1), recovered (bool), accused (who police believe), suspect_ids [top suspects], wrongful (accused != culprit),
##   charge, bail, lawyer, plea, trial {...}, verdict (guilty | not_guilty | mistrial | plea | ""), sentence {...}, serial (serial run id or -1),
##   notes [{day, text}] (the case board story), reopened (count), hush (bool: the victim never reported it), public (the paper may print it).
## Create with CaseStore.create(); look up with get_case(). Every state change calls note() which also feeds the Town Chronicle.

const KINDS := ["burglary", "robbery", "assault", "murder", "theft", "arson", "manslaughter", "serial"]

static func get_case(cid: int) -> Dictionary:
	return JusticeState.cases.get(cid, {})

static func has_case(cid: int) -> bool:
	return JusticeState.cases.has(cid)

static func create(kind: String, culprit: int, victim: int, scene: String, opts: Dictionary = {}) -> Dictionary:
	var vh: int = int(opts.get("vhid", 0))
	if vh <= 0 and victim >= 0:
		vh = CrimePerson.hid(victim)
	if vh <= 0 and scene.begins_with("home:"):
		vh = int(scene.get_slice(":", 1))
	var c: Dictionary = {"id": JusticeState.next_case, "kind": kind, "scene": scene, "day": SysUtil.day(), "minute": SysUtil.now(), "culprit": culprit,
		"victim": victim, "vhid": vh, "witnessed": bool(opts.get("witnessed", false)), "witnesses": SysUtil.to_ints(opts.get("witnesses", [])),
		"witness_clarity": float(opts.get("witness_clarity", 0.0)), "trace": float(opts.get("trace", 0.2)), "loot": opts.get("loot", []),
		"loot_value": int(opts.get("loot_value", 0)), "stolen_coins": int(opts.get("stolen_coins", 0)), "state": "hidden", "disc_day": -1, "reporter": -1,
		"progress": 0.0, "tips": 0.0, "recovered": false, "accused": -1, "suspect_ids": [], "wrongful": false, "charge": "", "bail": 0, "lawyer": -1,
		"plea": false, "trial": {}, "verdict": "", "sentence": {}, "serial": int(opts.get("serial", -1)), "notes": [], "reopened": 0,
		"hush": false, "victim_name": CrimePerson.name_of(victim) if victim >= 0 else "", "public": bool(opts.get("public", true)), "missing": 0.0, "hours_hidden": 0, "reported_min": -1}
	JusticeState.next_case += 1
	JusticeState.cases[int(c["id"])] = c
	JusticeState.count(kind)
	JusticeState.year_log.append({"day": SysUtil.day(), "kind": kind, "solved": false, "case": int(c["id"])})
	_trim()
	return c

static func _trim() -> void:
	var cap: int = int(JusticeState.sect("general").get("case_cap", 160))
	while JusticeState.cases.size() > cap:
		var oldest: int = -1
		for cid in JusticeState.cases:
			if str(JusticeState.cases[cid]["state"]) == "closed" and (oldest < 0 or int(cid) < oldest):
				oldest = int(cid)
		if oldest < 0:
			break
		JusticeState.cases.erase(oldest)
	while JusticeState.year_log.size() > 400:
		JusticeState.year_log.pop_front()

## A line for the case board, plus (optionally) a Town Chronicle entry. `sev` 1..5.
static func note(c: Dictionary, text: String, chron_kind: String = "", sev: int = 2, is_public: bool = true) -> void:
	(c["notes"] as Array).append({"day": SysUtil.day(), "text": text})
	while (c["notes"] as Array).size() > 24:
		(c["notes"] as Array).pop_front()
	if chron_kind != "":
		var subs: Array = []
		for k in ["culprit", "victim"]:
			if int(c.get(k, -1)) >= 0 and str(c["state"]) != "hidden":
				subs.append(int(c[k]))
		if str(c["state"]) == "hidden":
			subs = []
		ChronicleHook.note(chron_kind, text, subs, str(c["scene"]) if str(c["scene"]).begins_with(("home:")) or str(c["scene"]).begins_with("town:") else "",
			sev, is_public and bool(c.get("public", true)))

static func mark_solved(c: Dictionary) -> void:
	for e in JusticeState.year_log:
		if int(e.get("case", -1)) == int(c["id"]):
			e["solved"] = true

## Cases in a given state (or any of several), oldest first.
static func in_state(states: Array) -> Array:
	var out: Array = []
	var ids: Array = JusticeState.cases.keys()
	ids.sort()
	for id in ids:
		if states.has(str(JusticeState.cases[id]["state"])):
			out.append(JusticeState.cases[id])
	return out

static func open_cases() -> Array:
	return in_state(["open", "cold"])

static func cases_of_culprit(pid: int) -> Array:
	return JusticeState.cases.values().filter(func(c): return int(c["culprit"]) == pid)

static func household_involved(c: Dictionary) -> bool:
	for k in ["culprit", "victim", "accused"]:
		if int(c.get(k, -1)) >= 0 and CrimePerson.is_player(int(c[k])):
			return true
	return int(c.get("vhid", 0)) > 0 and str(c.get("scene", "")).begins_with("home:") or CrimePerson.hid(int(c.get("accused", -1))) > 0

## Toast only when the household is involved, or when `force` is set (town news).
static func toast(c: Dictionary, text: String, kind: String = "info", force: bool = false) -> void:
	if force or household_involved(c) or _household_knows(c):
		SysUtil.notify(text, kind)

static func _household_knows(c: Dictionary) -> bool:
	for k in ["victim", "culprit"]:
		var pid: int = int(c.get(k, -1))
		if pid < 0:
			continue
		for r in SysUtil.residents():
			if RelationshipService.knows(int(r.id), pid) and RelationshipService.value(int(r.id), pid, "friendship") >= 25.0:
				return true
	return false

static func kind_label(kind: String) -> String:
	return {"burglary": "burglary", "robbery": "robbery", "assault": "assault", "murder": "murder", "theft": "theft", "arson": "arson",
		"manslaughter": "manslaughter", "serial": "murder", "order_violation": "breach of a protective order"}.get(kind, kind)

## One short player-facing title for lists: "Murder of Ada Finch (open)".
static func title(c: Dictionary) -> String:
	var v: String = CaseText.victim_name(c) if int(c["victim"]) >= 0 else ""
	var base: String
	match str(c["kind"]):
		"burglary": base = "Break-in at %s" % house_label(str(c["scene"]))
		"theft": base = "Theft at %s" % house_label(str(c["scene"]))
		"robbery": base = "Robbery of %s" % v
		"assault": base = "Assault on %s" % v
		"murder", "serial": base = "Death of %s" % v
		"arson": base = "Arson at %s" % house_label(str(c["scene"]))
		"manslaughter": base = "Death of %s" % v
		"order_violation": base = "Broken protective order (%s)" % v
		"fraud": base = "Fraud against %s" % v
		"embezzlement": base = "Missing money at work"
		"blackmail": base = "Blackmail of %s" % v
		"vandalism", "trespassing", "disturbance", "shoplifting": base = kind_label(str(c["kind"])).capitalize()
		_: base = "Case"
	return base

static func house_label(scene: String) -> String:
	if scene.begins_with("home:"):
		return "your home" if CrimePerson.hid(int(JusticeState.sect("general").get("_probe", -1))) < 0 else "your home"
	if scene.begins_with("town:"):
		var n: int = int(scene.get_slice(":", 1))
		for tid in Story.townies:
			if int(Story.townies[tid].get("lot", 0)) == n:
				var parts: PackedStringArray = str(Story.townies[tid]["name"]).split(" ")
				return "the %s house" % parts[parts.size() - 1]
		return "a house in town"
	return "the street"

static func state_label(c: Dictionary) -> String:
	return {"hidden": "Unnoticed", "open": "Open", "cold": "Cold", "arrested": "Suspect held", "charged": "Charged", "trial": "In court",
		"closed": "Closed"}.get(str(c["state"]), str(c["state"]))

## The accused died before the trial (or before the sentence ended): the case is closed with a plain line in the notes and the Chronicle.
static func close_for_death(c: Dictionary, pid: int) -> void:
	if str(c["state"]) in ["closed"] or int(c.get("accused", -1)) != pid:
		return
	c["state"] = "closed"
	c["closed_day"] = SysUtil.day()
	c["verdict"] = ""
	c["died_before_trial"] = true
	JusticeState.inmates.erase(pid)
	note(c, "%s died before the trial. The case is closed." % CrimePerson.name_of(pid), "case_closed", 3)

## Called when somebody dies: any case that was waiting for their trial is closed.
static func on_death(pid: int) -> void:
	for c in in_state(["arrested", "charged", "trial"]):
		if int(c.get("accused", -1)) == pid:
			close_for_death(c, pid)