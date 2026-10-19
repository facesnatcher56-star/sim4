class_name CrimeLifeCmd
extends RefCounted
## Command-layer actions of the criminal life and security (task 21; multiplayer-ready: every decision arrives as a command, never as a direct state
## change). Envelope: {player_id, folk_id, action: "crimelife", args: {action, ...}}. Only the player who owns the folk's household may act for them.
##   join {} | leave {}                          start or end the criminal path
##   job {job, target {scene, case_scene, victim, label}}   a job (CrimeLifeJobs.start); it takes time and resolves later
##   case {target}                               watch a place ("biz:bank", "town:3")
##   plan {target} | abort {} | recruit {heist, pid, role, cut} | drop_crew {heist, pid} | getaway {heist} | go {heist}   a planned heist
##   gear {gear}                                 buy kit
##   fence {ids, fence_pid}                      sell stolen goods (fence_pid -1 = on the street)
##   biz_upgrade {biz, key}                      a business owner buys cover
##   home_service {key, value}                   alarm monitoring ("monitored" 0/1) or a hired guard ("guard" 0..2)
## Each returns {ok, msg, ...}.

static func run(e: Dictionary) -> Dictionary:
	var a: Dictionary = e.get("args", {})
	var fid: int = int(e.get("folk_id", -1))
	var f = SysUtil.folk(fid)
	var pl: int = int(e.get("player_id", -1))
	if f == null or not Players.owns(pl, int(f.household_id)):
		return {"ok": false, "msg": "That is not your folk."}
	var hid: int = int(f.household_id)
	match str(a.get("action", "")):
		"join":
			return {"ok": CrimeLifePath.join(fid, "chose"), "msg": ""}
		"leave":
			CrimeLifePath.leave(fid)
			return {"ok": true, "msg": ""}
		"job":
			return CrimeLifeJobs.start(fid, str(a.get("job", "")), a.get("target", {}))
		"case":
			return CrimeLifeCasing.start(fid, str(a.get("target", "")))
		"plan":
			return CrimeLifeHeist.plan(fid, str(a.get("target", "")))
		"abort":
			return {"ok": CrimeLifeHeist.abort(fid), "msg": ""}
		"recruit":
			return CrimeLifeHeist.recruit(fid, int(a.get("heist", -1)), int(a.get("pid", -1)), str(a.get("role", "")), float(a.get("cut", -1.0)))
		"drop_crew":
			return {"ok": CrimeLifeHeist.drop_crew(fid, int(a.get("heist", -1)), int(a.get("pid", -1))), "msg": ""}
		"getaway":
			var ok: bool = CrimeLifeHeist.use_getaway(fid, int(a.get("heist", -1)))
			return {"ok": ok, "msg": "" if ok else "You need a stolen car in your stash."}
		"go":
			return CrimeLifeHeist.go(fid, int(a.get("heist", -1)))
		"gear":
			return CrimeLifeHeist.buy_gear(fid, str(a.get("gear", "")))
		"fence":
			return CrimeLifeFence.sell(fid, SysUtil.to_ints(a.get("ids", [])), int(a.get("fence_pid", -1)))
		"biz_upgrade":
			return CrimeSecurityUpgrade.buy_business(hid, int(a.get("biz", -1)), str(a.get("key", "")))
		"home_service":
			return CrimeSecurityUpgrade.set_home_service(hid, str(a.get("key", "")), int(a.get("value", 0)))
	return {"ok": false, "msg": "Unknown action."}
