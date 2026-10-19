extends RefCounted
## Task 14b, 28 game days with NO player input (SLOW tier): three households nobody plays use the places by themselves, weighted by who they are.
## Checks: every household uses at least N kinds of places; the kids are at school on school days; a sick adult goes to the clinic; the pets are looked after;
## a teen applies to college; the outings stay rare enough (home life is not swamped: needs, work attendance); nobody under age uses the bar or the nightclub.
## (The same run on the real map with the feature switched off and the time at home: life_auto_home_longrun_test.)
## `-- life_auto_longrun_test --days=10` runs a shorter version for tuning.

const L = preload("res://tests/life_auto_kit.gd")
const K = preload("res://tests/systems_kit.gd")
const MIN_PLACES := 6
const MIN_KINDS := 4            # place KINDS (food, culture, health ...) per household; the run prints the measured fewest (7 in 28 days at the time of writing)

var _days: int = 28
var _worst: float = 1000.0
var _worst_who: String = ""
var _off: bool = false
var _work_due: int = 0                # workdays on which the cook had a job
var _treats: Dictionary = {}          # "folk|day" -> treatments at the clinic that day
var _pet_low: float = 1000.0
var _school_due: Dictionary = {}      # folk name -> school days on which they were a school-age student

func _sample(d: Dictionary) -> void:
	for nm in d["who"]:
		for n in ["hunger", "energy", "bladder", "hygiene"]:
			var v: float = d["who"][nm].get_stat_value(n)
			if v < _worst:
				_worst = v
				_worst_who = "%s %s day %d %02d:00" % [nm, n, SysUtil.day(), int(SysUtil.hour_f())]
	for pet in [d["rex"], d["mittens"]]:
		if PetState.pets.has(int(pet["id"])):
			_pet_low = minf(_pet_low, float(pet["fullness"]))

func _start_of_day(d: Dictionary, day: int) -> void:
	var who: Dictionary = d["who"]
	if day == 6:
		Health.fall_ill(who["hal"], "flu", 1, "test")
	if day == 12:
		Health.fall_ill(who["ann"], "flu", 1, "test")
	var bo = who["bo"]
	if Careers.jobs.has(int(bo.id)) and CareerShifts.is_work_day(str(Careers.jobs[int(bo.id)]["career"]), day, str(Careers.jobs[int(bo.id)].get("shift", "day"))):
		_work_due += 1
	if CareerShifts.is_school_day(day):
		for nm in ["cy", "di"]:
			if Careers.school.has(int(who[nm].id)) and not Careers.jobs.has(int(who[nm].id)):          # (a teen with a job is not sent to school: Careers)
				_school_due[nm] = int(_school_due.get(nm, 0)) + 1

func run() -> Array:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--days="):
			_days = int(a.substr(7))
		if a == "--off":
			_off = true
	var f: Array = []
	var d: Dictionary = L.build()
	var who: Dictionary = d["who"]
	SimEnv.events().game_event.connect(func(n, pl):
		if n == "place_used" and str(pl.get("service", "")) == "treat":
			var k := "%d|%d" % [int(pl.get("folk_id", -1)), SysUtil.day()]
			_treats[k] = int(_treats.get(k, 0)) + 1)
	PlaceAuto.off = _off              # `-- --off`: the same run without the outings, to compare
	var t0 := Time.get_ticks_msec()
	L.run_days(d, _days, func(day): _start_of_day(d, day), func(): _sample(d))
	print("life_auto_longrun: %d days in %d s" % [_days, (Time.get_ticks_msec() - t0) / 1000])
	var s: Dictionary = PlaceAuto.stats
	print("life_auto_longrun: planned %d, started %d, done %d, dropped %d, pet jobs %d" % [s["planned"], s["started"], s["done"], s["dropped"], int(s.get("pet_care", 0))])
	var ks_sorted: Array = (s["kinds"] as Dictionary).keys()
	ks_sorted.sort_custom(func(a, b): return int(s["kinds"][a]) > int(s["kinds"][b]))
	print("life_auto_longrun: by kind ", ", ".join(ks_sorted.map(func(k): return "%s %d" % [k, int(s["kinds"][k])])))
	print("life_auto_longrun: drops ", s["drops"])
	print("life_auto_longrun: outings per person ", s["who"])
	var kinds_min := 99
	for hid in [1, 2, 3]:
		var ks: Array = L.kinds_used(hid)
		kinds_min = mini(kinds_min, ks.size())
		print("life_auto_longrun: household %d used %d place kinds %s, %d places %s" % [hid, ks.size(), str(ks), PlaceAuto.kinds_used(hid).size(), str(PlaceAuto.kinds_used(hid))])
		K.expect(f, ks.size() >= MIN_KINDS and PlaceAuto.kinds_used(hid).size() >= MIN_PLACES, "household %d used at least %d kinds (%d places) in %d days (%s)" % [hid, MIN_KINDS, MIN_PLACES, _days, str(ks)])
	print("life_auto_longrun: fewest place kinds in a household: %d" % kinds_min)
	# the kids go to school on school days
	for nm in ["cy", "di"]:
		var went := 0
		for e in K.events:
			if e[0] == "returned_from_school" and int(e[1].get("folk_id", -1)) == int(who[nm].id) and not bool(e[1].get("skipped", false)):
				went += 1
		var due: int = int(_school_due.get(nm, 0))
		print("life_auto_longrun: %s at school %d of %d school days" % [nm, went, due])
		K.expect(f, (due >= 5 or nm == "di") and went >= due - 2, "%s was at school on %d of %d school days" % [nm, went, due])
	# a sick adult visits the clinic (and is not sent back every day)
	var clinic_hal := 0
	var clinic_ann := 0
	var ill_hal := 0
	var ill_ann := 0
	for e5 in K.events:
		if e5[0] == "fell_ill":
			if int(e5[1].get("folk_id", -1)) == int(who["hal"].id):
				ill_hal += 1
			if int(e5[1].get("folk_id", -1)) == int(who["ann"].id):
				ill_ann += 1
	for e2 in K.events:
		if e2[0] == "place_used" and str(e2[1].get("place", "")) == "clinic" and str(e2[1].get("service", "")) == "treat":
			if int(e2[1].get("folk_id", -1)) == int(who["hal"].id):
				clinic_hal += 1
			if int(e2[1].get("folk_id", -1)) == int(who["ann"].id):
				clinic_ann += 1
	print("life_auto_longrun: Hal treated %d times, Ann %d times" % [clinic_hal, clinic_ann])
	var adult_treats := 0
	for e6 in K.events:
		if e6[0] == "place_used" and str(e6[1].get("place", "")) == "clinic" and str(e6[1].get("service", "")) == "treat" and str(SysUtil.folk(int(e6[1]["folk_id"])).age_stage) in ["adult", "elder"]:
			adult_treats += 1
	print("life_auto_longrun: %d treatments of grown-ups at the clinic" % adult_treats)
	if _days >= 8:
		K.expect(f, adult_treats >= 1 and ill_hal + ill_ann >= 1, "a sick adult went to the clinic by themselves (%d treatments, %d illnesses forced or natural)" % [adult_treats, ill_hal + ill_ann])
	print("life_auto_longrun: Hal fell ill %d times, Ann %d times" % [ill_hal, ill_ann])
	var worst_day := 0
	for k2 in _treats:
		worst_day = maxi(worst_day, int(_treats[k2]))
	K.expect(f, worst_day <= 1, "nobody sees the doctor twice in a day (%d at most)" % worst_day)
	# the pets are cared for
	K.expect(f, PetState.pets.has(int(d["rex"]["id"])) and PetState.pets.has(int(d["mittens"]["id"])), "both pets are still at home after %d days" % _days)
	for pet in [d["rex"], d["mittens"]]:
		K.expect(f, int(pet["hungry_days"]) == 0 and float(pet["bond"]) >= 25.0, "%s is fed and the bond held (fullness %.0f, bond %.0f)" % [pet["name"], float(pet["fullness"]), float(pet["bond"])])
	print("life_auto_longrun: lowest pet fullness %.0f" % _pet_low)
	K.expect(f, _pet_low > 5.0, "no pet was ever left with an empty bowl (lowest %.0f)" % _pet_low)
	K.expect(f, int(s.get("pet_care", 0)) >= _days, "the pets were cared for every day (%d jobs)" % int(s.get("pet_care", 0)))
	# the teen looked ahead
	var applied: String = str(EduState.peek(int(who["di"].id)).get("applied", ""))
	print("life_auto_longrun: Di applied for %s" % applied)
	if _days >= 20:
		K.expect(f, applied != "", "the teen applied to college")
	# rare enough: outings per person per day
	var per_day: float = float(s["started"]) / (8.0 * float(_days))
	print("life_auto_longrun: %d outings, %.2f per person per day" % [int(s["started"]), per_day])
	K.expect(f, per_day > 0.08 and per_day < 0.5, "outings stay rare: %.2f per person per day" % per_day)
	# nobody under age in the bar
	for e3 in K.events:
		if e3[0] == "place_used" and str(e3[1].get("place", "")) in ["bar", "nightclub"]:
			K.expect(f, str(SysUtil.folk(int(e3[1]["folk_id"])).age_stage) in ["adult", "elder"], "only grown-ups used the %s" % str(e3[1]["place"]))
	# home life: nobody starved, the cook went to work
	print("life_auto_longrun: worst need over the run %.0f (%s)" % [_worst, _worst_who])
	K.expect(f, _worst > -95.0, "nobody's needs hit rock bottom (worst %.0f)" % _worst)
	# work and school are never skipped because of an outing: every missed shift has another reason (illness, a run-down body ...)
	var shifts := 0
	var why_counts: Dictionary = {}
	for e4 in K.events:
		if e4[0] == "returned_from_work" and int(e4[1].get("folk_id", -1)) == int(who["bo"].id) and not bool(e4[1].get("skipped", false)):
			shifts += 1
		if e4[0] == "missed_shift":
			var w := "%s: %s" % [str(e4[1].get("kind", "")), str(e4[1].get("why", ""))]
			why_counts[w] = int(why_counts.get(w, 0)) + 1
	print("life_auto_longrun: Bo finished %d of %d workdays; missed shifts by reason %s" % [shifts, _work_due, str(why_counts)])
	for w2 in why_counts:
		K.expect(f, str(w2).find("busy with something else") < 0 and str(w2).find("chose to skip") < 0, "no shift or school day was skipped because the person was busy elsewhere (%s)" % str(w2))
	K.teardown()
	return f
