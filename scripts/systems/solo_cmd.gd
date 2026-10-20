class_name SoloCmd
extends RefCounted
## Command door of one-character play (action "solo"): housing. args.action = move {rung} | quote {rung} | apply_council | give_up_home.
## Every player order goes through Commands.run, so the UI never changes the tenancy directly.

static func run(e: Dictionary) -> Dictionary:
	var a: Dictionary = e["args"]
	if not SoloHome.active:
		return {"ok": false, "msg": "This game has no tenancy.", "reason": "This game has no tenancy."}
	var res: Dictionary
	match str(a.get("action", "")):
		"move":
			res = SoloLadder.move_to(str(a.get("rung", "")))
		"quote":
			res = SoloLadder.quote(str(a.get("rung", "")))
		"apply_council":
			res = SoloLadder.apply_council()
		"give_up_home":
			res = SoloLadder.give_up_home()
		"leave_crew":
			res = SoloPressure.leave(SysUtil.folk(Pawn.of()))
		_:
			res = {"ok": false, "reason": "Unknown housing action."}
	res["msg"] = str(res.get("reason", ""))
	return res
