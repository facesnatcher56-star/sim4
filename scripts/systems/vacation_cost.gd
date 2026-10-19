class_name VacationCost
extends RefCounted
## What a holiday costs and whether a party may go (task 22). Pure functions of the data (data/vacation.json, data/cruise_ship.json) and the
## household: nothing is charged here (Vacation.book charges). Cost = travel + lodging + spending money (the unspent part comes back).
##   VacationCost.quote(hid, dest, opts) -> {ok, reason, total, travel, lodging, spending, sitter, package, people, days, lines: [{label, amount}], leave: [...],
##                                           who: [folk ids], guests: [townie ids], cabins: int, depart_min, arrive_min, end_min, return_min}
## opts: length_days, who (default: the whole household), guests, cabin_class (cruise), package, sitter, depart_min, travel_min

static func dest_def(dest: String) -> Dictionary:
	return ((SysUtil.table("vacation").get("destinations", {}) as Dictionary).get(dest, {}) as Dictionary)

static func cruise_cfg() -> Dictionary:
	return SysUtil.table("cruise_ship")

static func is_known(dest: String) -> bool:
	return dest == "cruise" or not dest_def(dest).is_empty()

static func label_of(dest: String) -> String:
	if dest == "cruise":
		return str(cruise_cfg().get("ship", {}).get("name", "Cruise"))
	return str(dest_def(dest).get("label", dest.capitalize()))

static func day_range(dest: String) -> Array:
	if dest == "cruise":
		return cruise_cfg().get("ship", {}).get("lengths", [3, 14])
	return dest_def(dest).get("days", [2, 14])

## Why this person cannot go right now ("" = free to go).
static func busy_reason(f) -> String:
	if f == null:
		return "unknown"
	var fid: int = int(f.id)
	if Vacation.on_trip(fid):
		return "%s is already away" % f.name
	if Hospital.is_in(fid):
		return "%s is in hospital" % f.name
	if CrimePerson.in_custody(fid):
		return "%s is in custody" % f.name
	if Away.is_away(fid) or Away.pending.has(fid) or Commute.active(fid):
		return "%s is out at work, school or an errand" % f.name
	if Health.is_collapsed(f):
		return "%s is too unwell" % f.name
	return ""

static func household_folk(hid: int) -> Array:
	var out: Array = []
	for f in SysUtil.residents():
		if int(f.household_id) == hid:
			out.append(f)
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "total": 0, "lines": []}

static func quote(hid: int, dest: String, opts: Dictionary = {}) -> Dictionary:
	if not is_known(dest):
		return _fail("Nobody has heard of that place.")
	var cap: int = int(Vacation.cfg().get("travel_party_cap", 6))
	var members: Array = household_folk(hid)
	if members.is_empty():
		return _fail("There is nobody to send.")
	var who: Array = []
	var want: Array = opts.get("who", [])
	for f in members:
		if want.is_empty() or SysUtil.has_int(want, int(f.id)):
			who.append(f)
	if who.is_empty():
		return _fail("Nobody chosen to go.")
	for f2 in who:
		var br: String = busy_reason(f2)
		if br != "" and not bool(opts.get("ignore_busy", false)):
			return _fail(br + ".")
	var stay: Array = []
	for f3 in members:
		if not who.has(f3):
			stay.append(f3)
	var young: Callable = func(x): return str(x.age_stage) in ["baby", "toddler", "child"]
	var little_going: int = who.filter(young).size()
	if little_going > 0 and who.size() - little_going <= 0:
		return _fail("Children cannot travel without a grown-up.")
	var grown_home: int = stay.filter(func(x): return str(x.age_stage) in ["adult", "elder"]).size()
	for s in stay:
		if young.call(s) and grown_home == 0:
			return _fail("%s would be home alone. Take them along or leave a grown-up behind." % s.name)
	var guests: Array = []
	for g in opts.get("guests", []):
		if Story.townies.has(int(g)) and bool(Story.townies[int(g)].get("alive", false)) and not CrimePerson.in_custody(int(g)) \
				and Story.stage_of(Story.townies[int(g)]) in ["teen", "adult", "elder"]:
			guests.append(int(g))
	guests = guests.slice(0, int(Vacation.cfg().get("max_guests", 3)))
	var people: int = who.size() + guests.size()
	if people > cap:
		return _fail("A party of %d is too big (most %d)." % [people, cap])
	var rng_days: Array = day_range(dest)
	var days: int = clampi(int(opts.get("length_days", rng_days[0])), int(rng_days[0]), int(rng_days[1]))
	var q: Dictionary = _prices(dest, people, days, opts)
	if not bool(q.get("ok", true)):
		return q
	if dest == "cruise":
		var need: String = str((cruise_cfg().get("packages", {}) as Dictionary).get(str(q.get("package_id", "")), {}).get("needs", ""))
		if need != "" and not _package_ok(who, need):
			return _fail("The %s package is for %s." % [str(q["package_id"]), "a married couple" if need == "married" else "a couple"])
	var lines: Array = q["lines"]
	var sitter: int = 0
	if bool(opts.get("sitter", false)):
		sitter = int(Vacation.cfg().get("home", {}).get("sitter_per_day", 12)) * days
		lines.append({"label": "House-sitter", "amount": sitter})
	var total: int = int(q["travel"]) + int(q["lodging"]) + int(q["spending"]) + sitter + int(q.get("package", 0))
	var now: int = SysUtil.now()
	var depart: int = int(opts.get("depart_min", now + int(Vacation.cfg().get("depart_delay_min", 30))))
	var tmin: int = int(opts.get("travel_min", q.get("travel_min", 60)))
	var arrive: int = depart + tmin
	var end_min: int = arrive + days * 1440
	var ret: int = end_min + tmin
	var res: Dictionary = {"ok": true, "reason": "", "total": total, "travel": q["travel"], "lodging": q["lodging"], "spending": q["spending"], "sitter": sitter,
		"package": int(q.get("package", 0)), "people": people, "days": days, "lines": lines, "who": who.map(func(x): return int(x.id)), "guests": guests,
		"cabins": int(q.get("cabins", 0)), "depart_min": depart, "arrive_min": arrive, "end_min": end_min, "return_min": ret, "travel_min": tmin,
		"cabin_class": str(q.get("cabin_class", "")), "package_id": str(q.get("package_id", ""))}
	if dest == "cruise":
		var sc: Dictionary = cruise_cfg().get("ship", {})
		var sail: int = _next_hour(arrive + int(sc.get("board_walk_min", 25)), float(sc.get("sail_hour", 17.0)))
		res["sail_min"] = sail
		res["end_min"] = _day_start(sail) + days * 1440 + int(float(sc.get("home_arrive_hour", 7.0)) * 60.0)
		res["return_min"] = _day_start(sail) + days * 1440 + int(float(sc.get("disembark_hour", 9.0)) * 60.0) + int(sc.get("transit_min", 30))
	res["leave"] = VacationWork.plan(res["who"], depart, int(res["return_min"]))
	var reserve: int = Economy.owed(hid) + int(round(float(Economy.compute_bill(hid)) * ceil(float(days + 3) / 7.0) * float(Vacation.cfg().get("reserve_for_bills", 1.0))))
	if Economy.balance(hid) - total < reserve and not bool(opts.get("force_afford", false)):
		res["ok"] = false
		res["reason"] = "That costs %d coins, and the bills still to come need %d. The household has %d." % [total, reserve, Economy.balance(hid)]
	return res

## Honeymoon = two of the party are married to each other, anniversary = any couple.
static func _package_ok(who: Array, need: String) -> bool:
	for a in who:
		for b in who:
			if int(a.id) < int(b.id):
				var bit: String = RelationshipBits.bit_for(int(a.id), int(b.id))
				if need == "married" and bit == "spouse":
					return true
				if need == "couple" and bit in ["spouse", "partner", "sweetheart"]:
					return true
	return false

static func _day_start(minute: int) -> int:
	return (minute / 1440) * 1440

## The next absolute minute with clock hour `hour` at or after `from_min`.
static func _next_hour(from_min: int, hour: float) -> int:
	var m: int = _day_start(from_min) + int(hour * 60.0)
	while m < from_min:
		m += 1440
	return m

static func _prices(dest: String, people: int, days: int, opts: Dictionary) -> Dictionary:
	var lines: Array = []
	if dest == "cruise":
		var cc: Dictionary = cruise_cfg()
		var classes: Dictionary = cc.get("classes", {})
		var klass: String = str(opts.get("cabin_class", "inside"))
		if not classes.has(klass):
			return _fail("There is no such cabin class.")
		var cd: Dictionary = classes[klass]
		var cabins: int = int(ceil(float(people) / float(cd.get("beds", 2))))
		var fees: Dictionary = cc.get("fees", {})
		var travel: int = int(fees.get("boarding", 45)) * people + int(fees.get("port_per_person", 12)) * people * maxi(days / 2, 1)
		var lodging: int = int(cd.get("per_day", 70)) * days * cabins
		var spending: int = int(fees.get("onboard_credit_per_day", 28)) * days * people
		var service: int = int(fees.get("gratuity_per_day", 6)) * days * people
		var pkg_id: String = str(opts.get("package", "standard"))
		var pkg: Dictionary = (cc.get("packages", {}) as Dictionary).get(pkg_id, {})
		if pkg.is_empty():
			return _fail("There is no such package.")
		var extra: int = int(pkg.get("extra", 0))
		lines.append({"label": "Fares and port fees (%d)" % people, "amount": travel})
		lines.append({"label": "%s x%d (%d nights)" % [str(cd.get("label", klass)), cabins, days], "amount": lodging})
		lines.append({"label": "Service charge", "amount": service})
		lines.append({"label": "Onboard spending money (unspent part comes back)", "amount": spending})
		if extra > 0:
			lines.append({"label": str(pkg.get("label", pkg_id)), "amount": extra})
		return {"ok": true, "lines": lines, "travel": travel + service, "lodging": lodging, "spending": spending, "package": extra, "cabins": cabins,
			"travel_min": int(cc.get("ship", {}).get("transit_min", 30)), "cabin_class": klass, "package_id": pkg_id}
	var d: Dictionary = dest_def(dest)
	var rooms: int = int(ceil(float(people) / 2.0))
	var travel2: int = int(d.get("travel_cost", 60)) * people
	var lodging2: int = int(d.get("lodging_per_day", 50)) * days * rooms
	var spending2: int = int(d.get("spending_per_day", 30)) * days * people
	lines.append({"label": "Travel (%d)" % people, "amount": travel2})
	lines.append({"label": "Lodging (%d room%s, %d nights)" % [rooms, "" if rooms == 1 else "s", days], "amount": lodging2})
	lines.append({"label": "Spending money (unspent part comes back)", "amount": spending2})
	return {"ok": true, "lines": lines, "travel": travel2, "lodging": lodging2, "spending": spending2, "cabins": rooms, "travel_min": int(d.get("travel_min", 90))}
