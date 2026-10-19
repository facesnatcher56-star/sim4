class_name CrimeUnderHit
extends RefCounted
## Task 23, part 1: HIRED GUN contracts. Contracts come from desperate or furious townies with a grudge (09c rage, the client outsources it) and from
## gang bosses; each has a target, a fee, a deadline and conditions (quiet, alone). A hitman (the player's folk via commands, or a townie statistically)
## takes it, RESEARCHES the target's routine, picks an opportunity and the killing is an abstracted event through 04's murder flow (CrimeMurder.kill,
## non-graphic). Risks: witnesses, cameras, police, the target's family. A contract can be refused, botched or tipped off (CrimeUnderHitRun).
## A very rare contract on the player's folk needs a strong grudge and gives warning signs and counterplay.
## Tier: daily pass over OPEN contracts (a handful) and the few townie hitmen; nothing per minute; the player's timed work uses CrimeLifeState.pending.

static func cfg() -> Dictionary:
	return CrimeUnderState.sect("hit")

static func get_contract(id: int) -> Dictionary:
	return CrimeUnderState.contracts.get(id, {})

static func live() -> Array:
	var out: Array = []
	for id in CrimeUnderState.contracts:
		if str(CrimeUnderState.contracts[id].get("state", "")) in ["open", "taken"]:
			out.append(CrimeUnderState.contracts[id])
	out.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	return out

static func open_list() -> Array:
	return live().filter(func(c): return str(c["state"]) == "open")

static func against(target: int) -> Array:
	return live().filter(func(c): return int(c["target"]) == target)

static func _has_live(client: int, target: int) -> bool:
	for c in live():
		if int(c["client"]) == client and int(c["target"]) == target:
			return true
	return false

## A client puts a contract out. Returns the contract ({} when not possible).
static func post(client: int, target: int, why: String = "grudge", opts: Dictionary = {}) -> Dictionary:
	var k: Dictionary = cfg()
	if client == target or not CrimePerson.alive(target) or not CrimePerson.alive(client) or _has_live(client, target) or live().size() >= int(k.get("open_cap", 8)):
		return {}
	var fee: int = CrimeUnderState.range_i(k.get("fee", [260, 900])) + int(float(CrimePerson.coins(target)) * float(k.get("fee_wealth", 0.08)))
	if CrimePerson.is_player(target):
		fee = int(float(fee) * float(k.get("player_target_fee_mult", 1.6)))
	fee = mini(fee, int(k.get("fee_cap", 2600)))
	if CrimePerson.coins(client) < fee / 2 and not opts.has("fee"):
		return {}
	fee = int(opts.get("fee", fee))
	var dl: Array = k.get("deadline_days", [8, 18])
	var c: Dictionary = {"id": CrimeUnderState.next_contract, "client": client, "target": target, "fee": fee, "posted": SysUtil.day(), "deadline": SysUtil.day() + CrimeUnderState.range_i(dl),
		"cond": {"quiet": CrimeUnderState.chance(float(k.get("quiet_chance", 0.3))), "alone": CrimeUnderState.chance(float(k.get("alone_chance", 0.25)))}, "state": "open",
		"hitman": -1, "research": 0.0, "mistakes": 0, "seen": false, "case": -1, "why": why, "due_day": -1}
	CrimeUnderState.next_contract += 1
	CrimeUnderState.contracts[int(c["id"])] = c
	CrimeUnderState.count("contract_posted")
	_trim()
	SysUtil.game_event("contract_posted", {"client": client, "target": target, "contract": int(c["id"])})
	return c

static func _trim() -> void:
	var done: Array = []
	for id in CrimeUnderState.contracts:
		if not str(CrimeUnderState.contracts[id].get("state", "")) in ["open", "taken"]:
			done.append(int(id))
	done.sort()
	while done.size() > 30:
		CrimeUnderState.contracts.erase(done.pop_front())

## What the player's hitman sees on the board: open contracts they could take (rank/fee/target/deadline). The client is a mystery unless trusted.
static func board(pid: int) -> Array:
	var out: Array = []
	for c in open_list():
		out.append({"id": int(c["id"]), "target": int(c["target"]), "target_name": CrimePerson.name_of(int(c["target"])), "fee": int(c["fee"]), "deadline": int(c["deadline"]),
			"quiet": bool(c["cond"]["quiet"]), "alone": bool(c["cond"]["alone"]), "client_name": CrimePerson.name_of(int(c["client"])) if CrimeLifePath.cred(pid) >= 35.0 else "an anonymous client"})
	return out

# ------------------------------------------------------------------ daily
static func on_day() -> void:
	var k: Dictionary = cfg()
	_expire()
	_post_dice(k)
	_npc_work(k)
	_hunted_signs(k)

static func _expire() -> void:
	for c in live():
		if SysUtil.day() > int(c["deadline"]):
			c["state"] = "expired"
			CrimeUnderState.count("contract_expired")
			if int(c["hitman"]) >= 0 and CrimePerson.is_player(int(c["hitman"])):
				SysUtil.notify("The deadline on the contract passed. The client is not pleased.", "warn")
				CrimeLifePath.add_cred(int(c["hitman"]), float(cfg().get("refuse", {}).get("cred", -1.5)) * 2.0, "late")

static func _post_dice(k: Dictionary) -> void:
	if live().size() >= int(k.get("open_cap", 8)):
		return
	var keys: Array = JusticeState.grudges.keys()
	keys.sort()
	for gk in keys:
		var parts: PackedStringArray = str(gk).split(">")
		if parts.size() != 2:
			continue
		var a: int = int(parts[0])
		var b: int = int(parts[1])
		var rage: float = float((JusticeState.grudges[gk] as Dictionary).get("rage", 0.0))
		var to_player: bool = CrimePerson.is_player(b)
		if rage < (float(k.get("player_rage", 85.0)) if to_player else float(k.get("grudge_rage", 58.0))) or CrimePerson.is_player(a) or not CrimePerson.is_adult(a):
			continue
		if not CrimeUnderState.chance(float(k.get("player_daily", 0.004)) if to_player else float(k.get("client_daily", 0.006))):
			continue
		var c: Dictionary = post(a, b, "grudge")
		if not c.is_empty():
			JusticeState.grudges[gk]["rage"] = rage * 0.85          # the client has outsourced the anger
			if live().size() >= int(k.get("open_cap", 8)):
				return

## Townie hitmen take open contracts, research, then act on the day (the same odds as the player). Contracts on the player's folk are always staffed
## by a real townie so the case has a culprit.
static func _npc_work(k: Dictionary) -> void:
	var npc: Dictionary = k.get("npc", {})
	for c in live():
		var hm: int = int(c["hitman"])
		if str(c["state"]) == "open":
			if CrimePerson.is_player(int(c["target"])) or CrimeUnderState.chance(float(npc.get("take_daily", 0.2))):
				var cand: int = _pick_hitman(c)
				if cand < 0:
					continue
				c["hitman"] = cand
				c["state"] = "taken"
				c["taken_day"] = SysUtil.day()
				c["due_day"] = SysUtil.day() + CrimeUnderState.range_i(npc.get("research_days", [2, 5]))
				c["npc"] = true
				CrimeUnderState.count("contract_taken_npc")
			continue
		if hm < 0 or CrimePerson.is_player(hm) or not bool(c.get("npc", false)):
			continue
		if not CrimePerson.alive(hm) or CrimePerson.in_custody(hm):
			c["state"] = "open"
			c["hitman"] = -1
			continue
		c["research"] = minf(float(c["research"]) + CrimeUnderState.range_f(k.get("research", {}).get("gain", [0.2, 0.34])) * 0.5, 1.0)
		if SysUtil.day() >= int(c["due_day"]):
			CrimeUnderHitRun.npc_act(c)

## The townie best placed: hit-line members first, else a hard member of the path (a "stranger" is promoted for a contract on the player).
static func _pick_hitman(c: Dictionary) -> int:
	var best: int = -1
	var bs: float = -1.0
	for pid in CrimeUnderLines.townie_members("hit"):
		if pid == int(c["client"]) or pid == int(c["target"]) or CrimePerson.in_custody(pid) or _busy(pid):
			continue
		var s: float = CrimeUnderLines.standing(pid, "hit") + CrimeLifePath.cred(pid) * 0.2
		if s > bs:
			bs = s
			best = pid
	if best >= 0 or not CrimePerson.is_player(int(c["target"])):
		return best
	var pool: Array = []
	var fallback: Array = []
	for tid in CrimePerson.townies_only():
		if CrimePerson.is_adult(tid) and CrimePerson.stage(tid) != "elder" and tid != int(c["client"]) and tid != int(c["target"]) and not CrimePerson.in_custody(tid):
			fallback.append(tid)
			if CrimePerson.has_trait(tid, "vengeful") or CrimePerson.has_trait(tid, "dishonest") or CrimeLifePath.is_member(tid):
				pool.append(tid)
	if pool.is_empty():
		pool = fallback
	pool.sort()
	if pool.is_empty():
		return -1
	var pick: int = int(pool[CrimeUnderState.rng.randi_range(0, pool.size() - 1)])
	if not CrimeLifePath.is_member(pick):
		CrimeLifePath.join(pick, "drift")
		CrimeLifePath.member(pick)["cred"] = 30.0
	var l: Dictionary = CrimeUnderState.lines.get(pick, {})
	l["hit"] = {"standing": 12.0, "since": SysUtil.day(), "acts": 0, "via": "desperate"}
	CrimeUnderState.lines[pick] = l
	return pick

static func _busy(pid: int) -> bool:
	for c in live():
		if int(c["hitman"]) == pid:
			return true
	return false

## Warning signs for the player's folk while a contract hangs over them.
static func _hunted_signs(k: Dictionary) -> void:
	for c in live():
		var t: int = int(c["target"])
		if not CrimePerson.is_player(t) or str(c["state"]) != "taken" or bool(c.get("warned", false)):
			continue
		if SysUtil.day() - int(c.get("taken_day", c["posted"])) >= int(k.get("attack", {}).get("warn_days", 2)) or SysUtil.day() >= int(c["due_day"]) - 1:
			c["warned"] = true
			var f = CrimePerson.folk(t)
			if f != null:
				f.add_buff("hunted")
			SysUtil.notify("A stranger has been asking about %s around town. Something is wrong." % CrimePerson.name_of(t), "warn")

# ------------------------------------------------------------------ townie hitmen (daily dice, once per person)
static func person_day(pid: int) -> void:
	var npc: Dictionary = cfg().get("npc", {})
	if CrimePerson.is_player(pid) or CrimeUnderLines.has(pid, "hit") or not CrimePerson.is_adult(pid) or CrimePerson.stage(pid) == "elder":
		return
	if CrimeLifePath.rank_index(pid) < CrimeLifePath.rank_index_of_id(str(npc.get("min_rank", "burglar"))):
		return
	if CrimeUnderLines.townie_members("hit").size() >= int(npc.get("max_hitmen", 2)) or CrimeUnderLines.townie_share("hit") >= float(npc.get("max_share", 0.02)):
		return
	CrimeUnderLines.townie_join_dice(pid, "hit", float(npc.get("join_daily", 0.0012)), npc.get("traits", []))
