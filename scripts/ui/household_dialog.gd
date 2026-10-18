class_name HouseholdDialog
extends UIDialog
## Coins, bills due / overdue, and what came in and went out over the last 7 days.

func _ready() -> void:
	dialog_width = 420.0
	super._ready()

func build() -> void:
	var hid := int(World.current_household_id) if World.get("current_household_id") != null else 1
	title_label.text = "Household money"
	line("%d Coins" % Economy.balance(hid), 26, Color("#f2c94c"))
	_bills(hid)
	_week(hid)

func _bills(hid: int) -> void:
	heading("Bills")
	var due: Array = Economy.outstanding(hid)
	var today := SysUtil.day()
	if due.is_empty():
		var nxt := int(Economy.next_bill_day)
		line("Nothing to pay. Next bill arrives around day %d." % nxt if nxt > 0 else "Nothing to pay.", 14, UITheme.MUTED)
	for bl in due:
		var late := bool(bl.get("late", false))
		var days_left := int(bl["due"]) - today
		var when := "OVERDUE (includes a %d coin late fee)" % int(bl.get("fee", 0)) if late else ("due today" if days_left <= 0 else "due in %d day%s (day %d)" % [days_left, "" if days_left == 1 else "s", int(bl["due"])])
		line("%d coins, %s" % [int(bl["amount"]), when], 15, Color("#e8913d") if late else UITheme.TEXT)
	if not due.is_empty():
		var pay := Button.new()
		pay.text = "Pay all bills (%d coins)" % Economy.owed(hid)
		pay.disabled = not Economy.can_afford(hid, Economy.owed(hid))
		if pay.disabled:
			pay.tooltip_text = "Not enough coins yet."
			pay.mouse_filter = Control.MOUSE_FILTER_STOP
		pay.pressed.connect(func():
			Economy.pay_bill(hid)
			refresh())
		body.add_child(pay)
	if Economy.auto_pay:
		line("Bills are paid automatically on the due date if you can afford them. Several missed bills lead to repossession.", 11, UITheme.MUTED)
	else:
		line("Auto-pay is off: pay bills here before they go overdue.", 11, UITheme.MUTED)

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
	line("Income: +%d      Spending: -%d" % [income, spent], 15)
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
	return r.replace("_", " ").replace("/", " and ").capitalize()
