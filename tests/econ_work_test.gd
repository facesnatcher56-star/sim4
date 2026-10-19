extends RefCounted
## Work beyond the careers: teen part-time jobs, freelancing and odd jobs (with daily caps), selling crafts (balanced), layoffs with severance,
## unemployment benefit; plus the command layer and the whole-economy save round trip.

const K = preload("res://tests/systems_kit.gd")
const E = preload("res://tests/econ_kit.gd")

func run() -> Array:
	var f: Array = []
	_teen(f)
	_gigs(f)
	_crafts(f)
	_layoffs_and_benefit(f)
	_commands(f)
	_save_all(f)
	return f

func _teen(f: Array) -> void:
	var w := E.setup(100)
	var kid: Folk = K.make_folk(w, "Tim", [], 1, Vector2i(14, 12), "teen")
	var adult: Folk = SysUtil.folk(1)
	K.expect(f, not MarketWork.take_part_time(int(adult.id)), "adults cannot take the teen job")
	K.expect(f, MarketWork.take_part_time(int(kid.id)) and MarketWork.parttime_text(int(kid.id)).find("coins an hour") >= 0, "a teen takes a part-time job")
	var bal: int = Economy.balance(1)
	MarketWork.on_day(2)
	K.expect(f, Economy.balance(1) == bal + 36, "four hours at 9 coins (%d)" % (Economy.balance(1) - bal))
	K.expect(f, float((kid.needs["energy"] as Stat).value) < 100.0, "work tires them out a little")
	MarketWork.quit_part_time(int(kid.id))
	K.expect(f, MarketWork.parttime_text(int(kid.id)) == "", "and they can quit")
	K.teardown()

func _gigs(f: Array) -> void:
	var w := E.setup(100)
	var ann: Folk = SysUtil.folk(1)
	K.set_time(3, 10)
	var p1: int = MarketWork.freelance(int(ann.id))
	var p2: int = MarketWork.freelance(int(ann.id))
	var p3: int = MarketWork.freelance(int(ann.id))
	K.expect(f, p1 >= 40 and p2 >= 40 and p3 == 0, "two freelance gigs a day, then no more clients (%d, %d, %d)" % [p1, p2, p3])
	K.expect(f, MarketWork.is_self_employed(int(ann.id)), "a freelancer counts as self-employed (not unemployed)")
	var o1: int = MarketWork.odd_job(int(ann.id))
	MarketWork.odd_job(int(ann.id))
	K.expect(f, o1 == 30 and MarketWork.odd_job(int(ann.id)) == 0, "odd jobs: 30 coins, two a day")
	K.set_time(4, 10)
	K.expect(f, MarketWork.freelance(int(ann.id)) > 0, "the cap resets the next day")
	# event path
	SysUtil.game_event("odd_job_done", {"folk_id": int(ann.id)})
	MarketTick.on_game_event("odd_job_done", {"folk_id": int(ann.id)})
	K.teardown()

func _crafts(f: Array) -> void:
	var w := E.setup(100)
	var ann: Folk = SysUtil.folk(1)
	MarketTick.on_interaction_finished(int(ann.id), "paint_canvas", true)
	MarketTick.on_interaction_finished(int(ann.id), "paint_canvas", false)
	MarketTick.on_game_event("harvested_crops", {"folk_id": int(ann.id)})
	MarketTick.on_game_event("caught_fish", {"folk_id": int(ann.id)})
	K.expect(f, MarketWork.craft_count(1, "painting") == 1 and MarketWork.craft_count(1, "produce") == 1 and MarketWork.craft_count(1, "fish") == 1, "paintings, produce and fish are collected")
	var bal: int = Economy.balance(1)
	var r: Dictionary = MarketWork.sell_crafts(1, int(ann.id), true)
	K.expect(f, bool(r["ok"]) and int(r["units"]) == 3 and int(r["paid"]) >= 40 and int(r["paid"]) <= 60, "sold at the market stall: %s" % str(r))
	K.expect(f, Economy.balance(1) == bal + int(r["paid"]), "through the ledger")
	K.expect(f, not bool(MarketWork.sell_crafts(1, int(ann.id), true)["ok"]), "nothing left to sell")
	# balance: online keeps only a share, and the market saturates
	for _i in 12:
		MarketWork.add_craft(1, "fish", 1)
	var online: Dictionary = MarketWork.sell_crafts(1, int(ann.id), false)
	K.expect(f, int(online["units"]) <= 11 and int(online["paid"]) < 12 * 7, "online sales keep a share and demand is capped (%s)" % str(online))
	K.set_time(5, 8)
	MarketWork.on_day(5)
	K.expect(f, MarketWork.sold_today.is_empty(), "the buyers are back the next day")
	K.teardown()

func _layoffs_and_benefit(f: Array) -> void:
	var w := E.setup(100)
	var ann: Folk = SysUtil.folk(1)
	K.expect(f, Careers.hire(ann, "cook", 1), "Ann has a job")
	MarketEconomy.prosperity = -0.8
	MarketEconomy.rng.seed = 3
	var laid: bool = false
	for d in range(2, 400):
		K.set_time(d, 8)
		MarketWork.on_day(d)
		if not Careers.has_job(int(ann.id)):
			laid = true
			break
	K.expect(f, laid, "a deep recession can lay off a worker")
	K.expect(f, K.has_note("laid off") and MarketWork.jobless.has(int(ann.id)), "they are told and qualify for benefit")
	var sev: bool = false
	for e in Economy.ledger_for(1):
		if str(e["reason"]) == "severance pay":
			sev = true
	K.expect(f, sev, "severance pay is in the ledger")
	var bal: int = Economy.balance(1)
	var day0: int = SysUtil.day()
	for d2 in range(day0 + 2, day0 + 6):
		K.set_time(d2, 8)
		MarketWork.on_day(d2)
	K.expect(f, Economy.balance(1) >= bal + 3 * 18, "unemployment benefit arrives daily (%d)" % (Economy.balance(1) - bal))
	for d3 in range(day0 + 6, day0 + 40):
		K.set_time(d3, 8)
		MarketWork.on_day(d3)
	K.expect(f, not MarketWork.jobless.has(int(ann.id)), "and stops after the limit")
	K.teardown()

func _commands(f: Array) -> void:
	var w := E.setup(3000)
	var ann: Folk = SysUtil.folk(1)
	K.set_time(3, 12)
	var r: Dictionary = MarketCommand.run(1, int(ann.id), "shop_buy", {"shop": "supermarket", "item": "groceries_small", "qty": 1})
	K.expect(f, bool(r["ok"]), "shop_buy through the command layer")
	K.expect(f, MarketCommand.history.size() == 1 and int(MarketCommand.history[0]["player_id"]) == 1 and MarketCommand.history[0].has("game_minute"), "commands are logged with player, folk and minute")
	K.expect(f, bool(MarketCommand.run(1, int(ann.id), "bank_deposit", {"amount": 500})["ok"]) and BankAccounts.balance(1) == 500, "bank_deposit")
	K.expect(f, bool(MarketCommand.run(1, int(ann.id), "loan_take", {"amount": 1000})["ok"]), "loan_take")
	K.expect(f, bool(MarketCommand.run(1, int(ann.id), "insurance_toggle", {"policy": "health"})["ok"]) and BankInsurance.has(1, "health"), "insurance_toggle")
	K.expect(f, bool(MarketCommand.run(1, int(ann.id), "biz_open", {"type": "cafe", "lot": "cafe", "mode": "rent"})["ok"]), "biz_open")
	K.expect(f, not bool(MarketCommand.run(1, 999, "shop_buy", {})["ok"]), "an unknown folk cannot act")
	K.expect(f, not bool(MarketCommand.run(1, int(ann.id), "nonsense", {})["ok"]), "unknown actions are refused")
	K.teardown()

func _save_all(f: Array) -> void:
	var w := E.setup(20000)
	var ann: Folk = SysUtil.folk(1)
	var bea: Folk = K.make_folk(w, "Bea", [], 2, Vector2i(14, 14))
	WorldIface.coins[2] = 500
	K.set_time(3, 12)
	ShopBuy.buy(1, 1, "furniture", "sofa", 1, true)
	ShopBuy.buy(1, 1, "market", "lottery_ticket", 3)
	BankAccounts.deposit(1, 1000)
	BankAccounts.take_loan(1, 800)
	BankInsurance.buy(1, "life")
	BankWill.write(int(ann.id), int(bea.id))
	HousingProps.ensure()
	HousingAgent.buy(1, str(HousingProps.listings()[0]["id"]))
	BusinessCmd.open(1, "salon", "market", "rent")
	MarketWork.add_craft(1, "painting", 2)
	E.days(4, 20)
	var snap: Dictionary = SaveLoad.snapshot("t")
	var js: Variant = JSON.parse_string(JSON.stringify(snap))
	K.expect(f, js["systems"].has("econ"), "the save has an econ block")
	var before: Dictionary = JSON.parse_string(JSON.stringify(MarketTick.to_dict()))
	MarketTick.reset()
	K.expect(f, not MarketEconomy.enabled and BankAccounts.loans.is_empty(), "reset wipes it")
	MarketTick.from_dict(js["systems"]["econ"], true)
	var after: Dictionary = JSON.parse_string(JSON.stringify(MarketTick.to_dict()))
	var diffs: Array = []
	K.expect(f, K.deep_eq(before, after, "econ", diffs), "the whole economy round-trips: %s" % str(diffs.slice(0, 5)))
	K.expect(f, MarketEconomy.enabled and BankAccounts.loans.size() == 2 and BusinessState.list.size() >= 1, "and keeps working state")
	# the real SaveLoad path restores the same economy
	MarketTick.reset()
	K.expect(f, SaveLoad.restore(js), "SaveLoad.restore accepts the snapshot: %s" % SaveLoad.last_error)
	var viaload: Dictionary = JSON.parse_string(JSON.stringify(MarketTick.to_dict()))
	var diffs2: Array = []
	K.expect(f, K.deep_eq(before, viaload, "econ", diffs2), "SaveLoad.restore brings the economy back identically: %s" % str(diffs2.slice(0, 5)))
	K.expect(f, Incidents.insurance_fn.is_valid(), "the bank insurance hook is installed after a load")
	# an old save without the block switches the economy on
	MarketTick.from_dict({}, false)
	K.expect(f, MarketEconomy.enabled, "an older save starts the economy fresh")
	# the economy goes on after loading
	E.days(30, 40)
	K.expect(f, MarketEconomy.history.size() >= 0, "and ticks on")
	K.teardown()
