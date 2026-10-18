extends RefCounted
## Hospital rabbit hole: injured / sick markers, admit -> away -> discharge with a bill, insurance hook, early discharge,
## unaffordable bills, status chips, the statistical townie version (returns or dies per data), save round trip.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_markers(f)
	_stay(f)
	_money(f)
	_townies(f)
	_save(f)
	return f

func _setup() -> StubWorld:
	var w := K.setup()
	Incidents.reset()
	Incidents.set_level("rare")
	return w

func _markers(f: Array) -> void:
	var w := _setup()
	var a := K.make_folk(w, "Ada", [], 1)
	Hospital.injure(a, 1, "a trip")
	K.expect(f, a.has_buff("injured") and not Hospital.is_in(a), "minor injury: marker only")
	var chips: Array = Hospital.status_chips(a)
	K.expect(f, chips.size() == 1 and chips[0]["text"] == "Injured", "folk panel chip for injured")
	Hospital.fall_ill(a, 1, "a bug")
	K.expect(f, a.has_buff("sick") and Hospital.status_chips(a).size() == 2, "sick marker + chip")
	var b := K.make_folk(w, "Bo", [], 1, Vector2i(9, 9))
	Hospital.injure(b, 2, "a bad fall")
	K.expect(f, a.has_buff("injured") and Hospital.is_in(b) and b.has_buff("in_hospital"), "serious injury is admitted")
	K.expect(f, not Hospital.admit(b.id, 2, "again"), "no double admission")
	var labels: String = ",".join(Hospital.status_chips(b).map(func(c): return c["text"]))
	K.expect(f, labels.find("In hospital") >= 0, "chip says In hospital: %s" % labels)
	K.teardown()

func _stay(f: Array) -> void:
	var w := _setup()
	var a := K.make_folk(w, "Ada", [], 1)
	WorldIface.coins[1] = 1000
	K.set_time(3, 8, 0)
	var dir = K.director()
	K.expect(f, Hospital.admit(a.id, 1, "a check"), "admit")
	K.run(dir, 5)
	K.expect(f, SysUtil.is_away(a) and Away.info(a.id)["reason"] == "hospital", "the patient leaves the lot (hidden Away: hospital)")
	K.run(dir, 120)
	K.expect(f, Hospital.is_in(a), "still in hospital after 2 hours (severity 1 = 4 h)")
	K.run(dir, 140)
	K.expect(f, not Hospital.is_in(a) and not SysUtil.is_away(a) and not a.has_buff("in_hospital"), "discharged after the stay")
	K.expect(f, WorldIface.get_coins(1) == 1000 - 60 and K.has_note("home from hospital"), "bill scaled by severity (60) paid: %d" % WorldIface.get_coins(1))
	# insurance hook halves it
	Incidents.insurance_fn = func(amount, _hid): return amount / 2
	K.expect(f, Incidents.insurance_cover(100, 1) == 50, "insurance_cover uses the hook")
	var b := K.make_folk(w, "Bo", [], 1, Vector2i(9, 9))
	Hospital.admit(b.id, 1, "x")
	K.run(dir, 5)
	K.expect(f, Hospital.discharge(b.id), "early discharge")
	K.run(dir, 3)
	K.expect(f, not Hospital.is_in(b) and not SysUtil.is_away(b), "early discharge brings them back")
	K.expect(f, WorldIface.get_coins(1) == 1000 - 60 - 30, "insurance paid half the bill: %d" % WorldIface.get_coins(1))
	Incidents.clear_handlers()
	K.teardown()

func _money(f: Array) -> void:
	var w := _setup()
	var a := K.make_folk(w, "Ada", [], 1)
	WorldIface.coins[1] = 20
	K.set_time(3, 8, 0)
	var net: int = Hospital.charge(1, 220, "Ada")
	K.expect(f, net == 220 and WorldIface.get_coins(1) == 20 and Economy.owed(1) == 220, "unaffordable bill becomes an ordinary bill (owed %d)" % Economy.owed(1))
	WorldIface.coins[1] = 500
	K.expect(f, Economy.pay_bill(1) == 220 and Economy.owed(1) == 0, "and can be paid later")
	var sev: Array = [Hospital.cfg()["bill"]["1"], Hospital.cfg()["bill"]["2"], Hospital.cfg()["bill"]["3"]]
	K.expect(f, sev[0] < sev[1] and sev[1] < sev[2], "cost scales with severity")
	var _a = a
	K.teardown()

func _townies(f: Array) -> void:
	var w := _setup()
	K.make_folk(w, "Ada", [], 1)
	Story.generate_townies()
	var ids: Array = Story.townies.keys()
	ids.sort()
	var t1: int = int(ids[0])
	var t2: int = int(ids[1])
	K.set_time(3, 8, 0)
	K.expect(f, Hospital.admit(t1, 1, "x") and Hospital.admit(t2, 3, "y") and bool(Story.townies[t1]["in_hospital"]), "far townies are admitted statistically")
	K.expect(f, IncidentChecks.townie_subjects(true).filter(func(s): return s.id == t1).is_empty(), "patients roll no new incidents")
	IncidentDefs.config["hospital"]["townie_death_chance"]["3"] = 1.0
	K.set_time(3, 14, 0)
	Hospital.on_hour()
	K.expect(f, not Hospital.is_in(t1) and not bool(Story.townies[t1].get("in_hospital", false)) and bool(Story.townies[t1]["alive"]), "minor stay: the townie comes home")
	K.expect(f, Hospital.is_in(t2), "serious stay is not over yet")
	K.set_time(5, 14, 0)
	K.events.clear()
	Hospital.on_hour()
	K.expect(f, not bool(Story.townies[t2]["alive"]) and str(Story.townies[t2]["cause"]) == "illness" and K.count_events("chronicle") >= 1, "death chance from data: dies (illness), chronicled")
	K.teardown()

func _save(f: Array) -> void:
	var w := _setup()
	var a := K.make_folk(w, "Ada", [], 1)
	WorldIface.coins[1] = 1000
	K.set_time(3, 8, 0)
	var dir = K.director()
	Hospital.admit(a.id, 2, "x")
	K.run(dir, 5)
	var before: Dictionary = Hospital.to_dict()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(before))
	Hospital.reset()
	Hospital.from_dict(parsed)
	var diffs: Array = []
	K.expect(f, K.deep_eq(before, Hospital.to_dict(), "hospital", diffs), "patients survive JSON: %s" % str(diffs))
	K.expect(f, SaveLoad.save(94, "hospital") and SaveLoad.load_slot(94), "whole-game save + load with a patient")
	SaveLoad.delete_slot(94)
	var a2 = w.get_folk(a.id)
	K.expect(f, a2 != null and Hospital.is_in(a2) and SysUtil.is_away(a2), "after loading the patient is still away in hospital")
	K.teardown()
