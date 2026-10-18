extends RefCounted
## Core tests: clock, events, stat decay, thresholds->buffs, mood, cond, loot, skills, save/load.

const Kit = preload("res://tests/sim_testkit.gd")

var _count: Dictionary = {}

func run() -> Array:
	var f: Array = []
	var w := Kit.setup()
	_test_clock(f)
	_test_stat(f)
	_test_thresholds(f)
	_test_mood(f)
	_test_buff_duration(f)
	_test_cond(f, w)
	_test_loot(f, w)
	_test_skills(f)
	_test_traits_decay(f)
	_test_saveload(f)
	Kit.teardown()
	return f

func _bump(key: String) -> void:
	_count[key] = int(_count.get(key, 0)) + 1

func _test_clock(f: Array) -> void:
	var c = SimEnv.clock()
	Kit.set_time(1, 7, 0)
	_count.clear()
	c.minute_passed.connect(func(_t): _bump("min"))
	c.hour_passed.connect(func(_h): _bump("hour"))
	c.day_passed.connect(func(_d): _bump("day"))
	c.advance_minutes(130)
	Kit.expect(f, int(_count.get("min", 0)) == 130, "clock: expected 130 minute signals, got %s" % _count.get("min", 0))
	Kit.expect(f, int(_count.get("hour", 0)) == 2, "clock: expected 2 hour signals (08:00, 09:00), got %s" % _count.get("hour", 0))
	Kit.expect(f, c.hour() == 9 and c.minute() == 10, "clock: should be 09:10, is %s" % c.time_string())
	c.advance_minutes(15 * 60)   # 09:10 -> 00:10 next day
	Kit.expect(f, int(_count.get("day", 0)) == 1 and c.day() == 2, "clock: day rollover failed (%s)" % c.time_string())
	c.set_speed(5)
	Kit.expect(f, c.speed == 3, "clock: speed should clamp to 3")
	c.set_speed(0)
	Kit.expect(f, c.speed == 0, "clock: pause")

func _test_stat(f: Array) -> void:
	var s := Stat.from_def("hunger", {"min": -100, "max": 100, "start": 50, "decay_per_min": 0.5})
	s.tick(10)
	Kit.expect(f, Kit.near(s.value, 45.0), "stat: decay 0.5*10 from 50 -> 45, got %f" % s.value)
	s.tick(10, 2.0)
	Kit.expect(f, Kit.near(s.value, 35.0), "stat: decay with x2 modifier -> 35, got %f" % s.value)
	s.add(1000)
	Kit.expect(f, Kit.near(s.value, 100.0), "stat: add clamps at max")
	s.set_value(-500)
	Kit.expect(f, Kit.near(s.value, -100.0), "stat: set_value clamps at min")
	Kit.expect(f, Kit.near(s.ratio(), 0.0), "stat: ratio at min is 0")
	s.set_value(0)
	Kit.expect(f, Kit.near(s.ratio(), 0.5), "stat: ratio mid is 0.5")
	var t := Stat.from_def("x", {"min": -100, "max": 100, "start": 0, "thresholds": [{"below": -20, "buff": "a"}, {"below": -60, "buff": "b"}, {"above": 80, "buff": "c"}]})
	t.set_value(-30)
	Kit.expect(f, t.active_threshold_buffs() == ["a"], "stat: threshold -30 -> [a], got %s" % str(t.active_threshold_buffs()))
	t.set_value(-70)
	Kit.expect(f, t.active_threshold_buffs() == ["b"], "stat: threshold -70 -> only most severe [b], got %s" % str(t.active_threshold_buffs()))
	t.set_value(90)
	Kit.expect(f, t.active_threshold_buffs() == ["c"], "stat: above threshold")
	# decay is observable through a Folk (needs come from data/needs.json)
	var folk := Folk.create("T")
	var before: float = (folk.needs["hunger"] as Stat).value
	folk.tick_needs(100.0)
	var after: float = (folk.needs["hunger"] as Stat).value
	Kit.expect(f, Kit.near(before - after, 7.0, 0.05), "folk: hunger should drop 0.07*100=7, dropped %f" % (before - after))

func _test_thresholds(f: Array) -> void:
	var folk := Folk.create("T")
	_count.clear()
	var ev = SimEnv.events()
	ev.buff_added.connect(func(_id, b): _bump("add_" + b))
	ev.buff_removed.connect(func(_id, b): _bump("rem_" + b))
	(folk.needs["hunger"] as Stat).set_value(-30)
	folk.update_thresholds()
	Kit.expect(f, folk.has_buff("hungry") and not folk.has_buff("starving"), "threshold: -30 hunger -> hungry")
	(folk.needs["hunger"] as Stat).set_value(-70)
	folk.update_thresholds()
	Kit.expect(f, folk.has_buff("starving") and not folk.has_buff("hungry"), "threshold: -70 hunger -> starving only")
	(folk.needs["hunger"] as Stat).set_value(50)
	folk.update_thresholds()
	Kit.expect(f, not folk.has_buff("starving") and not folk.has_buff("hungry"), "threshold: recovered hunger clears buffs")
	Kit.expect(f, int(_count.get("add_hungry", 0)) == 1 and int(_count.get("rem_starving", 0)) == 1, "threshold: buff_added/removed signals fired (%s)" % str(_count))

func _test_mood(f: Array) -> void:
	var folk := Folk.create("T")
	folk.buffs.clear()
	var m := Mood.compute(folk)
	Kit.expect(f, m["mood"] == "neutral" and m["intensity"] == 0, "mood: no buffs -> neutral/0")
	folk.add_buff("entertained")   # happy 2
	folk.add_buff("well_rested")   # happy 1, energized 2
	m = Mood.compute(folk)
	Kit.expect(f, m["mood"] == "happy" and m["intensity"] == 2, "mood: happy(3) beats energized(2), intensity 2, got %s" % str(m))
	var g := Folk.create("G")
	g.buffs.clear()
	g.add_buff("starving")    # sad 2, uncomfortable 2
	g.add_buff("exhausted")   # sad 1, uncomfortable 2
	m = Mood.compute(g)
	Kit.expect(f, m["mood"] == "uncomfortable" and m["intensity"] == 2, "mood: uncomfortable(4) > sad(3), intensity 2, got %s" % str(m))
	g.add_buff("filthy")      # sad 1, unc 2 -> unc 6
	m = Mood.compute(g)
	Kit.expect(f, m["mood"] == "uncomfortable" and m["intensity"] == 3, "mood: intensity 3 at sum 6, got %s" % str(m))
	var ev_seen: Array = []
	SimEnv.events().mood_changed.connect(func(_i, mood, inten): ev_seen.append([mood, inten]))
	var h := Folk.create("H")
	h.buffs.clear()
	h.add_buff("flirty_buzz")
	Kit.expect(f, h.mood_name == "flirty" and not ev_seen.is_empty(), "mood: mood_changed emitted with flirty")

func _test_buff_duration(f: Array) -> void:
	var folk := Folk.create("T")
	folk.buffs.clear()
	folk.add_buff("entertained")   # 120 min
	folk.tick_buffs(119)
	Kit.expect(f, folk.has_buff("entertained"), "buff: still active at 119/120")
	folk.add_buff("entertained")   # refresh
	folk.tick_buffs(119)
	Kit.expect(f, folk.has_buff("entertained"), "buff: refreshed duration")
	folk.tick_buffs(5)
	Kit.expect(f, not folk.has_buff("entertained"), "buff: expired after duration")
	var bursting := Folk.create("B", ["hot_headed"])
	bursting.buffs.clear()
	bursting.add_buff("hungry")
	Kit.expect(f, bursting.has_buff("annoyed"), "trait: hot_headed gets 'annoyed' when hungry (buffs_on)")

func _test_cond(f: Array, w: StubWorld) -> void:
	var folk := Folk.create("T", ["lazy"])
	var other := Folk.create("O")
	var fridge := w.add_object("fridge", Vector2i(1, 1))
	var ctx := {"folk": folk, "object": fridge, "target": other}
	(folk.needs["energy"] as Stat).set_value(10)
	Kit.expect(f, Cond.check([{"stat_below": ["energy", 40]}], ctx), "cond: stat_below true")
	Kit.expect(f, not Cond.check([{"stat_above": ["energy", 40]}], ctx), "cond: stat_above false")
	Kit.expect(f, Cond.check([{"has_trait": "lazy"}, {"lacks_trait": "neat"}], ctx), "cond: has/lacks trait")
	Kit.expect(f, Cond.check([{"not": {"has_trait": "neat"}}], ctx), "cond: not wrapper")
	Kit.expect(f, Cond.check([{"any": [{"has_trait": "neat"}, {"has_trait": "lazy"}]}], ctx), "cond: any (OR)")
	Kit.expect(f, not Cond.check([{"any": [{"has_trait": "neat"}, {"has_buff": "hungry"}]}], ctx), "cond: any all-false")
	Kit.expect(f, Cond.check([{"object_state_above": ["stock", 5]}, {"object_state_eq": ["broken", false]}], ctx), "cond: object state (fridge stock 10, not broken)")
	Kit.expect(f, not Cond.check([{"object_state_above": ["stock", 10]}], ctx), "cond: object_state_above strict")
	Kit.expect(f, not Cond.check([{"skill_at_least": ["cooking", 1]}], ctx), "cond: skill_at_least false at 0")
	folk.add_skill_xp("cooking", 120)
	Kit.expect(f, Cond.check([{"skill_at_least": ["cooking", 1]}], ctx), "cond: skill_at_least true after xp")
	Kit.expect(f, not Cond.check([{"relationship_above": ["friendship", 5]}], ctx), "cond: relationship none")
	folk.add_rel(other.id, "friendship", 10)
	Kit.expect(f, Cond.check([{"relationship_above": ["friendship", 5]}], ctx), "cond: relationship_above")
	Kit.expect(f, not Cond.check([{"coins_at_least": 50}], ctx), "cond: coins_at_least false")
	WorldIface.add_coins(folk.household_id, 80)
	Kit.expect(f, Cond.check([{"coins_at_least": 50}], ctx), "cond: coins_at_least true")
	Kit.set_time(1, 14, 0)
	Kit.expect(f, Cond.check([{"time_between": [12, 16]}], ctx) and not Cond.check([{"time_between": [18, 20]}], ctx), "cond: time_between")
	Kit.set_time(1, 23, 0)
	Kit.expect(f, Cond.check([{"time_between": [22, 6]}], ctx), "cond: time_between wraps midnight")
	Kit.expect(f, not Cond.check([{"mood_is": "happy"}], ctx), "cond: mood_is false")
	folk.add_buff("cheered_up")
	Kit.expect(f, Cond.check([{"mood_is": "happy"}, {"has_buff": "cheered_up"}], ctx), "cond: mood_is true")
	Kit.expect(f, Cond.check([], ctx), "cond: empty list is true")

func _test_loot(f: Array, w: StubWorld) -> void:
	var folk := Folk.create("T")
	var other := Folk.create("O")
	var fridge := w.add_object("fridge", Vector2i(1, 1))
	var ctx := {"folk": folk, "object": fridge, "target": other}
	WorldIface.coins.clear()
	var notes: Array = []
	var events: Array = []
	SimEnv.events().notification.connect(func(t, k): notes.append([t, k]))
	SimEnv.events().game_event.connect(func(n, p): events.append([n, p]))
	var before: float = (folk.needs["fun"] as Stat).value
	Loot.apply([
		{"add_buff": "cheered_up"}, {"stat_add": ["fun", 10]}, {"skill_xp": ["logic", 130]},
		{"object_state_add": ["stock", -3]}, {"coins_add": 25}, {"relationship_add": ["friendship", 7]},
		{"fire_event": "party"}, {"notify": "hello"}, {"target_add_buff": "annoyed"},
	], ctx)
	Kit.expect(f, folk.has_buff("cheered_up"), "loot: add_buff")
	Kit.expect(f, Kit.near((folk.needs["fun"] as Stat).value, before + 10.0), "loot: stat_add")
	Kit.expect(f, folk.skill_level("logic") == 1, "loot: skill_xp 130 -> level 1 (100 xp)")
	Kit.expect(f, int(fridge.state["stock"]) == 7, "loot: object_state_add (stock 10-3=7), got %s" % str(fridge.state["stock"]))
	Kit.expect(f, WorldIface.get_coins(folk.household_id) == 25, "loot: coins_add")
	Kit.expect(f, Kit.near(folk.get_rel(other.id, "friendship"), 7.0) and Kit.near(other.get_rel(folk.id, "friendship"), 7.0), "loot: relationship_add both ways")
	Kit.expect(f, other.has_buff("annoyed"), "loot: target_add_buff")
	Kit.expect(f, not events.is_empty() and events[0][0] == "party", "loot: fire_event -> game_event")
	Kit.expect(f, not notes.is_empty() and notes[0][0] == "hello", "loot: notify -> notification")
	Loot.apply([{"remove_buff": "cheered_up"}], ctx)
	Kit.expect(f, not folk.has_buff("cheered_up"), "loot: remove_buff")
	# chance 0 never applies, chance 1 always
	Loot.apply([{"chance": 0.0, "add_buff": "proud"}], ctx)
	Kit.expect(f, not folk.has_buff("proud"), "loot: chance 0 skipped")
	Loot.apply([{"chance": 1.0, "add_buff": "proud"}], ctx)
	Kit.expect(f, folk.has_buff("proud"), "loot: chance 1 applied")

func _test_skills(f: Array) -> void:
	var folk := Folk.create("T")
	var levels: Array = []
	SimEnv.events().skill_changed.connect(func(_i, s, l): levels.append([s, l]))
	folk.add_skill_xp("cooking", 99)
	Kit.expect(f, folk.skill_level("cooking") == 0, "skill: 99xp -> level 0")
	folk.add_skill_xp("cooking", 1)
	Kit.expect(f, folk.skill_level("cooking") == 1, "skill: 100xp -> level 1")
	folk.add_skill_xp("cooking", 100000)
	Kit.expect(f, folk.skill_level("cooking") == 10, "skill: capped at level 10")
	Kit.expect(f, levels.size() >= 2 and levels[0] == ["cooking", 1], "skill: skill_changed emitted")
	for s in ["cooking", "fitness", "logic", "charisma", "handiness", "painting"]:
		Kit.expect(f, folk.skills.has(s), "skill: %s exists" % s)

func _test_traits_decay(f: Array) -> void:
	var a := Folk.create("A")
	var b := Folk.create("B", ["glutton"])
	a.tick_needs(100.0)
	b.tick_needs(100.0)
	var da: float = 55.0 - (a.needs["hunger"] as Stat).value
	var db: float = 55.0 - (b.needs["hunger"] as Stat).value
	Kit.expect(f, Kit.near(db / da, 1.3, 0.02), "trait: glutton hunger decays x1.3 (ratio %f)" % (db / da))

func _test_saveload(f: Array) -> void:
	var folk := Folk.create("Mira", ["neat", "social"])
	folk.household_id = 3
	folk.tile = Vector2i(4, 9)
	folk.work_start = 9.0
	(folk.needs["hunger"] as Stat).set_value(-12.5)
	folk.add_skill_xp("painting", 310)
	folk.add_buff("fresh")
	folk.add_rel(77, "friendship", 12.0)
	folk.remember("obj:5", -0.3)
	var json := JSON.stringify(folk.to_dict())
	var parsed: Variant = JSON.parse_string(json)
	Kit.expect(f, parsed is Dictionary, "save: JSON round trip parses")
	var g := Folk.from_dict(parsed)
	Kit.expect(f, g.id == folk.id and g.name == "Mira" and g.household_id == 3, "save: identity restored")
	Kit.expect(f, g.tile == Vector2i(4, 9) and g.traits == folk.traits, "save: tile+traits restored")
	Kit.expect(f, Kit.near((g.needs["hunger"] as Stat).value, -12.5), "save: need value restored")
	Kit.expect(f, g.skill_level("painting") == 2 and g.has_buff("fresh") and g.has_job(), "save: skill/buff/job restored")
	Kit.expect(f, Kit.near(g.get_rel(77, "friendship"), 12.0), "save: relationship restored")
	Kit.expect(f, g.memory.size() == 1 and g.memory_bias("obj:5") < 0.0, "save: memory restored")
