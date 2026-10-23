class_name LifeCommand
extends RefCounted
## The command layer of the life areas (multiplayer-ready rule 1): every player action of the Town window is
## `run(player_id, folk_id, action, args)` -> {ok, reason, ...}, reached through Commands.run({action: "life", args: {action, args}}). The household comes
## from the folk (never "household 1"). Actions:
##   use {place, service, target}      go {place, opts}      home {opts}      college_apply {major}      college_drop      preschool_leave      job_apply {career}
##   phone_call {other}   phone_text {other}   phone_invite {other, outing, pay_both}   phone_respond {id, yes}   post {kind}
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
			if lot == Places.HOME:
				var home: Dictionary = Neighborhood.go_home([folk_id], args.get("opts", {}))
				return {"ok": bool(home.get("ok", false)), "reason": str(home.get("msg", home.get("reason", "")))}
			if not Places.on_map(lot):
				return {"ok": false, "reason": "That place is not on the map."}
			var res: Dictionary = Neighborhood.travel([folk_id], lot, args.get("opts", {}))
			return {"ok": bool(res.get("ok", false)), "reason": str(res.get("msg", res.get("reason", "")))}
		"home":
			var back: Dictionary = Neighborhood.go_home([folk_id], args.get("opts", {}))
			return {"ok": bool(back.get("ok", false)), "reason": str(back.get("msg", back.get("reason", "")))}
		"college_apply":
			return EduCollege.apply(folk_id, str(args.get("major", "")))
		"college_drop":
			var dropped: bool = EduCollege.drop(folk_id)
			return {"ok": dropped, "reason": "" if dropped else "Not studying."}
		"preschool_leave":
			EduSchool.enrol_preschool(folk_id, false)
			return {"ok": true, "reason": ""}
		"phone_call":
			return PhoneCmd.call_person(folk_id, int(args.get("other", -1)))
		"phone_text":
			return PhoneCmd.text_person(folk_id, int(args.get("other", -1)))
		"phone_invite":
			return PhoneCmd.invite(folk_id, int(args.get("other", -1)), str(args.get("outing", "")), bool(args.get("pay_both", true)), bool(args.get("instant", false)), args.get("use_opts", {}))
		"phone_respond":
			return PhoneCmd.respond(folk_id, int(args.get("id", -1)), bool(args.get("yes", false)), bool(args.get("instant", false)), args.get("use_opts", {}))
		"post":
			return SocialFeed.post(folk_id, str(args.get("kind", "")))
		"job_apply":
			var nojob: String = PhoneJobs.why_not(folk_id, str(args.get("career", "")))
			if nojob != "":
				return {"ok": false, "reason": nojob}
			return JobApps.send(folk_id, str(args.get("career", "")))
		"phone_buy":
			return PhoneOwn.buy(folk_id, str(args.get("kind", "old")))
		"phone_sell":
			var got: int = PhoneOwn.sell(folk_id)
			return {"ok": got > 0, "reason": "" if got > 0 else "You have no phone to sell."}
		"paper":
			var pr: Dictionary = PhoneJobs.read_paper(folk_id)
			return {"ok": bool(pr.get("ok", false)), "reason": str(pr.get("reason", ""))}
	return {"ok": false, "reason": "That action is not available."}
