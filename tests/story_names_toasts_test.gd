extends RefCounted
## Story review fixes: relationship toasts follow the notify policy (household or well-known people only), the name pool is big and
## first names are not reused while in use, repetition memory ("bored of it"), spoilage toast rules.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_toasts(f)
	_names(f)
	_variety(f)
	_spoilage(f)
	return f

func _rel_notes() -> Array:
	return K.notes.filter(func(n): return n[1] == "relationship")

func _toasts(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Hera", [], 1)
	var x := K.make_folk(w, "Xander", [], 0)
	var y := K.make_folk(w, "Yvonne", [], 0)
	var z := K.make_folk(w, "Zed", [], 0)
	ChronicleHook.reset()
	RelationshipService.add_both(x.id, y.id, "friendship", 45.0)
	K.expect(f, _rel_notes().is_empty(), "strangers becoming friends: no toast (%s)" % str(_rel_notes()))
	RelationshipService.add_both(x.id, y.id, "friendship", 40.0)
	K.expect(f, _rel_notes().is_empty(), "strangers becoming best friends: no toast")
	K.expect(f, ChronicleHook.recent.any(func(p): return p["kind"] == "relationship"), "big steps between strangers go quietly to the chronicle")
	RelationshipService.add_both(a.id, z.id, "friendship", 45.0)
	K.expect(f, _rel_notes().size() >= 1, "a household member's new friend is announced")
	K.notes.clear()
	# z is a friend of the household now: z and y becoming friends is news the household cares about
	RelationshipService.add_both(z.id, y.id, "friendship", 45.0)
	K.expect(f, _rel_notes().size() >= 1, "people the household knows well are announced (%s)" % str(K.notes))
	K.teardown()

func _names(f: Array) -> void:
	var w := K.setup()
	var nm: Dictionary = SysUtil.table("names")
	K.expect(f, (nm.get("first_names", []) as Array).size() >= 300, "at least 300 first names (%d)" % (nm.get("first_names", []) as Array).size())
	K.expect(f, (nm.get("last_names", []) as Array).size() >= 150, "at least 150 last names (%d)" % (nm.get("last_names", []) as Array).size())
	K.make_folk(w, "Mira", [], 1)
	Story.generate_townies(60)
	var seen: Dictionary = {}
	var dup := 0
	for t in Story.alive_townies():
		var fn: String = Names.first_of(str(t["name"]))
		if seen.has(fn) or fn == "Mira":
			dup += 1
		seen[fn] = true
	K.expect(f, Story.alive_townies().size() >= 60 and dup == 0, "60 townies have 60 different first names, none shared with the household (dups %d)" % dup)
	var used: Array = []
	for i in 30:
		var n: String = HouseholdSetup.random_name(used)
		K.expect(f, not used.has(n) and not seen.has(n) and n != "Mira", "random household name %s is unused in town" % n)
		used.append(n)
	K.teardown()

func _variety(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Hera", [], 1)
	var iid: String = "play_computer"
	var d: Dictionary = SimEnv.data().interaction_def(iid)
	AutonomyVariety.reset()
	K.expect(f, is_equal_approx(AutonomyVariety.mult(a, iid, d, null), 1.0), "no history: no penalty")
	var last := 1.0
	var cap: int = int(AutonomyVariety.cfg().get("daily_cap", 0))
	for i in 8:
		AutonomyVariety.on_started(a.id, iid, -1)
		var m: float = AutonomyVariety.mult(a, iid, d, null)
		if cap > 0 and i + 1 >= cap:
			K.expect(f, m == 0.0, "after %d starts today autonomy has had enough of it (%.2f)" % [i + 1, m])
			continue
		K.expect(f, m < last + 0.0001, "repeat %d lowers the score (%.2f)" % [i, m])
		last = m
	K.expect(f, last < 0.8 and last >= 0.12, "the repeats before the daily cap: well below one but never zero (%.2f)" % last)
	K.set_time(5, 12)
	var later: float = AutonomyVariety.mult(a, iid, d, null)
	K.expect(f, later > last + 0.2, "boredom recovers over days (%.2f -> %.2f)" % [last, later])
	for ex in ["sleep_bed", "use_toilet", "eat_meal", "take_shower"]:
		var ed: Dictionary = SimEnv.data().interaction_def(ex)
		for i in 10:
			AutonomyVariety.on_started(a.id, ex, -1)
		K.expect(f, is_equal_approx(AutonomyVariety.mult(a, ex, ed, null), 1.0), "%s is never penalised" % ex)
	K.teardown()

func _spoilage(f: Array) -> void:
	var w := K.setup()
	var st: Dictionary = SysUtil.table("content_rules").get("spoil_toast", {})
	K.expect(f, int(st.get("min_items", 0)) >= 3 and int(st.get("gap_days", 0)) >= 2, "spoilage toast rules are in data")
	var fr = w.add_object("fridge", Vector2i(12, 12))
	WorldIface.state_set(fr, "stock", 10.0)
	var toasts := 0
	for d in range(1, 10):
		K.notes.clear()
		ContentRules.on_day(d)
		toasts += K.notes.filter(func(n): return str(n[0]).find("fridge") >= 0).size()
	K.expect(f, toasts <= 3, "fridge spoilage is not a daily toast (%d toasts in 9 days)" % toasts)
	K.teardown()
