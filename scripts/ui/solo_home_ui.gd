class_name SoloHomeUi
extends RefCounted
## The top of the "Homes" tab in one-character play: where you live (rent, deposit, notice), the ladder of places with what each costs and why
## you can or cannot move there now, the council list and giving up the flat. Every button is the "solo" command (SoloCmd).

static func build(dlg: BankHub) -> void:
	dlg.heading("Where you live")
	dlg.line(_now_text(), 14)
	var p: Dictionary = SoloHome.prop()
	if bool(p.get("notice", false)):
		dlg.line("EVICTION NOTICE: pay the overdue rent before the locks are changed (day %d + %d)." % [SoloHome.notice_day, int(SoloCfg.sect("start").get("notice_days", 3))], 14, Color("#e5534b"))
	var owed: int = Economy.owed(dlg.hid())
	if owed > 0:
		dlg.line("You owe %d coins in unpaid bills. They block a new tenancy until paid." % owed, 13, UITheme.MUTED)
	dlg.heading("Places to live")
	for r in SoloCfg.ladder():
		_rung(dlg, r)
	if not SoloHome.homeless:
		dlg.row_with("Give up the flat and live on the street. You keep what you carry; everything in the flat is lost, your deposit comes back.", [
			dlg.button("Give it up", "Only if the rent is beating you. The shelter and day labour are open to you after.", func(): _act(dlg, "give_up_home", {}))])

static func _now_text() -> String:
	var r: Dictionary = SoloHome.rung_def()
	if SoloHome.homeless:
		return "You have no home. Sleep rough (Myself menu) or use the night shelter (%d free nights left this week). Day labour at the Works pays 10 coins an hour." % SoloShelter.nights_left()
	return "%s. Rent %d a week, bills about %d. Deposit held: %d." % [str(r.get("label", "Home")), SoloCfg.rung_rent(r), SoloCfg.rung_bills(r), SoloHome.deposit]

static func _rung(dlg: BankHub, r: Dictionary) -> void:
	var id: String = str(r["id"])
	if id in ["street", "shelter"]:
		dlg.line("%s: %s" % [str(r["label"]), str(r.get("cause", ""))], 12, UITheme.MUTED)
		return
	var q: Dictionary = SoloLadder.quote(id)
	var txt: String = "%s: rent %d + bills %d a week, deposit %d. %s" % [str(r["label"]), SoloCfg.rung_rent(r), SoloCfg.rung_bills(r), SoloCfg.rung_deposit(r), str(r.get("cause", ""))]
	if not bool(q["ok"]) and str(q["reason"]) != "":
		txt += "  [%s]" % str(q["reason"])
	var bs: Array = [dlg.button("Move here", "Costs %d to move in (deposit, first week, movers)" % int(q["due"]), func(): _act(dlg, "move", {"rung": id}), bool(q["ok"]))]
	if id == "council" and SoloHome.council_day < 0:
		bs.append(dlg.button("Join the list", "The council list has a wait", func(): _act(dlg, "apply_council", {})))
	dlg.row_with(txt, bs)

static func _act(dlg: BankHub, action: String, args: Dictionary) -> void:
	var a: Dictionary = args.duplicate()
	a["action"] = action
	var r: Dictionary = Commands.run({"player_id": BankHub.PLAYER_ID, "folk_id": dlg.folk_id, "action": "solo", "args": a})
	if not bool(r.get("ok", false)) and str(r.get("reason", "")) != "":
		UIU.notify(str(r["reason"]), "warn")
	dlg.refresh()
	dlg.call_deferred("_center")
