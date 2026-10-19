class_name PlaceAutoPlan
extends RefCounted
## Deciding the day (task 14b). For each resident, once a day: for every outing kind of data/life/95_auto.json work out a chance from the kind's base,
## the person's age, traits, needs, money, who they are with (a partner), how long since they last did it and the gate's own check, roll it with the
## seeded stream, keep up to the day's cap of ordinary outings (the essential ones, a doctor or a funeral, do not count), and give each a start hour
## inside the kind's windows, the place's opening hours and the person's free hours (awake, not at work or school, back by their usual time).
## `make_one` plans one kind right now (illness, a pet that needs the vet).

static var _sid_place: Dictionary = {}       # service id -> place id (built once per data load)
static var _sid_n: int = -1
static var _sorted: Array = []               # kind ids in order
static var _sorted_src: Dictionary = {}

static func reset() -> void:
	_sid_place = {}
	_sid_n = -1
	_sorted = []
	_sorted_src = {}

static func place_of(sid: String) -> String:
	var all: Dictionary = Places.all()
	if _sid_n != all.size() or _sid_place.is_empty():
		_sid_place = {}
		_sid_n = all.size()
		for pid in all:
			for s in Places.services(str(pid)):
				_sid_place[str(s)] = str(pid)
	return str(_sid_place.get(sid, ""))

static func kind_ids() -> Array:
	var k: Dictionary = PlaceAuto.kinds()
	if not is_same(k, _sorted_src):
		_sorted_src = k
		_sorted = k.keys()
		_sorted.sort()
	return _sorted

static func kind_def(kid: String) -> Dictionary:
	return PlaceAuto.kinds().get(kid, {})

# ------------------------------------------------------------------ the chance of a kind
static func deficit(f, need: String) -> float:
	var s = f.needs.get(need, null)
	if s == null:
		return 0.0
	var span: float = s.max - s.min
	return 0.0 if span <= 0.0 else clampf((s.max - s.value) / span, 0.0, 1.0)

static func has_partner(fid: int) -> bool:
	return not RelationshipBits.others_with_bit(fid, "partner").is_empty() or not RelationshipBits.others_with_bit(fid, "spouse").is_empty()

## Money factor 0..1 for paying `price` (0 = cannot afford it with the household's reserve kept).
static func money_mult(f, price: int) -> float:
	var c: Dictionary = PlaceAuto.cfg()
	var bal: int = Economy.balance(int(f.household_id))
	if price > 0 and bal < price * 2 + int(c.get("reserve_coins", 60)):
		return 0.0
	return clampf(float(bal) / float(c.get("money_comfort", 500)), 0.3, 1.0)

## Chance per day of the kind, without the gate: base x scale x age x traits x needs x partner x money x cool-down.
static func chance(f, kid: String, d: Dictionary, price: int) -> float:
	var c: Dictionary = PlaceAuto.cfg()
	var stage: String = str(f.age_stage)
	if d.has("stages") and not (d["stages"] as Array).has(stage):
		return 0.0
	var p: float = float(d.get("base", 0.0))
	if not bool(d.get("essential", false)):
		p *= float(c.get("scale", 1.0)) * float((c.get("stage_all", {}) as Dictionary).get(stage, 1.0))
		for t in (c.get("trait_all", {}) as Dictionary):
			if f.has_trait(str(t)):
				p *= float(c["trait_all"][t])
	p *= float((d.get("stage_mult", {}) as Dictionary).get(stage, 1.0))
	for t2 in (d.get("traits", {}) as Dictionary):
		if f.has_trait(str(t2)):
			p *= float(d["traits"][t2])
	for n in (d.get("needs", {}) as Dictionary):
		var gain: float = float(d["needs"][n])
		p *= maxf(1.0 + gain * deficit(f, str(n)), 0.2)
	if d.has("partner") and has_partner(int(f.id)):
		p *= float(d["partner"])
	p *= money_mult(f, price)
	var cool: int = int(d.get("cool", 2))
	if cool > 0 and SysUtil.day() - PlaceAuto.was_done(int(f.id), kid) < cool:
		p *= 0.25
	return minf(p, 0.95)

## Cheapest listed service price (0 if free or unknown), for the money check.
static func price_of(f, services: Array) -> int:
	var best := -1
	for s in services:
		var pid: String = place_of(str(s))
		if pid == "":
			continue
		var pr: int = PlaceUse.price(pid, str(s), int(f.id))
		if best < 0 or pr < best:
			best = pr
	return maxi(best, 0)

# ------------------------------------------------------------------ a service that suits a start hour
static func viable(f, sid: String, day: int, h: int, target: int = -1) -> bool:
	return viable_at(f, sid, (day - 1) * 1440 + h * 60 + 30, target)

## Can this person use the service at this game minute: age, day rule, the place's hours and the handler's own check (not the price or the staff).
static func viable_at(f, sid: String, at: int, target: int = -1) -> bool:
	var pid: String = place_of(sid)
	if pid == "":
		return false
	var svc: Dictionary = Places.services(pid).get(sid, {})
	var stage: String = str(f.age_stage)
	if Places.place_reason(stage, pid) != "" or Places.stage_reason(stage, svc) != "" or Places.when_reason(svc, at) != "":
		return false
	if not Places.open_at(pid, at):
		return false
	if target >= 0:
		svc = svc.duplicate()
		svc["_target"] = target
	return PlaceHandlers.check(str(svc.get("handler", "")), f, pid, sid, svc) == ""

static func windows_of(d: Dictionary) -> Array:
	return d.get("windows", [[7, 22]])

## Start hours of the day for these services: inside a window, free for the person, the place open, the visit over by their usual time.
static func hours_for(f, services: Array, d: Dictionary, day: int, free: Array, from_hour: int, target: int) -> Array:
	var out: Array = []
	var back: float = PlaceAutoTime.home_by(f)
	for w in windows_of(d):
		for h in range(int(ceil(float(w[0]) - 0.01)), int(floor(float(w[1]))) + 1):
			if h < from_hour or h > 23 or not bool(free[h]) or out.has(h):
				continue
			for s in services:
				var pid: String = place_of(str(s))
				var mins: float = float(Places.services(pid).get(str(s), {}).get("minutes", 30))
				if float(h) + mins / 60.0 + 0.5 > back and h >= 17:
					continue
				if viable(f, str(s), day, h, target):
					out.append(h)
					break
	out.sort()
	return out

# ------------------------------------------------------------------ making the plans
static func trips_cap(f, day: int) -> int:
	var t: Dictionary = PlaceAuto.cfg().get("trips_per_day", {})
	return int(t.get("work", 1)) if PlaceAutoTime.works_today(f, day) else int(t.get("free", 2))

## Everything this person might do today with its chance: [{kind, p, services, ctx, claim, essential}].
static func rolled(f, day: int) -> Array:
	var out: Array = []
	for kid in kind_ids():
		var d: Dictionary = kind_def(str(kid))
		var g: Dictionary = {"mult": 1.0}
		if d.has("gate"):
			g = PlaceAutoGate.eval(str(d["gate"]), f, str(kid), d, day)
			if float(g.get("mult", 0.0)) <= 0.0:
				continue
		var services: Array = g.get("services", d.get("services", []))
		if services.is_empty():
			continue
		var p: float = chance(f, str(kid), d, price_of(f, services)) * float(g.get("mult", 1.0))
		if p <= 0.0:
			continue
		if PlaceAuto.rng.randf() < minf(p, 0.97):
			out.append({"kind": str(kid), "p": p, "services": services, "ctx": g.get("ctx", {}), "claim": str(g.get("claim", "")), "essential": bool(d.get("essential", false))})
	return out

## A teen in the last part of school looks ahead and applies to the college for a subject (no trip: the same call the Town window has).
static func _apply(f) -> void:
	var fid: int = int(f.id)
	if str(f.age_stage) != "teen" or str(EduState.peek(fid).get("applied", "")) != "":
		return
	var cc: Dictionary = PlaceAuto.cfg().get("college", {})
	var grade: float = float(Careers.school[fid]["grade"]) if Careers.school.has(fid) else 60.0
	if Aging.stage_part(Aging.age_days(fid), "teen") == "early" or (grade < float(cc.get("apply_min_grade", 70)) and not PlaceAutoGate._ambitious(f, "college")):
		return
	if PlaceAuto.rng.randf() >= float(cc.get("apply_chance", 0.15)):
		return
	var major: String = PlaceAutoGate._pick_major(f)
	if major != "":
		LifeCommand.run(PlaceAutoTrip.PLAYER, fid, "college_apply", {"major": major})

static func make(f, day: int) -> void:
	var stage: String = str(f.age_stage)
	if stage == "baby" or SysUtil.is_away(f) or Hospital.is_in(int(f.id)) or JusticeState.inmates.has(int(f.id)):
		return
	_apply(f)
	var picks: Array = rolled(f, day)
	if picks.is_empty():
		return
	var free: Array = PlaceAutoTime.free_hours(f, day)
	var ordinary: Array = picks.filter(func(x): return not bool(x["essential"]))
	var cap: int = trips_cap(f, day)
	var chosen: Array = picks.filter(func(x): return bool(x["essential"]))
	while chosen.filter(func(x): return not bool(x["essential"])).size() < cap and not ordinary.is_empty():
		var idx := 0
		var total := 0.0
		for o in ordinary:
			total += float(o["p"])
		var roll: float = PlaceAuto.rng.randf() * total
		for i in ordinary.size():
			roll -= float(ordinary[i]["p"])
			if roll <= 0.0:
				idx = i
				break
		chosen.append(ordinary[idx])
		ordinary.remove_at(idx)
	for c in chosen:
		_place_plan(f, c, day, free, 0)

## Give the pick a start hour and store it. Returns true when a plan was made.
static func _place_plan(f, c: Dictionary, day: int, free: Array, from_hour: int) -> bool:
	var fid: int = int(f.id)
	var d: Dictionary = kind_def(str(c["kind"]))
	var ck := "%d|%s" % [int(f.household_id), c["claim"]]
	if str(c["claim"]) != "" and int(PlaceAuto.claims.get(ck, -1)) == day:
		return false
	for p in PlaceAuto.plans:
		if int(p["fid"]) == fid and str(p["kind"]) == str(c["kind"]) and int(p["expires"]) > SysUtil.now():
			return false
	var target: int = int((c["ctx"] as Dictionary).get("target", -1))
	var hours: Array = hours_for(f, c["services"], d, day, free, from_hour, target)
	if hours.is_empty():
		return false
	var h: int = int(hours[PlaceAuto.rng.randi_range(0, hours.size() - 1)])
	var gap: int = int(PlaceAuto.cfg().get("min_gap_hours", 3))
	for q in PlaceAuto.plans:
		if int(q["fid"]) == fid and absi(int(q["at"]) / 60 - ((day - 1) * 24 + h)) < gap and not bool(d.get("essential", false)):
			return false
	var at: int = (day - 1) * 1440 + h * 60 + PlaceAuto.rng.randi_range(0, int(PlaceAuto.cfg().get("start_jitter_min", 40)))
	if str(c["claim"]) != "":
		PlaceAuto.claims[ck] = day
	PlaceAuto.plans.append({"fid": fid, "kind": str(c["kind"]), "at": at, "expires": at + int(PlaceAuto.cfg().get("wait_min", 150)),
		"services": (c["services"] as Array).duplicate(), "ctx": (c["ctx"] as Dictionary).duplicate()})
	PlaceAuto.count("planned")
	return true

## Plan one kind for this person now (the hourly illness and pet checks). `from_hour` = the earliest start hour.
static func make_one(f, kid: String, from_hour: int) -> bool:
	var day: int = SysUtil.day()
	var d: Dictionary = kind_def(kid)
	if d.is_empty():
		return false
	var g: Dictionary = {"mult": 1.0}
	if d.has("gate"):
		g = PlaceAutoGate.eval(str(d["gate"]), f, kid, d, day)
		if float(g.get("mult", 0.0)) <= 0.0:
			return false
	var services: Array = g.get("services", d.get("services", []))
	if services.is_empty():
		return false
	var c := {"kind": kid, "p": 1.0, "services": services, "ctx": g.get("ctx", {}), "claim": str(g.get("claim", "")), "essential": true}
	return _place_plan(f, c, day, PlaceAutoTime.free_hours(f, day), from_hour)
