extends RefCounted
## Household chaos (task 07b), the runaway teen: only teens, only after about five miserable days in a row, a warning first (cheering them up cancels it),
## then a few days away with worried grown-ups, then they come home on their own. Children and adults can never run away; nothing graphic.

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/chaos_kit.gd")

func run() -> Array:
	var f: Array = []
	_tracker(f)
	_warning_and_defuse(f)
	_runaway_and_home(f)
	return f

func _low(p: Folk, on: bool) -> void:
	p.add_to_stat("fun", -300.0 if on else 300.0)
	p.add_to_stat("social", -300.0 if on else 300.0)

func _tracker(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	var teen := K.make_folk(h["w"], "Teo Voss", [], 1, Vector2i(14, 12), "teen")
	var kid := K.make_folk(h["w"], "Kit Voss", [], 1, Vector2i(15, 12), "child")
	var subj := IncidentSubject.of_folk(teen)
	K.expect(f, Incidents.effective_rate("runaway_teen", subj) == 0.0, "a content teen never runs away")
	_low(teen, true)
	for d in 4:
		C.days(1)
		_low(teen, true)
	K.expect(f, int(ChaosState.unhappy.get(int(teen.id), 0)) == 4 and Incidents.effective_rate("runaway_teen", subj) == 0.0, "four bad days are not enough yet")
	C.days(1)
	K.expect(f, int(ChaosState.unhappy.get(int(teen.id), 0)) >= 5 and absf(Incidents.effective_rate("runaway_teen", subj) - 1.5) < 0.001, "five bad days in a row: possible (%.2f a year)" % Incidents.effective_rate("runaway_teen", subj))
	for p in [ada, kid]:
		ChaosState.unhappy[int(p.id)] = 9
		K.expect(f, Incidents.effective_rate("runaway_teen", IncidentSubject.of_folk(p)) == 0.0, "%s can never run away" % p.name)
	_low(teen, false)
	C.days(1)
	K.expect(f, int(ChaosState.unhappy.get(int(teen.id), 0)) < 5, "one good day takes two off (%d)" % int(ChaosState.unhappy.get(int(teen.id), 0)))
	K.teardown()

func _warning_and_defuse(f: Array) -> void:
	var h: Dictionary = C.setup()
	var teen := K.make_folk(h["w"], "Teo Voss", [], 1, Vector2i(14, 12), "teen")
	ChaosState.unhappy[int(teen.id)] = 6
	var w: Dictionary = Incidents.force("runaway_teen", {"folk_id": teen.id, "warn": true})
	K.expect(f, str(w["mode"]) == "warned" and K.has_note("miserable"), "a warning comes first")
	ChaosState.unhappy[int(teen.id)] = 1                      # somebody cheered them up
	C.minutes(380)
	K.expect(f, ChaosState.gone.is_empty() and K.has_note("unpacked the bag"), "cheering them up cancels it")
	K.teardown()

func _runaway_and_home(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	var teen := K.make_folk(h["w"], "Teo Voss", [], 1, Vector2i(14, 12), "teen")
	ChaosState.unhappy[int(teen.id)] = 7
	var r: Dictionary = Incidents.force("runaway_teen", {"folk_id": teen.id, "outcome": 0})
	K.expect(f, bool(r["ok"]) and ChaosState.gone.has(int(teen.id)) and Away.pending.has(int(teen.id)), "the teen is gone for a few days")
	var span: int = int(ChaosState.gone[int(teen.id)]["back"]) - int(ChaosState.gone[int(teen.id)]["since"])
	K.expect(f, span >= 2 * 1440 and span <= 4 * 1440, "two to four days (%d minutes)" % span)
	K.expect(f, ada.has_buff("worried_sick") and not teen.has_buff("worried_sick"), "the grown-ups are worried sick")
	K.expect(f, str(r["text"]).contains("note"), "plain words (%s)" % str(r["text"]))
	K.expect(f, not ChaosState.unhappy.has(int(teen.id)), "the sad streak starts over")
	Away.on_started(int(teen.id), "sys_away")
	Away.on_finished(int(teen.id), "sys_away", true)
	K.expect(f, ChaosState.gone.is_empty() and not ada.has_buff("worried_sick") and K.has_note("came home"), "they come home and the worry ends")
	var snap: Dictionary = Incidents.to_dict()
	var before: Dictionary = ChaosState.to_dict()
	Incidents.from_dict(snap)
	K.expect(f, K.deep_eq(before, ChaosState.to_dict()), "state survives save and load")
	K.teardown()
