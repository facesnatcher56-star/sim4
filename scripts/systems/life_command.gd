class_name LifeCommand
extends RefCounted
## The command layer of the life areas (multiplayer-ready rule 1): every player action of the Town window is
## `run(player_id, folk_id, action, args)` -> {ok, reason, ...}, reached through Commands.run({action: "life", args: {action, args}}). The household comes
## from the folk (never "household 1"). Actions:
##   use {place, service}      go {place}      college_drop      preschool_leave      job_apply {career}
## Reads (no state change) are plain static calls: Places, EduJobs.board_for, EduCollege.summary ...

static func run(_player_id: int, folk_id: int, action: String, args: Dictionary = {}) -> Dictionary:
	var f = SysUtil.folk(folk_id)
	if f == null:
		return {"ok": false, "reason": "Nobody is acting."}
	match action:
		"use":
			return PlaceUse.use(folk_id, str(args.get("place", "")), str(args.get("service", "")), args)
		"go":
			var lot: String = Places.lot_of(str(args.get("place", "")))
			if not Places.on_map(lot):
				return {"ok": false, "reason": "That place is not on the map."}
			var res: Dictionary = Neighborhood.travel([folk_id], lot, args.get("opts", {}))
			return {"ok": bool(res.get("ok", false)), "reason": str(res.get("msg", res.get("reason", "")))}
		"college_drop":
			var dropped: bool = EduCollege.drop(folk_id)
			return {"ok": dropped, "reason": "" if dropped else "Not studying."}
		"preschool_leave":
			EduSchool.enrol_preschool(folk_id, false)
			return {"ok": true, "reason": ""}
		"job_apply":
			return EduJobs.apply(folk_id, str(args.get("career", "")))
	return {"ok": false, "reason": "That action is not available."}
