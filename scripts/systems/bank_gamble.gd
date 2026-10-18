class_name BankGamble
extends RefCounted
## Gambling (task 13): a weekly lottery (tickets from the market stalls) and a simple card game, with an addiction track per person.
## Tier: town-wide, DAILY (urges, decay) + a draw every `draw_days`. Active set: households holding tickets + people with addiction > 0.
## Caps: addiction 0..100 (entries below 0.5 are dropped). Everything is seeded; prize odds are in data/shops.json "lottery".
## Health hook (later): the `gambling_addiction` game event fires once when somebody becomes hooked.

static var tickets: Dictionary = {}     # hid -> tickets for the next draw
static var addiction: Dictionary = {}   # folk id -> 0..100
static var streak: Dictionary = {}      # folk id -> consecutive losses (cards / draws)
static var hooked: Dictionary = {}      # folk id -> true once the event fired
static var jackpot: int = 0
static var next_draw: int = 0
static var last_draw: Dictionary = {}   # {day, jackpot_won, winner}
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func reset() -> void:
	tickets.clear()
	addiction.clear()
	streak.clear()
	hooked.clear()
	jackpot = 0
	next_draw = 0
	last_draw = {}
	rng = RandomNumberGenerator.new()
	rng.seed = 130031

static func cfg() -> Dictionary:
	return SysUtil.table("shops").get("lottery", {})

static func _start_jackpot() -> int:
	return int(cfg().get("jackpot_start", 400))

static func current_jackpot() -> int:
	return maxi(jackpot, _start_jackpot())

static func tickets_of(hid: int) -> int:
	return int(tickets.get(hid, 0))

static func level_of(folk_id: int) -> float:
	return float(addiction.get(folk_id, 0.0))

static func is_hooked(folk_id: int) -> bool:
	return level_of(folk_id) >= float((cfg().get("addiction", {}) as Dictionary).get("hooked_at", 40))

# ------------------------------------------------------------------ buying
static func add_tickets(hid: int, qty: int, folk_id: int = -1) -> void:
	tickets[hid] = tickets_of(hid) + qty
	jackpot = current_jackpot() + qty * int(cfg().get("jackpot_add_per_ticket", 3))
	if folk_id >= 0:
		_gain(folk_id, float(cfg().get("addiction", {}).get("gain_per_ticket", 1.2)) * float(qty))

static func _gain(folk_id: int, amount: float) -> void:
	addiction[folk_id] = clampf(level_of(folk_id) + amount, 0.0, 100.0)
	if is_hooked(folk_id) and not hooked.has(folk_id):
		hooked[folk_id] = true
		SysUtil.game_event("gambling_addiction", {"folk_id": folk_id})
		SysUtil.notify("%s can't stop thinking about the next bet." % SysUtil.folk_name(folk_id), "warn")

# ------------------------------------------------------------------ one ticket
## The prize id of one ticket ("" = nothing). Cumulative odds from the table.
static func roll_ticket(r: RandomNumberGenerator) -> String:
	var x: float = r.randf()
	for o in cfg().get("odds", []):
		x -= float(o["p"])
		if x < 0.0:
			return str(o["id"])
	return ""

static func prize_of(id: String) -> int:
	for o in cfg().get("odds", []):
		if str(o["id"]) == id:
			var p: int = int(o["prize"])
			return current_jackpot() if p < 0 else int(round(float(p) * MarketEconomy.price_mult()))
	return 0

# ------------------------------------------------------------------ draws & urges
static func on_day(day: int) -> void:
	var c: Dictionary = cfg()
	var a: Dictionary = c.get("addiction", {})
	for fid in addiction.keys():
		addiction[fid] = maxf(level_of(int(fid)) - float(a.get("decay_per_day", 1.0)), 0.0)
		if level_of(int(fid)) <= 0.5:
			addiction.erase(fid)
			hooked.erase(fid)
			streak.erase(fid)
	_urges(c, a)
	if next_draw <= 0:
		next_draw = day + int(c.get("draw_days", 7))
	if day >= next_draw:
		draw(day)
		next_draw = day + int(c.get("draw_days", 7))

## Hooked people buy tickets on their own when they can afford it (the player sees it in the ledger and a toast).
static func _urges(c: Dictionary, a: Dictionary) -> void:
	for fid in addiction.keys():
		if not is_hooked(int(fid)) or rng.randf() >= float(a.get("buy_urge_chance", 0.25)):
			continue
		var f = SysUtil.folk(int(fid))
		if f == null or not SysUtil.is_resident(f):
			continue
		f.add_buff("gambling_urge")
		var n: int = int(a.get("urge_tickets", 4))
		var cost: int = n * int(c.get("ticket_price", 5))
		if Economy.spend(int(f.household_id), cost, "lottery tickets (an urge)"):
			add_tickets(int(f.household_id), n, -1)

static func draw(day: int) -> void:
	var c: Dictionary = cfg()
	var won_jackpot: bool = false
	var winner: String = ""
	var hids: Array = tickets.keys()
	hids.sort()
	for hid in hids:
		var total: int = 0
		for _i in tickets_of(int(hid)):
			var pid: String = roll_ticket(rng)
			if pid == "":
				continue
			if pid == "jackpot" and won_jackpot:
				pid = "big"
			total += prize_of(pid)
			if pid == "jackpot":
				won_jackpot = true
				winner = "household %d" % int(hid)
		if total > 0:
			Economy.deposit(int(hid), total, "lottery prize")
			SysUtil.notify("The lottery paid out %d coins!" % total, "good")
		elif tickets_of(int(hid)) > 0:
			for f in SysUtil.residents():
				if int(f.household_id) == int(hid) and addiction.has(int(f.id)):
					streak[int(f.id)] = int(streak.get(int(f.id), 0)) + 1
					_gain(int(f.id), float(c.get("addiction", {}).get("gain_per_loss_streak", 0.2)) * float(streak[int(f.id)]))
	# the town buys tickets too: somebody local may take the jackpot
	if not won_jackpot:
		var town: int = int(c.get("town_tickets_per_draw", 40))
		var p_any: float = 1.0 - pow(1.0 - _jackpot_p(), float(town))
		if rng.randf() < p_any:
			won_jackpot = true
			winner = "a local"
			ChronicleHook.note("lottery", "Somebody in town won the lottery jackpot of %d coins!" % current_jackpot(), [], "town:0", 2, true)
	last_draw = {"day": day, "jackpot_won": won_jackpot, "winner": winner, "jackpot": current_jackpot()}
	if won_jackpot:
		jackpot = _start_jackpot()
	tickets.clear()

static func _jackpot_p() -> float:
	for o in cfg().get("odds", []):
		if str(o["id"]) == "jackpot":
			return float(o["p"])
	return 0.0

# ------------------------------------------------------------------ cards
## A hand of cards for `stake` coins. Returns {ok, won, delta, reason}.
static func play_cards(hid: int, folk_id: int, stake: int) -> Dictionary:
	var g: Dictionary = SysUtil.table("bank").get("gamble", {})
	if stake <= 0 or not Economy.spend(hid, stake, "card game stake"):
		return {"ok": false, "won": false, "delta": 0, "reason": "Not enough coins."}
	var won: bool = rng.randf() < float(g.get("cards_win_p", 0.47))
	var delta: int = -stake
	if won:
		var back: int = int(round(float(stake) * float(g.get("cards_payout", 2.0))))
		Economy.deposit(hid, back, "card game winnings")
		delta = back - stake
		streak[folk_id] = 0
	else:
		streak[folk_id] = int(streak.get(folk_id, 0)) + 1
	if folk_id >= 0:
		_gain(folk_id, float(cfg().get("addiction", {}).get("gain_per_ticket", 1.2)) * (1.0 + 0.2 * float(streak.get(folk_id, 0))))
	return {"ok": true, "won": won, "delta": delta, "reason": ""}

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"tickets": SysUtil.str_keys(tickets), "addiction": SysUtil.str_keys(addiction), "streak": SysUtil.str_keys(streak), "hooked": SysUtil.str_keys(hooked),
		"jackpot": jackpot, "next_draw": next_draw, "last_draw": last_draw.duplicate(true), "rng_seed": str(rng.seed), "rng_state": str(rng.state)}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	tickets = SysUtil.int_keys(d.get("tickets", {}))
	for k in tickets:
		tickets[k] = int(tickets[k])
	addiction = SysUtil.int_keys(d.get("addiction", {}))
	for k2 in addiction:
		addiction[k2] = float(addiction[k2])
	streak = SysUtil.int_keys(d.get("streak", {}))
	for k3 in streak:
		streak[k3] = int(streak[k3])
	hooked = SysUtil.int_keys(d.get("hooked", {}))
	jackpot = int(d.get("jackpot", 0))
	next_draw = int(d.get("next_draw", 0))
	last_draw = (d.get("last_draw", {}) as Dictionary).duplicate(true)
	rng.seed = int(str(d.get("rng_seed", "130031")))
	rng.state = int(str(d.get("rng_state", str(rng.state))))
