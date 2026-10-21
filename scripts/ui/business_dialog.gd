class_name BusinessDialog
extends RefCounted
## The "Business" tab of BankHub: your businesses (prices, hours, staff, stock, reviews, profit, expand, sell) or how to open one.
## Optional: with no business it is just a short menu. Rivals owned by townies are listed so you can see the competition.

static var new_type: String = "cafe"

static func build(dlg: BankHub) -> void:
	var h: int = dlg.hid()
	var mine: Array = BusinessState.of_owner("player", h)
	if mine.is_empty():
		dlg.line("You don't run a business. One can earn steady money, or lose it.", 13, UITheme.MUTED)
	for b in mine:
		_mine(dlg, b)
	_open_menu(dlg, h)
	_rivals(dlg)

static func _mine(dlg: BankHub, b: Dictionary) -> void:
	var id: int = int(b["id"])
	var td: Dictionary = BusinessState.type_def(str(b["type"]))
	dlg.heading("%s (%s, %s)" % [str(b["name"]), str(td.get("label", "")), Neighborhood.label_of(str(b["lot"]))])
	var last: Dictionary = b["last"]
	var week: float = 0.0
	for p in b["hist"]:
		week += float(p)
	var pf: int = int(last.get("profit", 0))
	UICard.chips(dlg.body, [["Stars", "%.1f" % float(b["stars"])], ["Size", "%d" % int(b["level"])], ["Customers", "%d" % int(last.get("customers", 0))]])          # no hidden reputation score: the stars are what an owner sees
	UICard.chips(dlg.body, [["In", "%d" % int(last.get("revenue", 0))], ["Out", "%d" % int(last.get("costs", 0))], ["Profit", "%+d" % pf, UICard.OK if pf >= 0 else UICard.NO],
		["%dd" % (b["hist"] as Array).size(), "%+d" % int(week)], ["All time", "%+d" % int(b["profit_total"])]])
	if not bool(b["open"]):
		dlg.line("Closed for the day.", 12, UITheme.MUTED)
	var prices: Array = BusinessState.cfg().get("price_levels", [1.0])
	var pr := HBoxContainer.new()
	dlg.body.add_child(pr)
	pr.add_child(UIU.make_label("Prices:", 13))
	for lv in prices:
		var bt := Button.new()
		bt.text = "%d%%" % int(round(float(lv) * 100.0))
		bt.toggle_mode = true
		bt.button_pressed = absf(float(b["price"]) - float(lv)) < 0.01
		bt.tooltip_text = "Higher prices earn more per customer but cost customers."
		bt.pressed.connect(func(): dlg.act("biz_price", {"id": id, "price": float(lv)}))
		pr.add_child(bt)
	var hrs: Array = b["hours"]
	dlg.row_with("Open %02d:00 to %02d:00." % [int(hrs[0]), int(hrs[1])], [
		dlg.button("Earlier", "Open an hour earlier", func(): dlg.act("biz_hours", {"id": id, "open": maxi(int(hrs[0]) - 1, 0), "close": int(hrs[1])})),
		dlg.button("Later", "Close an hour later", func(): dlg.act("biz_hours", {"id": id, "open": int(hrs[0]), "close": mini(int(hrs[1]) + 1, 24)})),
		dlg.button("Shorter", "Close an hour earlier", func(): dlg.act("biz_hours", {"id": id, "open": int(hrs[0]), "close": int(hrs[1]) - 1})),
		dlg.button("Close today" if bool(b["open"]) else "Reopen", "", func(): dlg.act("biz_open_close", {"id": id, "open": not bool(b["open"])}))])
	dlg.row_with("Stock: %d of %d. %s" % [int(b["stock"]), BusinessState.stock_cap(b), "Restocked automatically." if bool(b["auto_stock"]) else "You restock by hand."], [
		dlg.button("Auto" if not bool(b["auto_stock"]) else "Manual", "Switch automatic restocking", func(): dlg.act("biz_auto_stock", {"id": id, "on": not bool(b["auto_stock"])})),
		dlg.button("+20", "Buy 20 units", func(): dlg.act("biz_stock", {"id": id, "units": 20}), not bool(b["auto_stock"]))])
	for s in b["staff"]:
		dlg.row_with("%s: %d coins an hour, skill %d" % [Story.name_of(int(s["tid"])), int(s["wage"]), int(s["skill"])], [dlg.button("Let go", "", func(): dlg.act("biz_fire", {"id": id, "tid": int(s["tid"])}))])
	if (b["staff"] as Array).size() < BusinessCmd.max_staff(b):
		for c in BusinessCmd.candidates().slice(0, 3):
			dlg.row_with("%s looks for work: skill %d, %d coins an hour." % [str(c["name"]), int(c["skill"]), int(c["wage"])], [dlg.button("Hire", "Hiring fee applies", func(): dlg.act("biz_hire", {"id": id, "tid": int(c["tid"])}))])
	var why: String = BusinessCmd.why_not_expand(b)
	dlg.row_with("Expand for %d coins. %s" % [BusinessCmd.expand_cost(b), why], [
		dlg.button("Expand", "More capacity and customers", func(): dlg.act("biz_expand", {"id": id}), why == ""),
		dlg.button("Sell up", "Sell for about %d coins" % BusinessCmd.sale_value(b), func(): dlg.act("biz_sell", {"id": id}))])
	for r in (b["reviews"] as Array).slice(maxi((b["reviews"] as Array).size() - 3, 0)):
		dlg.line("%s %s" % ["*".repeat(int(r["stars"])), str(r["text"])], 12, UITheme.MUTED)

static func _open_menu(dlg: BankHub, h: int) -> void:
	dlg.heading("Open a business")
	var row := HFlowContainer.new()
	dlg.body.add_child(row)
	for t in BusinessState.type_ids():
		var bt := Button.new()
		bt.text = str(BusinessState.type_def(t)["label"])
		bt.toggle_mode = true
		bt.button_pressed = (t == new_type)
		bt.pressed.connect(func():
			new_type = t
			dlg.refresh())
		row.add_child(bt)
	var td: Dictionary = BusinessState.type_def(new_type)
	if td.is_empty():
		return
	var lots: Array = BusinessState.open_lots_for(new_type)
	if lots.is_empty():
		dlg.line("No free space for a %s right now." % str(td["label"]).to_lower(), 13, UITheme.MUTED)
		return
	var w: float = dlg.dialog_width - 50.0
	var have: int = Economy.balance(h)
	for lot in lots:
		var rent: int = BusinessCmd.open_cost(new_type, str(lot), "rent")
		var own: int = BusinessCmd.open_cost(new_type, str(lot), "own")
		var day_rent: int = int(round(float((BusinessState.cfg().get("lot_rent", {}) as Dictionary).get(str(lot), 30)) * MarketEconomy.rent_mult()))
		var c: VBoxContainer = UICard.card(dlg.body, w, Neighborhood.label_of(str(lot)))
		UICard.chips(c, [["Fit-out", "%d" % rent], ["Rent", "%d/day" % day_rent], ["Buy the space", "%d" % own]])
		var acts := HBoxContainer.new()
		c.add_child(acts)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		acts.add_child(sp)
		acts.add_child(dlg.button("Rent it", "Pay the fit-out, then rent by the day", func(): dlg.act("biz_open", {"type": new_type, "lot": lot, "mode": "rent"}), have >= rent))
		acts.add_child(dlg.button("Buy it", "Pay for the space and the fit-out once", func(): dlg.act("biz_open", {"type": new_type, "lot": lot, "mode": "own"}), have >= own))
		if have < rent:
			UICard.note(c, "Renting needs %d coins; you have %d." % [rent, have])
		elif have < own:
			UICard.note(c, "Buying needs %d coins; you have %d." % [own, have])

static func _rivals(dlg: BankHub) -> void:
	var others: Array = []
	for id in BusinessState.ids_sorted():
		var b: Dictionary = BusinessState.list[id]
		if str(b["owner_kind"]) == "townie":
			others.append(b)
	if others.is_empty():
		return
	dlg.heading("Other businesses in town")
	for b in others:
		dlg.line("%s (%s): %.1f stars at %s." % [str(b["name"]), str(BusinessState.type_def(str(b["type"])).get("label", "")), float(b["stars"]), Neighborhood.label_of(str(b["lot"]))], 13, UITheme.MUTED)
