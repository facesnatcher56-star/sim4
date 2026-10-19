extends RefCounted
## First jobs are spread over the careers (task 19j): the six children of the owner's family all took Barista (Cashier) first. Teens and young adults now get a
## weighted pick by skills, traits, aspiration and the job board; housemates avoid each other's career; a young adult may change careers, with friction.

const K = preload("res://tests/systems_kit.gd")

const SKILLS := ["cooking", "charisma", "logic", "painting", "fitness", "guitar", "gardening", "handiness", "writing"]

func run() -> Array:
	var f: Array = []
	_teens(f)
	_adults(f)
	_siblings(f)
	_switch(f)
	return f

func _person(w: StubWorld, stage: String, hid: int, rng: RandomNumberGenerator, idx: int) -> Folk:
	var tr: Array = []
	var all: Array = SimEnv.data().get_table("traits").keys()
	while tr.size() < 2:
		var t = all[rng.randi() % all.size()]
		if not tr.has(t):
			tr.append(t)
	var p := K.make_folk(w, "P%d Lane" % idx, tr, hid, Vector2i(12 + idx % 5, 12 + (idx / 5) % 5), stage)
	p.skills[SKILLS[rng.randi() % SKILLS.size()]] = {"xp": 0.0, "level": rng.randi() % 3}
	if stage == "adult":
		Aging.set_age_days(p, 80.0)
	return p

func _share(tally: Dictionary, total: int) -> Array:
	var best := ""
	var top := 0
	for k in tally:
		if int(tally[k]) > top:
			top = int(tally[k])
			best = str(k)
	return [best, float(top) / float(maxi(total, 1))]

func _teens(f: Array) -> void:
	var w := K.setup(91)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var tally: Dictionary = {}
	var n := 300
	for i in n:
		var p := _person(w, "teen", 100 + i, rng, i)
		Careers.offers.erase(int(p.id))
		var o: Dictionary = Careers.make_offer(p)
		K.expect(f, not o.is_empty() and CareerSpread.teen_careers().has(str(o["career"])) and int(o["level"]) == 1, "a teen is offered a part-time level 1 job (%s)" % str(o))
		tally[str(o.get("career", ""))] = int(tally.get(str(o.get("career", "")), 0)) + 1
		w.remove_folk(p) if w.has_method("remove_folk") else null
	var sh: Array = _share(tally, n)
	K.expect(f, float(sh[1]) <= 0.40, "teens: no career above 40%% (%s has %.0f%%, all %s)" % [sh[0], float(sh[1]) * 100.0, str(tally)])
	K.expect(f, tally.size() >= 5, "teens: at least five different part-time careers (%d)" % tally.size())
	K.teardown()

func _adults(f: Array) -> void:
	var w := K.setup(92)
	var rng := RandomNumberGenerator.new()
	rng.seed = 92
	var tally: Dictionary = {}
	var n := 400
	for i in n:
		var p := _person(w, "adult", 200 + i, rng, i)
		var cid: String = CareerSpread.pick(p, Careers.career_ids())
		tally[cid] = int(tally.get(cid, 0)) + 1
	var sh: Array = _share(tally, n)
	K.expect(f, float(sh[1]) <= 0.40, "young adults: no career above 40%% (%s has %.0f%%, all %s)" % [sh[0], float(sh[1]) * 100.0, str(tally)])
	K.expect(f, tally.size() >= 10, "young adults: at least ten different careers (%d)" % tally.size())
	K.teardown()

## Three siblings in one household: they rarely all start in the same career.
func _siblings(f: Array) -> void:
	var w := K.setup(93)
	var rng := RandomNumberGenerator.new()
	rng.seed = 93
	var same := 0
	var fam := 120
	for h in fam:
		var picks: Array = []
		for k in 3:
			var p := _person(w, "teen", 300 + h, rng, h * 3 + k)
			Careers.offers.erase(int(p.id))
			var o: Dictionary = Careers.make_offer(p)
			if not o.is_empty():
				Careers.accept_offer(int(p.id))
				picks.append(str(o["career"]))
		if picks.size() == 3 and picks[0] == picks[1] and picks[1] == picks[2]:
			same += 1
	K.expect(f, float(same) / float(fam) < 0.10, "three teens in one house all in the same career in %d of %d families" % [same, fam])
	K.teardown()

func _switch(f: Array) -> void:
	var w := K.setup(94)
	SimEnv.data().get_table("careers")["switch"]["chance_per_day"] = 1.0
	var p := K.make_folk(w, "Ada Lane", [])
	Aging.set_age_days(p, 80.0)
	K.set_time(40, 8)
	Careers.hire(p, "barista", 1)
	(Careers.jobs[int(p.id)] as Dictionary)["hired_day"] = 40
	p.skills["logic"] = {"xp": 0.0, "level": 4}
	K.expect(f, CareerSpread.maybe_switch(p) == "", "someone hired today does not switch")
	(Careers.jobs[int(p.id)] as Dictionary)["hired_day"] = 10
	Careers.changed_day[int(p.id)] = 10
	var to: String = CareerSpread.maybe_switch(p)
	var j: Dictionary = Careers.jobs.get(int(p.id), {})
	K.expect(f, to != "" and str(j.get("career", "")) == to and int(j.get("level", 0)) == 1, "a young adult whose skills point elsewhere changes career, back at level 1 (%s)" % to)
	K.expect(f, float(j.get("performance", 99)) < float(Careers.settings().get("start_performance", 50)), "and starts with less standing (friction)")
	K.expect(f, K.has_note("to try something new"), "the change is announced in plain words")
	K.expect(f, CareerSpread.maybe_switch(p) == "", "no second change right away")
	# not for the experienced, nor for older adults
	var q := K.make_folk(w, "Bo Lane", [], 1, Vector2i(14, 12))
	Aging.set_age_days(q, 80.0)
	Careers.hire(q, "barista", 3)
	(Careers.jobs[int(q.id)] as Dictionary)["hired_day"] = 10
	q.skills["logic"] = {"xp": 0.0, "level": 4}
	K.expect(f, CareerSpread.maybe_switch(q) == "", "level 3 is too senior to switch")
	var r := K.make_folk(w, "Cy Lane", [], 1, Vector2i(15, 12))
	Aging.set_age_days(r, 150.0)
	Careers.hire(r, "barista", 1)
	(Careers.jobs[int(r.id)] as Dictionary)["hired_day"] = 10
	r.skills["logic"] = {"xp": 0.0, "level": 4}
	K.expect(f, CareerSpread.maybe_switch(r) == "", "late adults do not switch")
	K.teardown()
