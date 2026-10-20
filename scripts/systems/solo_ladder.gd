class_name SoloLadder
extends RefCounted
## The housing ladder (R12.2) as actions: `quote(rung)` says whether the pawn can move there and what it costs, `move_to(rung)` does it
## (belongings, role swap, tenancy, the pawn walks in), `apply_council()` joins the council list, `give_up_home()` ends the tenancy on purpose
## (the step down that keeps a failing player out of an eviction). The rungs and their numbers are data/solo.json "ladder"; the lots they use are
## real lots (the studio, the Cedar Court flat, the Maple Row house, Elm Court); two rungs share Elm Court (a bedsit and a council flat).

static func rungs() -> Array:
	return SoloCfg.ladder()

## The label (lot id as the game knows it NOW) of the physical lot a rung uses; "" for the street / the shelter rungs.
static func label_of(r: Dictionary) -> String:
	var orig: String = str(r.get("lot", ""))
	if orig == "" or orig == SoloShelter.lot_id():
		return orig
	for id in SoloHome.phys:
		if str(SoloHome.phys[id]) == orig:
			return str(id)
	return orig

## Wages in the last 7 days: what the council and the landlords judge "income" by.
static func income_week(hid: int) -> int:
	var total := 0
	var from: int = SysUtil.day() - 7
	for e in Economy.ledger_for(hid):
		var why: String = str(e.get("reason", ""))
		if int(e.get("day", 0)) >= from and int(e.get("amount", 0)) > 0 and (why.begins_with("wages") or why in ["odd job", "day labour", "freelance work"]):
			total += int(e.get("amount", 0))
	return total

static func unpaid_total(hid: int) -> int:
	return Economy.owed(hid)

## {ok, reason, rent, bills, deposit, due (coins to pay now), fee, rung}.
static func quote(rung_id: String) -> Dictionary:
	var r: Dictionary = SoloCfg.rung(rung_id)
	var out: Dictionary = {"ok": false, "reason": "", "rung": rung_id, "rent": 0, "bills": 0, "deposit": 0, "due": 0, "fee": 0}
	if r.is_empty():
		out["reason"] = "No such place."
		return out
	var hid: int = Economy.primary_household()
	out["rent"] = SoloCfg.rung_rent(r)
	out["bills"] = SoloCfg.rung_bills(r)
	out["deposit"] = SoloCfg.rung_deposit(r)
	if rung_id == SoloHome.rung and not SoloHome.homeless:
		out["reason"] = "You live here."
		return out
	if rung_id in ["street", "shelter"]:
		out["reason"] = "You get there by losing your home, not by moving."
		return out
	if unpaid_total(hid) > 0:
		out["reason"] = "Unpaid bills (%d coins) block a new tenancy: clear them first." % unpaid_total(hid)
		return out
	var fee: int = int(SoloMove.cfg().get("fee", 15)) if not SoloHome.homeless else 0
	out["fee"] = fee
	out["due"] = int(out["deposit"]) + int(out["rent"]) + fee
	if int(r.get("income_min", 0)) > 0 and income_week(hid) < int(r["income_min"]):
		out["reason"] = "The landlord wants proof of income: about %d a week (you made %d)." % [int(r["income_min"]), income_week(hid)]
		return out
	if rung_id == "council":
		var wait: int = int((r.get("wait_days", {}) as Dictionary).get(SoloCfg.diff_id(), 14))
		if SoloHome.council_day < 0:
			out["reason"] = "Apply to the council list first (a %d day wait)." % wait
			return out
		if SysUtil.day() - SoloHome.council_day < wait:
			out["reason"] = "On the council list: %d more days." % (wait - (SysUtil.day() - SoloHome.council_day))
			return out
		if income_week(hid) > int(r.get("income_max", 450)):
			out["reason"] = "The council lets flats only to people earning under %d a week." % int(r.get("income_max", 450))
			return out
	if Economy.balance(hid) < int(out["due"]):
		out["reason"] = "You need %d coins to move in (deposit, first week, movers)." % int(out["due"])
		return out
	out["ok"] = true
	return out

static func apply_council() -> Dictionary:
	if SoloHome.council_day >= 0:
		return {"ok": false, "reason": "You are already on the council list."}
	SoloHome.council_day = SysUtil.day()
	var r: Dictionary = SoloCfg.rung("council")
	var wait: int = int((r.get("wait_days", {}) as Dictionary).get(SoloCfg.diff_id(), 14))
	SysUtil.notify("You are on the council list for a flat. The wait is about %d days." % wait, "info")
	return {"ok": true, "reason": ""}

## Leave the present place on purpose and become homeless (belongings are lost; the deposit comes back).
static func give_up_home() -> Dictionary:
	if SoloHome.homeless:
		return {"ok": false, "reason": "You have no home to give up."}
	var hid: int = Economy.primary_household()
	var p: Dictionary = SoloHome.prop()
	if not p.is_empty():
		p["tenant_kind"] = ""
		p["tenant"] = 0
		p["notice"] = false
		p["to_let"] = true
	if SoloHome.deposit > 0:
		Economy.deposit(hid, SoloHome.deposit, "deposit returned")
	SoloHome.deposit = 0
	SoloHome.homeless = true
	SoloHome.rung = "street"
	SoloMove.lose_everything_here(hid)
	SoloMove.put_on_street(hid)
	SysUtil.notify("You have given up the flat. You have what you carry.", "warn")
	return {"ok": true, "reason": ""}

## Move the pawn's household to a rung. Returns {ok, reason}.
static func move_to(rung_id: String) -> Dictionary:
	var q: Dictionary = quote(rung_id)
	if not bool(q["ok"]):
		return {"ok": false, "reason": str(q["reason"])}
	var r: Dictionary = SoloCfg.rung(rung_id)
	var hid: int = Economy.primary_household()
	var target: String = label_of(r)
	var carried: Array = []
	if not SoloHome.homeless:
		carried = SoloMove.take_belongings(hid)          # removed from the old lot, kept in the movers' store
		var old_p: Dictionary = SoloHome.prop()
		if not old_p.is_empty():
			old_p["tenant_kind"] = ""
			old_p["tenant"] = 0
			old_p["notice"] = false
			old_p["to_let"] = true
		if SoloHome.deposit > 0:
			Economy.deposit(hid, SoloHome.deposit, "deposit returned")
	SoloHome.stored = carried
	if target != Neighborhood.HOME and not SoloMove.swap_roles(target):
		return {"ok": false, "reason": "That place is not available."}
	Economy.spend(hid, int(q["due"]), "moving in: deposit, first week, movers")
	var p: Dictionary = SoloMove.prop_at(Neighborhood.HOME)
	if p.is_empty():
		p = SoloMove.make_prop(Neighborhood.HOME, r)
	SoloRent.let_to_pawn(p, hid, SoloCfg.rung_rent(r), SoloCfg.rung_deposit(r))
	SoloHome.rung = rung_id
	SoloHome.homeless = false
	SoloHome.notice_day = -1
	SoloHome.since_day = SysUtil.day()
	HousingRent.next_cycle = SysUtil.day() + 7
	SoloMove.mark_fixtures(Neighborhood.HOME)
	SoloMove.move_in()
	SysUtil.notify("You moved to %s." % str(r.get("label", rung_id)), "good")
	ChronicleHook.note("move", "%s moved to %s." % [SoloRent._pawn_name(), str(r.get("label", rung_id))], [], "home:%d" % hid, 2, true)
	SysUtil.game_event("moved_house", {"household_id": hid, "rung": rung_id})
	return {"ok": true, "reason": ""}
