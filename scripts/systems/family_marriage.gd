class_name FamilyMarriage
extends RefCounted
## Engagements, marriage, surnames and divorce.

# ------------------------------------------------------------------ marriage
static func _pair_ro_fr(a: int, b: int) -> Dictionary:
	return {"romance": minf(RelationshipService.value(a, b, "romance"), RelationshipService.value(b, a, "romance")),
		"friendship": minf(RelationshipService.value(a, b, "friendship"), RelationshipService.value(b, a, "friendship"))}

static func is_engaged(a: int, b: int) -> bool:
	return Family.engaged.has(SysUtil.pair_key(a, b))

## Handles the `propose` interaction: partner -> engaged; everything else keeps the old sweetheart -> partner path.
## Returns "engaged" | "already_engaged" | "already_married" | "declined" | "too_soon" | "no_bond" | "accepted" (became partners).
static func on_propose(a: int, b: int) -> String:
	if FamilyTree.spouse_of(a) == b:
		return "already_married"
	if is_engaged(a, b):
		return "already_engaged"
	if RelationshipBits.has_flag(a, b, "partner"):
		return propose_marriage(a, b)
	return RelationshipBits.propose(a, b)

static func propose_marriage(a: int, b: int) -> String:
	if FamilyTree.spouse_of(a) == b:
		return "already_married"
	if is_engaged(a, b):
		return "already_engaged"
	if not RelationshipBits.has_flag(a, b, "partner"):
		return "no_bond"
	if FamilyTree.spouse_of(a) >= 0 or FamilyTree.spouse_of(b) >= 0 or FamilyTree.fiance_of(a) >= 0 or FamilyTree.fiance_of(b) >= 0:
		return "declined"
	var mc: Dictionary = Family.cfg().get("marriage", {})
	var v: Dictionary = _pair_ro_fr(a, b)
	if float(v["romance"]) < float(mc.get("min_romance", 70)) or float(v["friendship"]) < float(mc.get("min_friendship", 50)):
		return "too_soon" if float(v["romance"]) >= 50.0 else "declined"
	Family.engaged[SysUtil.pair_key(a, b)] = {"a": a, "b": b, "since": SysUtil.day()}
	for x in [a, b]:
		var f = SysUtil.folk(int(x))
		if f != null:
			f.add_buff(str(mc.get("engaged_buff", "engaged")))
	SysUtil.notify("%s and %s are engaged!" % [Family.name_of(a), Family.name_of(b)], "relationship")
	SysUtil.game_event("engaged", {"folk_id": a, "target_id": b})
	return "engaged"

static func break_engagement(a: int, b: int, reason: String = "") -> void:
	var k: String = SysUtil.pair_key(a, b)
	if not Family.engaged.has(k):
		return
	Family.engaged.erase(k)
	var eb: String = str(Family.cfg().get("marriage", {}).get("engaged_buff", "engaged"))
	for x in [a, b]:
		var f = SysUtil.folk(int(x))
		if f != null:
			f.remove_buff(eb)
	SysUtil.notify("%s and %s called off the engagement.%s" % [Family.name_of(a), Family.name_of(b), (" (" + reason + ")") if reason != "" else ""], "relationship")
	SysUtil.game_event("engagement_broken", {"folk_id": a, "target_id": b})

static func _surname(full: String) -> String:
	var parts: PackedStringArray = full.split(" ")
	return parts[parts.size() - 1] if parts.size() > 1 else ""

static func _given(full: String) -> String:
	var parts: PackedStringArray = full.split(" ")
	return parts[0]

static func _set_name(id: int, new_name: String) -> void:
	var f = SysUtil.folk(id)
	if f != null:
		f.name = new_name
	elif Story.townies.has(id):
		Story.townies[id]["name"] = new_name
	Family.note_person(id, new_name)

## modes: "none" | "actor" (the other takes the actor's surname) | "target" | "hyphen" (actor's surname hyphenated with the other's).
static func apply_surname(a: int, b: int, mode: String) -> void:
	var na: String = Family.name_of(a)
	var nb: String = Family.name_of(b)
	var sa: String = _surname(na)
	var sb: String = _surname(nb)
	match mode:
		"actor":
			if sa != "":
				_set_name(b, "%s %s" % [_given(nb), sa])
		"target":
			if sb != "":
				_set_name(a, "%s %s" % [_given(na), sb])
		"hyphen":
			if sa != "" and sb != "" and sa != sb:
				_set_name(b, "%s %s-%s" % [_given(nb), sa, sb])

## Wedding. `a` is the proposer / actor. Returns true when they are now married.
static func marry(a: int, b: int, surname_mode: String = "", force: bool = false) -> bool:
	var mc: Dictionary = Family.cfg().get("marriage", {})
	var key: String = SysUtil.pair_key(a, b)
	if not Family.engaged.has(key) and not force:
		return false
	if FamilyTree.spouse_of(a) >= 0 or FamilyTree.spouse_of(b) >= 0:
		return false
	Family.engaged.erase(key)
	Family.spouses[a] = b
	Family.spouses[b] = a
	for x in [a, b]:
		var f = SysUtil.folk(int(x))
		if f != null:
			f.remove_buff(str(mc.get("engaged_buff", "engaged")))
			f.add_buff(str(mc.get("married_buff", "married")))
			f.add_buff(str(mc.get("newlywed_buff", "newlywed")))
	RelationshipService.add_both(a, b, "romance", float(mc.get("wedding_romance", 10)))
	RelationshipService.add_both(a, b, "friendship", float(mc.get("wedding_friendship", 10)))
	RelationshipBits.set_flag(a, b, "spouse", true, false)
	if surname_mode == "":
		surname_mode = str(mc.get("surname", "none"))
	apply_surname(a, b, surname_mode)
	if bool(mc.get("merge_households", true)):
		_merge_households(a, b)
	SysUtil.notify("%s and %s are married!" % [Family.name_of(a), Family.name_of(b)], "relationship")
	SysUtil.game_event("married", {"folk_id": a, "target_id": b})
	return true

## The partner who does not live with the other moves into the actor's household.
static func _merge_households(a: int, b: int) -> void:
	var fa = SysUtil.folk(a)
	var fb = SysUtil.folk(b)
	if fa != null and fb != null:
		if int(fa.household_id) == int(fb.household_id):
			return
		var hid: int = int(fa.household_id)
		if int(fb.household_id) > 0 and not SysUtil.is_resident(fa):
			return
		_move_household(fb, hid)
	elif fa != null and fb == null and Story.townies.has(b):
		FamilyHousehold.invite_to_household(b, int(fa.household_id))
	elif fb != null and fa == null and Story.townies.has(a):
		FamilyHousehold.invite_to_household(a, int(fb.household_id))

## Change a folk's household, carrying coins / objects when their old household becomes empty.
static func _move_household(f, new_hid: int) -> void:
	var old: int = int(f.household_id)
	f.household_id = new_hid
	if f.has_meta("visitor"):
		f.remove_meta("visitor")
	if old > 0 and old != new_hid:
		var left: int = 0
		for o in SysUtil.residents():
			if int(o.household_id) == old:
				left += 1
		if left == 0:
			var coins: int = WorldIface.get_coins(old)
			if coins > 0:
				WorldIface.add_coins(old, -coins)
				WorldIface.add_coins(new_hid, coins)
			for ob in Economy.objects_of(old):
				Economy.owner[int(ob.id)] = new_hid

static func divorce(a: int, b: int, mover: int = -1) -> bool:
	if FamilyTree.spouse_of(a) != b:
		return false
	var dc: Dictionary = Family.cfg().get("divorce", {})
	Family.spouses.erase(a)
	Family.spouses.erase(b)
	Family._push(Family.exes, a, b)
	Family._push(Family.exes, b, a)
	var mb: String = str(Family.cfg().get("marriage", {}).get("married_buff", "married"))
	var nl: String = str(Family.cfg().get("marriage", {}).get("newlywed_buff", "newlywed"))
	for x in [a, b]:
		var f = SysUtil.folk(int(x))
		if f != null:
			f.remove_buff(mb)
			f.remove_buff(nl)
			f.add_buff(str(dc.get("buff", "divorced")))
	RelationshipBits.set_flag(a, b, "spouse", false, false)
	RelationshipService.add_both(a, b, "friendship", -float(dc.get("friendship_loss", 35)))
	RelationshipService.add_both(a, b, "romance", -float(dc.get("romance_loss", 80)))
	RelationshipService.add_history(a, b, "divorce", -1.0, a)
	SysUtil.notify("%s and %s got divorced." % [Family.name_of(a), Family.name_of(b)], "relationship")
	SysUtil.game_event("divorced", {"folk_id": a, "target_id": b})
	# one of them moves out when they shared a home
	var fa = SysUtil.folk(a)
	var fb = SysUtil.folk(b)
	if fa != null and fb != null and int(fa.household_id) == int(fb.household_id) and int(fa.household_id) > 0:
		var leaver: int = mover if mover in [a, b] else b
		FamilyHousehold.move_out(leaver, float(dc.get("coin_share", 0.5)))
	return true
