class_name CrimeDomestic
extends RefCounted
## Domestic violence aftermath (task 19.1): what changes after a shove or a hit between household members, family or partners.
## - The household's own victim gets a clear prompt with options: call the police, make them leave (separate / divorce), leave with the kids, or stay.
## - A townie victim reports with a chance (data/justice.json domestic.domestic_report) and may end the relationship (victim_leaves).
## - The case is flagged `domestic`; an arrest brings a protective order (JusticeOrders), a conviction a longer one.
## - Tension drops after the incident (a cool-off), so the same row is not instantly repeated.
## Non-graphic by design: notices say "shoved" or "hit", never more.

static func cfg() -> Dictionary:
	return JusticeState.sect("domestic")

static func is_domestic(a: int, b: int) -> bool:
	var ha: int = CrimePerson.hid(a)
	return (ha > 0 and ha == CrimePerson.hid(b)) or CrimePerson.is_kin_or_partner(a, b) or RelationshipRomance.exclusive_partners(a).has(b)

## Called by CrimeAssault.fight after the effects. Fills out["case"] when a case was opened.
static func after(aggressor: int, victim: int, kind: String, sev: int, text: String, out: Dictionary) -> void:
	var domestic: bool = is_domestic(aggressor, victim)
	var cool: float = float(JusticeState.sect("assault").get("cool_off_tension", 35))
	RelationshipRomance.add_tension(aggressor, victim, -cool)
	RelationshipRomance.add_tension(victim, aggressor, -cool)
	var fa = CrimePerson.folk(aggressor)
	if fa != null:
		fa.add_buff("shaken")
	if CrimePerson.is_player(victim):
		_ask_household(aggressor, victim, kind, sev, text, domestic, out)
		return
	var p: float = float(cfg().get("domestic_report", 0.6)) if domestic else float(JusticeState.sect("assault").get("police_called", 0.5))
	if JusticeState.chance(p):
		out["case"] = CrimeAssault.report(aggressor, victim, sev, text, domestic, kind)
	else:
		ChronicleHook.note("fight", text, [aggressor, victim], CrimePerson.home_key(victim), 1, false)
		if CrimePerson.is_player(aggressor):
			SysUtil.notify(text, "bad")
	if domestic:
		victim_reacts(aggressor, victim, kind)

# ------------------------------------------------------------------ the household's choice
static func _ask_household(aggressor: int, victim: int, kind: String, sev: int, text: String, domestic: bool, out: Dictionary) -> void:
	SysUtil.notify(text, "bad")
	var opts: Array = [{"id": "police", "label": "Call the police"}]
	if domestic and (CrimePerson.hid(aggressor) == CrimePerson.hid(victim) or RelationshipRomance.exclusive_partners(victim).has(aggressor)):
		opts.append({"id": "separate", "label": "Make %s leave" % CrimePerson.name_of(aggressor)})
		if not dependents(victim).is_empty():
			opts.append({"id": "leave", "label": "Leave with the kids"})
	opts.append({"id": "stay", "label": "Stay and talk"})
	var body: String = "%s What should %s do?" % [text, CrimePerson.name_of(victim)]
	JusticePlayer.ask(victim, "Trouble at home", body, opts, func(ch): _household_choice(str(ch), aggressor, victim, kind, sev, text, domestic, out), "police")

static func _household_choice(ch: String, aggressor: int, victim: int, kind: String, sev: int, text: String, domestic: bool, out: Dictionary) -> void:
	match ch:
		"police":
			out["case"] = CrimeAssault.report(aggressor, victim, sev, text, domestic, kind)
		"separate":
			separate(victim, aggressor)
		"leave":
			move_out_with_kids(victim, aggressor)
		_:
			ChronicleHook.note("fight", text, [aggressor, victim], CrimePerson.home_key(victim), 1, false)

## Children (under 13, in the same household) that depend on `pid`.
static func dependents(pid: int) -> Array:
	var out: Array = []
	var h: int = CrimePerson.hid(pid)
	for c in Aging.children_of(pid):
		if h > 0 and CrimePerson.hid(int(c)) == h and CrimePerson.stage(int(c)) in ["baby", "toddler", "child"]:
			out.append(int(c))
	return out

## The aggressor goes: a spouse is divorced (the aggressor moves out), a partner is left, otherwise they move out of the shared home.
static func separate(victim: int, aggressor: int) -> void:
	if FamilyTree.spouse_of(victim) == aggressor:
		FamilyMarriage.divorce(victim, aggressor, aggressor)
	elif RelationshipRomance.exclusive_partners(victim).has(aggressor):
		RelationshipRomance.breakup(victim, aggressor, "violence", 1.5)
	if CrimePerson.hid(aggressor) > 0 and CrimePerson.hid(aggressor) == CrimePerson.hid(victim) and CrimePerson.folk(aggressor) != null:
		FamilyHousehold.move_out(aggressor, 0.3)
	JusticeState.count("separations")
	ChronicleHook.note("separation", "%s and %s separated after the trouble at home." % [CrimePerson.name_of(victim), CrimePerson.name_of(aggressor)], [victim, aggressor], CrimePerson.home_key(victim), 3, true)

## The victim and their young children move out together (a divorce when married).
static func move_out_with_kids(victim: int, aggressor: int) -> void:
	var kids: Array = dependents(victim)
	if FamilyTree.spouse_of(victim) == aggressor:
		FamilyMarriage.divorce(victim, aggressor, victim)
	elif CrimePerson.folk(victim) != null and CrimePerson.hid(victim) > 0:
		FamilyHousehold.move_out(victim, 0.4)
	for kid in kids:
		if CrimePerson.folk(int(kid)) != null:
			FamilyHousehold.move_out(int(kid), 0.0, false, true)
	JusticeState.count("victims_left")
	ChronicleHook.note("separation", "%s left %s and took the children." % [CrimePerson.name_of(victim), CrimePerson.name_of(aggressor)] if not kids.is_empty()
		else "%s left %s." % [CrimePerson.name_of(victim), CrimePerson.name_of(aggressor)], [victim, aggressor], CrimePerson.home_key(victim), 3, true)

## A victim that is not the player's: sometimes ends it (divorce, breakup, or cuts contact).
static func victim_reacts(aggressor: int, victim: int, kind: String) -> void:
	var p: float = float((cfg().get("victim_leaves", {}) as Dictionary).get(kind, 0.1))
	if not JusticeState.chance(p):
		return
	JusticeState.count("victims_left")
	if FamilyTree.spouse_of(victim) == aggressor:
		FamilyMarriage.divorce(victim, aggressor, aggressor)
	elif RelationshipRomance.exclusive_partners(victim).has(aggressor):
		RelationshipRomance.breakup(victim, aggressor, "violence", 1.5)
	else:
		RelationshipService.add_both(victim, aggressor, "friendship", -25.0)
	ChronicleHook.note("separation", "%s ended things with %s after being %s." % [CrimePerson.name_of(victim), CrimePerson.name_of(aggressor),
		"shoved" if kind == "shove" else "hit"], [victim, aggressor], CrimePerson.home_key(victim), 3, true)
