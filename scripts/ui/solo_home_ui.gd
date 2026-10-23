class_name SoloHomeUi
extends RefCounted
## The top of the "Homes" tab in one-character play, in the panel style of docs/UI_STYLE.md: a CARD for where you live now and one per place you could move
## to (key numbers as chips, requirements as tick / cross chips, one action, the reason under a disabled button, the flavour in the tooltip). Every
## button is the "solo" command (SoloCmd).

static func build(dlg: BankHub) -> void:
	var w: float = dlg.dialog_width - 50.0
	dlg.heading("Where you live")
	_now_card(dlg, w)
	if SoloPressure.member:
		_crew_card(dlg, w)
	dlg.heading("Places to move to")
	for r in SoloCfg.ladder():
		if str(r["id"]) in ["street", "shelter", SoloHome.rung]:
			continue
		_rung_card(dlg, w, r)
	if SoloHome.homeless:
		return
	var inner: VBoxContainer = UICard.card(dlg.body, w, "Give up the flat", "", "You keep what you carry; everything in the flat is lost and your deposit comes back. The shelter and day labour are open to you after.")
	UICard.note(inner, "Live on the street. Only if the rent is beating you.")
	UICard.action(inner, "Give it up", func(): _act(dlg, "give_up_home", {}))

static func _now_card(dlg: BankHub, w: float) -> void:
	var r: Dictionary = SoloHome.rung_def()
	if SoloHome.homeless:
		var inner: VBoxContainer = UICard.card(dlg.body, w, "No home", "HOMELESS", "Sleep rough (Myself menu), use the night shelter, take day labour at the Works.")
		UICard.chips(inner, [["Shelter nights left", "%d this week" % SoloShelter.nights_left()], ["Day labour", "40 / 4 h"]])
		var owed: int = Economy.owed(dlg.hid())
		if owed > 0:
			UICard.reqs(inner, [["Unpaid bills %d: they block a new tenancy" % owed, false]])
		return
	var p: Dictionary = SoloHome.prop()
	var badge: String = "EVICTION NOTICE" if bool(p.get("notice", false)) else "YOU LIVE HERE"
	var inner2: VBoxContainer = UICard.card(dlg.body, w, str(r.get("label", "Home")), badge, str(r.get("cause", "")))
	UICard.chips(inner2, [["Rent", "%d/wk" % Upkeep.weekly_rent(dlg.hid())], ["Bills", "about %d/wk" % Economy.compute_bill(dlg.hid())], ["Deposit held", "%d" % SoloHome.deposit]])          # what you actually pay here (Upkeep)
	if bool(p.get("notice", false)):
		UICard.reqs(inner2, [["Pay the overdue rent to cancel the notice", false]])
	var owed2: int = Economy.owed(dlg.hid())
	if owed2 > 0:
		UICard.reqs(inner2, [["Unpaid bills %d" % owed2, false]])

static func _crew_card(dlg: BankHub, w: float) -> void:
	var inner: VBoxContainer = UICard.card(dlg.body, w, SoloPressure.crew_name.capitalize() if SoloPressure.crew_name != "" else "Your crew", "IN A CREW", "Errands for the crew pay well and bring police attention. Leaving costs a payoff.")
	UICard.chips(inner, [["Standing", "%d" % int(SoloPressure.standing)], ["Heat", "%d" % int(SoloPressure.heat)], ["Dues", "%d/day" % int(SoloCfg.sect("pressure").get("dues_per_day", 3))]])
	var pay: int = int(SoloCfg.sect("pressure").get("leave_payoff", 150))
	UICard.action(inner, "Leave (%d)" % pay, func(): _act(dlg, "leave_crew", {}), true, "")

static func _rung_card(dlg: BankHub, w: float, r: Dictionary) -> void:
	var id: String = str(r["id"])
	var q: Dictionary = SoloLadder.quote(id)
	var tags: Array = Heritage.tags_for_lot(str(r.get("lot", "")), SysUtil.folk(Pawn.of()))
	var inner: VBoxContainer = UICard.card(dlg.body, w, str(r["label"]), "", str(r.get("cause", "")))
	UICard.chips(inner, [["Rent", "%d/wk" % SoloCfg.rung_rent(r)], ["Bills", "about %d/wk" % SoloCfg.rung_bills(r)], ["Deposit", "%d" % SoloCfg.rung_deposit(r)]])
	UICard.reqs(inner, q.get("checks", []))
	var did: String = SoloDistricts.district_of(str(r.get("lot", "")))
	var line: Array = []
	if did != "":
		line.append(SoloDistricts.label_of(did))
	line.append_array(tags)
	if not line.is_empty():
		UICard.note(inner, " · ".join(line))
	if id == "council" and SoloHome.council_day < 0:
		UICard.action(inner, "Join the list", func(): _act(dlg, "apply_council", {}))
	else:
		UICard.action(inner, "Move here", func(): _act(dlg, "move", {"rung": id}), bool(q["ok"]), str(q["reason"]))

static func _act(dlg: BankHub, action: String, args: Dictionary) -> void:
	var a: Dictionary = args.duplicate()
	a["action"] = action
	var r: Dictionary = Commands.run({"player_id": BankHub.PLAYER_ID, "folk_id": dlg.folk_id, "action": "solo", "args": a})
	if not bool(r.get("ok", false)) and str(r.get("reason", "")) != "":
		UIU.notify(str(r["reason"]), "warn")
	dlg.refresh()
	dlg.call_deferred("_center")
