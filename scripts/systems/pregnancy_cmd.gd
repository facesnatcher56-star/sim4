class_name PregnancyCmd
extends RefCounted
## Command-layer actions of the pregnancy system (task 18; multiplayer-ready: the player's decisions arrive as commands, never as direct state
## changes). Envelope: {player_id, folk_id, action: "pregnancy", args: {action, ...}}.
##   name_baby {baby_id, name}        give the newborn its first name (the mother's household only)
##   labour_place {place}             "hospital" | "home" for the folk in labour
##   bed_rest {on}                    start or stop bed rest
##   fertility_treatment {}           the clinic route for a couple that cannot conceive
## Each returns {ok, msg}. Only the player who owns the folk's household may act for them.

static func run(e: Dictionary) -> Dictionary:
	var a: Dictionary = e.get("args", {})
	var fid: int = int(e.get("folk_id", -1))
	var f = SysUtil.folk(fid)
	var pid: int = int(e.get("player_id", -1))
	match str(a.get("action", "")):
		"name_baby":
			var baby = SysUtil.folk(int(a.get("baby_id", -1)))
			if baby == null or not Players.owns(pid, int(baby.household_id)):
				return {"ok": false, "msg": "That is not your baby."}
			var ok: bool = PregnancyNaming.rename(int(baby.id), str(a.get("name", "")))
			return {"ok": ok, "msg": "" if ok else "Pick a name of 2 to 14 letters."}
		"labour_place":
			if f == null or not Players.owns(pid, int(f.household_id)) or not PregnancyLabour.in_labour(fid):
				return {"ok": false, "msg": "Nobody is in labour."}
			PregnancyLabour.set_place(fid, str(a.get("place", "")))
			return {"ok": true, "msg": ""}
		"bed_rest":
			if f == null or not Players.owns(pid, int(f.household_id)) or not Pregnancy.is_pregnant(fid):
				return {"ok": false, "msg": "That is not possible right now."}
			PregnancyStage.set_bed_rest(fid, bool(a.get("on", true)))
			return {"ok": true, "msg": ""}
		"fertility_treatment":
			if f == null or not Players.owns(pid, int(f.household_id)):
				return {"ok": false, "msg": "That is not possible right now."}
			var res: Dictionary = Fertility.treat(fid)
			return {"ok": bool(res["ok"]), "msg": "" if bool(res["ok"]) else "The clinic could not help right now."}
	return {"ok": false, "msg": "Unknown pregnancy action."}
