class_name TownDrama
extends RefCounted
## Task 61d: the town starts with its own drama, random every game. At world creation a handful of threads (scaled by town size) are rolled from
## the world seed and set up as REAL STATES in the existing systems, as if they had been going for a while: a feud (history + a grudge), an
## affair (romance + an affairs entry the cheating discovery reads), a secret a third person knows, a loan shark's overdue loan, someone in a
## crew, a cold break-in case with the culprit still in town, a struggling business, an estranged parent and child or a divorce, an addiction,
## two people circling each other. Kinds are weighted by district (rough blocks lean crews, debts, using), never by heritage.
## Nothing is scripted afterwards: no planned beats, no meeting with the player, no storyteller push. The player finds out the real way.
## The only thing kept is the list, so the end-of-life summary can record a thread the player got involved in (friends with someone in it,
## or a grudge with them), with its cause. Data: data/town_drama.json.

static var threads: Array = []          # [{kind, a, b, day, touched}]

static func reset() -> void:
	threads = []

static func cfg() -> Dictionary:
	return SysUtil.table("town_drama")

# ------------------------------------------------------------------ the seed
static func seed_town() -> void:
	reset()
	var c: Dictionary = cfg()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("town_drama|%d" % Neighborhood.world_seed)
	var adults: Array = Story.alive_townies().filter(func(t): return Story.stage_of(t) in ["adult", "elder"]).map(func(t): return int(t["id"]))
	if adults.size() < 4:
		return
	var cr: Array = c.get("count", [4, 8])
	var scale: float = clampf(float(adults.size()) / 40.0, 0.8, 1.5)          # a small town still gets its handful
	var cl: Array = c.get("clamp", [3, 10])
	var n: int = clampi(int(round(rng.randf_range(float(cr[0]), float(cr[1])) * scale)), int(cl[0]), int(cl[1]))
	var used: Dictionary = {}
	var weights: Dictionary = c.get("weights", {})
	var tries: int = 0
	while threads.size() < n and tries < n * 6:
		tries += 1
		var kinds: Array = weights.keys()
		var ws: Array = []
		var lead: int = _pick(adults, used, rng)
		if lead < 0:
			break
		for k in kinds:
			ws.append(float(weights[k]) * (float((c.get("rough_mult", {}) as Dictionary).get(k, 1.0)) if _rough(lead) else 1.0))
		var kind: String = str(_weighted(kinds, ws, rng))
		var th: Dictionary = _make(kind, lead, adults, used, rng)
		if th.is_empty():
			continue
		th["kind"] = kind
		th["day"] = SysUtil.day()
		th["touched"] = false
		threads.append(th)
		used[int(th["a"])] = true
		if int(th.get("b", -1)) >= 0:
			used[int(th["b"])] = true
	for t in threads:          # a debug line for whoever reads the log; nothing is shown to the player
		print("TOWN DRAMA %s: %s / %s" % [str(t["kind"]), Story.name_of(int(t["a"])), Story.name_of(int(t["b"])) if int(t.get("b", -1)) >= 0 else "-"])

static func _pick(pool: Array, used: Dictionary, rng: RandomNumberGenerator, not_id: int = -1) -> int:
	var free: Array = pool.filter(func(id): return not used.has(int(id)) and int(id) != not_id)
	return -1 if free.is_empty() else int(free[rng.randi_range(0, free.size() - 1)])

static func _weighted(items: Array, ws: Array, rng: RandomNumberGenerator):
	var total: float = 0.0
	for w in ws:
		total += float(w)
	var r: float = rng.randf() * total
	for i in items.size():
		r -= float(ws[i])
		if r <= 0.0:
			return items[i]
	return items[items.size() - 1]

## Living under one roof, or sharing a family name: household trouble is the family kind, not a feud.
static func _same_home(a: int, b: int) -> bool:
	var ta: Dictionary = Story.townies.get(a, {})
	var tb: Dictionary = Story.townies.get(b, {})
	if str(ta.get("home_prop", "")) != "" and str(ta.get("home_prop", "")) == str(tb.get("home_prop", "")):
		return true
	return Story.name_of(a).get_slice(" ", 1) != "" and Story.name_of(a).get_slice(" ", 1) == Story.name_of(b).get_slice(" ", 1)

static func _rough(tid: int) -> bool:
	var t: Dictionary = Story.townies.get(tid, {})
	var lot: String = str(HousingProps.get_prop(str(t.get("home_prop", ""))).get("lot", ""))
	if lot == "":
		return false
	var d: String = SoloDistricts.district_of(lot)
	return d != "" and SoloDistricts.roughness_of(d) >= float(cfg().get("rough_at", 0.6))

## One thread of `kind` led by `a`: the real states, or {} when the town has nobody fitting.
static func _make(kind: String, a: int, adults: Array, used: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var day: int = SysUtil.day()
	match kind:
		"feud":
			var b: int = _pick(adults, used, rng, a)
			if b < 0 or RelationshipBits.kin_bit(a, b) != "" or FamilyTree.spouse_of(a) == b or _same_home(a, b):
				return {}          # a family rift is its own kind
			RelationshipService.set_value(a, b, "friendship", -rng.randf_range(35.0, 60.0))
			RelationshipService.set_value(b, a, "friendship", -rng.randf_range(35.0, 60.0))
			RelationshipService.add_history(a, b, "fight", -0.8, a)
			RelationshipService.add_history(b, a, "insulted", -0.6, b)
			JusticeState.grudges["%d>%d" % [a, b]] = {"rage": rng.randf_range(0.2, 0.45), "since": day - rng.randi_range(20, 200), "warned": false, "vow": false}
			return {"a": a, "b": b}
		"affair":
			var partners: Array = RelationshipRomance.exclusive_partners(a)
			if partners.is_empty():
				return {}
			var o: int = _pick(adults.filter(func(x): return RomanceRules.allowed(a, int(x)) and not partners.has(int(x))), used, rng, a)
			if o < 0:
				return {}
			RelationshipService.set_value(a, o, "romance", rng.randf_range(40.0, 60.0))
			RelationshipService.set_value(o, a, "romance", rng.randf_range(40.0, 60.0))
			RelationshipService.set_value(a, o, "friendship", 35.0)
			RelationshipService.affairs.append({"cheater": a, "other": o, "victim": int(partners[0]), "day": day - rng.randi_range(10, 120)})
			return {"a": a, "b": o}
		"secret":
			var b2: int = _pick(adults, used, rng, a)
			var s: Array = RelationshipKnowledge.ensure_secrets(a)
			if b2 < 0 or s.is_empty():
				return {}
			RelationshipKnowledge.learn_secret(b2, a, int(s[rng.randi_range(0, s.size() - 1)]["id"]))
			return {"a": a, "b": b2}
		"debt":
			var sharks: Array = Story.alive_townies().map(func(t): return int(t["id"])).filter(func(id): return CrimeUnderLines.has(int(id), "racket") and int(id) != a)
			if sharks.is_empty():
				return {}
			var shark: int = int(sharks[rng.randi_range(0, sharks.size() - 1)])
			var p: int = rng.randi_range(60, 300)
			var r: Dictionary = CrimeUnderRacket._new("loan", shark, a, p, int(ceil(float(p) * 1.25)), day - rng.randi_range(1, 6))
			r["missed"] = 1
			RelationshipService.add_value(a, shark, "friendship", -10.0)
			return {"a": a, "b": shark}
		"crew":
			if not CrimeLifePath.join(a, "drift"):
				return {}
			CrimeLifePath.add_cred(a, rng.randf_range(5.0, 25.0))
			if rng.randf() < 0.4:
				JusticeState.probation[a] = day + rng.randi_range(20, 60)
			return {"a": a, "b": -1}
		"cold_case":
			var v: int = _pick(adults, used, rng, a)
			if v < 0:
				return {}
			var lot: int = int(Story.townies[v].get("lot", 1))
			var cs: Dictionary = CaseStore.create("burglary", a, v, "town:%d" % lot, {"trace": rng.randf_range(0.15, 0.4), "stolen_coins": rng.randi_range(40, 220), "public": true})
			cs["day"] = day - rng.randi_range(30, 150)
			cs["disc_day"] = int(cs["day"]) + 1
			cs["state"] = "cold"
			return {"a": a, "b": v}
		"business":
			var mine: Array = BusinessState.of_owner("townie", a).filter(func(bz): return bool(bz.get("open", false)))
			if mine.is_empty():
				return {}
			var bz: Dictionary = mine[0]
			bz["cash"] = -rng.randf_range(80.0, 300.0)
			bz["neg_days"] = rng.randi_range(4, 10)
			bz["rep"] = rng.randf_range(25.0, 40.0)
			bz["stars"] = rng.randf_range(2.0, 2.8)
			return {"a": a, "b": -1}
		"family":
			var kids: Array = FamilyTree.children_of(a).filter(func(k): return Story.townies.has(int(k)) and Story.stage_of(Story.townies[int(k)]) in ["adult", "elder"])
			var sp: int = FamilyTree.spouse_of(a)
			if not kids.is_empty() and (sp < 0 or rng.randf() < 0.6):
				var k2: int = int(kids[rng.randi_range(0, kids.size() - 1)])
				RelationshipService.set_value(a, k2, "friendship", -rng.randf_range(30.0, 50.0))
				RelationshipService.set_value(k2, a, "friendship", -rng.randf_range(30.0, 50.0))
				RelationshipService.add_history(k2, a, "fell_out", -0.9, k2)
				return {"a": a, "b": k2}
			if sp >= 0 and Story.townies.has(sp):
				Family.spouses.erase(a)
				Family.spouses.erase(sp)
				RelationshipBits.set_flag(a, sp, "spouse", false, false)
				RelationshipBits.set_flag(a, sp, "partner", false, false)
				RelationshipService.set_value(a, sp, "romance", -20.0)
				RelationshipService.set_value(sp, a, "romance", -20.0)
				RelationshipService.add_history(a, sp, "divorced", -0.7, a)
				return {"a": a, "b": sp}
			return {}
		"addiction":
			var subs: Array = CrimeUnderAddict.substances()
			if subs.is_empty() or not CrimeUnderAddict.try_onset(a, str(subs[rng.randi_range(0, subs.size() - 1)]), -1, true):
				return {}
			var ar: Dictionary = CrimeUnderState.addicts[a]
			ar["level"] = rng.randf_range(0.3, 0.6)
			ar["since"] = day - rng.randi_range(20, 120)
			return {"a": a, "b": -1}
		"tension":
			if not RelationshipRomance.exclusive_partners(a).is_empty():
				return {}
			var o2: int = _pick(adults.filter(func(x): return RomanceRules.allowed(a, int(x)) and RelationshipRomance.exclusive_partners(int(x)).is_empty()), used, rng, a)
			if o2 < 0:
				return {}
			RelationshipService.set_value(a, o2, "romance", rng.randf_range(18.0, 28.0))
			RelationshipService.set_value(o2, a, "romance", rng.randf_range(18.0, 28.0))
			RelationshipService.set_value(a, o2, "friendship", 25.0)
			RelationshipService.add_history(a, o2, "flirted", 0.4, a)
			return {"a": a, "b": o2}
	return {}

# ------------------------------------------------------------------ the player gets involved
## Daily: a thread the player is now part of (a friend of someone in it, or a grudge with them) goes into the life story once, with its cause.
static func on_day(_day: int) -> void:
	if threads.is_empty():
		return
	var pawn: int = Pawn.of()
	if pawn < 0:
		return
	var c: Dictionary = cfg()
	for t in threads:
		if bool(t["touched"]):
			continue
		for who in [int(t["a"]), int(t.get("b", -1))]:
			if who < 0:
				continue
			if RelationshipService.value(pawn, who, "friendship") >= float(c.get("involved_friendship", 30)) \
					or RelationshipService.grudge(pawn, who) >= float(c.get("involved_grudge", 0.2)):
				t["touched"] = true
				var line: String = str((c.get("ledger", {}) as Dictionary).get(str(t["kind"]), "Got caught up in {a}'s story."))
				line = line.replace("{who}", Story.name_of(who)).replace("{a}", Story.name_of(int(t["a"]))).replace("{b}", Story.name_of(int(t["b"])) if int(t["b"]) >= 0 else "")
				LifeLedger.add("drama", line, [pawn, who], false, 2)
				break

static func to_dict() -> Array:
	return threads.duplicate(true)

static func from_dict(a) -> void:
	reset()
	if a is Array:
		threads = (a as Array).duplicate(true)
