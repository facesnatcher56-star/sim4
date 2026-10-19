class_name WorksCmd
extends RefCounted
## Command layer of the industrial careers (task 31; multiplayer-ready: decisions arrive as commands).
## Envelope: {player_id, folk_id, action: "works", args: {action, ...}}. Only the player who owns the folk's household may act for them.
##   join_union | leave_union | overtime {on: bool}   (overtime = stay late on busy days for extra pay, at the cost of energy)
##   status                                           plain words about the job: union, overtime, strike, wage rise
## Each returns {ok, msg, ...}.

static func run(e: Dictionary) -> Dictionary:
	var a: Dictionary = e.get("args", {})
	var f = SysUtil.folk(int(e.get("folk_id", -1)))
	if f == null or not Players.owns(int(e.get("player_id", -1)), int(f.household_id)):
		return {"ok": false, "msg": "That is not your folk."}
	var fid: int = int(f.id)
	if not Careers.has_job(fid) or not Works.is_works(Careers.career_of(fid)):
		return {"ok": false, "msg": "That is not an industrial job."}
	match str(a.get("action", "")):
		"join_union":
			return WorksUnion.join(f)
		"leave_union":
			return WorksUnion.leave(f)
		"overtime":
			Careers.jobs[fid]["overtime"] = bool(a.get("on", true))
			return {"ok": true, "msg": ""}
		"status":
			return {"ok": true, "msg": "", "lines": status_lines(fid)}
	return {"ok": false, "msg": "That is not possible."}

static func status_lines(fid: int) -> Array:
	var cid: String = Careers.career_of(fid)
	var lines: Array = []
	lines.append("Union: %s." % ("member" if WorksUnion.is_member(fid) else "not a member"))
	lines.append("Overtime: %s." % ("open to staying late" if bool(Careers.jobs.get(fid, {}).get("overtime", false)) else "off"))
	if WorksEvents.on_strike(cid):
		lines.append("The %s workers are on strike today." % Works.sector_label(cid))
	elif WorksEvents.strike_pending(cid):
		lines.append("A strike is coming.")
	if WorksEvents.wage_mult(cid) > 1.0:
		lines.append("Pay is up %d percent from past strikes." % int(round((WorksEvents.wage_mult(cid) - 1.0) * 100.0)))
	return lines
