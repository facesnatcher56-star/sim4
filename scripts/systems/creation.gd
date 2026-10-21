class_name Creation
extends RefCounted
## Task 55: character creation points (data/creation.json, written by the reviewer). A spec is {background, skills {id: bought levels}, perks [], flaws []}.
## Creation.left(spec, diff) = points left (must be >= 0); Creation.apply(f, spec) at the start of a new game puts it into the real systems.
## The chosen perks / flaws are kept per person (picks) so the hooks can read them: Creation.mult(pid, key), Creation.add(pid, key), Creation.check(pid, skill).
## Heirs never get a spec: their life made them.

static var picks: Dictionary = {}          # fid -> spec

static func reset() -> void:
	picks = {}

static func cfg() -> Dictionary:
	return SysUtil.table("creation")

static func background(id: String) -> Dictionary:
	return (cfg().get("backgrounds", {}) as Dictionary).get(id, {})

static func perk(id: String) -> Dictionary:
	return (cfg().get("perks", {}) as Dictionary).get(id, {})

static func flaw(id: String) -> Dictionary:
	return (cfg().get("flaws", {}) as Dictionary).get(id, {})

static func empty_spec() -> Dictionary:
	return {"background": "nobody", "skills": {}, "perks": [], "flaws": []}

# ------------------------------------------------------------------ the budget
static func budget(spec: Dictionary, diff: String) -> int:
	var b: Dictionary = cfg().get("budget", {})
	return int(b.get("base", 6)) + int((b.get("difficulty", {}) as Dictionary).get(diff, 0)) + int(background(str(spec.get("background", ""))).get("points", 0))

## The price of buying `n` levels on top of a background's free `start` levels (each level costs skill_costs[level-1]).
static func skill_price(start: int, n: int) -> int:
	var costs: Array = cfg().get("skill_costs", [1, 2, 3])
	var t: int = 0
	for lv in range(start + 1, start + n + 1):
		t += int(costs[clampi(lv - 1, 0, costs.size() - 1)])
	return t

static func start_level(spec: Dictionary, sk: String) -> int:
	return int((background(str(spec.get("background", ""))).get("skills", {}) as Dictionary).get(sk, 0))

static func spent(spec: Dictionary) -> int:
	var s: int = 0
	for sk in (spec.get("skills", {}) as Dictionary):
		s += skill_price(start_level(spec, str(sk)), int(spec["skills"][sk]))
	for p in spec.get("perks", []):
		s += int(perk(str(p)).get("cost", 0))
	for fl in spec.get("flaws", []):
		s -= int(flaw(str(fl)).get("points", 0))
	return s

static func left(spec: Dictionary, diff: String) -> int:
	return budget(spec, diff) - spent(spec)

## Can this perk / flaw be added to the spec (opposites, the background)?
static func allowed(spec: Dictionary, id: String) -> bool:
	var d: Dictionary = perk(id) if not perk(id).is_empty() else flaw(id)
	var taken: Array = (spec.get("perks", []) as Array) + (spec.get("flaws", []) as Array)
	for x in d.get("excludes", []):
		if taken.has(x):
			return false
	for t in taken:
		var td: Dictionary = perk(str(t)) if not perk(str(t)).is_empty() else flaw(str(t))
		if (td.get("excludes", []) as Array).has(id):
			return false
	if (d.get("excludes_background", []) as Array).has(str(spec.get("background", ""))):
		return false
	return true

static func can_buy_level(spec: Dictionary, sk: String) -> bool:
	return start_level(spec, sk) + int((spec.get("skills", {}) as Dictionary).get(sk, 0)) < int(cfg().get("skill_cap", 3))

## Skills that can be bought: data/skills.json plus the registry ones.
static func skill_ids() -> Array:
	var out: Array = (SysUtil.table("skills").get("skills", {}) as Dictionary).keys()
	for k in ContentRules.skill_ids():
		if not out.has(k):
			out.append(k)
	return out

## A valid spec within the budget (the creator's Random button).
static func random_spec(diff: String, rng: RandomNumberGenerator) -> Dictionary:
	var r: Dictionary = cfg().get("random", {})
	var spec: Dictionary = empty_spec()
	var bgs: Array = (cfg().get("backgrounds", {}) as Dictionary).keys()
	spec["background"] = str(bgs[rng.randi_range(0, bgs.size() - 1)])
	var fl: Array = (cfg().get("flaws", {}) as Dictionary).keys()
	for i in rng.randi_range(0, int(r.get("max_flaws", 3))):
		var id: String = str(fl[rng.randi_range(0, fl.size() - 1)])
		if not (spec["flaws"] as Array).has(id) and allowed(spec, id):
			spec["flaws"].append(id)
	var pk: Array = (cfg().get("perks", {}) as Dictionary).keys()
	for i in rng.randi_range(0, int(r.get("max_perks", 3))):
		var id2: String = str(pk[rng.randi_range(0, pk.size() - 1)])
		if not (spec["perks"] as Array).has(id2) and allowed(spec, id2) and left(spec, diff) >= int(perk(id2).get("cost", 0)):
			spec["perks"].append(id2)
	if bool(r.get("spend_skills", true)):
		var sks: Array = skill_ids()
		for guard in 40:
			var sk: String = str(sks[rng.randi_range(0, sks.size() - 1)])
			if not can_buy_level(spec, sk):
				continue
			var have: int = int((spec["skills"] as Dictionary).get(sk, 0))
			if skill_price(start_level(spec, sk) + have, 1) > left(spec, diff):
				continue
			spec["skills"][sk] = have + 1
	while left(spec, diff) < 0 and not (spec["perks"] as Array).is_empty():
		spec["perks"].pop_back()
	return spec

# ------------------------------------------------------------------ in play: what the hooks read
static func _effects(pid: int) -> Array:
	var spec: Dictionary = picks.get(pid, {})
	if spec.is_empty():
		return []
	var out: Array = [background(str(spec.get("background", ""))).get("effects", {})]
	for p in spec.get("perks", []):
		out.append(perk(str(p)).get("effects", {}))
	for fl in spec.get("flaws", []):
		out.append(flaw(str(fl)).get("effects", {}))
	return out

## Product of a multiplier effect (skill_xp_mult, heal_mult, wake_on_noise, food_sickness_mult, addiction_mult, smoke_dose_mult, chase_mult, witness_id_mult, fight_start_mult).
static func mult(pid: int, key: String) -> float:
	var m: float = 1.0
	for e in _effects(pid):
		if (e as Dictionary).has(key):
			m *= float(e[key])
	return m

## Sum of an additive effect (willpower, first_impression, sleep_quality).
static func add(pid: int, key: String) -> float:
	var s: float = 0.0
	for e in _effects(pid):
		if (e as Dictionary).has(key) and not (e[key] is Dictionary):
			s += float(e[key])
	return s

## The check bonus for a skill, in levels (a flaw fixed by an item, such as glasses, does not count while the item is carried).
static func check(pid: int, skill: String) -> float:
	var s: float = 0.0
	for e in _effects(pid):
		var c: Dictionary = (e as Dictionary).get("check", {})
		if c.has(skill):
			var fix: String = str((e as Dictionary).get("fixed", ""))
			if fix != "" and float(c[skill]) < 0.0 and Inventory.has(pid, fix):
				continue
			s += float(c[skill])
	return s

## Hiring bonus by job kind ("all" applies to every job).
static func hiring(pid: int, kind: String) -> float:
	var s: float = 0.0
	for e in _effects(pid):
		var h: Dictionary = (e as Dictionary).get("hiring", {})
		s += float(h.get(kind, 0)) + float(h.get("all", 0))
	return s

static func has_licence(pid: int, id: String) -> bool:
	for e in _effects(pid):
		if str((e as Dictionary).get("licence", "")) == id:
			return true
	return false

static func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for k in picks:
		out[str(k)] = picks[k]
	return out

static func from_dict(d: Dictionary) -> void:
	picks = {}
	for k in d:
		picks[int(k)] = d[k]

# ------------------------------------------------------------------ the start of a new game
## Put a spec into the real systems: skill levels, a real loan, bad credit history, a criminal record, a bike, a first acquaintance.
## Effects with no system behind them yet are kept in the picks only (see the builder's status message).
static func apply(f, spec: Dictionary) -> void:
	if f == null or spec.is_empty():
		return
	var fid: int = int(f.id)
	var hid: int = int(f.household_id)
	picks[fid] = spec.duplicate(true)
	var levels: Dictionary = (background(str(spec.get("background", ""))).get("skills", {}) as Dictionary).duplicate()
	for sk in (spec.get("skills", {}) as Dictionary):
		levels[sk] = int(levels.get(sk, 0)) + int(spec["skills"][sk])
	for sk2 in levels:
		var lv: int = clampi(int(levels[sk2]), 0, int(cfg().get("skill_cap", 3)))
		if lv > 0:
			f.skills[str(sk2)] = {"xp": Folk.xp_for_level(lv), "level": lv}
	for e in _effects(fid):
		var ed: Dictionary = e
		if str(ed.get("item", "")) == "bike":
			Transport.bikes[str(hid)] = Transport.bikes_of(hid) + 1
		elif str(ed.get("item", "")) != "":
			Inventory.add(fid, str(ed["item"]))
		if ed.has("debt"):
			var dd: Dictionary = ed["debt"]
			var amount: int = int(dd.get("amount", 500))
			var weeks: int = maxi(int(ceil(float(amount) / maxf(float(dd.get("repay_per_week", 25)), 1.0))), 1)
			BankAccounts.open_loan(hid, amount, weeks, BankAccounts.loan_rate(hid), str(dd.get("lender", "loan")), "")
		if str(ed.get("credit", "")) == "bad":
			var r: Dictionary = BankAccounts.record.get(hid, {})
			r["defaults"] = maxi(int(r.get("defaults", 0)), 1)
			BankAccounts.record[hid] = r
		if ed.has("record"):
			var rec: Dictionary = ed["record"]
			var recs: Array = JusticeState.records.get(fid, [])
			for ch in rec.get("charges", []):
				recs.append({"day": SysUtil.day() - 365 * int(rec.get("years_ago", 0)), "charge": str(ch), "case": -1, "result": "convicted"})
			JusticeState.records[fid] = recs
		if ed.has("contact"):
			var cands: Array = Story.alive_townies().filter(func(t): return Story.stage_of(t) in ["adult", "elder"])
			if not cands.is_empty():
				var t: Dictionary = cands[absi(hash("%d|contact" % fid)) % cands.size()]
				RelationshipService.add_both(fid, int(t["id"]), "friendship", 15.0)
				RelationshipService.add_history(fid, int(t["id"]), "met", 0.3, int(t["id"]))
