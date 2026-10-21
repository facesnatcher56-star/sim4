class_name MarketCommand
extends RefCounted
## The command layer of the economy track (multiplayer-ready rule 1): every player action of the shop / business / bank / housing / work UI is
## `run(player_id, folk_id, action, args)` -> {ok, reason, ...}. The household comes from the folk (never "household 1"); the UI never touches
## state. Every command is logged `{player_id, folk_id, action, args, game_minute}` (capped) so it can be replayed or sent over a wire.

const LOG_CAP := 40
static var history: Array = []

static func reset() -> void:
	history.clear()

static func _hid(folk_id: int) -> int:
	var f = SysUtil.folk(folk_id)
	return int(f.household_id) if f != null else -1

static func run(player_id: int, folk_id: int, action: String, args: Dictionary = {}) -> Dictionary:
	var hid: int = _hid(folk_id)
	if hid <= 0:
		return {"ok": false, "reason": "Nobody is acting."}
	history.append({"player_id": player_id, "folk_id": folk_id, "action": action, "args": args.duplicate(true), "game_minute": SysUtil.now()})
	while history.size() > LOG_CAP:
		history.pop_front()
	var a: Dictionary = args
	if action in ["bank_deposit", "bank_withdraw", "loan_take"]:          # task 46: done at the bank counter (the phone keeps balance, repaying, insurance)
		var bf = SysUtil.folk(folk_id)
		if BankBranch.needs_branch(bf) and not BankBranch.at_counter(bf):
			return {"ok": false, "reason": "That's done at the bank counter."}
	match action:
		# shops
		"shop_buy":
			return ShopBuy.buy(hid, folk_id, str(a.get("shop", "")), str(a.get("item", "")), int(a.get("qty", 1)), bool(a.get("online", false)))
		"shop_use":
			var n: int = ShopBuy.use(hid, int(a.get("target", folk_id)), str(a.get("item", "")), int(a.get("qty", 1)))
			return {"ok": n > 0, "reason": "" if n > 0 else "Nothing happened.", "used": n}
		"craft_sell":
			return MarketWork.sell_crafts(hid, folk_id, bool(a.get("at_market", false)))
		# bank
		"bank_deposit":
			return _bool(BankAccounts.deposit(hid, int(a.get("amount", 0))), "Not enough coins.")
		"bank_withdraw":
			return _bool(BankAccounts.withdraw(hid, int(a.get("amount", 0))), "Not enough in savings.")
		"loan_take":
			return BankAccounts.take_loan(hid, int(a.get("amount", 0)), int(a.get("term", -1)))
		"loan_repay":
			var paid: int = BankAccounts.repay(hid, int(a.get("loan", 0)), int(a.get("amount", 0)))
			return {"ok": paid > 0, "reason": "" if paid > 0 else "Could not repay that.", "paid": paid}
		"insurance_toggle":
			return {"ok": true, "reason": "", "on": BankInsurance.toggle(hid, str(a.get("policy", "")))}
		"home_insurance_cycle":
			return {"ok": true, "reason": "", "level": DisasterInsurance.cycle(hid)}
		"will_write":
			return _bool(BankWill.write(folk_id, int(a.get("heir", -1))), "They cannot be named.")
		"gamble_cards":
			return BankGamble.play_cards(hid, folk_id, int(a.get("stake", 0)))
		# work
		"work_teen":
			if bool(a.get("take", true)):
				return _bool(MarketWork.take_part_time(folk_id), "Only teens can take a part-time job.")
			MarketWork.quit_part_time(folk_id)
			return {"ok": true, "reason": ""}
		# business
		"biz_open":
			return BusinessCmd.open(hid, str(a.get("type", "")), str(a.get("lot", "")), str(a.get("mode", "rent")), str(a.get("name", "")))
		"biz_price":
			return BusinessCmd.set_price(hid, int(a.get("id", 0)), float(a.get("price", 1.0)))
		"biz_hours":
			return BusinessCmd.set_hours(hid, int(a.get("id", 0)), int(a.get("open", 9)), int(a.get("close", 17)))
		"biz_open_close":
			return BusinessCmd.set_open(hid, int(a.get("id", 0)), bool(a.get("open", true)))
		"biz_auto_stock":
			return BusinessCmd.set_auto_stock(hid, int(a.get("id", 0)), bool(a.get("on", true)))
		"biz_stock":
			return BusinessCmd.restock(hid, int(a.get("id", 0)), int(a.get("units", 20)))
		"biz_hire":
			return BusinessCmd.hire(hid, int(a.get("id", 0)), int(a.get("tid", 0)))
		"biz_fire":
			return BusinessCmd.fire(hid, int(a.get("id", 0)), int(a.get("tid", 0)))
		"biz_expand":
			return BusinessCmd.expand(hid, int(a.get("id", 0)))
		"biz_sell":
			return BusinessCmd.sell(hid, int(a.get("id", 0)))
		# housing
		"house_buy":
			return HousingAgent.buy(hid, str(a.get("prop", "")), int(a.get("down", -1)))
		"house_sell":
			return HousingAgent.sell(hid, str(a.get("prop", "")))
		"house_rent_out":
			return HousingAgent.rent_out(hid, str(a.get("prop", "")), int(a.get("rent", -1)))
		"house_stop_letting":
			return HousingAgent.stop_letting(hid, str(a.get("prop", "")))
		"house_set_rent":
			return HousingAgent.set_rent(hid, str(a.get("prop", "")), int(a.get("rent", 0)))
		"house_repair":
			return HousingAgent.repair(hid, str(a.get("prop", "")))
		"house_evict":
			return HousingAgent.evict_tenant(hid, str(a.get("prop", "")))
	return {"ok": false, "reason": "Unknown action."}

static func _bool(ok: bool, why: String) -> Dictionary:
	return {"ok": ok, "reason": "" if ok else why}
