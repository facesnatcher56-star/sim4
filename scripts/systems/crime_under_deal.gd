class_name CrimeUnderDeal
extends RefCounted
## Task 23: the DEALER's trade in FICTIONAL substances (data/crimeunder.json "deal"). Buy from "a supplier" (a price, no process), sell on a CORNER to
## townies, with customers hooked through CrimeUnderAddict. Risks: undercover STINGS (police presence, heat, tips; a corrupt cop cuts them),
## INFORMANTS (a customer talks; tips pile up and a RAID with a search warrant finds the stash), RIVAL dealers (stock stolen, a beating on a corner
## fight). Effects on the town: dealing writes crime points (CrimeRate) and addiction among townies grows. Production stays abstract.
## Tier: a sale is one instant `session` (the player's folk is away for the minutes first); townie dealers play one session a day statistically.

static func cfg() -> Dictionary:
	return CrimeUnderState.sect("deal")

static func rec(pid: int) -> Dictionary:
	return CrimeUnderState.dealers.get(pid, {})

static func ensure(pid: int) -> Dictionary:
	if not CrimeUnderState.dealers.has(pid):
		CrimeUnderState.dealers[pid] = {"stock": {}, "corner": "", "customers": [], "tips": 0.0, "sales": 0, "stung": 0, "stash_hidden": false, "last_sale_day": -1}
	return CrimeUnderState.dealers[pid]

static func stock_total(pid: int) -> int:
	var n: int = 0
	for s in (rec(pid).get("stock", {}) as Dictionary):
		n += int(rec(pid)["stock"][s])
	return n

static func stock_cap(pid: int) -> int:
	return int(CrimeUnderLines.rank_data(pid, "deal").get("stock_cap", 8))

static func corner_label(id: String) -> String:
	return str((cfg().get("corners", {}) as Dictionary).get(id, "the street"))

static func corner_ids() -> Array:
	var out: Array = (cfg().get("corners", {}) as Dictionary).keys()
	out.sort()
	return out

# ------------------------------------------------------------------ buying
## Buy `qty` doses of `sub` from a supplier. Low ranks pay more.
static func buy(pid: int, sub: String, qty: int) -> Dictionary:
	if not CrimeUnderLines.has(pid, "deal"):
		return {"ok": false, "msg": "No supplier will deal with a stranger."}
	var s: Dictionary = CrimeUnderAddict.substance(sub)
	if s.is_empty() or qty <= 0 or CrimePerson.in_custody(pid):
		return {"ok": false, "msg": "Not possible."}
	var d: Dictionary = ensure(pid)
	qty = mini(qty, stock_cap(pid) - stock_total(pid))
	if qty <= 0:
		return {"ok": false, "msg": "There is no room to keep more."}
	var rank0: bool = CrimeUnderLines.rank_index(pid, "deal") <= 0
	var price: int = int(ceil(float(s.get("buy", 14)) * float(qty) * (1.0 + (float(cfg().get("buy_markup_low_rank", 0.15)) if rank0 else 0.0))))
	if CrimePerson.coins(pid) < price:
		return {"ok": false, "msg": "That costs %d coins." % price}
	CrimePerson.pay(pid, price, "a supplier")
	var st: Dictionary = d["stock"]
	st[sub] = int(st.get(sub, 0)) + qty
	d["stock"] = st
	CrimeUnderState.count("deal_buy")
	return {"ok": true, "msg": "%d doses of %s, %d coins." % [qty, str(s.get("label", sub)), price], "qty": qty, "price": price}

# ------------------------------------------------------------------ selling
## The player's folk spends an hour on the corner (timed), then `session` runs.
static func sell(pid: int, corner: String) -> Dictionary:
	var f = CrimePerson.folk(pid)
	if f == null or not CrimeUnderLines.has(pid, "deal") or SysUtil.is_away(f) or CrimePerson.in_custody(pid):
		return {"ok": false, "msg": "Not right now."}
	if stock_total(pid) <= 0:
		return {"ok": false, "msg": "Nothing to sell."}
	if not (cfg().get("corners", {}) as Dictionary).has(corner):
		corner = str(corner_ids()[0])
	var mins: int = int(cfg().get("sell_minutes", 60))
	Away.send(f, float(mins), "errand", {"label": "Working a corner"})
	CrimeLifeState.queue({"kind": "deal_sell", "pid": pid, "corner": corner, "due_min": SysUtil.now() + mins})
	return {"ok": true, "msg": "%s heads to %s." % [f.name, corner_label(corner)]}

static func _customers(pid: int, d: Dictionary, n: int) -> Array:
	var out: Array = []
	for cpid in SysUtil.to_ints(d.get("customers", [])):
		if out.size() >= n:
			break
		if CrimePerson.alive(cpid) and CrimeUnderAddict.is_addict(cpid) and not CrimePerson.in_custody(cpid) and not CrimePerson.is_player(cpid):
			out.append(cpid)
	var all: Array = CrimePerson.townies_only()
	if all.is_empty():
		return out
	var start: int = CrimeUnderState.rng.randi_range(0, all.size() - 1)
	var pool_n: int = mini(int(cfg().get("customer_pool", 40)), all.size())
	for i in pool_n:
		if out.size() >= n:
			break
		var q: int = int(all[(start + i) % all.size()])
		if out.has(q) or q == pid or not CrimePerson.is_adult(q) or CrimePerson.in_custody(q) or CrimePerson.coins(q) < int(cfg().get("new_customer_min_coins", 15)):
			continue
		var willing: float = 0.12 + CrimeUnderAddict.onset_chance(q, "glow") * 2.0 + (0.6 if CrimeUnderAddict.is_addict(q) else 0.0)
		if CrimeUnderState.chance(willing):
			out.append(q)
	return out

## One selling session. opts: force_sting (bool), no_sting (bool). Returns {sold, earned, sting, hooked, tips}.
static func session(pid: int, corner: String, opts: Dictionary = {}) -> Dictionary:
	var k: Dictionary = cfg()
	var d: Dictionary = ensure(pid)
	var res: Dictionary = {"sold": 0, "earned": 0, "sting": false, "hooked": 0, "rival": false}
	if stock_total(pid) <= 0 or not CrimePerson.alive(pid) or CrimePerson.in_custody(pid):
		return res
	d["corner"] = corner
	if not _corner_check(pid, corner, d, res):
		return res
	var n: int = CrimeUnderState.range_i(k.get("batch", [2, 5])) + maxi(CrimeUnderLines.rank_index(pid, "deal"), 0)
	var infocfg: Dictionary = k.get("informant", {})
	for q in _customers(pid, d, n):
		var sub: String = _next_sub(d)
		if sub == "":
			break
		var s: Dictionary = CrimeUnderAddict.substance(sub)
		var price: int = int(s.get("sell", 34))
		var addict: bool = CrimeUnderAddict.is_addict(q)
		if CrimePerson.coins(q) < price and not addict:
			continue
		var paid: int = CrimePerson.pay(q, price, "a dose")
		if paid <= 0:
			continue
		d["stock"][sub] = int(d["stock"][sub]) - 1
		CrimePerson.add_coins(pid, paid, "a sale")
		res["sold"] = int(res["sold"]) + 1
		res["earned"] = int(res["earned"]) + paid
		d["sales"] = int(d["sales"]) + 1
		if not addict and CrimeUnderAddict.try_onset(q, sub, pid):
			res["hooked"] = int(res["hooked"]) + 1
		elif addict:
			CrimeUnderAddict.rec(q)["dealer"] = pid
		var cust: Array = SysUtil.to_ints(d.get("customers", []))
		if not cust.has(q):
			cust.append(q)
			while cust.size() > 12:
				cust.pop_front()
		d["customers"] = cust
		if CrimeUnderState.chance(float(infocfg.get("per_sale", 0.012)) + (float(infocfg.get("addict", 0.02)) if addict else 0.0)):
			d["tips"] = float(d.get("tips", 0.0)) + 1.0
			res["tip"] = true
	_after(pid, d, res, k)
	if not bool(opts.get("no_sting", false)):
		_sting(pid, d, res, bool(opts.get("force_sting", false)))
	return res

static func _next_sub(d: Dictionary) -> String:
	var ids: Array = (d["stock"] as Dictionary).keys()
	ids.sort()
	for s in ids:
		if int(d["stock"][s]) > 0:
			return str(s)
	return ""

static func _after(pid: int, d: Dictionary, res: Dictionary, k: Dictionary) -> void:
	var sold: int = int(res["sold"])
	if sold <= 0:
		return
	d["last_sale_day"] = SysUtil.day()
	CrimeUnderLines.add_standing(pid, "deal", float(k.get("standing_per_sale", 0.35)) * float(sold))
	CrimeLifePath.add_cred(pid, float(k.get("cred_per_sale", 0.35)) * float(sold), "dealing")
	CrimeLifePath.train(pid, "charisma", float(k.get("xp", 6)))
	var m: Dictionary = CrimeLifePath.member(pid)
	if not m.is_empty():
		m["heat"] = float(m.get("heat", 0.0)) + float(k.get("heat_per_sale", 0.45)) * float(sold)
		m["last_job_day"] = SysUtil.day()
	JusticeState.year_log.append({"day": SysUtil.day(), "kind": "drug_dealing", "solved": false, "case": -1})   # the town crime rate
	CrimeUnderState.count("deal_sessions")
	CrimeUnderState.count("deal_sold", sold)
	CrimeUnderGang.dues(pid, int(res["earned"]))

# ------------------------------------------------------------------ the corner
static func _corner_check(pid: int, corner: String, d: Dictionary, res: Dictionary) -> bool:
	var k: Dictionary = cfg().get("corner", {})
	var c: Dictionary = CrimeUnderState.corners.get(corner, {"owner": -1, "hold": 0.0, "day": SysUtil.day()})
	var owner: int = int(c.get("owner", -1))
	if owner >= 0 and owner != pid and CrimePerson.alive(owner) and CrimeUnderLines.has(owner, "deal") and float(c.get("hold", 0.0)) > 0.1:
		# someone else's corner: a fight over it
		var mine: float = CrimeLifePath.skill_score(pid, {"fitness": 0.6, "charisma": 0.4}) + CrimeUnderLines.standing(pid, "deal") / 100.0 + CrimeUnderGang.muscle(pid)
		var theirs: float = CrimeLifePath.skill_score(owner, {"fitness": 0.6, "charisma": 0.4}) + CrimeUnderLines.standing(owner, "deal") / 100.0 + float(c["hold"]) + CrimeUnderGang.muscle(owner)
		var p: float = clampf(float(k.get("contest_pull", 0.5)) + (mine - theirs) * 0.5, 0.1, 0.9)
		res["rival"] = true
		if not CrimeUnderState.chance(p):
			_beaten(pid, d, res)
			return false
		c["owner"] = pid
		c["hold"] = float(k.get("claim_hold", 0.35))
		CrimeUnderState.count("corner_taken")
	elif owner < 0 or owner == pid or not CrimePerson.alive(owner):
		c["owner"] = pid
	c["hold"] = minf(float(c.get("hold", 0.0)) + float(k.get("hold_per_sale", 0.06)) * 3.0, 1.0)
	c["day"] = SysUtil.day()
	CrimeUnderState.corners[corner] = c
	return true

static func _beaten(pid: int, d: Dictionary, res: Dictionary) -> void:
	var rv: Dictionary = cfg().get("rival", {})
	res["beaten"] = true
	CrimeUnderState.count("deal_beaten")
	var lost: int = 0
	for s in (d["stock"] as Dictionary):
		var take: int = int(float(d["stock"][s]) * float(rv.get("lose_stock", 0.5)))
		d["stock"][s] = int(d["stock"][s]) - take
		lost += take
	res["lost"] = lost
	var f = CrimePerson.folk(pid)
	if f != null and CrimeUnderState.chance(float(rv.get("hurt", 0.3))):
		Health.injure(f, 1, "a beating")
	CrimeUnderLines.add_standing(pid, "deal", -2.0)
	if CrimePerson.is_player(pid):
		SysUtil.notify("%s was run off the corner by the dealer who holds it%s." % [CrimePerson.name_of(pid), " and lost some stock" if lost > 0 else ""], "bad")

# ------------------------------------------------------------------ stings and raids
static func sting_chance(pid: int, d: Dictionary) -> float:
	var k: Dictionary = cfg().get("sting", {})
	var m: Dictionary = CrimeLifePath.member(pid)
	var p: float = float(k.get("base", 0.03)) + float(Police.officers()) * float(k.get("per_officer", 0.012)) + float(m.get("heat", 0.0)) * float(k.get("heat", 0.02)) \
		+ float(d.get("tips", 0.0)) * float(k.get("per_tip", 0.02)) - float(CrimeLifePath.skill(pid, "stealth")) * float(k.get("stealth", 0.05)) * 0.2
	p *= Police.strength() * (1.0 - CrimeUnderGood.protection(pid))
	return clampf(p, 0.0, float(k.get("cap", 0.5)))

static func _sting(pid: int, d: Dictionary, res: Dictionary, force: bool) -> void:
	if int(res["sold"]) <= 0 and not force:
		return
	if not force and not CrimeUnderState.chance(sting_chance(pid, d)):
		return
	res["sting"] = true
	d["stung"] = int(d.get("stung", 0)) + 1
	CrimeUnderState.count("sting")
	arrest_for(pid, "sting")

## A dealing case against `pid` and the arrest (sting) or an open case (raid with the stash found).
static func arrest_for(pid: int, how: String) -> Dictionary:
	var c: Dictionary = CaseStore.create("dealing", pid, -1, "street", {"witnessed": true, "witnesses": [], "trace": 0.6, "public": true})
	c["charge_hint"] = "drug_dealing"
	c["state"] = "open"
	c["disc_day"] = SysUtil.day()
	c["how"] = how
	CaseStore.note(c, "An undercover officer bought from %s." % CrimePerson.name_of(pid) if how == "sting" else "A search of the stash turned up the stock.", "arrest", 3)
	var m: Dictionary = CrimeLifePath.member(pid)
	if not m.is_empty():
		m["caught"] = int(m.get("caught", 0)) + 1
	var d: Dictionary = rec(pid)
	if how == "raid" and not d.is_empty():
		d["stock"] = {}                                   # seized
	JusticeProcess.arrest(c, pid)
	CrimeUnderGang.dealer_lost(pid)
	return c

## Daily: tips decay, a raid may follow the tips (a search warrant); the stash can be hidden at a cost.
static func on_day() -> void:
	var ids: Array = CrimeUnderState.dealers.keys()
	ids.sort()
	var inf: Dictionary = cfg().get("informant", {})
	for pid in ids:
		var p: int = int(pid)
		var d: Dictionary = CrimeUnderState.dealers[pid]
		if not CrimePerson.alive(p):
			CrimeUnderState.dealers.erase(pid)
			continue
		d["tips"] = maxf(float(d.get("tips", 0.0)) - float(inf.get("tips_decay_day", 0.1)), 0.0)
		if float(d["tips"]) >= float(inf.get("raid_min_tips", 2)) and stock_total(p) > 0 and not CrimePerson.in_custody(p):
			var rp: float = minf(float(d["tips"]) * float(inf.get("raid_per_tip", 0.04)) * Police.strength(), float(inf.get("raid_cap", 0.4))) * (1.0 - CrimeUnderGood.protection(p))
			if bool(d.get("stash_hidden", false)):
				rp *= 1.0 - float(inf.get("hide_stash", 0.5))
			if CrimeUnderState.chance(rp):
				CrimeUnderState.count("raid")
				arrest_for(p, "raid")
				continue
		_rival_day(p, d)
	# corners fade when nobody works them
	for cid in CrimeUnderState.corners.keys():
		var c: Dictionary = CrimeUnderState.corners[cid]
		c["hold"] = maxf(float(c.get("hold", 0.0)) - float(cfg().get("corner", {}).get("hold_decay_day", 0.02)), 0.0)

## A rival dealer may rob a stash or lean on a corner (statistical; no rival person is needed for the stock part).
static func _rival_day(pid: int, d: Dictionary) -> void:
	var rv: Dictionary = cfg().get("rival", {})
	if stock_total(pid) <= 0 or not CrimeUnderState.chance(float(rv.get("daily", 0.012))):
		return
	var hurt: float = CrimeLifePath.skill_score(pid, {"fitness": 0.6, "charisma": 0.3}) + CrimeUnderGang.muscle(pid)
	if CrimeUnderState.chance(clampf(float(rv.get("muscle_skill", 0.6)) - hurt * 0.3, 0.1, 0.9)):
		_beaten(pid, d, {})
		CrimeUnderState.count("rival_hit")

## Hide the stash (a cost in stock and a bit of time): halves raid finds.
static func hide_stash(pid: int) -> Dictionary:
	var d: Dictionary = rec(pid)
	if d.is_empty():
		return {"ok": false, "msg": "No stash."}
	d["stash_hidden"] = true
	return {"ok": true, "msg": "The stock is somewhere nobody would look."}

# ------------------------------------------------------------------ townie dealers (daily dice)
static func person_day(pid: int) -> void:
	var npc: Dictionary = cfg().get("npc", {})
	if CrimePerson.is_player(pid) or not CrimePerson.is_adult(pid) or CrimePerson.stage(pid) == "elder" or CrimePerson.in_custody(pid):
		return
	if not CrimeUnderLines.has(pid, "deal"):
		if CrimeLifePath.rank_index(pid) >= CrimeLifePath.rank_index_of_id(str(npc.get("pool_min_rank", "burglar"))) and CrimeUnderLines.townie_share("deal") < float(npc.get("max_share", 0.04)):
			CrimeUnderLines.townie_join_dice(pid, "deal", float(npc.get("join_daily", 0.0016)), npc.get("traits", []))
		return
	if not CrimeUnderState.chance(float(npc.get("sell_daily", 0.25)) * CrimeRate.crime_mult()):
		return
	var d: Dictionary = ensure(pid)
	if stock_total(pid) < 3:
		var subs: Array = CrimeUnderAddict.substances()
		var st: Dictionary = d["stock"]
		var sub: String = str(subs[CrimeUnderState.rng.randi_range(0, subs.size() - 1)])
		st[sub] = int(st.get(sub, 0)) + mini(6, stock_cap(pid))
		d["stock"] = st                                   # a supplier delivers (their costs are not modelled for townies)
	var corner: String = str(corner_ids()[CrimeUnderState.rng.randi_range(0, corner_ids().size() - 1)])
	session(pid, corner, {})
