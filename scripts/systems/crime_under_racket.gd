class_name CrimeUnderRacket
extends RefCounted
## Task 23: RACKETEERING. Loan sharking (high interest, collection visits that pressure debtors, 09c), protection rackets on businesses (pay or suffer
## vandalism), illegal gambling dens (13), counterfeit cash (abstract batches) and money laundering through a FRONT business. All income from these is
## "dirty": it raises a taint score that makes an audit likelier; laundering through a front business turns it clean for a fee. Each op is a record in
## CrimeUnderState.rackets; a daily pass walks only those. Townie racketeers (line members) run the same ops with the same dice. Mechanics only.

static func cfg() -> Dictionary:
	return CrimeUnderState.sect("racket")

static func ops_of(pid: int, kind: String = "") -> Array:
	var out: Array = []
	for id in CrimeUnderState.rackets:
		var r: Dictionary = CrimeUnderState.rackets[id]
		if int(r["owner"]) == pid and str(r["state"]) == "active" and (kind == "" or str(r["kind"]) == kind):
			out.append(r)
	out.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	return out

static func ops_cap(pid: int) -> int:
	return int(CrimeUnderLines.rank_data(pid, "racket").get("ops_cap", 2))

static func taint(pid: int) -> float:
	return float(CrimeUnderState.taint.get(pid, 0.0))

static func add_taint(pid: int, v: float) -> void:
	CrimeUnderState.taint[pid] = maxf(taint(pid) + v, 0.0)

static func _new(kind: String, owner: int, target: int, principal: int, owed: int, due: int) -> Dictionary:
	var r: Dictionary = {"id": CrimeUnderState.next_racket, "kind": kind, "owner": owner, "target": target, "principal": principal, "owed": owed, "due": due, "state": "active", "missed": 0, "visits": 0, "biz": -1}
	CrimeUnderState.next_racket += 1
	CrimeUnderState.rackets[int(r["id"])] = r
	return r

static func _earn(pid: int, kind: String, k: Dictionary) -> void:
	CrimeLifePath.add_cred(pid, float(k.get("cred", 1.0)), kind)
	CrimeUnderLines.add_standing(pid, "racket", float(k.get("standing", 1.0)))
	add_taint(pid, float(k.get("taint", 0.5)))
	var m: Dictionary = CrimeLifePath.member(pid)
	if not m.is_empty():
		m["heat"] = float(m.get("heat", 0.0)) + float(k.get("heat", 1.0))
		m["last_job_day"] = SysUtil.day()

# ------------------------------------------------------------------ loans
static func lend(pid: int, debtor: int, amount: int) -> Dictionary:
	var k: Dictionary = cfg().get("loan", {})
	if not CrimeUnderLines.has(pid, "racket") or not CrimePerson.alive(debtor) or debtor == pid or not CrimePerson.is_adult(debtor) or CrimePerson.in_custody(pid):
		return {"ok": false, "msg": "Not possible."}
	if ops_of(pid).size() >= ops_cap(pid):
		return {"ok": false, "msg": "You can't keep track of any more."}
	for r in ops_of(pid, "loan"):
		if int(r["target"]) == debtor:
			return {"ok": false, "msg": "They already owe you."}
	var lo: Array = k.get("principal", [60, 300])
	amount = clampi(amount if amount > 0 else int(lo[0]), int(lo[0]), int(lo[1]))
	if CrimePerson.coins(pid) < amount:
		return {"ok": false, "msg": "You don't have that much to lend."}
	CrimePerson.pay(pid, amount, "a loan")
	CrimePerson.add_coins(debtor, amount, "a loan")
	var r2: Dictionary = _new("loan", pid, debtor, amount, int(ceil(float(amount) * (1.0 + float(k.get("interest", 0.25))))), SysUtil.day() + int(k.get("term_days", 7)))
	CrimeUnderState.count("loan")
	return {"ok": true, "msg": "%s lends %s %d coins. They owe %d." % [CrimePerson.name_of(pid), CrimePerson.name_of(debtor), amount, int(r2["owed"])], "racket": int(r2["id"])}

## Pay a visit to the debtor: pressure. Returns "paid", "pressed" or "reported".
static func collect(r: Dictionary) -> String:
	var k: Dictionary = cfg().get("loan", {})
	var debtor: int = int(r["target"])
	var owner: int = int(r["owner"])
	r["visits"] = int(r["visits"]) + 1
	RelationshipService.add_value(debtor, owner, "friendship", -6.0)
	var can: bool = CrimePerson.coins(debtor) >= int(r["owed"])
	if (can and CrimeUnderState.chance(float(k.get("pay_chance", 0.55)) + 0.3)) or (CrimeUnderState.chance(float(k.get("pay_chance", 0.55))) and CrimePerson.coins(debtor) > 0):
		var paid: int = CrimePerson.pay(debtor, int(r["owed"]), "a debt")
		CrimePerson.add_coins(owner, paid, "a debt repaid")
		r["owed"] = int(r["owed"]) - paid
		if int(r["owed"]) <= 0:
			r["state"] = "paid"
			CrimeUnderState.count("loan_paid")
			_earn(owner, "loan", k)
			return "paid"
	r["missed"] = int(r["missed"]) + 1
	CrimeLifePath.drift_check(debtor, 0.9)               # a debtor under pressure may drift into crime (09c)
	CrimeUnderState.count("loan_pressed")
	if int(r["visits"]) >= int(k.get("escalate_after", 2)) and CrimeUnderState.chance(float(k.get("report_chance", 0.12))):
		r["state"] = "reported"
		_case(owner, debtor, "loan_sharking", "%s went to the police about a lender's threats." % CrimePerson.name_of(debtor))
		return "reported"
	return "pressed"

static func _case(culprit: int, victim: int, charge: String, text: String) -> Dictionary:
	var c: Dictionary = CaseStore.create("racket", culprit, victim, "street", {"witnessed": true, "witnesses": [victim], "witness_clarity": 0.7, "trace": 0.5})
	c["charge_hint"] = charge
	c["state"] = "open"
	c["disc_day"] = SysUtil.day()
	CaseStore.note(c, text, "arrest", 3)
	if CrimePerson.is_player(culprit):
		SysUtil.notify(text, "bad")
	if CrimeUnderState.chance(0.6 * Police.strength()):
		JusticeProcess.arrest(c, culprit)
	return c

# ------------------------------------------------------------------ protection
static func protect(pid: int, biz: int) -> Dictionary:
	var k: Dictionary = cfg().get("protect", {})
	var b: Dictionary = BusinessState.get_biz(biz)
	if not CrimeUnderLines.has(pid, "racket") or b.is_empty() or str(b.get("owner_kind", "")) == "player" and CrimePerson.hid(pid) == int(b.get("owner", -1)):
		return {"ok": false, "msg": "Not possible."}
	if ops_of(pid).size() >= ops_cap(pid):
		return {"ok": false, "msg": "You can't keep track of any more."}
	for r in ops_of(pid, "protect"):
		if int(r["biz"]) == biz:
			return {"ok": false, "msg": "Already paying you."}
	var fee: int = CrimeUnderState.range_i(k.get("fee", [18, 55]))
	var r2: Dictionary = _new("protect", pid, int(b.get("owner", -1)), fee, fee, SysUtil.day() + int(k.get("term_days", 7)))
	r2["biz"] = biz
	CrimeUnderState.count("protect_set")
	return {"ok": true, "msg": "%s tells %s it would be a shame if something happened to the place." % [CrimePerson.name_of(pid), str(b.get("name", "the owner"))], "racket": int(r2["id"])}

## The weekly demand: the owner pays, refuses (and the place gets vandalised) or reports it.
static func demand(r: Dictionary) -> String:
	var k: Dictionary = cfg().get("protect", {})
	var b: Dictionary = BusinessState.get_biz(int(r["biz"]))
	var owner: int = int(r["owner"])
	if b.is_empty():
		r["state"] = "closed"
		return "closed"
	var biz_owner_player: bool = str(b.get("owner_kind", "")) == "player"
	if biz_owner_player:
		return _demand_player(r, b, k)
	var payer: int = int(b.get("owner", -1))
	var pays: bool = CrimeUnderState.chance(float(k.get("pay_chance", 0.6)))
	if pays and payer >= 0:
		var paid: int = CrimePerson.pay(payer, int(r["principal"]), "protection")
		CrimePerson.add_coins(owner, paid, "protection money")
		_earn(owner, "protect", k)
		r["due"] = SysUtil.day() + int(k.get("term_days", 7))
		return "paid"
	return _refused(r, b, k, payer)

static func _refused(r: Dictionary, b: Dictionary, k: Dictionary, victim: int) -> String:
	var owner: int = int(r["owner"])
	r["due"] = SysUtil.day() + int(cfg().get("protect", {}).get("term_days", 7))
	if CrimeUnderState.chance(float(k.get("report_chance", 0.1))):
		r["state"] = "reported"
		_case(owner, victim, "extortion", "%s reported being leaned on for protection money." % str(b.get("name", "A business")))
		return "reported"
	if CrimeUnderState.chance(float(k.get("refuse_vandal", 0.55))):
		var loss: int = CrimeUnderState.range_i(k.get("vandal_loss", [20, 90]))
		var c: Dictionary = CaseStore.create("vandalism", owner, victim, "street", {"witnessed": false, "trace": 0.2})
		c["state"] = "hidden"
		CaseDiscovery.report(c, victim, "noticed")
		if str(b.get("owner_kind", "")) == "player":
			Economy.deposit(int(b["owner"]), -mini(loss, WorldIface.get_coins(int(b["owner"]))), "vandalism: %s" % str(b["name"]))
			SysUtil.notify("%s was vandalised." % str(b["name"]), "bad")
		CrimeUnderState.count("protect_vandal")
		return "vandalised"
	return "ignored"

static func _demand_player(r: Dictionary, b: Dictionary, k: Dictionary) -> String:
	var hid: int = int(b["owner"])
	var fee: int = int(r["principal"])
	var owner: int = int(r["owner"])
	var rep: int = -1
	for f in SysUtil.residents():
		if int(f.household_id) == hid:
			rep = int(f.id)
			break
	if r.get("asked", false):
		return "waiting"
	r["asked"] = true
	if rep < 0:
		return _refused(r, b, k, -1)
	JusticePlayer.ask(rep, "Pay up, or else", "Someone says %s needs protection, for %d coins a week. It sounds like a threat." % [str(b["name"]), fee],
		[{"id": "pay", "label": "Pay (%d)" % fee}, {"id": "refuse", "label": "Refuse"}, {"id": "police", "label": "Tell the police"}], func(ch): _player_choice(str(ch), r, b, k, rep, hid, fee, owner), "refuse")
	return "asked"

static func _player_choice(ch: String, r: Dictionary, b: Dictionary, k: Dictionary, rep: int, hid: int, fee: int, owner: int) -> void:
	r["asked"] = false
	r["due"] = SysUtil.day() + int(k.get("term_days", 7))
	match ch:
		"pay":
			if WorldIface.get_coins(hid) >= fee:
				Economy.deposit(hid, -fee, "protection money")
				CrimePerson.add_coins(owner, fee, "protection money")
				_earn(owner, "protect", k)
				return
			_refused(r, b, k, rep)
		"police":
			r["state"] = "reported"
			_case(owner, rep, "extortion", "%s reported a protection racket." % CrimePerson.name_of(rep))
		_:
			_refused(r, b, k, rep)

# ------------------------------------------------------------------ dens, counterfeit, laundering
static func open_den(pid: int) -> Dictionary:
	var k: Dictionary = cfg().get("den", {})
	if not CrimeUnderLines.has(pid, "racket"):
		return {"ok": false, "msg": "Not possible."}
	if ops_of(pid, "den").size() >= int(k.get("cap", 2)) or ops_of(pid).size() >= ops_cap(pid):
		return {"ok": false, "msg": "No room for another."}
	if CrimePerson.coins(pid) < int(k.get("setup", 450)):
		return {"ok": false, "msg": "Setting up a card room costs %d coins." % int(k.get("setup", 450))}
	CrimePerson.pay(pid, int(k.get("setup", 450)), "a card room")
	var r: Dictionary = _new("den", pid, -1, 0, 0, SysUtil.day())
	CrimeUnderState.count("den_open")
	return {"ok": true, "msg": "A back room, a table and a few trusted regulars.", "racket": int(r["id"])}

static func counterfeit(pid: int) -> Dictionary:
	var k: Dictionary = cfg().get("counterfeit", {})
	if not CrimeUnderLines.has(pid, "racket") or CrimePerson.coins(pid) < int(k.get("batch_cost", 80)):
		return {"ok": false, "msg": "Not possible."}
	CrimePerson.pay(pid, int(k.get("batch_cost", 80)), "materials")
	var skill: float = CrimeLifePath.skill_score(pid, {"handiness": 0.6, "logic": 0.4})
	var passes: float = float(k.get("passes", 0.7)) * (0.6 + 0.6 * skill)
	var value: int = int(float(CrimeUnderState.range_i(k.get("batch_value", [180, 360]))) * passes)
	CrimePerson.add_coins(pid, value, "passed notes")
	CrimeLifePath.train(pid, "handiness", float(k.get("xp", 8)))
	_earn(pid, "counterfeit", k)
	CrimeUnderState.count("counterfeit")
	var spotted: bool = CrimeUnderState.chance(float(k.get("detect", 0.12)) * (1.0 - skill * 0.5) * Police.strength())
	if spotted:
		_case(pid, -1, "counterfeiting", "False notes were traced back to %s." % CrimePerson.name_of(pid))
	return {"ok": true, "msg": "A batch of notes goes into circulation (%d coins)." % value, "value": value, "spotted": spotted}

static func set_front(pid: int, biz: int) -> Dictionary:
	var k: Dictionary = cfg().get("launder", {})
	var b: Dictionary = BusinessState.get_biz(biz)
	if not CrimeUnderLines.has(pid, "racket") or b.is_empty() or str(b.get("owner_kind", "")) != "player" or int(b.get("owner", -1)) != CrimePerson.hid(pid):
		return {"ok": false, "msg": "A front has to be a business you own."}
	if CrimePerson.coins(pid) < int(k.get("front_setup", 300)):
		return {"ok": false, "msg": "Cooking the books costs %d coins." % int(k.get("front_setup", 300))}
	CrimePerson.pay(pid, int(k.get("front_setup", 300)), "a front")
	CrimeUnderState.front[pid] = biz
	return {"ok": true, "msg": "%s now has a very busy till." % str(b.get("name", "The business"))}

## Run dirty money through the front: a fee, a weekly cap, and the taint goes down.
static func launder(pid: int, amount: int) -> Dictionary:
	var k: Dictionary = cfg().get("launder", {})
	if not CrimeUnderState.front.has(pid) or BusinessState.get_biz(int(CrimeUnderState.front[pid])).is_empty():
		return {"ok": false, "msg": "You need a front business."}
	var week: int = SysUtil.day() / 7
	var rec: Dictionary = CrimeUnderState.laundered.get(pid, {"week": week, "amount": 0})
	if int(rec["week"]) != week:
		rec = {"week": week, "amount": 0}
	amount = mini(amount, int(k.get("week_cap", 800)) - int(rec["amount"]))
	if amount <= 0 or CrimePerson.coins(pid) < amount:
		return {"ok": false, "msg": "Nothing more can go through this week."}
	var fee: int = int(float(amount) * float(k.get("fee_share", 0.2)))
	CrimePerson.pay(pid, fee, "laundering costs")
	rec["amount"] = int(rec["amount"]) + amount
	CrimeUnderState.laundered[pid] = rec
	add_taint(pid, -float(amount) / 100.0 * float(k.get("taint_cut", 1.0)))
	CrimeUnderState.count("laundered", amount)
	return {"ok": true, "msg": "%d coins come out clean for a fee of %d." % [amount, fee], "fee": fee}

# ------------------------------------------------------------------ daily
static func on_day() -> void:
	var k: Dictionary = cfg()
	var ids: Array = CrimeUnderState.rackets.keys()
	ids.sort()
	for id in ids:
		var r: Dictionary = CrimeUnderState.rackets[id]
		var owner: int = int(r["owner"])
		if str(r["state"]) != "active":
			continue
		if not CrimePerson.alive(owner) or not CrimeUnderLines.has(owner, "racket"):
			r["state"] = "closed"
			continue
		if CrimePerson.in_custody(owner):
			continue
		match str(r["kind"]):
			"loan":
				if SysUtil.day() >= int(r["due"]):
					if not CrimePerson.alive(int(r["target"])):
						r["state"] = "closed"
					else:
						collect(r)
						r["due"] = SysUtil.day() + 2
			"protect":
				if SysUtil.day() >= int(r["due"]):
					demand(r)
			"den":
				_den_day(r, k.get("den", {}))
	_audits(k)
	_prune()
	for pid in CrimeUnderState.taint.keys():
		CrimeUnderState.taint[pid] = maxf(float(CrimeUnderState.taint[pid]) - float(k.get("taint_decay_day", 0.05)), 0.0)
		if float(CrimeUnderState.taint[pid]) <= 0.0:
			CrimeUnderState.taint.erase(pid)

static func _den_day(r: Dictionary, k: Dictionary) -> void:
	var owner: int = int(r["owner"])
	CrimePerson.add_coins(owner, CrimeUnderState.range_i(k.get("income_day", [14, 30])), "the card room")
	_earn(owner, "den", {"cred": float(k.get("cred", 1.5)) * 0.1, "standing": float(k.get("standing", 0.3)), "taint": float(k.get("taint", 0.5)) * 0.2, "heat": float(k.get("heat_day", 0.4))})
	if CrimeUnderState.chance(float(k.get("raid_daily", 0.012)) * Police.strength() * (1.0 - CrimeUnderGood.protection(owner))):
		r["state"] = "raided"
		CrimeUnderState.count("den_raid")
		_case(owner, -1, "illegal_gambling", "The police raided a card room run by %s." % CrimePerson.name_of(owner))

## Dirty money draws auditors; a front that launders it keeps them away.
static func _audits(k: Dictionary) -> void:
	var lc: Dictionary = k.get("launder", {})
	for pid in CrimeUnderState.taint.keys():
		var p: int = int(pid)
		var t: float = taint(p)
		if t < float(k.get("taint_audit_at", 4.0)) or not CrimePerson.alive(p) or CrimePerson.in_custody(p):
			continue
		if CrimeUnderState.chance((float(lc.get("audit_base", 0.004)) + float(lc.get("audit_taint", 0.012)) * (t - float(k.get("taint_audit_at", 4.0)))) * Police.strength()):
			var fine: int = CrimePerson.pay(p, int(float(CrimePerson.coins(p)) * float(k.get("audit_fine_share", 0.3))), "audit")
			CrimeUnderState.taint[pid] = t * 0.5
			CrimeUnderState.count("audit")
			if CrimeUnderState.chance(0.5):
				_case(p, -1, "money_laundering", "Auditors traced unexplained money to %s." % CrimePerson.name_of(p))
			elif CrimePerson.is_player(p):
				SysUtil.notify("The tax people took %d coins to ask no more questions." % fine, "warn")

static func _prune() -> void:
	var done: Array = []
	for id in CrimeUnderState.rackets:
		if str(CrimeUnderState.rackets[id]["state"]) != "active":
			done.append(int(id))
	done.sort()
	while done.size() > 30:
		CrimeUnderState.rackets.erase(done.pop_front())

# ------------------------------------------------------------------ townie racketeers
static func person_day(pid: int) -> void:
	var npc: Dictionary = cfg().get("npc", {})
	if CrimePerson.is_player(pid) or not CrimePerson.is_adult(pid) or CrimePerson.stage(pid) == "elder" or CrimePerson.in_custody(pid):
		return
	if not CrimeUnderLines.has(pid, "racket"):
		if CrimeLifePath.rank_index(pid) >= CrimeLifePath.rank_index_of_id("fence") and CrimeUnderLines.townie_share("racket") < float(npc.get("max_share", 0.03)):
			CrimeUnderLines.townie_join_dice(pid, "racket", float(npc.get("join_daily", 0.0012)), ["dishonest", "vengeful"])
		return
	if ops_of(pid).size() >= ops_cap(pid) or not CrimeUnderState.chance(float(npc.get("op_daily", 0.15))):
		return
	if CrimeUnderState.chance(0.6):
		var cands: Array = CrimePerson.townies_only().filter(func(t): return t != pid and CrimePerson.is_adult(t) and CrimePerson.coins(t) < 400)
		if not cands.is_empty():
			lend(pid, int(cands[CrimeUnderState.rng.randi_range(0, cands.size() - 1)]), 0)
	else:
		var bs: Array = BusinessState.ids_sorted().filter(func(b): return str(BusinessState.get_biz(int(b)).get("owner_kind", "")) != "player")
		if not bs.is_empty():
			protect(pid, int(bs[CrimeUnderState.rng.randi_range(0, bs.size() - 1)]))
