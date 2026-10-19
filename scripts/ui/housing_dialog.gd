class_name HousingDialog
extends RefCounted
## The "Homes" tab of BankHub: your home and any other property (value, rent, mortgage), the estate agent's listings and the actions on them.

static func build(dlg: BankHub) -> void:
	var h: int = dlg.hid()
	HousingProps.ensure()
	var home: Dictionary = HousingProps.home_prop(h)
	dlg.heading("Your home")
	if not home.is_empty():
		_prop(dlg, home, h)
	var mine: Array = HousingProps.owned_by(h)
	var others: Array = []
	for p in mine:
		if str(p["id"]) != str(home.get("id", "")):
			others.append(p)
	if not others.is_empty():
		dlg.heading("Other property you own")
		for p in others:
			_prop(dlg, p, h)
	dlg.heading("For sale (estate agent)")
	for p in HousingProps.listings():
		var q: Dictionary = HousingAgent.quote(h, str(p["id"]))
		dlg.row_with("%s: asking %d. %s. Down payment %d, about %d a week." % [str(p["label"]), int(q["price"]), HousingProps.condition_text(p), int(q["down_min"]), int(q["payment"])], [
			dlg.button("Buy", "Mortgage at %.1f%% a year; fee %d coins" % [float(q["rate"]) * 100.0, int(q["fee"])], func(): dlg.act("house_buy", {"prop": str(p["id"]), "down": -1}),
				Economy.can_afford(h, int(q["down_min"]) + int(q["fee"])))])
	dlg.line("Selling the home you live in means you stay on as tenants of the buyer.", 12, UITheme.MUTED)

static func _prop(dlg: BankHub, p: Dictionary, h: int) -> void:
	var pid: String = str(p["id"])
	var owner_you: bool = str(p["owner_kind"]) == "player" and int(p["owner"]) == h
	var t: String = "%s: worth %d. %s" % [str(p["label"]), HousingProps.value(p), "; ".join(HousingProps.value_notes(p))]
	dlg.line(t, 13)
	var l: Dictionary = BankAccounts.find(int(p["mortgage"]))
	if not l.is_empty():
		dlg.line("Mortgage: %d left, %d coins a week." % [int(l["balance"]), int(l["payment"])], 13, UITheme.MUTED)
	if owner_you:
		var bs: Array = []
		var net: int = HousingAgent.net_sale(p)
		bs.append(dlg.button("Sell", "You would get about %d coins after the agent and the mortgage" % net, func(): dlg.act("house_sell", {"prop": pid}), net >= 0))
		bs.append(dlg.button("Repair", "Raise the condition", func(): dlg.act("house_repair", {"prop": pid}), float(p["condition"]) < 90.0))
		if str(p["tenant_kind"]) != "player":
			if bool(p["to_let"]):
				bs.append(dlg.button("Stop letting", "", func(): dlg.act("house_stop_letting", {"prop": pid})))
			else:
				bs.append(dlg.button("Rent out", "At the going rate of %d a week" % HousingProps.market_rent(p), func(): dlg.act("house_rent_out", {"prop": pid})))
		dlg.row_with("You own it.%s" % _tenant_text(p), bs)
		if str(p["tenant_kind"]) == "townie":
			var rent: int = int(p["rent"])
			dlg.row_with("Rent %d a week (the market rate is %d)." % [rent, HousingProps.market_rent(p)], [
				dlg.button("+5%", "", func(): dlg.act("house_set_rent", {"prop": pid, "rent": int(round(float(rent) * 1.05))})),
				dlg.button("-5%", "", func(): dlg.act("house_set_rent", {"prop": pid, "rent": int(round(float(rent) * 0.95))})),
				dlg.button("Evict", "Ask the tenant to leave", func(): dlg.act("house_evict", {"prop": pid}))])
	else:
		var q: Dictionary = HousingAgent.quote(h, pid)
		var rent_t: String = "You rent it for %d a week." % int(p["rent"]) if str(p["tenant_kind"]) == "player" else ""
		dlg.row_with(rent_t, [dlg.button("Buy it back", "Price %d" % int(q.get("price", 0)), func(): dlg.act("house_buy", {"prop": pid, "down": -1}), HousingAgent.can_buy(p, h))])

static func _tenant_text(p: Dictionary) -> String:
	match str(p["tenant_kind"]):
		"player":
			return " You live there."
		"townie":
			return " %s rents it." % Story.name_of(int(p["tenant"]))
	return " It is empty."
