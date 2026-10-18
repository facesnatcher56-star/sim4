class_name CrimePressure
extends RefCounted
## Task 09c section 1: WHY ordinary people turn to crime. Each person has a PRESSURE score (0..1) from being broke, in debt, behind on bills,
## out of work, repossessed, with children to feed, or having a record and no job. A CONSCIENCE score (0..1) from traits, reputation and close
## relationships. RISK = pressure x (1 - conscience) (x2, capped at 1). High risk raises theft, shoplifting, burglary, robbery and fraud:
## the daily statistical roll below (for every townie, near or far) and the burglar choice (CrimeBurglary.pick_burglar). Help lowers it:
## a new job (counted automatically), a friend's loan, charity, family support (CrimePressure.help). Desperate townies are the usual suspects.

static func cfg() -> Dictionary:
	return JusticeState.sect("pressure")

static func pressure(pid: int) -> float:
	var k: Dictionary = cfg()
	var coins: int = CrimePerson.coins(pid)
	var p: float = 0.0
	if coins < 50:
		p += float(k.get("broke", 0.3))
	elif coins < 150:
		p += float(k.get("poor", 0.2))
	elif coins < 300:
		p += float(k.get("modest", 0.08))
	var hid: int = CrimePerson.hid(pid)
	if hid > 0:
		if Economy.owed(hid) > 0:
			p += float(k.get("debt", 0.15)) + (float(k.get("big_debt", 0.15)) if Economy.owed(hid) > 200 else 0.0)
		p += minf(float(Economy.missed.get(hid, 0)) * float(k.get("late_bill", 0.1)), 0.2)
		for r in Economy.repossessed:
			if int(r.get("hid", -1)) == hid and SysUtil.day() - int(r.get("day", -99)) < 28:
				p += float(k.get("repossessed", 0.2))
				break
	elif coins == 0:
		p += float(k.get("debt", 0.15))
	if CrimePerson.is_adult(pid) and not CrimePerson.has_job(pid) and CrimePerson.stage(pid) != "elder":
		p += float(k.get("jobless", 0.15))
		if CrimePerson.has_record(pid):
			p += float(k.get("record_no_job", 0.15))
	var kids: int = 0
	for c in Aging.children_of(pid):
		if CrimePerson.stage(int(c)) in ["baby", "toddler", "child"]:
			kids += 1
	p += minf(float(kids) * float(k.get("per_child", 0.05)), 0.15)
	var rel: Dictionary = JusticeState.relief.get(pid, {})
	if not rel.is_empty() and int(rel.get("until", 0)) >= SysUtil.day():
		p -= float(rel.get("amount", 0.0))
	return clampf(p, 0.0, 1.0)

static func conscience(pid: int) -> float:
	var k: Dictionary = cfg().get("conscience", {})
	var c: float = float(k.get("base", 0.5))
	for t in CrimePerson.traits(pid):
		c += float(k.get("traits", {}).get(str(t), 0.0))
	c += clampf(CrimePerson.reputation(pid) / 200.0, -0.25, 0.25)
	c += minf(float(CrimePerson.close_alive(pid).size()) * 0.05, 0.15)
	return clampf(c, 0.0, 1.0)

static func risk(pid: int) -> float:
	return clampf(pressure(pid) * (1.0 - conscience(pid)) * 2.0, 0.0, 1.0)

## Help: a loan from a friend, charity or family support lowers the pressure for `days` days.
static func help(pid: int, kind: String, coins: int = 0, from: int = -1) -> void:
	var k: Dictionary = cfg().get("help", {})
	var amt: float = float(k.get(kind, 0.2))
	if coins > 0:
		amt = maxf(amt, minf(float(coins) / 400.0, 0.5))
		if from >= 0:
			CrimePerson.pay(from, coins, "loan")
		CrimePerson.add_coins(pid, coins, "help")
	JusticeState.relief[pid] = {"amount": amt, "until": SysUtil.day() + int(k.get("days", 14))}

# ------------------------------------------------------------------ the daily roll
static func on_day() -> void:
	if not JusticeState.enabled:
		return
	var k: Dictionary = cfg()
	for pid in CrimePerson.everyone():
		var p: int = int(pid)
		if not CrimePerson.is_adult(p) or CrimePerson.stage(p) == "elder" or CrimePerson.in_custody(p) or Hospital.is_in(p):
			continue
		if CrimePerson.is_player(p):
			continue                       # a player folk makes their own choices
		var r: float = risk(p)
		var klepto: bool = CrimePerson.has_trait(p, "kleptomaniac")
		if klepto and JusticeState.chance(float(k.get("klepto_daily", 0.02)) * Incidents.surprise_mult()):
			CrimePetty.commit("shoplifting", p, "street", {"petty": true})
		if r < float(k.get("min_risk", 0.15)):
			continue
		var chance: float = r * r * float(k.get("daily", 0.02)) * Incidents.surprise_mult() * CrimeRate.crime_mult()
		if not JusticeState.chance(chance):
			continue
		_desperate_act(p, r)

static func _desperate_act(p: int, r: float) -> void:
	var kinds: Array = ["shoplifting", "theft", "burglary", "robbery", "fraud"]
	var w: Array = [0.4, 0.15, 0.2, 0.1 * r, 0.1 if CrimePerson.has_trait(p, "dishonest") else 0.03]
	var kind: String = str(kinds[JusticeState.pick_index(w)])
	JusticeState.count("pressure_" + kind)
	match kind:
		"shoplifting":
			CrimePetty.commit("shoplifting", p, "street", {})
		"theft", "burglary":
			var lots: Array = []
			for tid in CrimePerson.townies_only():
				var key: String = CrimePerson.home_key(int(tid))
				if int(tid) != p and key != CrimePerson.home_key(p) and not lots.has(key):
					lots.append(key)
			if CrimePerson.hid(p) <= 0 and not Economy.household_ids().is_empty() and JusticeState.chance(0.25):
				lots.append("home:%d" % int(Economy.household_ids()[0]))
			if not lots.is_empty():
				var lot: String = str(lots[JusticeState.rng.randi_range(0, lots.size() - 1)])
				var full: bool = lot.begins_with("home:")
				CrimeBurglary.attempt(lot, not full, false, p)
		"robbery":
			var victims: Array = CrimePerson.townies_only().filter(func(x): return x != p and CrimePerson.coins(int(x)) > 60)
			if not victims.is_empty():
				CrimeStreet._resolve(int(victims[JusticeState.rng.randi_range(0, victims.size() - 1)]), p, "hand", true)
		"fraud":
			CrimeFraud.scam(p)
