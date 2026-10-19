class_name CrimeUnderCmd
extends RefCounted
## Command-layer actions of the underworld (task 23; multiplayer-ready: every decision arrives as a command, never as a direct state change).
## Envelope: {player_id, folk_id, action: "crimeunder", args: {action, ...}}. Only the player who owns the folk's household may act for them.
##   line_join {line} | line_leave {line}                    hit / deal / racket
##   hit_take {contract} | hit_refuse {contract} | hit_research {contract} | hit_execute {contract, scene} | hit_tip {contract}
##   deal_buy {substance, qty} | deal_sell {corner} | deal_hide                                   (fictional substances only)
##   rehab                                                    the folk's own addiction: the clinic
##   racket_lend {debtor, amount} | racket_protect {biz} | racket_den | racket_counterfeit | racket_front {biz} | racket_launder {amount}
##   gang_found {name} | gang_join {gang} | gang_leave | gang_challenge | gang_inform | gang_protect
##   cop_sting {dealer} | cop_undercover {gang} | cop_end_cover | intervene {case}
##   redeem_begin | redeem_job
## Each returns {ok, msg, ...}.

static func run(e: Dictionary) -> Dictionary:
	var a: Dictionary = e.get("args", {})
	var fid: int = int(e.get("folk_id", -1))
	var f = SysUtil.folk(fid)
	var pl: int = int(e.get("player_id", -1))
	if f == null or not Players.owns(pl, int(f.household_id)):
		return {"ok": false, "msg": "That is not your folk."}
	if not CrimePerson.is_adult(fid):
		return {"ok": false, "msg": "Not for the young."}
	match str(a.get("action", "")):
		"line_join":
			return CrimeUnderLines.join(fid, str(a.get("line", "")))
		"line_leave":
			CrimeUnderLines.leave(fid, str(a.get("line", "")))
			return {"ok": true, "msg": ""}
		"hit_take":
			return CrimeUnderHitRun.take(fid, int(a.get("contract", -1)))
		"hit_refuse":
			return CrimeUnderHitRun.refuse(fid, int(a.get("contract", -1)))
		"hit_research":
			return CrimeUnderHitRun.research(fid, int(a.get("contract", -1)))
		"hit_execute":
			return CrimeUnderHitRun.execute(fid, int(a.get("contract", -1)), str(a.get("scene", "")))
		"hit_tip":
			return CrimeUnderHitRun.tip(fid, int(a.get("contract", -1)))
		"deal_buy":
			return CrimeUnderDeal.buy(fid, str(a.get("substance", "")), int(a.get("qty", 1)))
		"deal_sell":
			return CrimeUnderDeal.sell(fid, str(a.get("corner", "")))
		"deal_hide":
			return CrimeUnderDeal.hide_stash(fid)
		"rehab":
			return CrimeUnderAddict.rehab(fid)
		"racket_lend":
			return CrimeUnderRacket.lend(fid, int(a.get("debtor", -1)), int(a.get("amount", 0)))
		"racket_protect":
			return CrimeUnderRacket.protect(fid, int(a.get("biz", -1)))
		"racket_den":
			return CrimeUnderRacket.open_den(fid)
		"racket_counterfeit":
			return CrimeUnderRacket.counterfeit(fid)
		"racket_front":
			return CrimeUnderRacket.set_front(fid, int(a.get("biz", -1)))
		"racket_launder":
			return CrimeUnderRacket.launder(fid, int(a.get("amount", 0)))
		"gang_found":
			var gid: int = CrimeUnderGang.found(fid, str(a.get("name", ""))) if CrimeLifePath.rank_index(fid) >= CrimeLifePath.rank_index_of_id("crew_boss") else -1
			return {"ok": gid >= 0, "msg": "" if gid >= 0 else "You are not a name that people follow yet.", "gang": gid}
		"gang_join":
			return CrimeUnderGang.join(fid, int(a.get("gang", -1)))
		"gang_leave":
			return CrimeUnderGang.leave(fid)
		"gang_challenge":
			return CrimeUnderGang.challenge(fid)
		"gang_inform":
			return CrimeUnderGang.inform(fid)
		"gang_protect":
			return CrimeUnderGang.protect(fid)
		"cop_sting":
			return CrimeUnderGood.sting(fid, int(a.get("dealer", -1)))
		"cop_undercover":
			return CrimeUnderGood.go_undercover(fid, int(a.get("gang", -1)))
		"cop_end_cover":
			return CrimeUnderGood.end_cover(fid)
		"intervene":
			return CrimeUnderGood.intervene(fid, int(a.get("case", -1)))
		"redeem_begin":
			return CrimeUnderRedeem.begin(fid)
		"redeem_job":
			return CrimeUnderRedeem.find_job(fid)
	return {"ok": false, "msg": "Unknown action."}
