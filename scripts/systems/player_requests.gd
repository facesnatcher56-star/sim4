class_name PlayerRequests
extends RefCounted
## Task 48: the places where something used to happen to the pawn by itself and is now a question to the player (see PlayerPrompt). Each function
## returns true when the pawn is one of the people involved (the caller then does NOT do it automatically: it was asked, or is on cooldown) and false
## when it is an NPC pair (the old automatic behaviour stays). Answers have real consequences on the relationship.

static func _pair(a: int, b: int) -> Array:
	if Pawn.is_pawn_id(a):
		return [a, b]
	if Pawn.is_pawn_id(b):
		return [b, a]
	return []

## sweetheart / partner: the other asks "make it official?".
static func romance_step(a: int, b: int, step: String) -> bool:
	var p: Array = _pair(a, b)
	if p.is_empty():
		return false
	var type: String = "romance_" + step
	if PlayerPrompt.ready(type, p[0], p[1], 4):
		var pawn: int = int(p[0])
		var other: int = int(p[1])
		PlayerPrompt.ask(type, pawn, other, {}, func(ch):
			if str(ch) == "yes":
				RelationshipBits.set_flag(pawn, other, step)
				LifeLedger.choice("You and %s became %s." % [CrimePerson.name_of(other), "sweethearts" if step == "sweetheart" else "partners"], [pawn, other])
			else:
				RelationshipService.add_both(pawn, other, "romance", -4.0)
				LifeLedger.choice("You told %s you were not ready." % CrimePerson.name_of(other), [pawn, other]), "no")
	return true

static func proposal(a: int, b: int) -> bool:
	var p: Array = _pair(a, b)
	if p.is_empty():
		return false
	if PlayerPrompt.ready("proposal", p[0], p[1], 6):
		var pawn: int = int(p[0])
		var other: int = int(p[1])
		PlayerPrompt.ask("proposal", pawn, other, {}, func(ch):
			if str(ch) == "yes":
				var res: String = FamilyMarriage.propose_marriage(pawn, other)
				LifeLedger.choice("You said yes to %s." % CrimePerson.name_of(other), [pawn, other])
				if res == "too_soon":
					RelationshipService.add_both(pawn, other, "romance", 4.0)
			else:
				RelationshipService.add_both(pawn, other, "romance", -12.0)
				LifeLedger.choice("You turned down %s's proposal." % CrimePerson.name_of(other), [pawn, other]), "no")
	return true

static func wedding(a: int, b: int) -> bool:
	var p: Array = _pair(a, b)
	if p.is_empty():
		return false
	if PlayerPrompt.ready("wedding", p[0], p[1], 3):
		var pawn: int = int(p[0])
		var other: int = int(p[1])
		PlayerPrompt.ask("wedding", pawn, other, {}, func(ch):
			if str(ch) == "yes":
				FamilyMarriage.marry(pawn, other)
				SysUtil.notify("%s and %s had a small wedding at home." % [CrimePerson.name_of(pawn), CrimePerson.name_of(other)], "relationship")
				LifeLedger.choice("You married %s." % CrimePerson.name_of(other), [pawn, other]), "no")
	return true

static func baby(a: int, b: int) -> bool:
	var p: Array = _pair(a, b)
	if p.is_empty():
		return false
	if PlayerPrompt.ready("baby", p[0], p[1], 7):
		var pawn: int = int(p[0])
		var other: int = int(p[1])
		PlayerPrompt.ask("baby", pawn, other, {}, func(ch):
			if str(ch) == "yes":
				Aging.try_for_baby(pawn, other)
				LifeLedger.choice("You tried for a baby with %s." % CrimePerson.name_of(other), [pawn, other]), "no")
	return true

## A party invitation to the pawn: Go / Not tonight. true = the pawn was asked (no toast).
static func party(townie_id: int, folk_id: int, invite_id: int) -> bool:
	if not Pawn.is_pawn_id(folk_id):
		return false
	var ok: bool = PlayerPrompt.ask("party_invite", folk_id, townie_id, {}, func(ch):
		StoryVisits.respond_invite(invite_id, str(ch) == "yes")
		if str(ch) != "yes":
			RelationshipService.add_both(folk_id, townie_id, "friendship", -1.0), "no")
	return ok

# ------------------------------------------------------------------ a friend in need (real cause: no job and no money)
static func on_day(_day: int) -> void:
	if not SoloHome.active:
		return
	var pawn: int = Pawn.of()
	var pf = SysUtil.folk(pawn)
	if pf == null or str(pf.age_stage) not in ["adult", "elder"] or SysUtil.is_away(pf):
		return
	var have: int = Economy.balance(int(pf.household_id))
	if have < 20:
		return
	for t in Story.alive_townies():
		var tid: int = int(t["id"])
		if Story.stage_of(t) not in ["adult", "elder"] or int(t["coins"]) >= 15 or str(t.get("career", "")) != "":
			continue
		if RelationshipService.value(pawn, tid, "friendship") < 40.0 or not PlayerPrompt.ready("loan", pawn, tid, 7):
			continue
		if not SysUtil.chance(0.3):
			continue
		var amount: int = mini(30, have / 2)
		PlayerPrompt.ask("loan", pawn, tid, {"amount": amount}, func(ch):
			var give: int = amount if str(ch) == "lend" else (amount / 2 if str(ch) == "half" else 0)
			if give > 0 and Economy.spend(int(pf.household_id), give, "lent to a friend"):
				t["coins"] = int(t["coins"]) + give
				RelationshipService.add_both(pawn, tid, "friendship", 10.0 if give == amount else 5.0)
				LifeLedger.choice("You lent %s %d coins." % [CrimePerson.name_of(tid), give], [pawn, tid])
			elif str(ch) == "no":
				RelationshipService.add_both(pawn, tid, "friendship", -6.0)
				LifeLedger.choice("You refused to lend %s money." % CrimePerson.name_of(tid), [pawn, tid]), "no")
		return          # one request a day at most
