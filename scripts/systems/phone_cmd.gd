class_name PhoneCmd
extends RefCounted
## What a person can do with the phone (task 14), all reached through LifeCommand (phone_call, phone_text, phone_invite, phone_respond):
##   contacts(fid)         the people they know, best friends first: [{id, name, bit, label, friendship, townie, reason}] (`reason` = why a call would not get through)
##   call / text           a chat: social, a little friendship; once a day per person (texts: a few)
##   invite(fid, other, o) ask somebody out (an outing from data): they say yes with a chance that grows with friendship; the outing is then LifeOuting
##   respond(fid, id, yes) answer an invitation that came in (PhoneDay): each pays for themselves
## Tier: event driven. Residents and townies are both just ids here; nothing is simulated for the person on the other end.

static func pc() -> Dictionary:
	return LifeDefs.cfg("phone")

static func is_person(id: int) -> bool:
	var f = SysUtil.folk(id)
	return (f != null and SysUtil.is_resident(f)) or (Story.townies.has(id) and bool(Story.townies[id]["alive"]))

## Why a call to this person would not get through ("" = it does).
static func unreachable(id: int) -> String:
	if not is_person(id):
		return "Nobody answers."
	if Hospital.is_in(id):
		return "%s is in hospital." % SysUtil.folk_name(id)
	if JusticeState.inmates.has(id):
		return "%s cannot take calls." % SysUtil.folk_name(id)
	return ""

static func contacts(fid: int, limit: int = 14) -> Array:
	var rows: Array = []
	for other in RelationshipBits.all_known(fid):
		var o: int = int(other)
		if o == fid or not is_person(o):
			continue
		var bit: String = RelationshipBits.bit_for(fid, o)
		rows.append({"id": o, "name": SysUtil.folk_name(o), "bit": bit, "label": RelationshipBits.bit_label(bit), "friendship": RelationshipService.value(fid, o, "friendship"),
			"townie": Story.townies.has(o), "reason": unreachable(o)})
	rows.sort_custom(func(a, b): return float(a["friendship"]) > float(b["friendship"]) or (is_equal_approx(float(a["friendship"]), float(b["friendship"])) and int(a["id"]) < int(b["id"])))
	return rows.slice(0, limit)

static func _check(fid: int, other: int) -> String:
	if SysUtil.folk(fid) == null:
		return "Nobody is calling."
	if not RelationshipService.knows(fid, other):
		return "That is not in the contacts."
	return unreachable(other)

static func call_person(fid: int, other: int) -> Dictionary:
	var why: String = _check(fid, other)
	if why != "":
		return {"ok": false, "reason": why}
	if PhoneState.today_count(fid, other, "calls") >= 1:
		return {"ok": false, "reason": "You already spoke to %s today." % SysUtil.folk_name(other)}
	var c: Dictionary = pc().get("call", {})
	var f = SysUtil.folk(fid)
	f.add_to_stat("social", float(c.get("social", 10.0)))
	f.add_to_stat("fun", float(c.get("fun", 3.0)))
	RelationshipService.add_both(fid, other, "friendship", float(c.get("friendship", 2.0)))
	var of = SysUtil.folk(other)
	if of != null:
		of.add_to_stat("social", float(c.get("resident_social", 6.0)))
	PhoneState.note_contact(fid, other, "calls")
	SysUtil.notify("%s had a good chat with %s on the phone." % [f.name, SysUtil.folk_name(other)], "good")
	return {"ok": true, "reason": ""}

static func text_person(fid: int, other: int) -> Dictionary:
	var why: String = _check(fid, other)
	if why != "":
		return {"ok": false, "reason": why}
	var c: Dictionary = pc().get("text", {})
	if PhoneState.today_count(fid, other, "texts") >= int(c.get("daily_cap", 3)):
		return {"ok": false, "reason": "That is enough texts for today."}
	var f = SysUtil.folk(fid)
	f.add_to_stat("social", float(c.get("social", 3.0)))
	RelationshipService.add_both(fid, other, "friendship", float(c.get("friendship", 0.8)))
	PhoneState.note_contact(fid, other, "texts")
	return {"ok": true, "reason": ""}

static func outing_by_id(oid: String) -> Dictionary:
	for o in LifeOuting.outings():
		if str(o["id"]) == oid:
			return o
	return {}

## Chance that `other` says yes to an invitation from `fid`.
static func accept_chance(fid: int, other: int) -> float:
	var fr: float = RelationshipService.value(other, fid, "friendship")
	var p: float = float(pc().get("invite_base", 0.35)) + float(pc().get("invite_per_friendship", 0.006)) * fr
	if RelationshipBits.bit_for(fid, other) in ["partner", "spouse", "sweetheart", "dating", "best_friend"]:
		p += 0.25
	return clampf(p, 0.05, 0.95)

static func invite(fid: int, other: int, outing_id: String, pay_both: bool = true, instant: bool = false, use_opts: Dictionary = {}) -> Dictionary:
	var why: String = _check(fid, other)
	if why != "":
		return {"ok": false, "reason": why}
	var o: Dictionary = outing_by_id(outing_id)
	if o.is_empty():
		return {"ok": false, "reason": "That is not on offer."}
	var w2: String = LifeOuting.why_not(fid, other, o)
	if w2 != "":
		return {"ok": false, "reason": w2}
	if PhoneState.today_count(fid, other, "invites") >= 2:
		return {"ok": false, "reason": "%s has been asked enough for today." % SysUtil.folk_name(other)}
	PhoneState.note_contact(fid, other, "invites")
	if PhoneState.rng.randf() >= accept_chance(fid, other):
		var f = SysUtil.folk(fid)
		SysUtil.notify("%s is busy and cannot make it." % SysUtil.folk_name(other), "info")
		return {"ok": true, "accepted": false, "reason": ""}
	var r: Dictionary = LifeOuting.go(fid, other, o, pay_both, instant, use_opts)
	r["accepted"] = bool(r.get("ok", false))
	return r

static func respond(fid: int, mid: int, yes: bool, instant: bool = false, use_opts: Dictionary = {}) -> Dictionary:
	var m: Dictionary = {}
	for it in PhoneState.inbox:
		if int(it["id"]) == mid and int(it["folk"]) == fid:
			m = it
	if m.is_empty():
		return {"ok": false, "reason": "That invitation has gone."}
	if not yes:
		PhoneState.take(fid, mid)
		RelationshipService.add_value(int(m["from"]), fid, "friendship", -0.5)
		return {"ok": true, "reason": ""}
	var o: Dictionary = outing_by_id(str(m["service"]))
	if o.is_empty():
		PhoneState.take(fid, mid)
		return {"ok": false, "reason": "That plan fell through."}
	var r: Dictionary = LifeOuting.go(fid, int(m["from"]), o, false, instant, use_opts)
	if bool(r.get("ok", false)):
		PhoneState.take(fid, mid)
	return r
