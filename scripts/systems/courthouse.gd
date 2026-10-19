class_name Courthouse
extends RefCounted
## The courthouse: a rabbit hole (no map lot yet). On the trial day the accused and any player witnesses are away for a few hours (Away "court"),
## then the verdict is scored (JusticeTrial). Player folk who know the accused or the victim are called as WITNESSES: speak for them, against
## them, stay out of it, or LIE on the stand (a perjury risk). Townie witnesses testify by their relationships (JusticeTrial.testimony).

static func cfg() -> Dictionary:
	return JusticeState.sect("trial")

## The trial day starts.
static func open(c: Dictionary) -> void:
	if not CaseStore.has_case(int(c["id"])) or int(c["accused"]) < 0 or str(c["state"]) in ["closed"]:
		return
	var pid: int = int(c["accused"])
	if not CrimePerson.alive(pid):
		CaseStore.close_for_death(c, pid)
		return
	c["state"] = "trial"
	var hours: float = float(cfg().get("court_hours", 3))
	var f = CrimePerson.folk(pid)
	if f != null and CrimePerson.is_player(pid):
		JusticePlayer.hold(f, hours * 60.0 + 5.0, "court", "At court")
	for w in witness_candidates(c):
		var wf = CrimePerson.folk(w)
		if wf != null and not SysUtil.is_away(wf):
			JusticePlayer.hold(wf, hours * 60.0, "court", "Giving evidence")
		_ask_testimony(c, w)
	JusticeState.queue({"kind": "verdict", "case": int(c["id"]), "due_min": SysUtil.now() + int(hours * 60.0)})
	CaseStore.note(c, "The trial of %s began." % CrimePerson.name_of(pid))
	if CaseStore.household_involved(c):
		SysUtil.notify("The trial of %s has begun." % CrimePerson.name_of(pid), "story")

static func verdict_day(c: Dictionary) -> void:
	if str(c["state"]) == "closed":
		return
	if not CrimePerson.alive(int(c.get("accused", -1))):
		CaseStore.close_for_death(c, int(c.get("accused", -1)))
		return
	JusticeTrial.run(c)

## Player folk who may be called: they know the accused or the victim, or saw the crime.
static func witness_candidates(c: Dictionary) -> Array:
	var out: Array = []
	var pid: int = int(c["accused"])
	for r in SysUtil.residents():
		var id: int = int(r.id)
		if id == pid or not CrimePerson.is_adult(id):
			continue
		var knows: bool = RelationshipService.knows(id, pid) and absf(RelationshipService.value(id, pid, "friendship")) >= 20.0
		var vic: bool = id == int(c["victim"]) or (int(c["victim"]) >= 0 and RelationshipService.knows(id, int(c["victim"])) and RelationshipService.value(id, int(c["victim"]), "friendship") >= 40.0)
		if knows or vic or (c["witnesses"] as Array).has(id):
			out.append(id)
	return out.slice(0, 2)

static func _ask_testimony(c: Dictionary, w: int) -> void:
	var pid: int = int(c["accused"])
	var an: String = CrimePerson.name_of(pid)
	JusticePlayer.ask(w, "Called as a witness", "%s is called to testify about %s. What does %s say?" % [CrimePerson.name_of(w), an, CrimePerson.name_of(w)],
		[{"id": "for", "label": "Speak in their favour"}, {"id": "against", "label": "Speak against them"},
		 {"id": "for_lie", "label": "Swear they are innocent (a lie)"}, {"id": "against_lie", "label": "Swear they did it (a lie)"}, {"id": "stay", "label": "Say little"}],
		_testimony_choice.bind(int(c["id"]), w), "stay")

static func _testimony_choice(choice, case_id: int, w: int) -> void:
	testify(case_id, w, str(choice))

## choice: for | against | for_lie | against_lie | stay. Honest testimony is not a lie even if the accused is guilty (they only say what they believe).
static func testify(case_id: int, w: int, choice: String) -> void:
	var c: Dictionary = CaseStore.get_case(case_id)
	if c.is_empty() or choice == "stay":
		return
	var lie: bool = choice.ends_with("_lie")
	var side: String = choice.trim_suffix("_lie")
	var list: Array = c.get("testimony", [])
	list.append({"pid": w, "side": side, "lie": lie, "exposed": false})
	c["testimony"] = list
	CaseStore.note(c, "%s will testify %s the accused." % [CrimePerson.name_of(w), "for" if side == "for" else "against"])