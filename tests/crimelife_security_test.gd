extends RefCounted
## Task 21 part 2: security systems. Profiles from objects and business types, what they do to a break-in (harder, a burglar gives up, more
## detection, camera footage as evidence), alarm response and false alarms, insurance discounts, safes, and upgrades for business owners.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_profiles(f)
	_effects(f)
	_burglary_prevention(f)
	_cameras_convict(f)
	_footage_dodge_erase(f)
	_footage_review(f)
	_alarm(f)
	_false_alarms(f)
	_insurance(f)
	_safe(f)
	_business(f)
	_upgrades(f)
	return f

func _equip(w: StubWorld, ids: Array) -> void:
	var x: int = 10
	for id in ids:
		w.add_object(str(id), Vector2i(x, 14))
		x += 1
	Economy.refresh_objects()

func _profiles(f: Array) -> void:
	var w := C.town(8)
	K.expect(f, CrimeSecurity.score(CrimeSecurity.home_profile(1)) == 0, "a bare home has no security")
	_equip(w, ["door_lock_2", "window_lock", "window_lock", "burglar_alarm", "security_camera", "security_camera", "motion_sensor", "vault_safe", "security_light", "guard_dog_kennel"])
	var p: Dictionary = CrimeSecurity.home_profile(1)
	K.expect(f, int(p["lock"]) == 2 and int(p["windows"]) == 2 and bool(p["alarm"]) and int(p["cameras"]) == 2 and int(p["motion"]) == 1 and int(p["safe"]) == 2 and int(p["lights"]) == 1 and bool(p["dog"]), "objects become a profile: %s" % str(p))
	K.expect(f, CrimeSecurity.score(p) > 40 and CrimeSecurity.describe(p).contains("camera"), "and a plain description: %s" % CrimeSecurity.describe(p))
	var bank: Dictionary = CrimeSecurity.business_profile("bank")
	var cafe: Dictionary = CrimeSecurity.business_profile("cafe")
	K.expect(f, int(bank["guards"]) == 2 and int(bank["cameras"]) == 6 and bool(bank["alarm"]) and int(bank["safe"]) == 2, "a bank has guards, cameras, an alarm and a vault")
	K.expect(f, CrimeSecurity.score(bank) > CrimeSecurity.score(CrimeSecurity.business_profile("market")) and CrimeSecurity.score(CrimeSecurity.business_profile("market")) > CrimeSecurity.score(cafe), "security by value: bank > market > cafe")
	K.expect(f, bool(CrimeSecurity.business_profile("market")["detective"]) and not bool(CrimeSecurity.business_profile("jeweller")["detective"]), "a market has a store detective")
	var poor: Dictionary = CrimeSecurity.townie_profile(3, 100)
	var rich: Dictionary = CrimeSecurity.townie_profile(3, 5000)
	K.expect(f, CrimeSecurity.score(rich) >= CrimeSecurity.score(poor), "richer townies have at least as much cover")
	K.teardown()

func _effects(f: Array) -> void:
	var w := C.town(8)
	var none: Dictionary = CrimeSecurity.effects(CrimeSecurity.empty())
	var p: Dictionary = CrimeSecurity.empty()
	for id in ["door_lock_3", "burglar_alarm", "security_camera", "security_light", "guard_dog_kennel"]:
		CrimeSecurity.add_object(p, id)
	var full: Dictionary = CrimeSecurity.effects(p, true)
	K.expect(f, float(full["difficulty"]) > float(none["difficulty"]) and float(full["abort"]) > 0.0 and float(full["detect"]) > 1.4 and float(full["footage"]) > 0.0, "security makes entry harder, burglars give up, detection and footage rise")
	var day: Dictionary = CrimeSecurity.effects(p, false)
	K.expect(f, float(day["detect"]) < float(full["detect"]), "lights only help in the dark")
	var jam: Dictionary = CrimeSecurity.effects(p, true, 0.5)
	K.expect(f, float(jam["detect"]) < float(full["detect"]), "an alarm bypass kit weakens the alarm side")
	var mon: Dictionary = p.duplicate()
	mon["monitored"] = true
	K.expect(f, int(CrimeSecurity.effects(mon)["response_min"]) < int(full["response_min"]), "a monitored alarm brings help faster")
	K.teardown()

func _burglary_prevention(f: Array) -> void:
	var w := C.town(8)
	K.set_time(3, 2, 0)
	var quiet_bare: int = 0
	for i in 300:
		if CrimeBurglary._prevented(1, "home:1", false) != "":
			quiet_bare += 1
	_equip(w, ["door_lock_3", "window_lock", "window_lock", "window_lock", "security_light", "guard_dog_kennel", "security_camera"])
	var quiet_sec: int = 0
	for i in 300:
		if CrimeBurglary._prevented(1, "home:1", false) != "":
			quiet_sec += 1
	K.expect(f, quiet_sec > quiet_bare + 40, "locks, a dog and lights make burglars give up far more often (%d vs %d of 300)" % [quiet_sec, quiet_bare])
	K.teardown()

## Same crime, same investigation work: with camera footage the court is far more likely to convict.
func _cameras_convict(f: Array) -> void:
	var w := C.town(12)
	var culprit: int = int(C.adults()[0])
	var rate: Callable = func() -> Dictionary:
		var guilty: int = 0
		var with_clip: int = 0
		var psum: float = 0.0
		for i in 160:
			var res: Dictionary = CrimeBurglary.attempt("home:1", true, true, culprit)
			var c: Dictionary = CaseStore.get_case(int(res.get("case", -1)))
			if c.is_empty():
				continue
			c["progress"] = 0.5
			if float(c.get("footage", 0.0)) > 0.0:
				with_clip += 1
			var bd: Dictionary = JusticeTrial.breakdown(c, culprit, false)
			psum += float(bd["p_guilty"])
			if JusticeState.chance(float(bd["p_guilty"])):
				guilty += 1
		return {"guilty": guilty, "clips": with_clip, "p": psum / 160.0}
	var bare: Dictionary = rate.call()
	_equip(w, ["security_camera", "security_camera", "security_camera"])
	var cams: Dictionary = rate.call()
	K.expect(f, int(bare["clips"]) == 0 and int(cams["clips"]) > 30, "only watched homes produce footage (%d vs %d of 160)" % [bare["clips"], cams["clips"]])
	K.expect(f, float(cams["p"]) > float(bare["p"]) + 0.05 and int(cams["guilty"]) > int(bare["guilty"]), "cameras raise the conviction rate (%.2f vs %.2f chance, %d vs %d convictions of 160)" % [cams["p"], bare["p"], cams["guilty"], bare["guilty"]])
	K.teardown()

func _footage_dodge_erase(f: Array) -> void:
	var w := C.town(12)
	_equip(w, ["security_camera", "security_camera", "security_camera"])
	var amateur: int = int(C.adults()[0])
	var pro: int = int(C.adults()[1])
	CrimeLifePath.join(pro)
	CrimeLifePath.member(pro)["skills"] = {"stealth": 9, "handiness": 9, "logic": 8}
	var count: Callable = func(pid: int, masked: bool) -> Dictionary:
		var clips: int = 0
		var gaps: int = 0
		for i in 200:
			var c: Dictionary = CaseStore.create("burglary", pid, -1, "home:1", {"trace": 0.2})
			var r: Dictionary = CrimeSecurityFootage.capture(c, "home:1", pid, masked, false)
			if bool(r["caught"]):
				clips += 1
			if bool(r["gap"]):
				gaps += 1
		return {"clips": clips, "gaps": gaps}
	var a: Dictionary = count.call(amateur, false)
	var p: Dictionary = count.call(pro, false)
	var m: Dictionary = count.call(amateur, true)
	K.expect(f, int(p["clips"]) < int(a["clips"]) - 30, "a skilled thief dodges the camera far more often (%d vs %d clips of 200)" % [p["clips"], a["clips"]])
	K.expect(f, int(p["gaps"]) > int(a["gaps"]) and int(p["gaps"]) > 5, "and can erase a recording, which leaves a gap (%d vs %d)" % [p["gaps"], a["gaps"]])
	K.expect(f, int(m["clips"]) < int(a["clips"]) - 30, "a mask also hides the face")
	K.teardown()

func _footage_review(f: Array) -> void:
	var w := C.town(12)
	_equip(w, ["security_camera", "security_camera", "security_camera"])
	var culprit: int = int(C.adults()[0])
	var found: Dictionary = {}
	for i in 60:
		var c: Dictionary = CaseStore.create("burglary", culprit, -1, "home:1", {"trace": 0.2})
		c["vhid"] = 1
		CrimeSecurityFootage.capture(c, "home:1", culprit)
		if float(c.get("footage", 0.0)) > 0.0:
			found = c
			break
	K.expect(f, not found.is_empty() and str(found["state"]) == "hidden", "a camera caught a hidden break-in")
	K.expect(f, CrimeSecurityFootage.lines("home:1").size() >= 1, "the footage log has plain lines: %s" % str(CrimeSecurityFootage.lines("home:1").slice(0, 1)))
	CrimeSecurityFootage.on_review(1)
	K.expect(f, str(found["state"]) == "open", "reviewing the recordings reports the break-in")
	K.expect(f, float(CaseEvidence.hard(culprit, found)) > 0.3, "and the clip is hard evidence against the real culprit only (%.2f)" % CaseEvidence.hard(culprit, found))
	K.expect(f, CaseEvidence.hard(int(C.adults()[1]), found) == 0.0, "nobody else is implicated by it")
	K.teardown()

func _alarm(f: Array) -> void:
	var w := C.town(8)
	_equip(w, ["burglar_alarm"])
	K.set_time(3, 2, 0)
	var slow: int = CrimeSecurityAlarm.response_delay("home:1")
	CrimeLifeState.home_sec[1] = {"monitored": true}
	var fast: int = CrimeSecurityAlarm.response_delay("home:1")
	K.expect(f, fast < slow, "a monitored alarm gets the police there sooner (%d vs %d minutes)" % [fast, slow])
	var res: Dictionary = CrimeBurglary.attempt("home:1", false, true)
	var c: Dictionary = CaseStore.get_case(int(res["case"]))
	K.expect(f, bool(c.get("alarm_rang", false)) and bool(c.get("called", false)), "a burglary scene rings the alarm and calls the police")
	var due: int = 99999
	for p in JusticeState.pending:
		if str(p["kind"]) == "police_arrive":
			due = int(p["due_min"]) - SysUtil.now()
	K.expect(f, due <= fast + 1, "the arrival is queued at the monitored delay (%d)" % due)
	K.teardown()

func _false_alarms(f: Array) -> void:
	var w := C.town(8)
	_equip(w, ["burglar_alarm", "motion_sensor"])
	CrimeLifeState.home_sec[1] = {"monitored": true}
	var coins0: int = WorldIface.get_coins(1)
	for d in 400:
		K.set_time(5 + d, 12)
		CrimeSecurityAlarm.on_day()
	K.expect(f, CrimeLifeState.counter("false_alarms") >= 3, "alarms go off by mistake now and then (%d in 400 days)" % CrimeLifeState.counter("false_alarms"))
	K.expect(f, WorldIface.get_coins(1) < coins0, "a monitored alarm charges for the callout")
	CrimeLifeState.alarms[1] = {"strikes": 2, "ignore_until": -1, "last": -1}
	K.set_time(500, 12)
	CrimeSecurityAlarm.false_alarm(1, true)
	K.expect(f, CrimeSecurityAlarm.ignored(1), "three strikes and the police take that house's alarms less seriously")
	K.expect(f, CrimeSecurityAlarm.response_delay("home:1") >= 3 * 5, "so they come slower")
	K.teardown()

func _insurance(f: Array) -> void:
	var w := C.town(8)
	var lvl: String = str(DisasterInsurance.levels().keys()[0])
	DisasterInsurance.set_level(1, lvl)
	var plain: int = DisasterInsurance.premium(1)
	_equip(w, ["burglar_alarm", "security_camera", "door_lock_2"])
	CrimeLifeState.home_sec[1] = {"monitored": true}
	var safe: int = DisasterInsurance.premium(1)
	K.expect(f, plain > 0 and safe < plain, "alarms, cameras and good locks earn a discount (%d -> %d a week)" % [plain, safe])
	K.expect(f, CrimeSecurityAlarm.bill_extra(1) == 18, "alarm monitoring is a weekly charge")
	CrimeLifeState.home_sec[1] = {"monitored": true, "guard": 1}
	K.expect(f, CrimeSecurityAlarm.bill_extra(1) > 18, "a hired guard costs more")
	K.teardown()

func _safe(f: Array) -> void:
	var w := C.town(8)
	K.set_time(3, 2, 0)
	WorldIface.coins[1] = 2000
	var take: Callable = func() -> int:
		var total: int = 0
		for i in 12:
			WorldIface.coins[1] = 2000
			var res: Dictionary = CrimeBurglary.attempt("home:1", false, true)
			var c: Dictionary = CaseStore.get_case(int(res["case"]))
			c["target_obj"] = -1
			CrimeBurglary._take(c)
			total += int(c["stolen_coins"])
			CrimeBurglary.end_scene(c, false)
			JusticeState.pending.clear()
		return total
	var bare: int = take.call()
	_equip(w, ["vault_safe"])
	var safe: int = take.call()
	K.expect(f, bare > 0 and safe < bare / 4, "cash in a safe is out of the burglar's reach (%d vs %d)" % [safe, bare])
	K.teardown()

func _business(f: Array) -> void:
	var w := C.town(8)
	var b: Dictionary = BusinessState.make("cafe", "cafe", "own", "player", 1, "Ada's Cafe")
	var p0: Dictionary = CrimeSecurity.profile_for("biz:%d" % int(b["id"]))
	K.expect(f, int(p0["cameras"]) == 0 and not bool(p0["alarm"]), "a new cafe has little cover")
	WorldIface.coins[1] = 3000
	var r: Dictionary = CrimeSecurityUpgrade.buy_business(1, int(b["id"]), "camera")
	K.expect(f, bool(r["ok"]) and WorldIface.get_coins(1) == 2840, "the owner buys a camera: %s" % str(r))
	CrimeSecurityUpgrade.buy_business(1, int(b["id"]), "alarm")
	CrimeSecurityUpgrade.buy_business(1, int(b["id"]), "guard")
	var p1: Dictionary = CrimeSecurity.profile_for("biz:%d" % int(b["id"]))
	K.expect(f, int(p1["cameras"]) == 1 and bool(p1["alarm"]) and int(p1["guards"]) == 1, "upgrades show in the profile")
	var coins: int = WorldIface.get_coins(1)
	K.set_time(7, 12)
	CrimeSecurityUpgrade.on_day()
	K.expect(f, WorldIface.get_coins(1) < coins, "a hired guard draws a weekly wage")
	var other: Dictionary = CrimeSecurityUpgrade.buy_business(2, int(b["id"]), "camera")
	K.expect(f, not bool(other["ok"]), "only the owner can buy cover")
	K.teardown()

func _upgrades(f: Array) -> void:
	var w := C.town(8)
	var no_alarm: Dictionary = CrimeSecurityUpgrade.set_home_service(1, "monitored", 1)
	K.expect(f, not bool(no_alarm["ok"]), "monitoring needs an alarm first")
	_equip(w, ["burglar_alarm"])
	WorldIface.coins[1] = 1000
	var ok: Dictionary = CrimeSecurityUpgrade.set_home_service(1, "monitored", 1)
	K.expect(f, bool(ok["ok"]) and bool(CrimeSecurity.home_profile(1)["monitored"]), "monitoring can be bought once there is an alarm")
	var g: Dictionary = Commands.run({"player_id": 1, "folk_id": 1, "action": "crimelife", "args": {"action": "home_service", "key": "guard", "value": 1}})
	K.expect(f, bool(g["ok"]) and int(CrimeSecurity.home_profile(1)["guards"]) == 1, "a guard is hired through the command layer")
	K.teardown()
