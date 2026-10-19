extends RefCounted
## Task 21 part 2: security guards. Two careers (guard, night watchman) merged into the career table, posts at the bank, jeweller and museum staffed by
## townies, alertness that drops when tired, and a guard asleep on a night shift missing (almost) everything.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_careers(f)
	_posts(f)
	_alertness(f)
	_asleep(f)
	_night_sleep_rate(f)
	_rounds(f)
	_watchman(f)
	_record(f)
	return f

func _careers(f: Array) -> void:
	var w := C.town(12)
	K.expect(f, not Careers.career_def("security_guard").is_empty() and not Careers.career_def("night_watchman").is_empty(), "both guard careers exist after install")
	var nw: Dictionary = Careers.level_def("night_watchman", 1)
	K.expect(f, int(nw["start"]) == 22 and int(nw["end"]) == 6, "the night watchman works the small hours")
	CrimeFlow.uninstall()
	K.expect(f, Careers.career_def("security_guard").is_empty(), "uninstall removes them again (a second game starts clean)")
	CrimeFlow.install()
	K.teardown()

func _posts(f: Array) -> void:
	var w := C.town(14)
	CrimeSecurityGuards.staff_town()
	var bank: Array = CrimeSecurityGuards.guards_of("biz:bank")
	K.expect(f, bank.size() == 2, "the bank has a day guard and a night guard (%d)" % bank.size())
	var nights: int = 0
	for pid in bank:
		if str(CrimeLifeState.guards[pid]["shift"]) == "night":
			nights += 1
	K.expect(f, nights == 1 and CrimePerson.career(int(bank[0])) in ["security_guard", "night_watchman"], "one works nights, and they hold the careers")
	K.expect(f, CrimeSecurityGuards.guards_of("biz:market").is_empty(), "a market has no posted guard")
	CrimeSecurityGuards.staff_town()
	K.expect(f, CrimeSecurityGuards.guards_of("biz:bank").size() == 2, "staffing is idempotent")
	K.teardown()

func _alertness(f: Array) -> void:
	var w := C.town(14)
	CrimeSecurityGuards.staff_town()
	var day_guard: int = -1
	var night_guard: int = -1
	for pid in CrimeSecurityGuards.guards_of("biz:bank"):
		if str(CrimeLifeState.guards[pid]["shift"]) == "night":
			night_guard = int(pid)
		else:
			day_guard = int(pid)
	var a_day: float = CrimeSecurityGuards.alertness(day_guard)
	var a_night: float = CrimeSecurityGuards.alertness(night_guard)
	K.expect(f, a_night < a_day, "a night guard is less alert than a day guard (%.2f vs %.2f)" % [a_night, a_day])
	CrimeLifeState.guards[night_guard]["fatigue"] = 0.3
	K.expect(f, CrimeSecurityGuards.alertness(night_guard) < a_night, "a run of night shifts tires them further")
	Story.townies[day_guard]["traits"] = ["lazy"]
	K.expect(f, CrimeSecurityGuards.alertness(day_guard) < a_day, "a lazy guard watches less")
	for i in 20:
		K.set_time(4 + i, 12)
		CrimeSecurityGuards.on_day()
	K.expect(f, float(CrimeLifeState.guards[night_guard]["fatigue"]) >= 0.28, "fatigue builds up with nights worked")
	K.teardown()

func _asleep(f: Array) -> void:
	var w := C.town(14)
	CrimeLifePath.join(1)
	CrimeSecurityGuards.staff_town()
	K.set_time(3, 2, 0)
	var scene: String = "biz:bank"
	var awake: Dictionary = CrimeLifeRoll.odds(1, "heist", scene, {"night": true, "cased": 0.0})
	for pid in CrimeSecurityGuards.guards_of(scene):
		CrimeSecurityGuards.set_asleep(int(pid), true)
	var asleep: Dictionary = CrimeLifeRoll.odds(1, "heist", scene, {"night": true, "cased": 0.0})
	K.expect(f, float(asleep["detect"]) < float(awake["detect"]), "at the bank an asleep guard still leaves the cameras and alarm (%.2f vs %.2f)" % [asleep["detect"], awake["detect"]])
	K.expect(f, float(asleep["catch"]) < float(awake["catch"]) * 0.85, "but is far less likely to catch anyone (%.2f vs %.2f)" % [asleep["catch"], awake["catch"]])
	K.expect(f, CrimeSecurityGuards.alert_for(scene) < 0.3, "the watch of the place is nearly blind")
	# casing the round also opens gaps
	for pid in CrimeSecurityGuards.guards_of(scene):
		CrimeSecurityGuards.set_asleep(int(pid), false)
	var cased: Dictionary = CrimeLifeRoll.odds(1, "heist", scene, {"night": true, "cased": 1.0})
	K.expect(f, float(cased["detect"]) < float(awake["detect"]), "a cased target with known guard routes is easier (%.2f vs %.2f)" % [cased["detect"], awake["detect"]])
	# a place guarded by people alone: the sleeping guard is the whole difference
	var b: Dictionary = BusinessState.make("cafe", "cafe", "own", "player", 1, "Watched Cafe")
	CrimeLifeState.biz_sec[int(b["id"])] = {"guard": 2}
	var post: String = "biz:%d" % int(b["id"])
	var picks: Array = C.adults().slice(0, 2)
	for pid in picks:
		CrimeLifeState.guards[int(pid)] = {"post": post, "shift": "night", "fatigue": 0.0, "asleep_until": -1}
	var wake: Dictionary = CrimeLifeRoll.odds(1, "shoplift", post, {"night": true, "cased": 0.0})
	for pid2 in picks:
		CrimeSecurityGuards.set_asleep(int(pid2), true)
	var doze: Dictionary = CrimeLifeRoll.odds(1, "shoplift", post, {"night": true, "cased": 0.0})
	K.expect(f, float(doze["detect"]) < float(wake["detect"]) * 0.85, "guards alone: asleep on a night shift they miss more (%.2f vs %.2f)" % [doze["detect"], wake["detect"]])
	K.teardown()

func _night_sleep_rate(f: Array) -> void:
	var w := C.town(14)
	CrimeSecurityGuards.staff_town()
	var tired_total: int = 0
	var fresh_total: int = 0
	for night in 200:
		for pid in CrimeSecurityGuards.guards_of("biz:bank"):
			CrimeLifeState.guards[pid]["asleep_until"] = -1
			CrimeLifeState.guards[pid]["fatigue"] = 0.3 if night % 2 == 0 else 0.0
		K.set_time(10 + night, 2, 0)
		CrimeSecurityGuards.on_hour()
		for pid2 in CrimeSecurityGuards.guards_of("biz:bank"):
			if CrimeSecurityGuards.is_asleep(int(pid2)):
				if night % 2 == 0:
					tired_total += 1
				else:
					fresh_total += 1
	K.expect(f, tired_total > fresh_total and tired_total > 5, "night guards doze off now and then, tired ones more often (%d vs %d)" % [tired_total, fresh_total])
	for pid3 in CrimeSecurityGuards.guards_of("biz:bank"):
		if str(CrimeLifeState.guards[pid3]["shift"]) == "day":
			K.expect(f, not CrimeSecurityGuards.is_asleep(int(pid3)), "day guards never doze")
			break
	K.teardown()

func _rounds(f: Array) -> void:
	var w := C.town(12)
	var culprit: int = int(C.adults()[0])
	var c: Dictionary = CaseStore.create("burglary", culprit, -1, "town:2", {"trace": 0.2})
	c["state"] = "open"
	c["disc_day"] = SysUtil.day()
	var before: float = float(c["progress"])
	for i in 80:
		CrimeSecurityGuards.on_round(1)
	var ci: bool = CrimeLifeState.counter("guard_assists") >= 1
	K.expect(f, ci, "walking the round now and then spots a prowler and helps a recent case (%d assists)" % CrimeLifeState.counter("guard_assists"))
	K.teardown()

func _watchman(f: Array) -> void:
	var w := C.town(30)
	CrimeLifePath.join(1)
	K.set_time(3, 12, 0)
	var shop: Dictionary = CrimeSecurity.business_profile("cafe")
	K.expect(f, int(shop["guards"]) == 0, "a cafe has no guard")
	CrimeSecurityGuards.staff_town()
	var watch: Array = CrimeSecurityGuards.guards_of(CrimeSecurityGuards.WATCH)
	K.expect(f, watch.size() == 1 and CrimePerson.career(int(watch[0])) == "night_watchman", "the town has one night watchman")
	K.expect(f, int(CrimeSecurity.business_profile("cafe")["guards"]) == 0, "by day they are off duty")
	K.set_time(3, 2, 0)
	K.expect(f, int(CrimeSecurity.business_profile("cafe")["guards"]) == 1 and bool(CrimeSecurity.business_profile("cafe")["watchman"]), "at night the watchman covers the closed shops")
	var awake: Dictionary = CrimeLifeRoll.odds(1, "shoplift", "biz:cafe", {"night": true, "cased": 0.0})
	CrimeSecurityGuards.set_asleep(int(watch[0]), true)
	var asleep: Dictionary = CrimeLifeRoll.odds(1, "shoplift", "biz:cafe", {"night": true, "cased": 0.0})
	K.expect(f, float(asleep["detect"]) < float(awake["detect"]), "a watchman asleep misses more (%.2f vs %.2f)" % [asleep["detect"], awake["detect"]])
	K.teardown()

func _record(f: Array) -> void:
	var w := C.town(8)
	var ada = w.get_folk(1)
	ada.add_skill_xp("fitness", 700.0)
	var q: Dictionary = Careers.qualify(ada, "security_guard", 2)
	K.expect(f, bool(q["ok"]), "a clean folk with some fitness can be a guard (%s)" % str(q["missing"]))
	JusticeRecords.add(1, "burglary", 1, "guilty")
	var q2: Dictionary = Careers.qualify(ada, "security_guard", 2)
	K.expect(f, not bool(q2["ok"]) and str(q2["missing"]).contains("clean record"), "but not a convicted burglar")
	K.expect(f, not CrimeSecurityGuards.barred(1, "baker"), "other jobs are not affected by this rule")
	K.teardown()
