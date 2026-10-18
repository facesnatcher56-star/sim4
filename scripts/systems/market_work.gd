class_name MarketWork
extends RefCounted
## Work beyond the careers (task 13, slice 6): part-time jobs for teens, freelancing and odd jobs (interactions on the computer / mailbox),
## selling crafts (paintings, books, garden produce, fish) at the market or online, remote work (internet stub until task 12), layoffs in a
## recession with severance, and unemployment benefit. Tier: DAILY (payroll, benefit, layoffs) + events from interactions. Active set: the
## household's folk (a handful). Balance: crafts sell below what the same activity already pays, demand per kind is capped per day and
## each unit sold lowers the price, freelance/odd jobs are capped per day. Data: data/bank.json "work".

static var crafts: Dictionary = {}       # hid -> {kind -> count}
static var sold_today: Dictionary = {}   # kind -> units sold today (market saturation, shared by the whole town)
static var parttime: Dictionary = {}     # folk id -> {job, since}
static var gigs: Dictionary = {}         # folk id -> {day, freelance, odd}
static var freelance_day: Dictionary = {}  # folk id -> last day a gig was done
static var jobless: Dictionary = {}      # folk id -> {since, paid_days}: laid off or fired, eligible for benefit
static var _day: int = -1

static func reset() -> void:
	crafts.clear()
	sold_today.clear()
	parttime.clear()
	gigs.clear()
	freelance_day.clear()
	jobless.clear()
	_day = -1

static func cfg() -> Dictionary:
	return SysUtil.table("bank").get("work", {})

## Task 12 (city infrastructure) will answer this per household; until then everybody is online.
static func has_internet(_hid: int) -> bool:
	return true

static func is_self_employed(folk_id: int) -> bool:
	return SysUtil.day() - int(freelance_day.get(folk_id, -99)) <= 7

# ------------------------------------------------------------------ events
static func on_interaction(folk_id: int, iid: String, success: bool) -> void:
	if not success:
		return
	var kind: String = str((cfg().get("craft_interactions", {}) as Dictionary).get(iid, ""))
	if kind != "":
		add_craft(_hid(folk_id), kind, 1)

static func on_game_event(ev: String, payload: Dictionary) -> void:
	var fid: int = int(payload.get("folk_id", -1))
	var kind: String = str((cfg().get("craft_events", {}) as Dictionary).get(ev, ""))
	if kind != "":
		add_craft(_hid(fid), kind, 1)
		return
	match ev:
		"sell_crafts":
			var res: Dictionary = sell_crafts(_hid(fid), fid, false)
			if bool(res["ok"]):
				SysUtil.notify("Sold %d crafts online for %d coins." % [int(res["units"]), int(res["paid"])], "good")
			else:
				SysUtil.notify(str(res["reason"]), "info")
		"freelance_done":
			freelance(fid)
		"odd_job_done":
			odd_job(fid)
		"left_job":
			if str(payload.get("reason", "")) in ["fired", "laid_off"]:
				jobless[fid] = {"since": SysUtil.day(), "paid_days": 0}
		"write_will":
			BankWill.on_write_event(fid)

static func _hid(folk_id: int) -> int:
	var f = SysUtil.folk(folk_id)
	return int(f.household_id) if f != null else -1

# ------------------------------------------------------------------ crafts
static func craft_count(hid: int, kind: String) -> int:
	return int((crafts.get(hid, {}) as Dictionary).get(kind, 0))

static func add_craft(hid: int, kind: String, n: int) -> void:
	if hid <= 0:
		return
	if not crafts.has(hid):
		crafts[hid] = {}
	crafts[hid][kind] = craft_count(hid, kind) + n

static func craft_price(kind: String, skill: int) -> float:
	var c: Dictionary = (cfg().get("crafts", {}) as Dictionary).get(kind, {})
	var base: float = float(c.get("price", 5)) * (1.0 + float(cfg().get("skill_bonus", 0.08)) * float(skill)) * MarketEconomy.price_mult()
	return base * maxf(0.3, 1.0 - float(cfg().get("saturation", 0.08)) * float(sold_today.get(kind, 0)))

## Sell everything the household has made. `at_market`: standing at the market stall (full price); online keeps only `sell_share`.
static func sell_crafts(hid: int, folk_id: int, at_market: bool) -> Dictionary:
	var f = SysUtil.folk(folk_id)
	var total: int = 0
	var units: int = 0
	var share: float = 1.0 if at_market else float(cfg().get("sell_share", 0.6))
	for kind in (cfg().get("crafts", {}) as Dictionary):
		var have: int = craft_count(hid, str(kind))
		if have <= 0:
			continue
		var c: Dictionary = cfg()["crafts"][kind]
		var skill: int = f.skill_level(str(c.get("skill", ""))) if f != null else 0
		var room: int = maxi(int(c.get("demand", 5)) - int(sold_today.get(kind, 0)), 0)
		var n: int = mini(have, room)
		for _i in n:
			total += int(round(craft_price(str(kind), skill) * share))
			sold_today[kind] = int(sold_today.get(kind, 0)) + 1
		crafts[hid][kind] = have - n
		units += n
	if units <= 0:
		return {"ok": false, "reason": "Nothing to sell right now (the buyers have had enough today, or you have made nothing).", "units": 0, "paid": 0}
	Economy.deposit(hid, total, "crafts sold %s" % ("at the market" if at_market else "online"))
	return {"ok": true, "reason": "", "units": units, "paid": total}

# ------------------------------------------------------------------ freelance / odd jobs
static func _gig(folk_id: int) -> Dictionary:
	var g: Dictionary = gigs.get(folk_id, {})
	if int(g.get("day", -1)) != SysUtil.day():
		g = {"day": SysUtil.day(), "freelance": 0, "odd": 0}
		gigs[folk_id] = g
	return g

static func freelance(folk_id: int) -> int:
	var f = SysUtil.folk(folk_id)
	if f == null or not has_internet(int(f.household_id)):
		return 0
	var g: Dictionary = _gig(folk_id)
	var c: Dictionary = cfg().get("freelance", {})
	if int(g["freelance"]) >= int(c.get("daily_cap", 2)):
		SysUtil.notify("No more freelance clients today.", "info")
		return 0
	g["freelance"] = int(g["freelance"]) + 1
	var best: int = 0
	for s in c.get("skills", []):
		best = maxi(best, f.skill_level(str(s)))
	var pay: int = int(round((float(c.get("base", 40)) + float(c.get("skill_pay", 9)) * float(best)) * MarketEconomy.wage_mult()))
	Economy.deposit(int(f.household_id), pay, "freelance work")
	freelance_day[folk_id] = SysUtil.day()
	return pay

static func odd_job(folk_id: int) -> int:
	var f = SysUtil.folk(folk_id)
	if f == null:
		return 0
	var g: Dictionary = _gig(folk_id)
	var c: Dictionary = cfg().get("odd_job", {})
	if int(g["odd"]) >= int(c.get("daily_cap", 2)):
		SysUtil.notify("No more odd jobs going today.", "info")
		return 0
	g["odd"] = int(g["odd"]) + 1
	var pay: int = int(round(float(c.get("base", 30)) * MarketEconomy.wage_mult()))
	Economy.deposit(int(f.household_id), pay, "odd job")
	return pay

# ------------------------------------------------------------------ part-time (teens)
static func can_part_time(f) -> bool:
	return f != null and f.age_stage == "teen" and not parttime.has(int(f.id))

static func take_part_time(folk_id: int) -> bool:
	var f = SysUtil.folk(folk_id)
	if not can_part_time(f):
		return false
	parttime[folk_id] = {"job": "teen_job", "since": SysUtil.day()}
	return true

static func quit_part_time(folk_id: int) -> void:
	parttime.erase(folk_id)

static func parttime_text(folk_id: int) -> String:
	if not parttime.has(folk_id):
		return ""
	var j: Dictionary = cfg().get("teen_job", {})
	var h: Array = j.get("hours", [15, 19])
	return "%s, %d:00 to %d:00, %d coins an hour" % [str(j.get("label", "Part-time job")), int(h[0]), int(h[1]), int(round(float(j.get("pay_hour", 9)) * MarketEconomy.wage_mult()))]

# ------------------------------------------------------------------ daily
static func on_day(day: int) -> void:
	if day != _day:
		_day = day
		sold_today.clear()
	var c: Dictionary = cfg()
	var j: Dictionary = c.get("teen_job", {})
	for fid in parttime.keys():
		var f = SysUtil.folk(int(fid))
		if f == null or f.age_stage != "teen" or SysUtil.is_away(f):
			if f == null or f.age_stage != "teen":
				parttime.erase(fid)
			continue
		var h: Array = j.get("hours", [15, 19])
		var pay: int = int(round(float(j.get("pay_hour", 9)) * float(int(h[1]) - int(h[0])) * MarketEconomy.wage_mult()))
		Economy.deposit(int(f.household_id), pay, "part-time job")
		if f.needs.has("energy"):
			f.needs["energy"].add(-6.0)
	_benefit(day, c.get("benefit", {}))
	_layoffs()

static func _benefit(day: int, b: Dictionary) -> void:
	for fid in jobless.keys():
		var f = SysUtil.folk(int(fid))
		var rec: Dictionary = jobless[fid]
		if f == null or Careers.has_job(int(fid)) or day - int(rec["since"]) < int(b.get("wait_days", 1)):
			if f == null or Careers.has_job(int(fid)):
				jobless.erase(fid)
			continue
		if int(rec["paid_days"]) >= int(b.get("max_days", 14)):
			jobless.erase(fid)
			continue
		rec["paid_days"] = int(rec["paid_days"]) + 1
		Economy.deposit(int(f.household_id), int(round(float(b.get("per_day", 18)) * MarketEconomy.wage_mult())), "unemployment benefit")

## Recession: employed adults can be let go (with severance). Deterministic: MarketEconomy.rng.
static func _layoffs() -> void:
	var e: Dictionary = MarketEconomy.cfg()
	if not MarketEconomy.enabled or MarketEconomy.prosperity >= float(e.get("layoff_below", -0.3)):
		return
	for f in SysUtil.residents():
		if f.age_stage != "adult" or not Careers.has_job(int(f.id)):
			continue
		if MarketEconomy.rng.randf() >= float(e.get("resident_layoff_chance", 0.004)) * (-MarketEconomy.prosperity):
			continue
		var cid: String = Careers.career_of(int(f.id))
		var pay: int = int(Careers.level_def(cid, Careers.level_of(int(f.id))).get("pay", 10))
		var sev: int = pay * 8 * int(e.get("severance_days", 3))
		Careers.quit_job(f, "laid_off")
		Economy.deposit(int(f.household_id), sev, "severance pay")
		jobless[int(f.id)] = {"since": SysUtil.day(), "paid_days": 0}
		SysUtil.notify("%s was laid off in the cuts and received %d coins severance. Unemployment benefit will help." % [f.name, sev], "bad")

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"crafts": SysUtil.str_keys(crafts).duplicate(true), "parttime": SysUtil.str_keys(parttime).duplicate(true), "gigs": SysUtil.str_keys(gigs).duplicate(true),
		"freelance_day": SysUtil.str_keys(freelance_day), "jobless": SysUtil.str_keys(jobless).duplicate(true), "sold_today": sold_today.duplicate(), "day": _day}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	crafts = SysUtil.int_keys((d.get("crafts", {}) as Dictionary).duplicate(true))
	for hid in crafts:
		for k in crafts[hid]:
			crafts[hid][k] = int(crafts[hid][k])
	parttime = SysUtil.int_keys((d.get("parttime", {}) as Dictionary).duplicate(true))
	gigs = SysUtil.int_keys((d.get("gigs", {}) as Dictionary).duplicate(true))
	for g in gigs:
		SysUtil.ints_in(gigs[g], ["day", "freelance", "odd"])
	freelance_day = SysUtil.int_keys(d.get("freelance_day", {}))
	for k2 in freelance_day:
		freelance_day[k2] = int(freelance_day[k2])
	jobless = SysUtil.int_keys((d.get("jobless", {}) as Dictionary).duplicate(true))
	for j in jobless:
		SysUtil.ints_in(jobless[j], ["since", "paid_days"])
	sold_today = {}
	for k3 in (d.get("sold_today", {}) as Dictionary):
		sold_today[str(k3)] = int(d["sold_today"][k3])
	_day = int(d.get("day", -1))
