extends RefCounted
## Life stages instead of years: starting folk differ in age and birthday date, one small yearly celebration per calendar year on each
## folk's own date, stage-change birthdays fire once per stage, and no toast / data text shows an age in years.

const K = preload("res://tests/systems_kit.gd")

var _age_re: RegEx = null

func run() -> Array:
	var f: Array = []
	_age_re = RegEx.new()
	_age_re.compile("(?i)(\\b\\d+ years? old|\\baged \\d+|\\bturned \\d+|\\bthey are now \\d+|\\blived \\d+ years|\\(\\w+, \\d+\\))")
	_starting_folk(f)
	_yearly(f)
	_data_text(f)
	return f

func _starting_folk(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Mira", [], 1)
	var b := K.make_folk(w, "Tobin", [], 1)
	var c := K.make_folk(w, "Wren", [], 1)
	var ages := [Aging.age_days(a.id), Aging.age_days(b.id), Aging.age_days(c.id)]
	K.expect(f, ages[0] != ages[1] and ages[1] != ages[2] and ages[0] != ages[2], "starting folk have different age_days %s" % str(ages))
	for x in [a, b, c]:
		K.expect(f, x.age_stage == "adult", "%s stays an adult" % x.name)
	var doys := [Aging.birth_doy(a.id), Aging.birth_doy(b.id), Aging.birth_doy(c.id)]
	K.expect(f, doys[0] != doys[1] and doys[1] != doys[2] and doys[0] != doys[2], "household birthdays differ %s" % str(doys))
	AgingStart.settle_partner(a, b)
	K.expect(f, absf(Aging.age_days(a.id) - Aging.age_days(b.id)) <= 12.5, "partners within three years of each other")
	K.expect(f, Aging.stage_text(a.id).find(" adult") > 0 and not Aging.stage_text(a.id).is_valid_int(), "age shown as a stage: %s" % Aging.stage_text(a.id))
	K.teardown()

func _yearly(f: Array) -> void:
	var w := K.setup()
	var folks: Array = []
	for n in ["Mira", "Tobin", "Wren"]:
		folks.append(K.make_folk(w, n, [], 1))
	var kid := K.make_folk(w, "Kit", [], 1, Vector2i(14, 12), "child")
	folks.append(kid)
	Aging.set_lifespan("epic")          # nobody changes stage or dies in 56 days
	var days := 56
	var per: Dictionary = {}
	var ups: Dictionary = {}
	SimEnv.events().game_event.connect(func(n, p):
		if n == "birthday":
			per[int(p["folk_id"])] = (per.get(int(p["folk_id"]), []) as Array) + [SysUtil.day()]
		elif n == "aged_up":
			ups[int(p["folk_id"])] = int(ups.get(int(p["folk_id"]), 0)) + 1)
	for d in range(2, days + 2):
		K.set_time(d, 0)
		Aging.on_day(d)
	for x in folks:
		var ds: Array = per.get(x.id, [])
		K.expect(f, ds.size() == 2, "%s: exactly one celebration per 28-day year (%s)" % [x.name, str(ds)])
		if ds.size() == 2:
			K.expect(f, int(ds[1]) - int(ds[0]) == 28, "%s: the date repeats every 28 days" % x.name)
			K.expect(f, Aging.doy(int(ds[0])) == Aging.birth_doy(x.id), "%s: celebrates on their own date" % x.name)
	var firsts: Dictionary = {}
	for x in folks:
		firsts[(per.get(x.id, [0]) as Array)[0]] = true
	K.expect(f, firsts.size() >= 3, "household members celebrate on different days (%d distinct)" % firsts.size())
	for n in K.notes:
		K.expect(f, _age_re.search(str(n[0])) == null, "toast shows an age in years: %s" % str(n[0]))
	# the big birthday: the stage change, once per stage, with a chronicle line
	Aging.set_lifespan("normal")
	var teen := K.make_folk(w, "Rowan", [], 1, Vector2i(16, 12), "teen")
	Aging.set_age_days(teen, 74.5)
	K.notes.clear()
	ChronicleHook.reset()
	var n_up := 0
	for d in range(100, 106):          # 74.5 + 2 days crosses into adult at 76
		K.set_time(d, 0)
		Aging.on_day(d)
	n_up = K.events.filter(func(e): return e[0] == "aged_up" and int(e[1]["folk_id"]) == int(teen.id)).size()
	K.expect(f, n_up == 1 and teen.age_stage == "adult", "growing into an adult fires aged_up once (%d)" % n_up)
	K.expect(f, K.has_note("grew up into a"), "the stage-change toast")
	K.expect(f, ChronicleHook.recent.any(func(p): return p["kind"] == "aged_up"), "stage change has a chronicle line")
	for n in K.notes:
		K.expect(f, _age_re.search(str(n[0])) == null, "toast shows an age in years: %s" % str(n[0]))
	var gl: Dictionary = Aging.legacy_summary(teen.id)
	K.expect(f, _age_re.search(str(gl["summary"])) == null and str(gl["summary"]).find("as an adult") > 0, "legacy text uses the stage: %s" % gl["summary"])
	K.teardown()

func _scan(v: Variant, path: String, out: Array) -> void:
	if v is String:
		if _age_re.search(v) != null:
			out.append("%s: %s" % [path, v])
	elif v is Dictionary:
		for k in v:
			_scan(v[k], path + "." + str(k), out)
	elif v is Array:
		for i in (v as Array).size():
			_scan(v[i], path + "[%d]" % i, out)

func _data_text(f: Array) -> void:
	K.setup()
	var out: Array = []
	for t in SimEnv.data().tables:
		_scan(SimEnv.data().tables[t], t, out)
	K.expect(f, out.is_empty(), "data text mentions an age in years: %s" % str(out.slice(0, 5)))
	K.teardown()
