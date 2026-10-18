extends RefCounted
## Save / load: versioned file format, round trip of clock + folk + every system, migration, bad files, autosave.

const K = preload("res://tests/systems_kit.gd")
const SLOT := 97

func run() -> Array:
	var f: Array = []
	_roundtrip(f)
	_migration_and_errors(f)
	_autosave(f)
	return f

func _build(w: StubWorld) -> Dictionary:
	K.make_folk(w, "Ann", ["glutton", "neat"])
	var bo := K.make_folk(w, "Bo", ["lazy"])
	var kid := K.make_folk(w, "Kid", [], 1, Vector2i(14, 12), "child")
	Aging.set_age_days(kid, 15.0)
	var ann = w.get_folk(1) if w.get_folk(1) != null else null
	var folks: Array = w.all_folk()
	ann = folks[0]
	w.add_object("fridge", Vector2i(3, 3))
	WorldIface.coins[1] = 1234
	Careers.hire(ann, "cook", 2)
	CareerProgress.add_performance(ann.id, 17.0)
	RelationshipService.add_both(ann.id, bo.id, "friendship", 42.0)
	RelationshipService.add_both(ann.id, bo.id, "romance", 20.0)
	RelationshipService.add_history(ann.id, bo.id, "chat", 0.3)
	Goals.set_aspiration(ann.id, "master_chef")
	Goals.feed(ann, {"type": "interaction", "id": "cook_meal", "tags": []})
	Goals.profiles[ann.id]["next_whim_min"] = 0
	Goals.tick_whims(ann)
	Story.generate_townies()
	Economy.on_day(7)
	ann.add_skill_xp("cooking", 130.0)
	ann.add_buff("proud")
	(ann.needs["hunger"] as Stat).set_value(-12.5)
	return {"ann": ann, "bo": bo, "kid": kid}

func _roundtrip(f: Array) -> void:
	var w := K.setup()
	var cast: Dictionary = _build(w)
	K.set_time(8, 10, 30)
	# someone is at a party (away) while we save
	Story.auto_accept_invites = false
	var tid: int = int(Story.alive_townies()[2]["id"])
	var dir = K.director()
	var inv: Dictionary = StoryVisits.send_invite(tid, (cast["bo"] as Folk).id)
	StoryVisits.respond_invite(int(inv["id"]), true)
	K.run(dir, 3)
	K.expect(f, SysUtil.is_away(cast["bo"]), "precondition: Bo is away at save time")
	var snap_before: Dictionary = SaveLoad.snapshot("test")
	K.expect(f, SaveLoad.save(SLOT, "Roundtrip household"), "save() writes the file: %s" % SaveLoad.last_error)
	K.expect(f, SaveLoad.has_slot(SLOT), "slot file exists")
	var raw: Dictionary = SaveLoad.read(SLOT)
	K.expect(f, raw.get("format") == "sim4" and int(raw.get("version", 0)) == SaveLoad.VERSION, "versioned format")
	K.expect(f, raw["systems"].has("economy") and raw["systems"].has("careers") and raw["systems"].has("relationships") and raw["systems"].has("goals") and raw["systems"].has("aging") and raw["systems"].has("story"), "all systems are saved")
	K.expect(f, (raw["folk"] as Array).size() == 3, "all folk are saved")
	K.expect(f, SaveLoad.summary(SLOT).find("Roundtrip household") >= 0 and SaveLoad.summary(SLOT).find("Day 8") >= 0, "slot summary: %s" % SaveLoad.summary(SLOT))
	# wreck everything
	K.run(dir, 400)
	WorldIface.coins[1] = 5
	Careers.reset()
	Goals.reset()
	Aging.reset()
	RelationshipService.reset()
	Story.reset()
	Economy.reset()
	for fk in w.all_folk().duplicate():
		fk.current = null
		fk.queue.clear()
		SysUtil.world_remove_folk(fk.id)
	var ok: bool = SaveLoad.load(SLOT)
	K.expect(f, ok, "load() succeeds: %s" % SaveLoad.last_error)
	K.expect(f, w.all_folk().size() == 3, "folk restored: %d" % w.all_folk().size())
	K.expect(f, SimEnv.now_min() == int(snap_before["clock_total"]), "clock restored to the saved minute")
	var snap_after: Dictionary = SaveLoad.snapshot("test")
	var diffs: Array = []
	var same: bool = K.deep_eq(snap_before, snap_after, "save", diffs)
	K.expect(f, same, "state after load equals the saved state: %s" % str(diffs.slice(0, 8)))
	K.expect(f, WorldIface.get_coins(1) == 1234 + 0 or WorldIface.get_coins(1) >= 1000, "coins restored (%d)" % WorldIface.get_coins(1))
	var ann = null
	for fk2 in w.all_folk():
		if fk2.name == "Ann":
			ann = fk2
	K.expect(f, ann != null and ann.has_buff("proud") and absf((ann.needs["hunger"] as Stat).value + 12.5) < 1.0 and ann.skill_level("cooking") >= 1, "folk state restored: %s" % (str(ann.buff_ids()) + " hunger=" + str((ann.needs["hunger"] as Stat).value) + " cooking=" + str(ann.skill_level("cooking")) if ann != null else "none"))
	K.expect(f, ann != null and Careers.career_of(ann.id) == "cook" and ann.work_start == 10.0, "job restored and schedule re-applied")
	K.expect(f, ann != null and Goals.active_for(ann.id)["aspiration"] == "master_chef", "goals restored")
	# the away folk is still away and returns on schedule
	var bo = null
	for fk3 in w.all_folk():
		if fk3.name == "Bo":
			bo = fk3
	K.expect(f, bo != null and Away.is_away(bo.id), "Bo is still away after loading")
	K.run(dir, 5)
	K.expect(f, bo != null and SysUtil.is_away(bo), "Bo's away interaction resumed")
	K.run(dir, 200)
	K.expect(f, bo != null and not SysUtil.is_away(bo), "Bo came home from the party after loading")
	SaveLoad.delete_slot(SLOT)
	K.expect(f, not SaveLoad.has_slot(SLOT), "delete_slot removes the file")
	K.teardown()

func _migration_and_errors(f: Array) -> void:
	var w := K.setup()
	K.expect(f, not SaveLoad.load(SLOT), "loading an empty slot fails cleanly")
	K.expect(f, SaveLoad.last_error != "", "reports why")
	# a v1 file (as written by ui/save_slots.gd) has no systems block
	var folk := Folk.create("Old", ["neat"])
	folk.household_id = 1
	var v1: Dictionary = {"version": 1, "household_name": "Legacy", "day": 3, "clock_total": 4000, "folk": [folk.to_dict()], "world": {}}
	DirAccess.make_dir_recursive_absolute(SaveLoad.DIR)
	var fa := FileAccess.open(SaveLoad.path(SLOT), FileAccess.WRITE)
	fa.store_string(JSON.stringify(v1))
	fa.close()
	K.expect(f, SaveLoad.load(SLOT), "v1 files migrate and load")
	K.expect(f, w.all_folk().size() == 1 and SimEnv.now_min() == 4000, "v1 folk and clock restored")
	var migrated: Dictionary = SaveLoad.migrate({"version": 1})
	K.expect(f, int(migrated["version"]) == 2 and migrated.has("systems"), "migrate() upgrades the version")
	# newer versions are refused, garbage is refused
	var fb := FileAccess.open(SaveLoad.path(SLOT), FileAccess.WRITE)
	fb.store_string(JSON.stringify({"format": "sim4", "version": 99, "folk": []}))
	fb.close()
	K.expect(f, not SaveLoad.load(SLOT), "a save from the future is refused")
	var fc := FileAccess.open(SaveLoad.path(SLOT), FileAccess.WRITE)
	fc.store_string("{not json")
	fc.close()
	K.expect(f, not SaveLoad.load(SLOT), "corrupt files are refused")
	SaveLoad.delete_slot(SLOT)
	K.teardown()

func _autosave(f: Array) -> void:
	var w := K.setup()
	K.make_folk(w, "Ann")
	SaveLoad.autosave_slot = SLOT
	K.mgr.autosave_enabled = true
	SaveLoad.delete_slot(SLOT)
	SimEnv.clock().advance_minutes(24 * 60)
	K.expect(f, SaveLoad.has_slot(SLOT), "autosave happens when a game day passes")
	K.expect(f, int(SaveLoad.read(SLOT).get("day", 0)) == 2, "autosave records the day")
	SaveLoad.delete_slot(SLOT)
	SaveLoad.autosave_slot = 0
	K.teardown()
