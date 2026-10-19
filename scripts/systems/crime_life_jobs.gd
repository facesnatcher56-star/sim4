class_name CrimeLifeJobs
extends RefCounted
## Task 21: the jobs of a criminal life, from small to big: pickpocketing, shoplifting, car theft, burglary of homes, shop robbery, cons. (Planned
## heists are CrimeLifeHeist.) One pipeline for a player folk and for a far townie: pick a target -> odds (CrimeLifeRoll) -> outcome ->
## consequences: loot (coins and goods into the stash), a CASE RECORD for discovery (09b) and the trial (20) with trace, witnesses and camera footage,
## alarm and guard response, the thief's cred and heat, and the moral ledger. The player's job takes time away from home and resolves when it ends.
## Target = {"scene": roll scene ("town:3", "biz:market", "street"), "case_scene": scene of the case, "victim": person id or -1, "label": plain words}.

static func job(jid: String) -> Dictionary:
	return CrimeLifeRoll.job(jid)

static func ids() -> Array:
	var out: Array = CrimeLifeRoll.jobs().keys()
	out.sort_custom(func(a, b): return CrimeLifePath.rank_index_of_id(str(job(str(a)).get("rank", ""))) < CrimeLifePath.rank_index_of_id(str(job(str(b)).get("rank", ""))) \
		or (CrimeLifePath.rank_index_of_id(str(job(str(a)).get("rank", ""))) == CrimeLifePath.rank_index_of_id(str(job(str(b)).get("rank", ""))) and str(a) < str(b)))
	return out

## Is the job open to this person's rank?
static func unlocked(pid: int, jid: String) -> bool:
	return CrimeLifePath.rank_index(pid) >= CrimeLifePath.rank_index_of_id(str(job(jid).get("rank", "petty_thief")))

# ------------------------------------------------------------------ targets
static func _townie_owner(lot_no: int) -> int:
	for tid in CrimePerson.townies_only():
		if CrimePerson.lot_no(tid) == lot_no:
			return int(tid)
	return -1

## Possible targets, best first. `limit` keeps the list short.
static func targets(pid: int, jid: String, limit: int = 8) -> Array:
	var j: Dictionary = job(jid)
	var out: Array = []
	match str(j.get("victim", "")):
		"townie":
			for tid in CrimePerson.townies_only():
				if tid == pid or CrimePerson.in_custody(tid) or not CrimePerson.is_adult(tid) or CrimePerson.coins(tid) < int(CrimeLifeState.sect("townie").get("pickpocket_victim_min", 40)):
					continue
				out.append({"scene": "street", "case_scene": "street", "victim": tid, "label": CrimePerson.name_of(tid), "weight": CrimePerson.coins(tid)})
		"house":
			var seen: Dictionary = {}
			for tid in CrimePerson.townies_only():
				var n: int = CrimePerson.lot_no(tid)
				if seen.has(n) or n <= 0 or n == CrimePerson.lot_no(pid) or CrimePerson.in_custody(tid):
					continue
				seen[n] = true
				var coins: int = 0
				for t2 in CrimePerson.townies_only():
					if CrimePerson.lot_no(t2) == n:
						coins += CrimePerson.coins(t2)
				out.append({"scene": "town:%d" % n, "case_scene": "town:%d" % n, "victim": _townie_owner(n), "label": CaseStore.house_label("town:%d" % n), "weight": coins + 50})
		"shop", "business":
			for bid in BusinessState.list:                         # the real businesses of the town first (task 13): their own cover and owner
				var b: Dictionary = BusinessState.list[bid]
				if not bool(b.get("open", true)) or (str(j.get("victim", "")) == "shop" and str(b["type"]) not in ["shop", "bakery", "cafe", "restaurant"]):
					continue
				var owner: int = int(b["owner"]) if str(b["owner_kind"]) == "townie" else _first_resident(int(b["owner"]))
				out.append({"scene": "biz:%d" % int(bid), "case_scene": "street", "victim": owner, "label": str(b["name"]), "weight": 150, "biz": int(bid)})
			for t in ["market", "cafe", "gym", "library", "office", "shop", "bar", "bakery"]:
				if str(j.get("victim", "")) == "shop" and t not in ["market", "shop", "bakery"]:
					continue
				out.append({"scene": "biz:%s" % t, "case_scene": "street", "victim": _shop_victim(t), "label": "the %s" % t, "weight": 100})
	out.sort_custom(func(a, b): return int(a["weight"]) > int(b["weight"]) or (int(a["weight"]) == int(b["weight"]) and str(a["scene"]) < str(b["scene"])))
	return out.slice(0, limit)

static func _first_resident(hid: int) -> int:
	for r in SysUtil.residents():
		if int(r.household_id) == hid:
			return int(r.id)
	return -1

## The person behind the counter (a townie with a career, else the first townie): a witness and the victim of a shop robbery.
static func _shop_victim(_btype: String) -> int:
	var all: Array = CrimePerson.townies_only()
	for tid in all:
		if CrimePerson.has_job(tid) and CrimePerson.stage(tid) == "adult":
			return int(tid)
	return int(all[0]) if not all.is_empty() else -1

## A weighted pick for far townies (their own rng).
static func pick_target(pid: int, jid: String) -> Dictionary:
	var list: Array = targets(pid, jid, 12)
	if list.is_empty():
		return {}
	var w: Array = list.map(func(t): return float(t["weight"]))
	var i: int = CrimeLifeState.pick_index(w)
	return list[i] if i >= 0 else {}

# ------------------------------------------------------------------ the player's job
## Start a job for a Folk: it takes `minutes` away from home and is rolled when it ends. Returns {ok, msg}.
static func start(pid: int, jid: String, target: Dictionary) -> Dictionary:
	var j: Dictionary = job(jid)
	var f = CrimePerson.folk(pid)
	if j.is_empty() or f == null or not CrimePerson.is_player(pid):
		return {"ok": false, "msg": "That is not possible."}
	if not CrimePerson.is_adult(pid) or CrimePerson.in_custody(pid) or SysUtil.is_away(f):
		return {"ok": false, "msg": "Not right now."}
	if not CrimeLifePath.is_member(pid):
		CrimeLifePath.join(pid, "chose")
	if not unlocked(pid, jid):
		return {"ok": false, "msg": "Nobody trusts you with that yet."}
	if target.is_empty():
		return {"ok": false, "msg": "Pick a target first."}
	if bool(j.get("night", false)) and not (SysUtil.hour_f() >= 20.0 or SysUtil.hour_f() < 5.5):
		return {"ok": false, "msg": "Better to wait until after dark."}
	var mins: int = int(j.get("minutes", 30))
	Away.send(f, float(mins), "errand", {"label": "Out on a job"})
	CrimeLifeState.queue({"kind": "job", "pid": pid, "job": jid, "target": target, "due_min": SysUtil.now() + mins})
	return {"ok": true, "msg": "%s slips out." % f.name}

static func on_minute() -> void:
	if CrimeLifeState.pending.is_empty():
		return
	var keep: Array = []
	var due: Array = []
	var now: int = SysUtil.now()
	for p in CrimeLifeState.pending:
		if int(p.get("due_min", 0)) <= now:
			due.append(p)
		else:
			keep.append(p)
	CrimeLifeState.pending = keep
	for p2 in due:
		match str(p2.get("kind", "")):
			"job":
				var pid: int = int(p2["pid"])
				if CrimePerson.alive(pid) and not CrimePerson.in_custody(pid):
					run(pid, str(p2["job"]), p2["target"], {})
			"heist":
				CrimeLifeHeist.on_due(p2)
			"case":
				if CrimePerson.alive(int(p2["pid"])) and not CrimePerson.in_custody(int(p2["pid"])):
					CrimeLifeCasing.session(int(p2["pid"]), str(p2["target"]))

# ------------------------------------------------------------------ the act
## Roll and apply one job. Returns {outcome, loot, case, odds}. `opts`: odds overrides (cased, night ...), force (outcome), statistical.
static func run(pid: int, jid: String, target: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var j: Dictionary = job(jid)
	if j.is_empty() or target.is_empty() or not CrimePerson.alive(pid):
		return {"outcome": "none"}
	var scene: String = str(target.get("scene", "street"))
	var o: Dictionary = CrimeLifeRoll.odds(pid, jid, scene, opts)
	var outcome: String = str(opts.get("force", "")) if str(opts.get("force", "")) != "" else CrimeLifeRoll.roll(o)
	var res: Dictionary = {"outcome": outcome, "job": jid, "odds": o, "loot": 0, "goods": 0, "case": -1, "target": target}
	var m: Dictionary = CrimeLifePath.member(pid)
	if not m.is_empty():
		m["last_job_day"] = SysUtil.day()
	CrimeLifeState.count("job_" + jid)
	CrimeLifePath.train(pid, str(j.get("xp_skill", "stealth")), float(j.get("xp", 8)) * (1.0 if outcome in ["clean", "seen", "caught"] else 0.4))
	if outcome in ["fail", "fail_seen"]:
		_failed(pid, j, res, outcome)
		return res
	_take(pid, j, target, res)
	var c: Dictionary = _make_case(pid, jid, j, target, res, outcome, o)
	res["case"] = int(c.get("id", -1))
	_after(pid, j, res, outcome, o, c, target)
	return res

static func _failed(pid: int, j: Dictionary, res: Dictionary, outcome: String) -> void:
	var m: Dictionary = CrimeLifePath.member(pid)
	if outcome == "fail_seen" and not m.is_empty():
		m["heat"] = float(m.get("heat", 0.0)) + float(j.get("heat", 1.0)) * 0.5
	if CrimePerson.is_player(pid):
		SysUtil.notify("%s could not pull it off%s." % [CrimePerson.name_of(pid), " and thinks someone noticed" if outcome == "fail_seen" else ""], "warn")

## How much is taken. Coins come out of the victim's pocket; goods become stash items worth money only after fencing.
static func _take(pid: int, j: Dictionary, target: Dictionary, res: Dictionary) -> void:
	var amount: int = CrimeLifeState.range_i(j.get("loot", [10, 30]))
	var victim: int = int(target.get("victim", -1))
	var goods_share: float = 0.0
	if bool(j.get("goods", false)):
		goods_share = 1.0 if bool(j.get("car", false)) or str(j.get("kind", "")) == "shoplifting" else 0.6
	var goods: int = int(float(amount) * goods_share)
	var coins: int = amount - goods
	var biz: Dictionary = BusinessState.get_biz(int(target.get("biz", -1))) if int(target.get("biz", -1)) >= 0 else {}
	if not biz.is_empty() and str(biz["owner_kind"]) == "player":
		coins = mini(coins, WorldIface.get_coins(int(biz["owner"])))          # the takings come out of the owning household's money
		if coins > 0:
			Economy.deposit(int(biz["owner"]), -coins, "robbed: %s" % str(biz["name"]))
	elif coins > 0 and victim >= 0 and str(j.get("victim", "")) in ["townie", "house"]:
		coins = CrimePerson.pay(victim, coins, "stolen")
	if coins > 0:
		CrimePerson.add_coins(pid, coins, "ill-gotten gains")
	res["loot"] = coins
	res["goods"] = goods

static func _make_case(pid: int, jid: String, j: Dictionary, target: Dictionary, res: Dictionary, outcome: String, o: Dictionary) -> Dictionary:
	var kind: String = str(j.get("kind", "theft"))
	var victim: int = int(target.get("victim", -1))
	var seen: bool = outcome in ["seen", "caught"]
	var masked: bool = CrimeLifeRoll.has_gear(pid, "disguise")
	var clarity: float = clampf(CrimeLifeState.rng.randf_range(0.35, 0.75) * (1.0 - CrimeLifeRoll.gear_effect(pid, "witness")), 0.05, 0.95)
	var witnesses: Array = [victim] if seen and victim >= 0 and kind != "shoplifting" else []
	var c: Dictionary = CaseStore.create(kind, pid, victim, str(target.get("case_scene", "street")),
		{"witnessed": seen, "witnesses": witnesses, "witness_clarity": clarity if seen else 0.0, "trace": float(o["trace"]), "stolen_coins": int(res["loot"]),
		"loot_value": int(res["loot"]) + int(res["goods"]), "vhid": 0})
	c["life_job"] = jid
	if str(j.get("charge", "")) != "" and str(j["charge"]) != kind:
		c["charge_hint"] = str(j["charge"])
	if int(res["goods"]) > 0:
		var item: Dictionary = CrimeLifeFence.add_stash(pid, jid, int(res["goods"]), int(c["id"]), bool(j.get("car", false)))
		res["item"] = item
	CrimePlace.place_at_scene(pid, str(target.get("case_scene", "street")))
	var fscene: String = str(target.get("scene", ""))
	if fscene.begins_with("town:") or fscene.begins_with("biz:") or fscene.begins_with("home:"):
		var fg: Dictionary = CrimeSecurityFootage.capture(c, fscene, pid, masked, CrimeLifeRoll.has_gear(pid, "tools"))
		res["footage"] = fg
	return c

static func _after(pid: int, j: Dictionary, res: Dictionary, outcome: String, o: Dictionary, c: Dictionary, target: Dictionary) -> void:
	var m: Dictionary = CrimeLifePath.member(pid)
	var kind: String = str(j.get("kind", "theft"))
	var scene: String = str(target.get("scene", ""))
	var seen: bool = outcome in ["seen", "caught"]
	if not m.is_empty():
		m["jobs"] = int(m.get("jobs", 0)) + 1
		var h: Dictionary = m.get("hist", {})
		h[str(res["job"])] = int(h.get(str(res["job"]), 0)) + 1
		m["hist"] = h
		m["heat"] = float(m.get("heat", 0.0)) + float(j.get("heat", 1.0)) * (1.6 if seen else 0.6)
		CrimeLifePath.add_cred(pid, float(j.get("cred", 1.0)) * (0.6 if seen else 1.0), "job")
	CrimeLifeMoral.after_crime(pid, int(target.get("victim", -1)), kind, int(res["loot"]) + int(res["goods"]), c)
	if int(target.get("biz", -1)) >= 0:
		var rec: Dictionary = CrimeLifeState.biz_sec.get(int(target["biz"]), {})
		rec["robbed_day"] = SysUtil.day()
		CrimeLifeState.biz_sec[int(target["biz"])] = rec
		var bz: Dictionary = BusinessState.get_biz(int(target["biz"]))
		if not bz.is_empty() and str(bz["owner_kind"]) == "player":
			SysUtil.notify("%s was %s." % [str(bz["name"]), "robbed" if kind == "robbery" else "targeted by a thief"], "bad")
	var f = CrimePerson.folk(pid)
	if f != null and CrimePerson.is_player(pid):
		f.add_buff("on_the_run" if seen else "easy_money")
	# alarms and guards
	var prof: Dictionary = o["profile"]
	if seen:
		if bool(prof.get("alarm", false)) and kind != "shoplifting":
			CrimeSecurityAlarm.ring(c, scene)
		elif int(prof.get("guards", 0)) > 0 and CrimeLifeState.chance(float(CrimeSecurityGuards.cfg().get("call", 0.6)) * CrimeSecurityGuards.alert_for(scene)):
			Police.respond(c, 10)
			c["called"] = true
	if kind == "shoplifting":
		_petty(pid, c, seen)
		return
	if seen:
		if str(c["state"]) == "hidden":
			CaseDiscovery.report(c, int(c["victim"]), "seen")
	if outcome == "caught":
		c["recovered"] = true
		JusticeProcess.arrest(c, pid)
		_caught(pid, j, c)

static func _petty(pid: int, c: Dictionary, seen: bool) -> void:
	if not seen:
		c["state"] = "closed"
		c["hush"] = true
		return
	c["state"] = "open"
	c["disc_day"] = SysUtil.day()
	c["charge"] = "shoplifting"
	c["accused"] = pid
	CrimePetty.settle(c)
	var m: Dictionary = CrimeLifePath.member(pid)
	if not m.is_empty():
		m["caught"] = int(m.get("caught", 0)) + 1

static func _caught(pid: int, _j: Dictionary, _c: Dictionary) -> void:
	var m: Dictionary = CrimeLifePath.member(pid)
	if m.is_empty():
		return
	m["caught"] = int(m.get("caught", 0)) + 1
	CrimeLifePath.add_cred(pid, float(CrimeLifeState.sect("path").get("cred_caught_quiet", 4)) * 0.5, "caught")
