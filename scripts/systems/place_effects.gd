class_name PlaceEffects
extends RefCounted
## What a service does when the visit ends (task 14). Everything common is data on the service:
##   needs {need: +n}   buffs [ids]   skill_xp {skill: xp}   meters {fitness|diet|dental: +n}   pass {days}   event "name"   text "..{name}..{place}..{staff}.."
## plus an optional `handler` (PlaceHandlers) for the special ones (a lecture, a check-up, a class). Returns {text, ...handler fields}.

static func apply(f, pid: String, sid: String, svc: Dictionary, announce: bool = true) -> Dictionary:
	var out: Dictionary = {}
	for n in (svc.get("needs", {}) as Dictionary):
		f.add_to_stat(str(n), float(svc["needs"][n]))
	if FoodMenu.is_special(pid, sid):
		f.add_to_stat("fun", float(LifeDefs.cfg("food").get("special_fun", 4)))
	for b in svc.get("buffs", []):
		f.add_buff(str(b))
	for s in (svc.get("skill_xp", {}) as Dictionary):
		f.add_skill_xp(str(s), float(svc["skill_xp"][s]))
	for m in (svc.get("meters", {}) as Dictionary):
		HealthLife.add_meter(int(f.id), str(m), float(svc["meters"][m]))
	if svc.has("pass"):
		PlaceMember.grant(int(f.id), pid, int((svc["pass"] as Dictionary).get("days", 7)))
	var h: String = str(svc.get("handler", ""))
	if h != "":
		out.merge(PlaceHandlers.finish(h, f, pid, sid, svc), true)
	if svc.has("event"):
		SysUtil.game_event(str(svc["event"]), {"folk_id": int(f.id), "place": pid, "service": sid})
	var text: String = str(out.get("text", svc.get("text", "")))
	if text != "":
		text = text.replace("{title}", Programme.title(pid, str(svc.get("programme_slot", "")))).replace("{name}", str(f.name)).replace("{place}", Places.label(pid)).replace("{staff}", _staff(pid, str(svc.get("who_role", ""))))
		out["text"] = text
		if announce:
			SysUtil.notify(text, str(svc.get("kind", "good")))
	return out

static func _staff(pid: String, role: String = "") -> String:
	var n: String = PlaceStaff.who(pid, role)
	if n == "":
		n = PlaceStaff.who(pid)
	return n if n != "" else "the staff"
