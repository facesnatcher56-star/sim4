class_name CityGov
extends RefCounted
## The town government (task 12.4): taxes and the town budget, the mayor and the council, and the money that decides how well the services work.
##   tax          multiplier on the council-charges part of every bill and on the town's revenue (0.6 .. 1.6, default 1.0)
##   alloc        share of the revenue each department gets (utilities, fire, police, health, roads, parks, schools, reserve)
##   funding(d)   1.0 at the standard budget: alloc/default x revenue/standard revenue, topped up from the savings, cut in a debt. CityBudget.funding reads it.
## Weekly the budget is settled (revenue, spending, savings, funding). The mayor (a townie, or a player: buff `mayor`) and the council are elected / voted
## by CityElection and CityPolicy; the town's mood (CityMood) drives the votes. Everything is data (data/city.json `gov`) and seeded (CityState.rng).
## Tier behaviour: world-level numbers; townies are only counted (heads, voters). Cadence: one daily check; the budget weekly, elections every term, policies monthly.
## Save: part of the `city` block ("gov").

static var tax: float = 1.0
static var alloc: Dictionary = {}          # department -> share of the revenue
static var treasury: float = 0.0
static var funding_now: Dictionary = {}    # department -> funding (1.0 = standard)
static var income_last: float = 0.0
static var next_budget_day: int = 0
static var mayor: Dictionary = {}          # {id, name, since, term_end, platform, player}
static var council: Array = []             # [{id, name, lean:{axis: -1..1}}]
static var policies: Dictionary = {}       # id -> {since, by}
static var history: Array = []             # last town decisions [{day, kind, text}]
static var mood_now: float = 0.0
static var hours_down_mark: int = 0
static var debt_told: bool = false
static var permit_day: Dictionary = {}     # str(household) -> day a building permit was bought

static func reset() -> void:
	tax = float(cfg().get("tax", {}).get("default", 1.0))
	alloc = (cfg().get("alloc", {}) as Dictionary).duplicate()
	treasury = 0.0
	funding_now.clear()
	income_last = 0.0
	next_budget_day = 0
	mayor = {}
	council = []
	policies = {}
	history = []
	mood_now = 0.0
	hours_down_mark = 0
	debt_told = false
	permit_day = {}
	CityElection.reset()

static func cfg() -> Dictionary:
	return CityState.cfg().get("gov", {})

static func default_alloc() -> Dictionary:
	return cfg().get("alloc", {})

static func note(kind: String, text: String) -> void:
	history.append({"day": SysUtil.day(), "kind": kind, "text": text})
	while history.size() > 30:
		history.pop_front()

# ------------------------------------------------------------------ setup
## The first mayor and council, from the townies (seeded). Safe to call again: it only acts when there is no mayor and enough people.
static func ensure() -> void:
	if not mayor.is_empty() or CityState.cfg().is_empty():
		return
	var pool: Array = CityElection.eligible()
	if pool.size() < 3:
		return
	var best: int = -1
	var score: float = -1.0
	for pid in pool:
		var s: float = CrimePerson.charisma(int(pid)) + CityState.rng.randf() * 0.6
		if s > score:
			score = s
			best = int(pid)
	var plat: String = _pick_platform()
	mayor = {"id": best, "name": CrimePerson.name_of(best), "since": SysUtil.day(), "term_end": SysUtil.day() + int(cfg().get("term_days", 84)), "platform": plat, "player": false}
	_apply_platform(plat)
	council = CityPolicy.pick_council(pool, best)
	if next_budget_day <= 0:
		next_budget_day = SysUtil.day() + 7
	budget_week(false)

static func _pick_platform() -> String:
	var keys: Array = (cfg().get("platforms", {}) as Dictionary).keys()
	keys.sort()
	return str(keys[CityState.rng.randi_range(0, keys.size() - 1)])

## A mayor's platform changes taxes and the shares (taken from or given back to the other departments). Not for the first mayor of a new game: that one starts neutral.
static func _apply_platform(plat: String, quiet: bool = true) -> void:
	var p: Dictionary = (cfg().get("platforms", {}) as Dictionary).get(plat, {})
	if p.is_empty() or quiet:
		return
	set_tax(tax + float(p.get("tax", 0.0)))
	for d in (p.get("alloc", {}) as Dictionary):
		shift(str(d), float(p["alloc"][d]))

# ------------------------------------------------------------------ the levers (a player mayor uses them through interactions)
static func set_tax(v: float) -> void:
	var t: Dictionary = cfg().get("tax", {})
	tax = snappedf(clampf(v, float(t.get("min", 0.6)), float(t.get("max", 1.6))), 0.01)
	recompute()

## Give department `dept` `amount` more of the revenue, taken evenly from the others (never below the minimum).
static func shift(dept: String, amount: float) -> void:
	if not alloc.has(dept):
		return
	var lo: float = float(cfg().get("alloc_min", 0.03))
	var hi: float = float(cfg().get("alloc_max", 0.4))
	var others: Array = alloc.keys().filter(func(k): return k != dept and k != "reserve")
	var take: float = clampf(alloc[dept] + amount, lo, hi) - float(alloc[dept])
	var got: float = 0.0
	for k in others:
		var give: float = minf(take / float(others.size()), float(alloc[k]) - lo) if take > 0.0 else take / float(others.size())
		alloc[k] = float(alloc[k]) - give
		got += give
	alloc[dept] = float(alloc[dept]) + got
	recompute()

# ------------------------------------------------------------------ the budget
static func heads() -> int:
	var n: int = 0
	for tid in Story.townies:
		if bool(Story.townies[tid].get("alive", false)):
			n += 1
	for pid in Players.ids():
		n += 3
	return n

static func revenue(at_tax: float) -> float:
	var r: Dictionary = cfg().get("revenue", {})
	return (float(r.get("base", 20.0)) + float(r.get("per_head", 8.0)) * float(heads()) + float(r.get("per_player_household", 40.0)) * float(maxi(Players.count(), 1)) + CityPlan.revenue_bonus()) * at_tax

## Fresh funding numbers from the current shares and revenue (the savings top up the departments that fall short).
static func recompute() -> void:
	var rng_f: Array = cfg().get("funding_range", [0.4, 1.8])
	var std_income: float = revenue(1.0)
	var income: float = revenue(tax)
	var ratio: float = income / maxf(std_income, 1.0)
	var def: Dictionary = default_alloc()
	var debt: Dictionary = cfg().get("debt", {})
	var austerity: float = float(debt.get("austerity", 0.8)) if treasury < float(debt.get("limit", -400)) else 1.0
	var gaps: Dictionary = {}
	for d in def:
		if d == "reserve":
			continue
		var f: float = float(alloc.get(d, 0.0)) / maxf(float(def[d]), 0.001) * ratio * austerity
		f += CityPlan.funding_bonus(str(d))
		funding_now[d] = clampf(f, float(rng_f[0]), float(rng_f[1]))
		if f < 1.0:
			gaps[d] = (1.0 - f) * std_income * float(def[d])
	if treasury > 0.0 and not gaps.is_empty():
		var pot: float = treasury * float(cfg().get("topup_share", 0.25))
		var need: float = 0.0
		for g in gaps:
			need += float(gaps[g])
		var use: float = minf(pot, need)
		for g2 in gaps:
			funding_now[g2] = clampf(float(funding_now[g2]) + use * (float(gaps[g2]) / maxf(need, 0.001)) / maxf(std_income * float(def[g2]), 0.001), float(rng_f[0]), 1.0)

static func funding_of(dept: String) -> float:
	return float(funding_now.get(dept, 1.0))

## Weekly: collect, spend, save, fund.
static func budget_week(announce: bool = true) -> void:
	var income: float = revenue(tax)
	var spend: float = 0.0
	for d in alloc:
		if d != "reserve":
			spend += income * float(alloc[d])
	treasury += income - spend
	income_last = income
	recompute()
	var debt: Dictionary = cfg().get("debt", {})
	if treasury < float(debt.get("limit", -400)) and not debt_told:
		debt_told = true
		SysUtil.notify(str(cfg().get("texts", {}).get("debt", "")), "warn")
		ChronicleHook.note("town", str(cfg().get("texts", {}).get("debt", "")), [], "", 3, true)
	elif treasury >= 0.0:
		debt_told = false
	if announce:
		note("budget", str(cfg().get("texts", {}).get("budget", "")).replace("{income}", str(int(round(income)))))
	next_budget_day = SysUtil.day() + 7

# ------------------------------------------------------------------ the clock
static func on_day(day: int) -> void:
	ensure()
	CityPublic.on_day(day)
	CityPlan.on_day(day)
	if mayor.is_empty():
		return
	if day >= next_budget_day:
		budget_week()
	CityMood.update()
	CityElection.on_day(day)
	CityPolicy.on_day(day)
	CityElection.sync_buff()

# ------------------------------------------------------------------ the notice board (plain words for the player)
static func status_lines() -> Array:
	var out: Array = []
	if mayor.is_empty():
		return ["The town has no mayor yet."]
	var plat: String = str(((cfg().get("platforms", {}) as Dictionary).get(str(mayor.get("platform", "")), {}) as Dictionary).get("label", ""))
	out.append("Mayor %s%s. %s" % [str(mayor["name"]), (" (%s)" % plat) if plat != "" else "", CityMood.words()])
	out.append("Taxes are %d percent of the standard rate. The town takes in about %d coins a week." % [int(round(tax * 100.0)), int(round(revenue(tax)))])
	var top: String = ""
	var best: float = 0.0
	for d in alloc:
		if d != "reserve" and float(alloc[d]) > best:
			best = float(alloc[d])
			top = str(d)
	out.append("Most of the budget goes to %s. Savings: %d coins." % [str((cfg().get("dept_labels", {}) as Dictionary).get(top, top)), int(round(treasury))])
	if policies.is_empty():
		out.append("No special laws are in force.")
	else:
		var names: Array = []
		for pid in policies:
			names.append(str(((CityPolicy.cfg()[pid]) as Dictionary).get("label", pid)).to_lower())
		out.append("In force: %s." % ", ".join(names))
	if CityElection.phase == "campaign":
		out.append("Election campaign under way. Election day is day %d." % CityElection.vote_day)
	else:
		out.append("The next election is on day %d." % int(mayor["term_end"]))
	for p in CityPlan.projects:
		out.append(CityPlan.describe(p))
	var dark: int = 0
	for z in CityState.zone_ids():
		dark += int(CityPublic.broken.get(str(z), 0))
	if dark > 0:
		out.append("%d street lamps are out across town." % dark)
	return out

# ------------------------------------------------------------------ install (content generated from the data)
static func install() -> void:
	var g: Dictionary = cfg()
	if g.is_empty():
		return
	var table: Dictionary = Careers.cfg()
	if not table.is_empty():
		var careers: Dictionary = table.get("careers", {})
		var cid: String = str((g.get("career", {}) as Dictionary).get("id", "politician"))
		if not careers.has(cid):
			careers[cid] = CityElection.career_def()
	CityPolicy.install_content()

# ------------------------------------------------------------------ mailbox interactions of the player (events)
static func on_event(ev: String, payload: Dictionary) -> void:
	var f = SysUtil.folk(int(payload.get("folk_id", -1)))
	if f == null or int(f.household_id) <= 0:
		return
	var is_mayor: bool = bool(mayor.get("player", false)) and int(mayor.get("id", -1)) == int(f.id)
	match ev:
		"tax_up", "tax_down":
			if is_mayor:
				var step: float = float((cfg().get("tax", {}) as Dictionary).get("step", 0.1))
				set_tax(tax + (step if ev == "tax_up" else -step))
				SysUtil.notify("Taxes are now %d percent of the standard rate." % int(round(tax * 100.0)), "info")
		"town_notice":
			for line in status_lines():
				SysUtil.notify(str(line), "info")
		"vote_mayor":
			CityElection.cast_vote(f)
		"run_for_mayor":
			CityElection.declare(f)
		"campaign_speech":
			CityElection.speech(f)
		_:
			if ev.begins_with("focus_") and is_mayor:
				var d: String = ev.substr(6)
				shift(d, float(cfg().get("alloc_step", 0.03)))
				SysUtil.notify("More of the budget now goes to %s." % str((cfg().get("dept_labels", {}) as Dictionary).get(d, d)), "info")
			elif ev.begins_with("rezone_") and is_mayor:
				CityPlan.shift_zoning(ev.substr(7))
				SysUtil.notify("New land will be used more for %s." % ev.substr(7), "info")
			elif ev.begins_with("propose_") and is_mayor:
				CityPolicy.propose(ev.substr(8), true)

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"tax": tax, "alloc": alloc.duplicate(), "treasury": treasury, "funding": funding_now.duplicate(), "income": income_last, "next_budget": next_budget_day,
		"mayor": mayor.duplicate(true), "council": council.duplicate(true), "policies": policies.duplicate(true), "history": history.duplicate(true), "mood": mood_now,
		"down_mark": hours_down_mark, "debt_told": debt_told, "permits": permit_day.duplicate(), "election": CityElection.to_dict()}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	tax = float(d.get("tax", tax))
	alloc = (d.get("alloc", alloc) as Dictionary).duplicate()
	treasury = float(d.get("treasury", 0.0))
	funding_now = (d.get("funding", {}) as Dictionary).duplicate()
	income_last = float(d.get("income", 0.0))
	next_budget_day = int(d.get("next_budget", 0))
	mayor = (d.get("mayor", {}) as Dictionary).duplicate(true)
	SysUtil.ints_in(mayor, ["id", "since", "term_end"])
	council = (d.get("council", []) as Array).duplicate(true)
	for c in council:
		SysUtil.ints_in(c, ["id"])
	policies = (d.get("policies", {}) as Dictionary).duplicate(true)
	for k in policies:
		SysUtil.ints_in(policies[k], ["since", "by"])
	history = (d.get("history", []) as Array).duplicate(true)
	for h in history:
		SysUtil.ints_in(h, ["day"])
	mood_now = float(d.get("mood", 0.0))
	hours_down_mark = int(d.get("down_mark", 0))
	debt_told = bool(d.get("debt_told", false))
	permit_day = {}
	for pk in (d.get("permits", {}) as Dictionary):
		permit_day[str(pk)] = int(d["permits"][pk])
	CityElection.from_dict(d.get("election", {}))
