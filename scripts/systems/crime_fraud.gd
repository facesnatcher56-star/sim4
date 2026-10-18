class_name CrimeFraud
extends RefCounted
## Task 09c section 4: fraud and white-collar crime.
##   EMBEZZLEMENT  an office / finance worker under money pressure skims from the employer (low daily chance, more with a dishonest streak).
##                 An AUDIT a week or three later finds the money missing: the culprit is fired at once and the case opens with a paper trail.
##   SCAMS         a con artist sells something fake or runs a "lottery": the victim finds out later (hidden theft, discovered like any theft).
##   INSURANCE ARSON  burning your own house for the payout. Investigators can tell arson from an accident (detection grows with police strength);
##                 an undetected one is just "a house fire". Uses Fire.ignite (source "arson") on a real lot, a record on far lots.

static func cfg() -> Dictionary:
	return JusticeState.sect("fraud")

static func office_career(c: String) -> bool:
	return (cfg().get("office_careers", []) as Array).has(c)

# ------------------------------------------------------------------ embezzlement
static func embezzle(pid: int, amount: int = -1) -> Dictionary:
	var k: Dictionary = cfg()
	if amount < 0:
		amount = JusticeState.rng.randi_range(int(k.get("amount", [80, 400])[0]), int(k.get("amount", [80, 400])[1]))
	CrimePerson.add_coins(pid, amount, "skimmed")
	var days: int = JusticeState.rng.randi_range(int(k.get("audit_days", [7, 21])[0]), int(k.get("audit_days", [7, 21])[1]))
	var c: Dictionary = CaseStore.create("embezzlement", pid, -1, "work", {"trace": 0.45, "stolen_coins": amount, "loot_value": amount})
	c["audit_day"] = SysUtil.day() + days
	c["employer_career"] = CrimePerson.career(pid)
	CrimePlace.place_at_scene(pid, "work")
	return c

static func on_day() -> void:
	if not JusticeState.enabled:
		return
	var k: Dictionary = cfg()
	for pid in CrimePerson.everyone():
		var p: int = int(pid)
		if CrimePerson.is_player(p) or CrimePerson.in_custody(p):
			continue
		if office_career(CrimePerson.career(p)):
			var r: float = CrimePressure.risk(p)
			var chance: float = float(k.get("embezzle_daily", 0.004)) * (0.2 + 4.0 * r) * (3.0 if CrimePerson.has_trait(p, "dishonest") else 1.0) * Incidents.surprise_mult()
			if r >= float(k.get("embezzle_min_risk", 0.1)) and JusticeState.chance(chance):
				embezzle(p)
		if CrimePerson.has_trait(p, "dishonest") and JusticeState.chance(float(k.get("scam_daily", 0.002)) * Incidents.surprise_mult() * (0.5 + CrimePressure.risk(p) * 2.0)):
			scam(p)
		var r2: float = CrimePressure.risk(p)
		if r2 >= float(k.get("arson_min_risk", 0.5)) and JusticeState.chance(r2 * r2 * r2 * float(k.get("arson_daily", 0.003)) * (2.0 if CrimePerson.has_trait(p, "dishonest") else 1.0) * Incidents.surprise_mult()):
			insurance_arson(p)
	audit()

## The audit: embezzlement cases whose audit day has come are found (the culprit is fired right then).
static func audit() -> void:
	for c in CaseStore.in_state(["hidden"]):
		if str(c["kind"]) == "embezzlement" and SysUtil.day() >= int(c.get("audit_day", 99999)):
			var pid: int = int(c["culprit"])
			var text: String = "An audit found money missing at the office where %s works." % CrimePerson.name_of(pid)
			c["progress"] = 0.7
			c["tips"] = 0.2
			CaseDiscovery.report(c, -1, "audit")
			CaseStore.note(c, text, "embezzlement", 3)
			_fire(pid)

static func _fire(pid: int) -> void:
	var f = CrimePerson.folk(pid)
	if f != null and Careers.has_job(pid):
		Careers.fire(f)
	elif Story.townies.has(pid):
		Story.townies[pid]["career"] = ""
		Story.townies[pid]["level"] = 1

# ------------------------------------------------------------------ scams
static func scam(pid: int) -> Dictionary:
	var k: Dictionary = cfg()
	var pool: Array = []
	var w: Array = []
	for v in CrimePerson.everyone():
		var o: int = int(v)
		if o == pid or not CrimePerson.is_adult(o) or CrimePerson.coins(o) < 80:
			continue
		pool.append(o)
		w.append(1.0 + float(CrimePerson.coins(o)) / 400.0 + (1.0 if CrimePerson.stage(o) == "elder" else 0.0) - (0.8 if CrimePerson.has_trait(o, "pessimist") else 0.0))
	var i: int = JusticeState.pick_index(w)
	if i < 0:
		return {}
	var victim: int = int(pool[i])
	var amt: int = mini(CrimePerson.coins(victim), JusticeState.rng.randi_range(int(k.get("scam_amount", [40, 150])[0]), int(k.get("scam_amount", [40, 150])[1])))
	CrimePerson.pay(victim, amt, "a scam")
	CrimePerson.add_coins(pid, amt, "scam")
	var c: Dictionary = CaseStore.create("fraud", pid, victim, CrimePerson.home_key(victim), {"trace": 0.3, "stolen_coins": amt, "loot_value": amt})
	c["scam"] = str(JusticeState.pick(k.get("scam_kinds", ["a fake 'lottery win'"])))
	CrimePlace.place_at_scene(pid, CrimePerson.home_key(victim))
	return c

# ------------------------------------------------------------------ insurance arson
## `pid` burns their own house for the payout. Returns the case ({} when it passed as an accident).
static func insurance_arson(pid: int, lot_key: String = "") -> Dictionary:
	var k: Dictionary = cfg()
	if lot_key == "":
		lot_key = CrimePerson.home_key(pid)
	var payout: int = JusticeState.rng.randi_range(int(k.get("arson_payout", [300, 900])[0]), int(k.get("arson_payout", [300, 900])[1]))
	if lot_key.begins_with("home:") and Incidents.insurance_fn.is_valid():
		payout = maxi(payout, Incidents.insurance_cover(1500, int(lot_key.get_slice(":", 1))))
	if lot_key.begins_with("home:") and ResourceLoader.exists("res://scripts/systems/fire_core.gd"):
		var objs: Array = Economy.objects_of(int(lot_key.get_slice(":", 1)))
		if not objs.is_empty():
			Fire.ignite(objs[JusticeState.rng.randi_range(0, objs.size() - 1)], "arson", {"culprit": pid})
	CrimePerson.add_coins(pid, payout, "insurance payout")
	JusticeState.count("insurance_arson")
	var detected: bool = JusticeState.chance(float(k.get("arson_detect", 0.6)) * Police.strength())
	var nm: String = CrimePerson.name_of(pid)
	if not detected:
		var t: String = "The house of %s caught fire. No one was hurt." % nm
		ChronicleHook.note("fire", t, [pid], lot_key, 3, true)
		return {}
	var c: Dictionary = CaseStore.create("arson", pid, -1, lot_key, {"trace": 0.55, "stolen_coins": 0, "loot_value": payout})
	c["insurance"] = true
	c["found"] = true
	CaseDiscovery.report(c, -1, "seen")
	CaseStore.note(c, "Fire investigators found the fire at %s was set on purpose, for the insurance money." % CaseStore.house_label(lot_key), "arson", 4)
	CaseStore.toast(c, "Investigators say the fire at %s was set on purpose." % CaseStore.house_label(lot_key), "warn")
	return c

## Task 03 reports a fire with source "arson": investigators open an arson case if nobody did yet (culprit: the likeliest desperate townie).
static func on_fire_started(p: Dictionary) -> void:
	if str(p.get("source", "")) != "arson" or not JusticeState.enabled:
		return
	for c in CaseStore.in_state(["open", "hidden", "arrested", "charged"]):
		if str(c["kind"]) == "arson" and SysUtil.day() - int(c["day"]) <= 1:
			return
	var culprit: int = CrimeBurglary.pick_burglar(str(p.get("lot", "")))
	if culprit < 0:
		return
	var c: Dictionary = CaseStore.create("arson", culprit, -1, str(p.get("lot", "street")), {"trace": 0.5})
	c["found"] = true
	CaseDiscovery.report(c, -1, "seen")
