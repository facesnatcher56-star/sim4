class_name EventServices
extends RefCounted
## The handlers (PlaceHandlers) of the family and social events (task 14), all at a real place with a price:
##   wedding         a ceremony for an ENGAGED person (FamilyMarriage.marry; RomanceRules.allowed still guards it): guests bring presents, the couple glow
##   birthday_party  within a few days of the host's birthday, once a year: friends come, bring presents, everyone is happier
##   baby_shower     for a pregnant host or the partner of one
##   funeral         for a family member or friend who died in the last 10 days: the grief is eased a little for everyone who comes (children never lose their
##                   place at the service, the tone is quiet and non-graphic)
##   reunion         the host's relatives get together: friendship with each, a happy memory
##   mingle          a block party or a parade: some friendly words with a few neighbours (townies)
## Guests are the host's contacts (EventState.guests); each comes with the chance of PhoneCmd.accept_chance; the host pays the venue (the service price)
## and `per_guest` for every guest who comes (what they can afford). Townies are statistical: a friendship change and nothing more.

static func ec() -> Dictionary:
	return LifeDefs.cfg("events")

static func _pair_bit(id: int) -> int:
	return FamilyTree.fiance_of(id)

static func _grave_for(id: int) -> Dictionary:
	var best: Dictionary = {}
	for r in Graves.list():
		var dead: int = int(r.get("folk_id", -1))
		if dead < 0 or EventState.funerals.has(dead) or SysUtil.day() - int(r.get("died", -99)) > int(ec().get("funeral_days", 10)):
			continue
		if DeathCauses.closeness(id, dead) > 0.0 and (best.is_empty() or int(r["died"]) > int(best["died"])):
			best = r
	return best

static func _birthday_window(id: int) -> bool:
	var b: int = Aging.birth_doy(id)
	if b < 0:
		return false
	var yd: int = Aging.year_days()
	var d: int = Aging.doy(SysUtil.day())
	return posmod(b - d, yd) <= int(ec().get("birthday_before", 2)) or posmod(d - b, yd) <= int(ec().get("birthday_after", 3))

static func check(handler: String, f, _pid: String, _sid: String, _svc: Dictionary) -> String:
	var id: int = int(f.id)
	match handler:
		"wedding":
			var fi: int = _pair_bit(id)
			if fi < 0:
				return "%s is not engaged." % f.name
			if not RomanceRules.allowed(id, fi):
				return "They cannot marry."
			if PhoneCmd.unreachable(fi) != "":
				return PhoneCmd.unreachable(fi)
		"birthday_party":
			if not _birthday_window(id):
				return "A birthday party is for the days around a birthday."
			if EventState.done_this_year(id, "birthday"):
				return "%s already had a party this year." % f.name
		"baby_shower":
			var expecting: bool = Aging.pregnancies.has(id)
			for p in RelationshipBits.others_with_bit(id, "partner") + RelationshipBits.others_with_bit(id, "spouse"):
				expecting = expecting or Aging.pregnancies.has(int(p))
			if not expecting:
				return "A baby shower needs a baby on the way."
			if EventState.done_this_year(id, "shower"):
				return "There has been a shower already."
		"funeral":
			if _grave_for(id).is_empty():
				return "There is no funeral to hold."
		"reunion":
			if RelationshipBits.others_with_bit(id, "family").filter(func(x): return PhoneCmd.is_person(int(x))).size() < 2:
				return "A reunion needs at least two relatives."
			if EventState.done_this_year(id, "reunion"):
				return "The family got together this year already."
	return ""

## Who comes: the invited guests, each with the chance of accepting (`bonus` raises it).
static func attendees(id: int, invited: Array, bonus: float = 0.25) -> Array:
	var out: Array = []
	for g in invited:
		if PhoneState.rng.randf() < clampf(PhoneCmd.accept_chance(id, int(g)) + bonus, 0.05, 0.98):
			out.append(int(g))
	return out

static func _cheer(guests: Array, host: int, friendship: float, social: float) -> void:
	for g in guests:
		RelationshipService.add_both(host, int(g), "friendship", friendship)
		var gf = SysUtil.folk(int(g))
		if gf != null and SysUtil.is_resident(gf):
			gf.add_to_stat("social", social)
			gf.add_to_stat("fun", social * 0.5)

static func _pay_guests(f, n: int, per_guest: int, reason: String) -> int:
	var cost: int = n * per_guest
	var bal: int = Economy.balance(int(f.household_id))
	if cost > bal:
		cost = bal
	if cost > 0:
		Economy.spend(int(f.household_id), cost, reason)
	return cost

static func _gifts(f, n: int, lo: int, hi: int, reason: String) -> int:
	var total := 0
	for _i in n:
		total += PhoneState.rng.randi_range(lo, hi)
	if total > 0:
		Economy.deposit(int(f.household_id), total, reason)
	return total

static func finish(handler: String, f, pid: String, sid: String, svc: Dictionary) -> Dictionary:
	var a: Dictionary = svc.get("args", {})
	var id: int = int(f.id)
	var place: String = Places.label(pid)
	var invited: Array = []
	if a.has("guests"):
		invited = EventState.guests(id, int(a["guests"]), float(a.get("min_friendship", 10.0)))
	match handler:
		"wedding":
			var fi: int = _pair_bit(id)
			invited.erase(fi)
			var came: Array = attendees(id, invited)
			if not FamilyMarriage.marry(id, fi):
				return {"text": "The wedding could not go ahead.", "kind": "warn"}
			_pay_guests(f, came.size(), int(a.get("per_guest", 6)), "wedding: guests")
			var gifts: int = _gifts(f, came.size(), 10, 25, "wedding presents")
			_cheer(came, id, 3.0, 20.0)
			for x in [id, fi]:
				var pf = SysUtil.folk(int(x))
				if pf != null:
					pf.add_buff("bonded_glow")
					pf.add_to_stat("fun", 40.0)
					pf.add_to_stat("social", 30.0)
			var text := "%s and %s were married at %s with %d guest%s and %d coins of presents." % [f.name, SysUtil.folk_name(fi), place, came.size(), "" if came.size() == 1 else "s", gifts]
			LifeNote.say("wedding_party", text, [id, fi], 2, false)
			return {"text": text}
		"birthday_party":
			var came2: Array = attendees(id, invited)
			EventState.mark(id, "birthday")
			var cost: int = _pay_guests(f, came2.size(), int(a.get("per_guest", 6)), "birthday party")
			var gifts2: int = _gifts(f, came2.size(), 4, 12, "birthday presents")
			_cheer(came2, id, 3.0, 20.0)
			f.add_to_stat("fun", 20.0 + 6.0 * float(came2.size()))
			f.add_to_stat("social", 15.0 + 6.0 * float(came2.size()))
			f.add_buff("party_buzz")
			LifeFame.add(id, 0.3 * float(came2.size()))
			var text2 := "%s's birthday party at %s: %d friend%s came and brought %d coins of presents." % [f.name, place, came2.size(), "" if came2.size() == 1 else "s", gifts2]
			LifeNote.say("birthday_party", text2, [id], 1, false)
			return {"text": text2}
		"baby_shower":
			var came3: Array = attendees(id, invited)
			EventState.mark(id, "shower")
			_pay_guests(f, came3.size(), int(a.get("per_guest", 5)), "baby shower")
			var gifts3: int = _gifts(f, came3.size(), 8, 20, "baby shower presents")
			_cheer(came3, id, 3.0, 16.0)
			f.add_to_stat("fun", 25.0)
			f.add_buff("cheered_up")
			var text3 := "A baby shower for %s at %s: %d guest%s and %d coins of presents for the little one." % [f.name, place, came3.size(), "" if came3.size() == 1 else "s", gifts3]
			LifeNote.say("baby_shower", text3, [id], 1, false)
			return {"text": text3}
		"funeral":
			var rec: Dictionary = _grave_for(id)
			var dead: int = int(rec["folk_id"])
			var came4: Array = attendees(id, EventState.guests(id, int(a.get("guests", 8)), 5.0, [dead]), 0.4)
			EventState.funerals[dead] = SysUtil.day()
			_pay_guests(f, came4.size(), int(a.get("per_guest", 3)), "funeral")
			var cut: float = float(ec().get("funeral_grief_cut", 0.3))
			for x2 in [id] + came4:
				var gf = SysUtil.folk(int(x2))
				if gf == null or not SysUtil.is_resident(gf):
					continue
				for b in gf.buffs:
					if str(b["id"]).begins_with("grieving") and float(b["remaining"]) > 0.0:
						b["remaining"] = float(b["remaining"]) * (1.0 - cut)
			_cheer(came4, id, 2.0, 8.0)
			var text4 := "A funeral was held for %s at %s. %d people came to say goodbye." % [str(rec["name"]), place, came4.size() + 1]
			LifeNote.say("funeral", text4, [id, dead], 2, true, "info")
			return {"text": text4}
		"reunion":
			var rel: Array = RelationshipBits.others_with_bit(id, "family").filter(func(x): return PhoneCmd.is_person(int(x)) and PhoneCmd.unreachable(int(x)) == "")
			EventState.mark(id, "reunion")
			var came5: Array = attendees(id, rel.slice(0, int(a.get("guests", 8))), 0.35)
			_pay_guests(f, came5.size(), int(a.get("per_guest", 8)), "family reunion")
			_cheer(came5, id, 4.0, 18.0)
			f.add_to_stat("social", 25.0 + 5.0 * float(came5.size()))
			f.add_to_stat("fun", 20.0)
			f.remember("reunion", 0.6)
			var text5 := "%s had a family reunion at %s with %d relative%s." % [f.name, place, came5.size(), "" if came5.size() == 1 else "s"]
			LifeNote.say("reunion", text5, [id] + came5, 1, false)
			return {"text": text5}
		"mingle":
			var met: Array = []
			var pool: Array = Story.free_townies().map(func(t): return int(t["id"]))
			pool.sort()
			var want: int = mini(int(a.get("neighbours", 3)), pool.size())
			while met.size() < want:
				var pick: int = int(pool[PhoneState.rng.randi_range(0, pool.size() - 1)])
				if not met.has(pick):
					met.append(pick)
			for m in met:
				RelationshipService.add_both(id, int(m), "friendship", float(a.get("friendship", 2.0)))
			var names: Array = met.map(func(m): return Story.name_of(int(m)))
			return {"text": "%s chatted with %s at %s." % [f.name, ", ".join(names), place] if not names.is_empty() else ""}
	return {}
