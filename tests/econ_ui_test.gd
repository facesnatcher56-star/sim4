extends RefCounted
## The Town & Money window (headless): every tab builds, the buttons run MarketCommands, nothing is shown before the economy starts.

const K = preload("res://tests/systems_kit.gd")
const E = preload("res://tests/econ_kit.gd")

func _texts(n: Node, out: Array = []) -> Array:
	for c in n.get_children():
		if c is Label:
			out.append((c as Label).text)
		elif c is Button:
			out.append("[" + (c as Button).text + "]")
		_texts(c, out)
	return out

func _button(n: Node, text: String) -> Button:
	for c in n.get_children():
		if c is Button and (c as Button).text == text and not (c as Button).disabled:
			return c
		var r: Button = _button(c, text)
		if r != null:
			return r
	return null

func run() -> Array:
	var f: Array = []
	var root: Window = Engine.get_main_loop().root
	var w := K.setup()
	K.make_folk(w, "Ann Rowe")
	WorldIface.coins[1] = 6000
	Story.generate_townies(12)
	var hub := BankHub.new()
	root.add_child(hub)
	hub.show_for(1)
	K.expect(f, "\n".join(_texts(hub.body)).find("has not started") >= 0, "before the economy starts the window says so")
	MarketTick.new_game()
	for d in range(2, 12):
		E.day(d)
	K.set_time(12, 12)
	hub.show_for(1)
	var txt: String = "\n".join(_texts(hub.body))
	K.expect(f, txt.find("THE ECONOMY") >= 0 and txt.find("Credit score") >= 0 and txt.find("Nothing here is required") >= 0, "Town tab: stats, standing, optional note")
	# shops
	hub._pick("shops")
	txt = "\n".join(_texts(hub.body))
	K.expect(f, txt.find("[Supermarket") >= 0 and txt.find("Grocery bag") >= 0 and txt.find("MAKE A LITTLE MONEY") >= 0, "Shops tab lists shops, items and work")
	var order: Button = _button(hub.body, "Order")
	K.expect(f, order != null, "an Order button exists (online delivery)")
	var bal: int = Economy.balance(1)
	order.pressed.emit()
	K.expect(f, Economy.balance(1) < bal and ShopStock.orders.size() == 1, "pressing it places an online order through a command")
	K.expect(f, MarketCommand.history.size() >= 1 and str(MarketCommand.history[MarketCommand.history.size() - 1]["action"]) == "shop_buy", "the UI acts only through MarketCommand")
	# business
	hub._pick("business")
	txt = "\n".join(_texts(hub.body))
	K.expect(f, txt.find("OPEN A BUSINESS") >= 0 and txt.find("optional") >= 0, "Business tab offers opening one, optional")
	var rent: Button = _button(hub.body, "Rent")
	K.expect(f, rent != null, "a Rent button exists")
	rent.pressed.emit()
	K.expect(f, BusinessState.of_owner("player", 1).size() == 1, "renting opens the business")
	txt = "\n".join(_texts(hub.body))
	K.expect(f, txt.find("Reputation") >= 0 and txt.find("Prices:") >= 0 and txt.find("Expand for") >= 0, "and its management panel appears")
	var p115: Button = _button(hub.body, "115%")
	K.expect(f, p115 != null, "price buttons")
	p115.pressed.emit()
	K.expect(f, absf(float(BusinessState.of_owner("player", 1)[0]["price"]) - 1.15) < 0.01, "a price button sets the price")
	# homes
	hub._pick("homes")
	txt = "\n".join(_texts(hub.body))
	K.expect(f, txt.find("YOUR HOME") >= 0 and txt.find("FOR SALE") >= 0 and txt.find("Down payment") >= 0, "Homes tab shows the home and listings")
	var buy: Button = _button(hub.body, "Buy")
	K.expect(f, buy != null, "a Buy button for a listing")
	var owned0: int = HousingProps.owned_by(1).size()
	buy.pressed.emit()
	K.expect(f, HousingProps.owned_by(1).size() == owned0 + 1 or K.has_note("coins") or K.has_note("deposit"), "buying goes through the agent")
	# bank
	hub._pick("bank")
	txt = "\n".join(_texts(hub.body))
	K.expect(f, txt.find("YOUR ACCOUNTS") >= 0 and txt.find("Insurance") >= 0 or txt.find("INSURANCE") >= 0, "Bank tab")
	var save: Button = _button(hub.body, "Save 100")
	K.expect(f, save != null, "Save 100 button")
	save.pressed.emit()
	K.expect(f, BankAccounts.balance(1) == 100, "saving works through a command")
	var borrow: Button = _button(hub.body, "Borrow 500")
	if borrow != null:
		borrow.pressed.emit()
		K.expect(f, BankAccounts.loans_of(1, "loan").size() == 1, "borrowing works")
	K.expect(f, "\n".join(_texts(hub.body)).find("YOUR WILL") >= 0 and "\n".join(_texts(hub.body)).find("LUCK") >= 0, "will and luck sections")
	# the mailbox interaction opens the window on the bank tab
	hub.hide_dialog()
	hub.tab = "town"
	Events.game_event.emit("open_money", {"folk_id": 1})
	K.expect(f, hub.visible and hub.tab == "bank", "the mailbox interaction opens the window")
	root.remove_child(hub)
	hub.free()
	K.teardown()
	return f
