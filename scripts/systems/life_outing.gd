class_name LifeOuting
extends RefCounted
## Going out together (task 14): dates, friends' evenings, family trips. One person (the HOST, a resident) uses a service of a real place while a GUEST
## (a townie or another resident) comes along. The host's visit is the normal PlaceUse; when it ends (`place_used`) the company counts: friendship (and
## romance, only where RomanceRules.allows it AND the two are dating, sweethearts, partners, spouses or have a crush), a happier mood, a chronicle
## line for couples. A guest who is a resident gets the service's effects too; a townie guest is statistical.
## Outings are data (config.phone.outings: a label and the services to try in order, e.g. the adult late show before the family film), so every
## place with a suitable service can be an outing. Stage and opening rules are checked for BOTH people.

static func outings() -> Array:
	return LifeDefs.cfg("phone").get("outings", [])

static func stage_of(id: int) -> String:
	return EduState.stage_of(id)

## The first service of the outing that both people may use right now ("" = none).
static func pick_service(host: int, guest: int, o: Dictionary) -> String:
	var pid: String = str(o.get("place", ""))
	var gs: String = stage_of(guest)
	for sid in o.get("services", []):
		var svc: Dictionary = Places.services(pid).get(str(sid), {})
		if svc.is_empty():
			continue
		if Places.place_reason(gs, pid) != "" or Places.stage_reason(gs, svc) != "" or Places.when_reason(svc) != "":
			continue
		if PlaceUse.why_not(host, pid, str(sid)) == "":
			return str(sid)
	return ""

## Could these two go on this outing at all (ages and rules, not the clock)? Used for invitations that arrive overnight.
static func could(host: int, guest: int, o: Dictionary) -> bool:
	var pid: String = str(o.get("place", ""))
	if not Places.exists(pid):
		return false
	for sid in o.get("services", []):
		var svc: Dictionary = Places.services(pid).get(str(sid), {})
		if svc.is_empty():
			continue
		var ok := true
		for who in [stage_of(host), stage_of(guest)]:
			if Places.place_reason(who, pid) != "" or Places.stage_reason(who, svc) != "":
				ok = false
		if ok:
			return true
	return false

static func why_not(host: int, guest: int, o: Dictionary) -> String:
	var pid: String = str(o.get("place", ""))
	if not Places.exists(pid):
		return "That place is not in town."
	if not Places.is_open(pid):
		return "%s: %s." % [Places.label(pid), Places.status_text(pid)]
	if pick_service(host, guest, o) == "":
		var f = SysUtil.folk(host)
		var first: String = str((o.get("services", [""]) as Array)[0])
		var why: String = PlaceUse.why_not(host, pid, first)
		return why if why != "" else "%s cannot come along to that." % SysUtil.folk_name(guest)
	return ""

## Start the outing. `pay_both`: the host pays the guest's ticket too. `instant`: skip the visit's minutes (tests).
static func go(host: int, guest: int, o: Dictionary, pay_both: bool, instant: bool = false) -> Dictionary:
	var why: String = why_not(host, guest, o)
	if why != "":
		return {"ok": false, "reason": why}
	var pid: String = str(o.get("place", ""))
	var sid: String = pick_service(host, guest, o)
	var f = SysUtil.folk(host)
	var extra: int = PlaceUse.price(pid, sid, guest) if pay_both else 0
	if extra > 0 and not Economy.can_afford(int(f.household_id), PlaceUse.price(pid, sid, host) + extra):
		return {"ok": false, "reason": "That costs %d coins for two." % (PlaceUse.price(pid, sid, host) + extra)}
	PhoneState.companions[host] = {"other": guest, "place": pid, "service": sid, "pay_both": pay_both, "day": SysUtil.day()}
	var r: Dictionary = PlaceUse.use(host, pid, sid, {"instant": instant})
	if not bool(r.get("ok", false)):
		PhoneState.companions.erase(host)
		return r
	if extra > 0:
		Economy.spend(int(f.household_id), extra, "%s: a ticket for %s" % [Places.label(pid), SysUtil.folk_name(guest)])
	r["guest"] = guest
	r["service"] = sid
	return r

## The host's visit ended (event place_used): the company counts.
static func on_place_used(host: int, pid: String, sid: String) -> void:
	var c: Dictionary = PhoneState.companions.get(host, {})
	if c.is_empty() or str(c["place"]) != pid or str(c["service"]) != sid:
		return
	PhoneState.companions.erase(host)
	var guest: int = int(c["other"])
	var oc: Dictionary = LifeDefs.cfg("phone").get("outing", {})
	var f = SysUtil.folk(host)
	if f == null:
		return
	RelationshipService.add_both(host, guest, "friendship", float(oc.get("friendship", 4.0)))
	var bit: String = RelationshipBits.bit_for(host, guest)
	var couple: bool = bit in ["dating", "sweetheart", "partner", "spouse", "crush"]
	if couple and RomanceRules.allowed(host, guest):
		RelationshipService.add_both(host, guest, "romance", float(oc.get("romance", 4.0)))
	f.add_to_stat("social", float(oc.get("social", 10.0)))
	var gf = SysUtil.folk(guest)
	if gf != null and SysUtil.is_resident(gf):
		var svc: Dictionary = Places.services(pid).get(sid, {})
		PlaceEffects.apply(gf, pid, sid, svc, false)
		gf.add_to_stat("social", float(oc.get("social", 10.0)))
	var gname: String = SysUtil.folk_name(guest)
	SysUtil.notify("%s and %s had a lovely time at %s." % [f.name, gname, Places.label(pid)], "good")
	if couple:
		LifeNote.say("date", "%s and %s went out together to %s." % [f.name, gname, Places.label(pid)], [host, guest], 1, false)
	SysUtil.game_event("outing_done", {"folk_id": host, "guest": guest, "place": pid, "service": sid})
