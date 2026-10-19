extends RefCounted
## Household chaos (task 07b), work life, adults only: layoffs (rumours first, doing well protects, severance pay, a closure takes everybody with the
## same job in the household, far townies lose their career) and the midlife crisis (middle-aged adults only, several outcomes, never for teens).

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/chaos_kit.gd")

func run() -> Array:
	var f: Array = []
	_layoff(f)
	_closure(f)
	_far_layoff(f)
	_midlife(f)
	return f

func _job(f_: Folk, level: int = 1) -> void:
	Careers.hire(f_, "cook", level)

func _layoff(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	var bo: Folk = h["bo"]
	var teen := K.make_folk(h["w"], "Teo Voss", [], 1, Vector2i(14, 12), "teen")
	var kid := K.make_folk(h["w"], "Kit Voss", [], 1, Vector2i(15, 12), "child")
	K.expect(f, Incidents.effective_rate("layoff", IncidentSubject.of_folk(ada)) == 0.0, "no job, no layoff")
	_job(ada)
	K.expect(f, Careers.has_job(int(ada.id)), "test setup: Ada has a job")
	var rate: float = Incidents.effective_rate("layoff", IncidentSubject.of_folk(ada))
	K.expect(f, absf(rate - 0.04) < 0.001, "a working adult can be laid off (%.3f a year)" % rate)
	Careers.jobs[int(ada.id)]["performance"] = 90.0
	K.expect(f, Incidents.effective_rate("layoff", IncidentSubject.of_folk(ada)) < rate * 0.4, "doing well at work protects (%.3f)" % Incidents.effective_rate("layoff", IncidentSubject.of_folk(ada)))
	Careers.jobs[int(ada.id)]["performance"] = 40.0
	for p in [teen, kid]:
		K.expect(f, Incidents.effective_rate("layoff", IncidentSubject.of_folk(p)) == 0.0, "%s can never be laid off" % p.name)
	var w0: Dictionary = Incidents.force("layoff", {"folk_id": ada.id, "warn": true})
	K.expect(f, str(w0["mode"]) == "warned" and K.has_note("rumours"), "rumours of layoffs come first")
	Careers.jobs[int(ada.id)]["performance"] = 95.0
	C.minutes(740)
	K.expect(f, Careers.has_job(int(ada.id)) and K.has_note("kept the job"), "a good performer keeps the job when the cuts come")
	Careers.jobs[int(ada.id)]["performance"] = 40.0
	var bal: int = Economy.balance(1)
	var r: Dictionary = Incidents.force("layoff", {"folk_id": ada.id, "outcome": 0})
	K.expect(f, bool(r["ok"]) and not Careers.has_job(int(ada.id)), "laid off: the job is gone")
	K.expect(f, Economy.balance(1) > bal and ada.has_buff("laid_off"), "with severance pay (+%d) and a rough mood" % (Economy.balance(1) - bal))
	K.expect(f, str(r["text"]).contains("job board") and not str(r["text"]).contains("{"), "plain words, pointing at the job board")
	K.teardown()

func _closure(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	var bo: Folk = h["bo"]
	_job(ada)
	_job(bo)
	var r: Dictionary = Incidents.force("layoff", {"folk_id": ada.id, "outcome": 1})
	K.expect(f, bool(r["ok"]) and not Careers.has_job(int(ada.id)) and not Careers.has_job(int(bo.id)), "a closed business takes both cooks in the household")
	K.expect(f, str(r["text"]).contains("closed down"), "and says so (%s)" % str(r["text"]))
	K.teardown()

func _far_layoff(f: Array) -> void:
	var h: Dictionary = C.setup()
	Story.generate_townies()
	var t: Dictionary = {}
	for x in Story.alive_townies():
		if str(x.get("career", "")) != "" and Story.stage_of(x) == "adult":
			t = x
			break
	K.expect(f, not t.is_empty(), "test setup: a working townie")
	var r: Dictionary = Incidents.force("layoff", {"townie_id": int(t["id"]), "folk_id": int(t["id"]), "outcome": 0})
	K.expect(f, bool(r["ok"]) and str(r["mode"]) == "statistical" and str(t["career"]) == "" and bool(t.get("seeking", false)), "a far townie loses the career and starts looking")
	K.teardown()

func _midlife(f: Array) -> void:
	var h: Dictionary = C.setup()
	var ada: Folk = h["ada"]
	var teen := K.make_folk(h["w"], "Teo Voss", [], 1, Vector2i(14, 12), "teen")
	Aging.records[int(ada.id)]["age_days"] = 90.0
	K.expect(f, Incidents.effective_rate("midlife_crisis", IncidentSubject.of_folk(ada)) == 0.0, "a young adult has no midlife crisis")
	Aging.records[int(ada.id)]["age_days"] = 130.0
	var rate: float = Incidents.effective_rate("midlife_crisis", IncidentSubject.of_folk(ada))
	K.expect(f, absf(rate - 0.3) < 0.001, "in the middle years it is possible (%.2f a year)" % rate)
	Aging.records[int(teen.id)]["age_days"] = 130.0
	K.expect(f, Incidents.effective_rate("midlife_crisis", IncidentSubject.of_folk(teen)) == 0.0, "never for a teen")
	ada.traits.append("workaholic")
	K.expect(f, Incidents.effective_rate("midlife_crisis", IncidentSubject.of_folk(ada)) > rate * 1.5, "workaholics are hit harder")
	_job(ada)
	var r0: Dictionary = Incidents.force("midlife_crisis", {"folk_id": ada.id, "outcome": 0})
	K.expect(f, bool(r0["ok"]) and ada.has_buff("midlife_crisis") and str(r0["text"]).contains("midlife crisis"), "restless week")
	var r1: Dictionary = Incidents.force("midlife_crisis", {"folk_id": ada.id, "outcome": 1})
	K.expect(f, ada.has_buff("burnt_out") and str(r1["text"]).contains("burnt out"), "workaholic burnout")
	var bal: int = Economy.balance(1)
	var r3: Dictionary = Incidents.force("midlife_crisis", {"folk_id": ada.id, "outcome": 3})
	K.expect(f, Economy.balance(1) < bal and str(r3["text"]).contains("coins"), "a pricey splurge (%d -> %d)" % [bal, Economy.balance(1)])
	var r2: Dictionary = Incidents.force("midlife_crisis", {"folk_id": ada.id, "outcome": 2})
	K.expect(f, not Careers.has_job(int(ada.id)) and bool(r2["ok"]), "or a sudden quit")
	K.teardown()
