class_name HouseholdDialog
extends UIDialog
## Coins, bills due / overdue, and what came in and went out over the last 7 days.

func _ready() -> void:
	dialog_width = 420.0
	super._ready()

func build() -> void:
	var hid := int(World.current_household_id) if World.get("current_household_id") != null else 1
	title_label.text = "Household money"
	line("%d Coins" % Economy.balance(hid), 26, UITheme.sem("coin"))
	_bills(hid)
	_utilities(hid)
	_week(hid)

func _bills(hid: int) -> void:
	heading("Bills")
	var w: float = dialog_width - 50.0
	var due: Array = Economy.outstanding(hid)
	var today := SysUtil.day()
	if due.is_empty():
		line("Nothing to pay right now.", 14, UITheme.MUTED)
	for u in Upkeep.upcoming(hid):          # what comes next, with the same numbers that will charge it
		var ui: VBoxContainer = UICard.card(body, w, str(u["what"]), "COMING UP", "")
		UICard.chips(ui, [["About" if str(u["what"]) != "Rent" else "Amount", "%d" % int(u["amount"])], ["Due", "day %d" % int(u["day"])], ["Every", "week"]])
	for bl in due:
		var late := bool(bl.get("late", false))
		var days_left := int(bl["due"]) - today
		var what: String = str(bl.get("reason", "")).capitalize() if str(bl.get("reason", "")) != "" else "Household bills"
		var inner: VBoxContainer = UICard.card(body, w, what, "OVERDUE" if late else "", UtilityBills.describe(bl["parts"]) if bl.has("parts") else "")
		var chips: Array = [["Amount", "%d" % int(bl["amount"])], ["Due", "day %d" % int(bl["due"]) if days_left > 0 else "today"]]
		if late:
			chips.append(["Late fee", "%d" % int(bl.get("fee", 0)), UICard.NO])
		UICard.chips(inner, chips)
	var debt: int = JusticeDebt.owed(Pawn.of())
	if debt > 0:
		var di: VBoxContainer = UICard.card(body, w, "Court debt", "WEEKLY", "Paid every week from money above %d coins; with no income the court orders community service instead." % int(JusticeState.sect("debt").get("floor", 60)))
		UICard.chips(di, [["Owed", "%d" % debt]])
	if not due.is_empty():
		var pay := Button.new()
		pay.text = "Pay all bills (%d)" % Economy.owed(hid)
		pay.disabled = not Economy.can_afford(hid, Economy.owed(hid))
		if pay.disabled:
			pay.tooltip_text = "Not enough coins yet."
			pay.mouse_filter = Control.MOUSE_FILTER_STOP
		pay.pressed.connect(func():
			Commands.run({"action": "pay_bill", "args": {"household_id": hid}})
			refresh())
		body.add_child(pay)
	line("Auto-pay is %s." % ("on: bills are paid on the due date when you can afford them" if Economy.autopay_for(hid) else "off: pay here before they go overdue"), 11, UITheme.MUTED)

func _utilities(hid: int) -> void:
	heading("Utilities")
	var items: Array = []
	for l in Utilities.status_lines(hid):
		var txt: String = str(l)
		var ok: bool = txt.find("working") >= 0
		items.append([txt.get_slice(":", 0), ok])
	UICard.reqs(body, items)
	for l2 in Utilities.status_lines(hid):
		if str(l2).find("working") < 0:
			line(str(l2), 12, UITheme.sem("warn"))

func _week(hid: int) -> void:
	heading("Last 7 days")
	var today := SysUtil.day()
	var income := 0
	var spent := 0
	var by_reason: Dictionary = {}
	for e in Economy.ledger_for(hid):
		if int(e["day"]) <= today - 7:
			continue
		if str(e["reason"]) == "starting funds":
			continue
		var amt := int(e["amount"])
		if amt >= 0:
			income += amt
		else:
			spent -= amt
		var key := _reason_text(str(e["reason"]), amt >= 0)
		by_reason[key] = int(by_reason.get(key, 0)) + amt
	UICard.chips(body, [["Income", "+%d" % income, UICard.OK], ["Spending", "-%d" % spent, UICard.NO]])
	var keys: Array = by_reason.keys()
	keys.sort_custom(func(a, b): return absi(int(by_reason[a])) > absi(int(by_reason[b])))
	for k in keys.slice(0, 6):
		line("   %s: %+d" % [k, int(by_reason[k])], 12, UITheme.MUTED)
	if keys.is_empty():
		line("   Nothing yet.", 12, UITheme.MUTED)

static func _reason_text(r: String, gain: bool) -> String:
	if r == "":
		return "Income" if gain else "Spending"
	if r.begins_with("perk: "):
		return "Perk reward"
	return UIU.sentence(r.replace("_", " ").replace("/", " and "))
