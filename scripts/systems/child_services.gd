class_name ChildServices
extends RefCounted
## Child services (task 20.4): what happens after a child was hurt at home (CrimeChildAbuse).
## DISCOVERY (09b style): a teacher at school or a doctor (mandatory reporters, high chance), a relative or neighbour who notices, or the child telling
## a trusted adult. REPORT -> a HOME VISIT the next day -> unfounded (nothing more), a safety plan (parenting course, watched for a month, police when
## there is evidence) or REMOVAL (serious or repeated): the child is placed with a safe relative or in foster care. The child returns when the parenting
## course is done and no protective order stands. All text is clinical; the Chronicle says only "child services visited the Orr house".

static func cfg() -> Dictionary:
	return JusticeState.sect("child_abuse")

static func kids() -> Dictionary:
	return JusticeState.abuse["kids"]

static func _source_text(source: String) -> String:
	return {"teacher": "A teacher", "doctor": "A doctor", "relative": "A relative", "neighbour": "A neighbour", "child": "The child told a trusted adult, who"}.get(source, "Someone")

# ------------------------------------------------------------------ discovery
static func on_day() -> void:
	if not JusticeState.enabled:
		return
	var D: Dictionary = cfg().get("discovery", {})
	var ids: Array = kids().keys()
	ids.sort()
	for child in ids:
		var kid: Dictionary = kids()[child]
		if (kid.get("placed", {}) as Dictionary).is_empty() == false:
			try_return(int(child), kid)
			continue
		if not bool(kid.get("reported", false)):
			_detect(int(child), kid, D)
		elif not bool(kid.get("visited", false)) and SysUtil.day() >= int(kid.get("visit_day", 0)):
			visit(int(child))
		elif bool(kid.get("visited", false)) and int(kid.get("follow_day", -1)) >= 0 and SysUtil.day() >= int(kid["follow_day"]):
			kid["follow_day"] = -1
			var fc: Dictionary = CaseStore.get_case(int(kid.get("case", -1)))
			if not fc.is_empty():
				CaseStore.note(fc, "Child services checked on %s again; things were calmer." % CrimePerson.name_of(int(child)), "", 1)

static func _detect(child: int, kid: Dictionary, D: Dictionary) -> void:
	var c: Dictionary = CaseStore.get_case(int(kid.get("case", -1)))
	if c.is_empty() or str(c["state"]) != "hidden":
		return
	var visible: bool = SysUtil.day() - int(kid.get("last_day", -99)) <= int(D.get("visible_days", 10))
	var stage: String = CrimePerson.stage(child)
	var carer: int = int(kid.get("carer", -1))
	var routes: Array = []        # [source, probability today]
	if visible and stage == "child" and SysUtil.weekday() < 5:
		routes.append(["teacher", float(D.get("teacher_per_day", 0.3)) * float(D.get("teacher_report", 0.85))])
	var outside: bool = false
	for o in CrimePerson.close_alive(child) + CrimePerson.friends(child):
		var oid: int = int(o)
		if oid != carer and CrimePerson.is_adult(oid) and (CrimePerson.hid(oid) == 0 or CrimePerson.hid(oid) != CrimePerson.hid(child)):
			outside = true
			if stage == "child" and RelationshipService.value(child, oid, "friendship") >= 50.0:
				routes.append(["child", float(D.get("tells_per_day", 0.05)) * float(D.get("tells_report", 0.7))])
				break
	if outside:
		routes.append(["relative", (float(D.get("relative_per_day", 0.08)) if visible else float(D.get("late_per_day", 0.008))) * float(D.get("relative_report", 0.55))])
	for r in routes:
		if JusticeState.chance(float(r[1])):
			report(child, str(r[0]))
			return

## A doctor treats the child (hospital stay, clinic): the injuries are noticed at once.
static func on_treated(child: int) -> void:
	var kid: Dictionary = kids().get(child, {})
	if kid.is_empty() or bool(kid.get("reported", false)):
		return
	if SysUtil.day() - int(kid.get("last_day", -99)) > int(cfg().get("discovery", {}).get("visible_days", 10)):
		return
	if JusticeState.chance(float(cfg().get("discovery", {}).get("doctor_report", 0.95))):
		report(child, "doctor")

static func report(child: int, source: String) -> void:
	var kid: Dictionary = kids().get(child, {})
	if kid.is_empty():
		return
	kid["reported"] = true
	kid["visited"] = false
	kid["source"] = source
	kid["report_day"] = SysUtil.day()
	kid["visit_day"] = SysUtil.day() + int(cfg().get("services", {}).get("visit_delay", 1))
	kids()[child] = kid
	JusticeState.count("abuse_reports")
	var nm: String = CrimePerson.name_of(child)
	var text: String = "%s %s concerns about %s to child services." % [_source_text(source), "raised" if source != "child" else "passed on", nm]
	var c: Dictionary = CaseStore.get_case(int(kid.get("case", -1)))
	if not c.is_empty():
		CaseStore.note(c, text, "", 2)
	if CrimePerson.is_player(child) or CrimePerson.is_player(int(kid.get("carer", -1))):
		SysUtil.notify("Child services have been told about concerns for %s and will visit soon." % nm, "warn")

# ------------------------------------------------------------------ the home visit
static func visit(child: int) -> void:
	var S: Dictionary = cfg().get("services", {})
	var kid: Dictionary = kids()[child]
	kid["visited"] = true
	var carer: int = int(kid.get("carer", -1))
	var c: Dictionary = CaseStore.get_case(int(kid.get("case", -1)))
	var recent: bool = SysUtil.day() - int(kid.get("last_day", -99)) <= int(cfg().get("discovery", {}).get("visible_days", 10)) + 4
	var p: float = float(S.get("substantiated_base", 0.5)) + float(S.get("per_incident", 0.2)) * float(int(kid.get("incidents", 1)) - 1) + (float(S.get("injury_bonus", 0.2)) if recent else 0.0)
	if str(kid.get("source", "")) == "doctor":
		p += 0.2
	var house: String = _house(child)
	ChronicleHook.note("child_services", "Child services visited the %s house." % house, [carer, child], CrimePerson.home_key(child), 2, true)
	if not JusticeState.chance(clampf(p, 0.0, 0.95)):
		kid["reported"] = false                  # nothing found this time; the file stays and a later report can reopen it
		kid["unfounded"] = int(kid.get("unfounded", 0)) + 1
		kids()[child] = kid
		if not c.is_empty():
			CaseStore.note(c, "Child services found nothing to act on at the visit.", "", 1)
		JusticeState.count("abuse_unfounded")
		return
	JusticeState.count("abuse_substantiated")
	var serious: bool = bool(kid.get("serious", false)) or int(kid.get("incidents", 1)) >= int(S.get("removal_incidents", 2))
	if not c.is_empty():
		CaseStore.note(c, "Child services found that %s had been harmed at home." % CrimePerson.name_of(child), "", 3)
		var evidence: float = float(c.get("trace", 0.2)) + 0.2 * float(int(kid.get("incidents", 1))) + (0.3 if serious else 0.0) + (0.2 if CrimePerson.stage(child) == "child" else 0.0)
		c["state"] = "open"
		c["disc_day"] = SysUtil.day()
		c["how"] = "services"
		SysUtil.game_event("case_opened", {"case": int(c["id"]), "kind": "child_abuse"})
		if evidence >= float(S.get("arrest_evidence", 0.5)) and carer >= 0 and not CrimePerson.in_custody(carer):
			JusticeProcess.arrest(c, carer)
	if serious:
		place(child, carer, "removal")
	else:
		JusticeState.abuse["watched"][carer] = SysUtil.day() + int(S.get("monitor_days", 28))
		if bool(S.get("follow_up_course", true)) and not JusticeState.courses.has(carer):
			JusticeState.courses[carer] = [{"kind": "parenting", "days_left": 5, "last_day": -1}]
		kid["follow_day"] = SysUtil.day() + 14
		var text: String = "Child services made a safety plan for %s: a parenting course and regular check-ins." % CrimePerson.name_of(child)
		if CrimePerson.is_player(child) or CrimePerson.is_player(carer):
			SysUtil.notify(text, "warn")
	kids()[child] = kid

static func _house(child: int) -> String:
	var nm: String = CrimePerson.name_of(child)
	var parts: PackedStringArray = nm.split(" ")
	return parts[parts.size() - 1]

# ------------------------------------------------------------------ placement and return
static func relative_for(child: int, carer: int) -> int:
	for o in CrimePerson.close_alive(child):
		var oid: int = int(o)
		if oid != carer and CrimePerson.is_adult(oid) and not CrimePerson.in_custody(oid) and (CrimePerson.hid(oid) == 0 or CrimePerson.hid(oid) != CrimePerson.hid(carer)) \
				and RelationshipService.value(child, oid, "friendship") >= 20.0:
			return oid
	return -1

static func place(child: int, carer: int, why: String) -> void:
	var kid: Dictionary = kids().get(child, {"incidents": 0, "trauma": 0.0})
	if not (kid.get("placed", {}) as Dictionary).is_empty():
		return
	var rel: int = relative_for(child, carer)
	var placed: Dictionary = {"kind": "relative" if rel >= 0 else "foster", "with": rel, "since": SysUtil.day(), "carer": carer, "why": why}
	kid["placed"] = placed
	kid["carer"] = carer
	kids()[child] = kid
	JusticeState.count("abuse_placements")
	var nm: String = CrimePerson.name_of(child)
	var text: String = "%s was placed with %s, a relative, while the family gets help." % [nm, CrimePerson.name_of(rel)] if rel >= 0 else "%s was placed in foster care while the family gets help." % nm
	var was_home: bool = CrimePerson.is_player(child)
	if CrimePerson.folk(child) != null and CrimePerson.hid(child) > 0 and CrimePerson.hid(child) == CrimePerson.hid(carer):
		FamilyHousehold.move_out(child, 0.0, false, true)
	if Story.townies.has(child):
		Story.townies[child]["placed"] = {"kind": placed["kind"], "with": rel}
	ChronicleHook.note("child_placed", text, [child, carer], CrimePerson.home_key(carer), 3, true)
	if was_home or CrimePerson.is_player(carer):
		SysUtil.notify(text, "story")
	if JusticeState.abuse["carers"].has(carer):
		JusticeState.abuse["carers"][carer]["score"] = float(JusticeState.abuse["carers"][carer]["score"]) * 0.3
	SysUtil.game_event("child_placed", {"folk_id": child, "target_id": carer, "kind": str(placed["kind"])})

static func try_return(child: int, kid: Dictionary) -> void:
	var pl: Dictionary = kid["placed"]
	var carer: int = int(pl.get("carer", -1))
	var since: int = int(pl.get("since", 0))
	if SysUtil.day() - since < int(cfg().get("services", {}).get("return_min_days", 14)) or carer < 0 or not CrimePerson.alive(carer) or CrimePerson.in_custody(carer):
		return
	if not JusticeOrders.between(carer, child).is_empty():
		return
	var course_done: bool = int(JusticeState.abuse["parenting"].get(carer, -9999)) >= since
	var c: Dictionary = CaseStore.get_case(int(kid.get("case", -1)))
	var cleared: bool = not c.is_empty() and str(c.get("verdict", "")) == "not_guilty" and not bool(kid.get("custody_lost", false))
	if not (course_done or cleared):
		return
	kid["placed"] = {}
	kid["custody_lost"] = false
	kid["reported"] = false
	kid["visited"] = false
	kids()[child] = kid
	var nm: String = CrimePerson.name_of(child)
	if Story.townies.has(child):
		Story.townies[child].erase("placed")
		if CrimePerson.hid(carer) > 0 and CrimePerson.folk(child) == null and bool(Story.townies[child].get("moved_out", false)):
			FamilyHousehold.invite_to_household(child, CrimePerson.hid(carer))
	JusticeState.count("abuse_returns")
	var text: String = "%s went back home to %s." % [nm, CrimePerson.name_of(carer)]
	ChronicleHook.note("child_returned", text, [child, carer], CrimePerson.home_key(carer), 2, true)
	if CrimePerson.is_player(carer) or CrimePerson.is_player(child):
		SysUtil.notify(text, "good")
