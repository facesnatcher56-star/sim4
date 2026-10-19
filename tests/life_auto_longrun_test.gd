extends RefCounted
## Task 14b, 28 game days with NO player input (SLOW tier): three households nobody plays use the places by themselves, weighted by who they are.
## Checks: every household uses at least N kinds of places; the kids are at school on school days; a sick adult goes to the clinic; the pets are looked after;
## the outings stay rare enough (home life is not swamped: needs, work attendance); children and teens never use the bar or the nightclub.
## (The same run on the real map with the feature switched off and the time at home: life_auto_home_longrun_test.)

const L = preload("res://tests/life_auto_kit.gd")
const K = preload("res://tests/systems_kit.gd")
const DAYS := 28
const MIN_KINDS := 5            # place KINDS (food, culture, health ...) per household; the measured lowest is printed by the run

var _worst: float = 1000.0
var _pet_low: float = 1000.0

func _sample(d: Dictionary) -> void:
	for nm in d["who"]:
		for n in ["hunger", "energy", "bladder", "hygiene"]:
			_worst = minf(_worst, d["who"][nm].get_stat_value(n))
	for pet in [d["rex"], d["mittens"]]:
		if PetState.pets.has(int(pet["id"])):
			_pet_low = minf(_pet_low, float(pet["fullness"]))

func run() -> Array:
	var f: Array = []
	var d: Dictionary = L.build()
	var who: Dictionary = d["who"]
	var t0 := Time.get_ticks_msec()
	L.run_days(d, DAYS, func(day):
		if day == 6:
			Health.fall_ill(who["hal"], "flu", 1, "test")
		if day == 12:
			Health.fall_ill(who["ann"], "flu", 1, "test"),
		func(): _sample(d))
	print("life_auto_longrun: %d days in %d s" % [DAYS, (Time.get_ticks_msec() - t0) / 1000])
	print("life_auto_longrun: stats ", PlaceAuto.stats)
	var kinds_min := 99
	for hid in [1, 2, 3]:
		var ks: Array = L.kinds_used(hid)
		kinds_min = mini(kinds_min, ks.size())
		print("life_auto_longrun: household %d used %d place kinds %s, %d places %s" % [hid, ks.size(), str(ks), PlaceAuto.kinds_used(hid).size(), str(PlaceAuto.kinds_used(hid))])
		K.expect(f, ks.size() >= MIN_KINDS, "household %d used at least %d kinds of places in %d days (%s)" % [hid, MIN_KINDS, DAYS, str(ks)])
	print("life_auto_longrun: fewest place kinds in a household: %d" % kinds_min)
	# the kids go to school on school days
	var school_days := 0
	for day2 in range(1, DAYS + 1):
		if CareerShifts.is_school_day(day2):
			school_days += 1
	for nm in ["cy", "di"]:
		var went := 0
		for e in K.events:
			if e[0] == "returned_from_school" and int(e[1].get("folk_id", -1)) == int(who[nm].id) and not bool(e[1].get("skipped", false)):
				went += 1
		print("life_auto_longrun: %s at school %d of %d school days" % [nm, went, school_days])
		K.expect(f, went >= school_days - 3, "%s was at school on %d of %d school days" % [nm, went, school_days])
	# a sick adult visits the clinic
	var clinic_hal := 0
	var clinic_ann := 0
	for e2 in K.events:
		if e2[0] == "place_used" and str(e2[1].get("place", "")) == "clinic" and str(e2[1].get("service", "")) == "treat":
			if int(e2[1].get("folk_id", -1)) == int(who["hal"].id):
				clinic_hal += 1
			if int(e2[1].get("folk_id", -1)) == int(who["ann"].id):
				clinic_ann += 1
	K.expect(f, clinic_hal >= 1, "Hal, ill on day 6, saw the doctor by themselves (%d visits)" % clinic_hal)
	print("life_auto_longrun: Hal treated %d times, Ann %d times" % [clinic_hal, clinic_ann])
	# the pets are cared for
	K.expect(f, PetState.pets.has(int(d["rex"]["id"])) and PetState.pets.has(int(d["mittens"]["id"])), "both pets are still at home after %d days" % DAYS)
	for pet in [d["rex"], d["mittens"]]:
		K.expect(f, int(pet["hungry_days"]) == 0 and float(pet["bond"]) >= 25.0, "%s is fed and the bond held (fullness %.0f, bond %.0f)" % [pet["name"], float(pet["fullness"]), float(pet["bond"])])
	print("life_auto_longrun: lowest pet fullness %.0f, %d pet jobs" % [_pet_low, int(PlaceAuto.stats.get("pet_care", 0))])
	K.expect(f, _pet_low > 5.0, "no pet was ever left with an empty bowl (lowest %.0f)" % _pet_low)
	K.expect(f, int(PlaceAuto.stats.get("pet_care", 0)) >= DAYS, "the pets were cared for every day (%d jobs)" % int(PlaceAuto.stats.get("pet_care", 0)))
	# rare enough: outings per person per day
	var trips: int = int(PlaceAuto.stats["started"])
	var per_day: float = float(trips) / (8.0 * float(DAYS))
	print("life_auto_longrun: %d outings, %.2f per person per day" % [trips, per_day])
	K.expect(f, per_day > 0.1 and per_day < 0.75, "outings stay rare: %.2f per person per day" % per_day)
	# nobody under age in the bar
	for e3 in K.events:
		if e3[0] == "place_used" and str(e3[1].get("place", "")) in ["bar", "nightclub"]:
			K.expect(f, str(SysUtil.folk(int(e3[1]["folk_id"])).age_stage) in ["adult", "elder"], "only grown-ups used the %s" % str(e3[1]["place"]))
	# home life: nobody starved, the cook went to work
	print("life_auto_longrun: worst need over the run %.0f" % _worst)
	K.expect(f, _worst > -95.0, "nobody's needs hit rock bottom (worst %.0f)" % _worst)
	var shifts := 0
	var missed := 0
	for e4 in K.events:
		if e4[0] == "returned_from_work" and int(e4[1].get("folk_id", -1)) == int(who["bo"].id):
			shifts += 1
			if bool(e4[1].get("skipped", false)):
				missed += 1
	print("life_auto_longrun: Bo worked %d shifts, %d missed" % [shifts, missed])
	K.expect(f, shifts >= 10 and missed <= 1, "work is not hurt: %d shifts, %d missed" % [shifts, missed])
	K.teardown()
	return f
