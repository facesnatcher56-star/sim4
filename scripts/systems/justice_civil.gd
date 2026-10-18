class_name JusticeCivil
extends RefCounted
## Civil cases (lighter than crime): LAWSUITS after an injury on someone's property (game event `accident_on_property` from the accidents
## track), DIVORCE settlements and custody (event `divorced`), INHERITANCE disputes (event `died`), SMALL CLAIMS for stolen or damaged things.
## A civil case is a small record in JusticeState.civil: {id, kind, plaintiff, defendant, amount, state, due_day, result, text}.
## They settle a few days later by a scored roll (CivilScore); only household cases toast, the rest go to the Chronicle.

static func cfg() -> Dictionary:
	return JusticeState.sect("civil")

static func file(kind: String, plaintiff: int, defendant: int, amount: int, text: String, extra: Dictionary = {}) -> Dictionary:
	var k: Dictionary = cfg()
	var id: int = 1
	for o in JusticeState.civil:
		id = maxi(id, int(o["id"]) + 1)
	var c: Dictionary = {"id": id, "kind": kind, "plaintiff": plaintiff, "defendant": defendant, "amount": amount, "state": "filed", "filed_day": SysUtil.day(),
		"due_day": SysUtil.day() + JusticeState.rng.randi_range(int(k.get("days", [4, 7])[0]), int(k.get("days", [4, 7])[1])), "result": "", "text": text}
	c.merge(extra, true)
	JusticeState.civil.append(c)
	while JusticeState.civil.size() > 80:
		JusticeState.civil.pop_front()
	if CrimePerson.is_player(plaintiff) or CrimePerson.is_player(defendant):
		SysUtil.notify(text, "story")
	ChronicleHook.note("civil_" + kind, text, [plaintiff, defendant], "", 1, false)
	return c

# ------------------------------------------------------------------ triggers
static func on_game_event(ev: String, p: Dictionary) -> void:
	if not JusticeState.enabled:
		return
	match ev:
		"accident_on_property":
			_lawsuit(p)
		"divorced":
			_divorce(int(p.get("folk_id", -1)), int(p.get("target_id", -1)))
		"died":
			_inheritance(int(p.get("folk_id", -1)))

static func _lawsuit(p: Dictionary) -> void:
	var k: Dictionary = cfg().get("lawsuit", {})
	var victim: int = int(p.get("victim", -1))
	var owner_hid: int = int(p.get("owner", 0))
	var def: int = -1
	for r in SysUtil.residents():
		if int(r.household_id) == owner_hid:
			def = int(r.id)
			break
	if victim < 0 or def < 0 or not JusticeState.chance(float(k.get("chance", 0.3)) * (2.0 if bool(p.get("fatal", false)) else 1.0)):
		return
	var amt: int = int(k.get("amount", 250)) * (3 if bool(p.get("fatal", false)) else 1)
	file("lawsuit", victim, def, amt, "%s is suing %s for %d coins after getting hurt at their home." % [CrimePerson.name_of(victim), CrimePerson.name_of(def), amt])

static func _divorce(a: int, b: int) -> void:
	if a < 0 or b < 0:
		return
	var coins_a: int = CrimePerson.coins(a)
	var coins_b: int = CrimePerson.coins(b)
	var pot: int = coins_a + coins_b
	# the one who cheated pays more; skill of an (implied) lawyer gives a few percent either way
	var share_a: float = 0.5
	for ev in RelationshipService.history_for(a, b):
		if str(ev.get("kind", "")) == "cheated":
			share_a += 0.1 if int(ev.get("by", -1)) == b else -0.1
	share_a = clampf(share_a + (CrimePerson.charisma(a) - CrimePerson.charisma(b)) * 0.05, 0.25, 0.75)
	var kids: Array = []
	for c in Aging.children_of(a):
		if Aging.children_of(b).has(c):
			kids.append(int(c))
	var custody: int = a if CrimePerson.coins(a) >= CrimePerson.coins(b) else b
	var rec: Dictionary = file("divorce", a, b, int(float(pot) * share_a), "The court is settling the divorce of %s and %s." % [CrimePerson.name_of(a), CrimePerson.name_of(b)],
		{"share_a": share_a, "pot": pot, "children": kids, "custody": custody})
	rec["transfer"] = int(float(pot) * share_a) - coins_a      # + = b pays a

static func _inheritance(dead: int) -> void:
	var k: Dictionary = cfg().get("inheritance", {})
	var heirs: Array = []
	for o in CrimePerson.close_ones(dead):
		if CrimePerson.alive(int(o)):
			heirs.append(int(o))
	var estate: int = int(Story.townies.get(dead, {}).get("coins", 0))
	if heirs.size() < 2 or estate < int(k.get("min_estate", 300)) or not JusticeState.chance(float(k.get("chance", 0.1))):
		return
	file("inheritance", int(heirs[0]), int(heirs[1]), estate / 2, "%s and %s are fighting over what %s left behind." % [CrimePerson.name_of(int(heirs[0])), CrimePerson.name_of(int(heirs[1])), CrimePerson.name_of(dead)])

## Small claims: stolen or damaged property that nobody was convicted for.
static func small_claim(plaintiff: int, defendant: int, amount: int, reason: String) -> Dictionary:
	return file("small_claims", plaintiff, defendant, amount, "%s took %s to small claims court over %s." % [CrimePerson.name_of(plaintiff), CrimePerson.name_of(defendant), reason])

# ------------------------------------------------------------------ settling
static func score(c: Dictionary) -> float:
	var pl: int = int(c["plaintiff"])
	var df: int = int(c["defendant"])
	var s: float = 0.0
	s += (CrimePerson.charisma(pl) - CrimePerson.charisma(df)) * 0.2
	s += (CrimePerson.reputation(pl) - CrimePerson.reputation(df)) / 200.0
	if CrimePerson.has_record(df):
		s += 0.15
	if CrimePerson.has_record(pl):
		s -= 0.15
	if CrimePerson.coins(pl) >= 200:
		s += 0.1                                  # can afford a better lawyer
	if CrimePerson.coins(df) >= 200:
		s -= 0.1
	return s

static func on_day() -> void:
	for c in JusticeState.civil:
		if str(c["state"]) == "filed" and SysUtil.day() >= int(c["due_day"]):
			settle(c)

static func settle(c: Dictionary) -> void:
	var pl: int = int(c["plaintiff"])
	var df: int = int(c["defendant"])
	var k: Dictionary = cfg()
	c["state"] = "settled"
	if not (CrimePerson.alive(pl) and CrimePerson.alive(df)):
		c["result"] = "dropped"
		return
	var amount: int = int(c["amount"])
	var text: String = ""
	match str(c["kind"]):
		"divorce":
			var tr: int = int(c.get("transfer", 0))
			if tr > 0:
				CrimePerson.add_coins(pl, CrimePerson.pay(df, tr, "divorce settlement"), "divorce settlement")
			elif tr < 0:
				CrimePerson.add_coins(df, CrimePerson.pay(pl, -tr, "divorce settlement"), "divorce settlement")
			c["result"] = "settled"
			text = "The divorce of %s and %s was settled%s." % [CrimePerson.name_of(pl), CrimePerson.name_of(df),
				(". %s has the children" % CrimePerson.name_of(int(c.get("custody", pl)))) if not (c.get("children", []) as Array).is_empty() else ""]
			SysUtil.game_event("custody_decided", {"folk_id": int(c.get("custody", pl)), "children": c.get("children", [])})
		_:
			var p: float = clampf(float(k.get("base_win", 0.55)) + score(c), 0.1, 0.9)
			if JusticeState.chance(p):
				var paid: int = CrimePerson.pay(df, int(float(amount) * (0.6 if JusticeState.chance(float(k.get("settle_share", 0.5))) else 1.0)), "court award")
				CrimePerson.add_coins(pl, paid, "court award")
				c["result"] = "plaintiff"
				text = "%s won %d coins from %s in court." % [CrimePerson.name_of(pl), paid, CrimePerson.name_of(df)]
				RelationshipService.add_both(pl, df, "friendship", -10.0)
			else:
				c["result"] = "defendant"
				text = "The court sided with %s against %s." % [CrimePerson.name_of(df), CrimePerson.name_of(pl)]
				RelationshipService.add_both(pl, df, "friendship", -5.0)
	c["text"] = text
	ChronicleHook.note("civil_" + str(c["kind"]), text, [pl, df], "", 1, false)
	if CrimePerson.is_player(pl) or CrimePerson.is_player(df):
		SysUtil.notify(text, "story")

## Handler of incident `small_claims` (data/incidents/09_justice.json): a neighbour dispute over damaged or borrowed property.
static func on_small_claim(ctx: Dictionary, _args: Dictionary) -> Dictionary:
	if not JusticeState.enabled:
		return {"text": ""}
	var subj = ctx["subject"]
	var head = subj.head()
	if head == null:
		return {"text": ""}
	var plaintiff: int = int(head.id)
	var pool: Array = CrimePerson.townies_only().filter(func(p): return p != plaintiff and CrimePerson.is_adult(p))
	if pool.is_empty():
		return {"text": ""}
	var defendant: int = int(pool[JusticeState.rng.randi_range(0, pool.size() - 1)])
	small_claim(plaintiff, defendant, JusticeState.rng.randi_range(40, 140), "a damaged fence")
	return {"text": ""}
