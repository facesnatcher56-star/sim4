class_name ShopDialog
extends RefCounted
## The "Shops" tab of BankHub: pick a shop (open now where you stand, or order online), buy, use what you bought, sell your crafts.

static var shop_id: String = "supermarket"

static func build(dlg: BankHub) -> void:
	var folk_id: int = dlg.folk_id
	var f = dlg.folk_obj()
	var here: String = Neighborhood.lot_of(f) if f != null else ""
	dlg.heading("Choose a shop")
	var row := HFlowContainer.new()
	dlg.body.add_child(row)
	for sid in ShopStock.shop_ids():
		var sh: Dictionary = ShopStock.shop(sid)
		var b := Button.new()
		b.text = str(sh["label"]) + (" *" if ShopStock.on_sale(sid) else "")
		b.toggle_mode = true
		b.button_pressed = (sid == shop_id)
		b.tooltip_text = "%s, %02d:00 to %02d:00%s" % [Neighborhood.label_of(str(sh["lot"])), int(sh["hours"][0]), int(sh["hours"][1]), ("; on sale" if ShopStock.on_sale(sid) else "")]
		b.pressed.connect(func():
			shop_id = sid
			dlg.refresh())
		row.add_child(b)
	var sh2: Dictionary = ShopStock.shop(shop_id)
	if sh2.is_empty():
		return
	var lot: String = str(sh2["lot"])
	var inside: bool = ShopStock.is_open(shop_id) and here == lot
	var where: String = "You are here and it is open." if inside else ("Open %02d:00 to %02d:00 at %s." % [int(sh2["hours"][0]), int(sh2["hours"][1]), Neighborhood.label_of(lot)])
	dlg.line(where, 12, UITheme.MUTED)
	if ShopStock.on_sale(shop_id):
		dlg.line("SALE: %d%% off today." % int(round(ShopStock.deal_pct(shop_id) * 100.0)), 14, UITheme.sem("coin"))
	var cw: float = dlg.dialog_width - 50.0
	var online: bool = bool(sh2.get("online", false))
	var items: Dictionary = sh2["items"]
	if not inside:          # said once for the whole shop, not on every item
		var open_now: bool = ShopStock.is_open(shop_id)
		var msg: String = ("You are not there. " if open_now else "It is closed. ") + ("You can go there" if open_now else "Come back later") + (" or have things delivered." if online else ".")
		var fid0: int = folk_id
		var goto_row := HBoxContainer.new()
		dlg.body.add_child(goto_row)
		goto_row.add_child(UIU.make_label(msg, 13, UITheme.MUTED))
		if open_now:
			goto_row.add_child(dlg.button("Go there", "Walk to " + Neighborhood.label_of(lot), func(): Commands.run({"folk_id": fid0, "action": "travel", "args": {"folk_ids": [fid0], "lot_id": lot}}), true))
	for iid in items.keys():
		var it: Dictionary = items[iid]
		var have: int = ShopStock.units(shop_id, iid)
		var price: int = ShopStock.price(shop_id, iid)
		var card: VBoxContainer = UICard.card(dlg.body, cw, str(it["label"]), "SOLD OUT" if have <= 0 else "")
		UICard.chips(card, [["Price", "%d" % price], ["Left", "%d" % have]])
		if have <= 0:
			continue
		if inside:
			UICard.action(card, "Buy", func(): dlg.act("shop_buy", {"shop": shop_id, "item": iid, "qty": 1, "online": false}), true, "")
		if online:
			var ob: Button = dlg.button("Order (+%d delivery)" % int(ShopStock.cfg().get("delivery_fee", 8)), "Delivered tomorrow", func(): dlg.act("shop_buy", {"shop": shop_id, "item": iid, "qty": 1, "online": true}), true)
			card.add_child(ob)
	_owned(dlg, folk_id)
	_work(dlg, folk_id, here)

static func _owned(dlg: BankHub, folk_id: int) -> void:
	var h: int = dlg.hid()
	var inv: Dictionary = ShopStock.inventory.get(h, {})
	var parcels: Dictionary = ShopStock.parcels.get(h, {})
	if inv.is_empty() and parcels.is_empty() and ShopStock.orders.is_empty():
		return
	dlg.heading("What you have bought")
	for iid in inv:
		dlg.row_with("%s x%d" % [_label_of(str(iid)), int(inv[iid])], [dlg.button("Use", "Use one", func(): dlg.act("shop_use", {"item": iid}))])
	for did in parcels:
		dlg.line("%s x%d: place it in Build/Buy at no extra cost." % [str(SimEnv.data().object_def(str(did)).get("label", did)), int(parcels[did])], 13)
	for o in ShopStock.orders:
		if int(o["hid"]) == h:
			dlg.line("On its way: %s (due day %d)." % [_label_of(str(o["item"])), int(o["due"])], 13, UITheme.MUTED)

static func _label_of(iid: String) -> String:
	for sid in ShopStock.shop_ids():
		var it: Dictionary = ShopStock.item(sid, iid)
		if not it.is_empty():
			return str(it.get("label", iid))
	return iid

static func _work(dlg: BankHub, folk_id: int, here: String) -> void:
	var f = dlg.folk_obj()
	var h: int = dlg.hid()
	dlg.heading("Make a little money")
	var total: int = 0
	for kind in MarketWork.cfg().get("crafts", {}):
		total += MarketWork.craft_count(h, str(kind))
	if total > 0:
		dlg.row_with("You have %s to sell (paintings, books, produce, fish)." % SysUtil.count_text(total, "thing"), [
			dlg.button("At the market", "Full price; you must be at the market", func(): dlg.act("craft_sell", {"at_market": true}), here == "market"),
			dlg.button("Online", "Sell from home, keeping a share", func(): dlg.act("craft_sell", {"at_market": false}))])
	else:
		var mc: VBoxContainer = UICard.card(dlg.body, dlg.dialog_width - 50.0, "Nothing to sell yet", "", "Paint, write, garden or fish, then sell your crafts here. Freelance work and odd jobs are on your computer and mailbox.")
		UICard.note(mc, "Odd jobs: click the mailbox. Crafts: paint, write, garden or fish first.")
	if f != null and f.age_stage == "teen":
		var pt: String = MarketWork.parttime_text(folk_id)
		if pt == "":
			dlg.row_with("A part-time job after school is open to teens.", [dlg.button("Take it", "", func(): dlg.act("work_teen", {"take": true}))])
		else:
			dlg.row_with(pt, [dlg.button("Quit", "", func(): dlg.act("work_teen", {"take": false}))])
	if MarketWork.jobless.has(folk_id):
		dlg.line("You are on unemployment benefit.", 13, UITheme.MUTED)
	pass
