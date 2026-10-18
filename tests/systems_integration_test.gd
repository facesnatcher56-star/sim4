extends RefCounted
## Integrated 14-game-day headless run of every system on the stub world:
## folk go to work and get paid, bills are issued and paid, relationships form, birthdays / age-ups happen, goals
## complete, visitors drop by, and a mid-run save / load reproduces the saved state exactly.

const K = preload("res://tests/systems_kit.gd")
const SLOT := 96
const DAYS := 14

var _w: StubWorld
var _dir

func run() -> Array:
	var f: Array = []
	_w = K.setup(2024, true)
	var kit = load("res://tests/sim_testkit.gd")
	var objs: Dictionary = kit.furnish(_w)
	_w.add_object("bed", Vector2i(12, 14))
	_w.add_object("bed", Vector2i(14, 14))
	_w.add_object("toilet", Vector2i(16, 14))
	_w.add_object("sofa", Vector2i(16, 18))
	_w.add_object("shower", Vector2i(18, 14))
	var alice := Folk.create("Alice Reed", ["neat", "social"])
	var cara := Folk.create("Cara Reed", ["creative", "active", "romantic"])
	var dev := Folk.create("Dev Reed", ["bookworm"])
	var cast: Array = [alice, cara, dev]
	var tiles: Array = [Vector2i(12, 12), Vector2i(13, 12), Vector2i(14, 12)]
	for i in cast.size():
		(cast[i] as Folk).household_id = 1
		_w.add_folk(cast[i], tiles[i])
	dev.age_stage = "teen"
	K.mgr.new_game([1])
	Aging.set_age_days(alice, 60.0)
	Aging.set_age_days(cara, 47.0)
	Aging.set_age_days(dev, 42.6)       # teen who turns adult on day 3
	Careers.hire(alice, "coder", 1)
	Careers.hire(cara, "fitness_coach", 1)
	Careers.auto_accept_offers = true   # in the real game the player accepts via 'Look for Jobs'
	_dir = K.director()
	SaveLoad.autosave_slot = SLOT
	K.mgr.autosave_enabled = true
	SaveLoad.delete_slot(SLOT)
	var ids: Array = [alice.id, cara.id, dev.id]

	var stats: Dictionary = {"min_need": 999.0, "away_minutes": 0, "snap_ok": false, "snap_diff": [], "load_day": 0, "saved_state": {}}
	var t0: int = Time.get_ticks_msec()
	var total: int = DAYS * 1440
	var save_at: int = 7 * 1440 + (11 - 7) * 60          # day 8, 11:00 (a weekday, Alice is at work)
	var load_at: int = save_at + 600
	var minute: int = 0
	while minute < total:
		minute += 1
		if minute % 1440 == 1439:
			(objs["fridge"] as StubWorld.StubObject).state["stock"] = 10     # delivery truck, as in the sim tests
		K.run(_dir, 1)
		for fk in _w.all_folk():
			if not fk.has_meta("visitor") and SysUtil.is_away(fk):
				stats["away_minutes"] += 1
		if minute % 30 == 0:
			for fk2 in _w.all_folk():
				for n in fk2.needs:
					stats["min_need"] = minf(stats["min_need"], (fk2.needs[n] as Stat).value)
		if minute == save_at:
			stats["saved_state"] = SaveLoad.snapshot("mid-run")
			K.expect(f, SaveLoad.save(SLOT - 1, "mid-run"), "mid-run save works")
		if minute == load_at:
			_check_load(f, stats)
	var ms: int = Time.get_ticks_msec() - t0
	_report(f, stats, ids, ms)
	SaveLoad.delete_slot(SLOT)
	SaveLoad.delete_slot(SLOT - 1)
	SaveLoad.autosave_slot = 0
	K.teardown()
	return f

func _check_load(f: Array, stats: Dictionary) -> void:
	var later: Dictionary = SaveLoad.snapshot("later")
	# reload the mid-run save (the stub world has no save_dict, so free the object reservations by hand)
	K.expect(f, SaveLoad.load(SLOT - 1), "mid-run load works: %s" % SaveLoad.last_error)
	for o in _w.objects.values():
		o.slots_reserved.clear()
	var reloaded: Dictionary = SaveLoad.snapshot("mid-run")
	var diffs: Array = []
	var same: bool = K.deep_eq(stats["saved_state"], reloaded, "state", diffs)
	stats["snap_ok"] = same
	stats["snap_diff"] = diffs
	stats["load_day"] = SysUtil.day()
	K.expect(f, same, "loading the mid-run save reproduces its state: %s" % str(diffs.slice(0, 6)))
	K.expect(f, SysUtil.day() == 8 and SimEnv.hour_f() >= 10.99 and SimEnv.hour_f() < 11.1, "clock rewound to day 8 11:00, is %s" % SimEnv.clock().time_string())
	K.expect(f, int(later["clock_total"]) > int(stats["saved_state"]["clock_total"]), "we really went back in time")

func _report(f: Array, stats: Dictionary, ids: Array, ms: int) -> void:
	var ledger: Array = Economy.ledger_for(1)
	var wages: int = 0
	var wage_total: int = 0
	var bills_paid_total: int = 0
	for e in ledger:
		if str(e["reason"]).begins_with("wages"):
			wages += 1
			wage_total += int(e["amount"])
		if str(e["reason"]) == "bills":
			bills_paid_total += -int(e["amount"])
	var left: int = K.count_events("left_for_work")
	var back: int = K.count_events("returned_from_work")
	var bills_issued: int = K.count_events("bill_issued")
	var bills_paid: int = K.count_events("bill_paid")
	var birthdays: int = K.count_events("birthday")
	var aged: int = K.count_events("aged_up")
	var whims: int = K.count_events("whim_completed")
	var miles: int = K.count_events("milestone_completed")
	var visits: int = K.count_events("visit_started")
	var visits_done: int = K.count_events("visit_finished")
	var school: int = K.count_events("returned_from_school")
	var promos: int = K.count_events("promoted")
	var best_bit_rank: int = 0
	var bit_counts: Dictionary = {}
	for fid in ids:
		for other in ids:
			if fid == other:
				continue
			var bit: String = RelationshipBits.bit_for(fid, other)
			bit_counts[bit] = int(bit_counts.get(bit, 0)) + 1
	print("")
	print("  ===== systems integration: %d game days, 3 folk (+visitors), %d ms real time =====" % [DAYS, ms])
	print("  work      : %d departures, %d returns, %d wage payments totalling %d coins; %d promotions; %d school days" % [left, back, wages, wage_total, promos, school])
	print("  economy   : %d bills issued, %d paid (%d coins); funds now %d; repossessed %d" % [bills_issued, bills_paid, bills_paid_total, Economy.balance(1), Economy.repossessed.size()])
	print("  relations : bits between the household (directional): %s" % str(bit_counts))
	print("  life      : %d birthdays, %d age-ups; stages: %s" % [birthdays, aged, _stages(ids)])
	print("  goals     : %d whims fulfilled, %d milestones; satisfaction: %s" % [whims, miles, _points(ids)])
	print("  story     : %d visits started, %d finished, %d townies alive, news: %s" % [visits, visits_done, Story.alive_townies().size(), str(Story.recent_news(3).map(func(n): return n["text"]))])
	print("  away time : %d folk-minutes spent off the lot (work/school); min need seen %.0f" % [stats["away_minutes"], stats["min_need"]])
	print("  save/load : mid-run snapshot identical after reload = %s (autosave file present = %s)" % [str(stats["snap_ok"]), str(SaveLoad.has_slot(SLOT))])
	print("")
	K.expect(f, left >= 8, "folk went to work (%d departures)" % left)
	K.expect(f, back >= 8 and wages >= 8 and wage_total > 800, "folk got paid: %d returns, %d wages, %d coins" % [back, wages, wage_total])
	K.expect(f, bills_issued >= 2, "bills issued on days 7 and 14 (%d)" % bills_issued)
	K.expect(f, bills_paid >= 1 and bills_paid_total > 50, "the first bill was paid (%d paid, %d coins)" % [bills_paid, bills_paid_total])
	var known: int = 0
	for fid2 in ids:
		for other2 in ids:
			if fid2 != other2 and RelationshipBits.bit_for(fid2, other2) != "stranger":
				known += 1
	K.expect(f, known >= 3, "relationships formed between the folk (%d directed bits)" % known)
	var bonds: int = 0
	for b in ["friend", "best_friend", "sweetheart", "partner", "spouse", "family"]:
		bonds += int(bit_counts.get(b, 0))
	K.expect(f, bonds >= 1, "at least one real bond (friend or closer) formed: %s" % str(bit_counts))
	K.expect(f, birthdays >= 3, "birthdays happened (%d)" % birthdays)
	K.expect(f, aged >= 1, "someone aged up (%d)" % aged)
	K.expect(f, whims + miles >= 1, "goals completed (%d whims, %d milestones)" % [whims, miles])
	K.expect(f, school >= 1, "the teen went to school (%d)" % school)
	K.expect(f, Story.news.size() >= 1 and Story.alive_townies().size() >= 6, "townies lived their lives off-lot")
	K.expect(f, SaveLoad.has_slot(SLOT), "daily autosave wrote a file")
	K.expect(f, stats["min_need"] > -100.0, "nobody hit rock bottom on a need")
	K.expect(f, Aging.dead.is_empty(), "nobody died in 14 days")
	K.expect(f, _w.all_folk().size() >= 3, "household still intact")

func _stages(ids: Array) -> String:
	var parts: Array = []
	for id in ids:
		var fk = _w.get_folk(id)
		if fk != null:
			parts.append("%s=%s(%dy)" % [str(fk.name).split(" ")[0], fk.age_stage, Aging.age_years(id)])
	return ", ".join(parts)

func _points(ids: Array) -> String:
	var parts: Array = []
	for id in ids:
		var fk = _w.get_folk(id)
		if fk != null:
			parts.append("%s=%d" % [str(fk.name).split(" ")[0], Goals.points(id)])
	return ", ".join(parts)
