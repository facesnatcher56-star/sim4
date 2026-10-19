class_name WorksEvents
extends RefCounted
## Industrial trouble (task 31): strikes and plant closures, as events a storyteller (task 29) can also call.
##   WorksEvents.schedule_strike(career, days, cause)   announced today, the workers stay out from tomorrow for `days` days
##   WorksEvents.close_works(career, cause)              the firm shuts down: everybody with that career (residents and townies) is laid off
##   WorksEvents.on_strike(career)                       is the career out today? (WorksPay / CommuteTownies read it)
##   WorksEvents.strike_chance(career) / closure_chance(career)   today's dice, for tests and tuning
## The daily dice (`day/WorksEvents.on_day`) grow with a recession (MarketEconomy.prosperity), with recent workplace injuries (strikes) and with the
## career's layoff weight (closures). A strike ends in a raise (`raises`, applied to pay by WorksPay) or in nothing. State is saved inside the city block
## (CityState). Numbers and texts: data/careers_works.json `works`.

const SEED := 3131

static var rng: RandomNumberGenerator = RandomNumberGenerator.new()
static var strikes: Dictionary = {}     # career -> {start, end, cause}
static var raises: Dictionary = {}      # career -> permanent wage rise (0.05 = +5 percent)
static var cool: Dictionary = {}        # career -> first day a new event may happen
static var hurt: Dictionary = {}        # career -> recent workplace injuries (decays daily)
static var counts: Dictionary = {}      # "strike" / "closure" / "win" -> n (tests and stats)

static func reset() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = SEED
	strikes.clear()
	raises.clear()
	cool.clear()
	hurt.clear()
	counts.clear()
	WorksUnion.reset()

static func _c(key: String) -> Dictionary:
	return Works.cfg().get(key, {})

static func _count(k: String) -> void:
	counts[k] = int(counts.get(k, 0)) + 1

static func on_strike(cid: String) -> bool:
	var s: Dictionary = strikes.get(cid, {})
	return not s.is_empty() and SysUtil.day() >= int(s["start"]) and SysUtil.day() <= int(s["end"])

static func strike_pending(cid: String) -> bool:
	return strikes.has(cid)

static func wage_mult(cid: String) -> float:
	return 1.0 + float(raises.get(cid, 0.0))

static func note_injury(cid: String) -> void:
	if Works.is_works(cid):
		hurt[cid] = float(hurt.get(cid, 0.0)) + 1.0

static func _slump() -> float:
	return maxf(0.0, -MarketEconomy.prosperity) if MarketEconomy.enabled else 0.0

static func strike_chance(cid: String) -> float:
	var k: Dictionary = _c("strike")
	return float(k.get("daily_chance", 0.006)) * (1.0 + float(k.get("slump_mult", 3.0)) * _slump()) * (1.0 + float(k.get("injury_mult", 0.5)) * float(hurt.get(cid, 0.0)))

static func closure_chance(cid: String) -> float:
	var k: Dictionary = _c("closure")
	return float(k.get("daily_chance", 0.0015)) * (1.0 + float(k.get("slump_mult", 6.0)) * _slump()) * Works.layoff_mult(cid)

# ------------------------------------------------------------------ announcements
static func _residents_of(cid: String) -> Array:
	var out: Array = []
	for fid in Careers.jobs.keys():
		if str(Careers.jobs[fid]["career"]) == cid:
			var f = SysUtil.folk(int(fid))
			if f != null:
				out.append(f)
	return out

static func _say(cid: String, text: String, chronicle_kind: String, severity: int) -> void:
	if not _residents_of(cid).is_empty():
		SysUtil.notify(text, "warn")                  # only households with that job hear it as a toast
	ChronicleHook.note(chronicle_kind, text, [], "town:0", severity, true)

# ------------------------------------------------------------------ strikes
## Called by the daily dice and by the storyteller. False when the career is not industrial or already has one.
static func schedule_strike(cid: String, days: int = -1, cause: String = "") -> bool:
	if not Works.is_works(cid) or strikes.has(cid):
		return false
	var k: Dictionary = _c("strike")
	if days < 0:
		var r: Array = k.get("days", [2, 5])
		days = rng.randi_range(int(r[0]), int(r[1]))
	var d: int = SysUtil.day()
	strikes[cid] = {"start": d + 1, "end": d + days, "cause": cause}
	cool[cid] = d + days + int(k.get("cooldown_days", 20))
	_count("strike")
	_say(cid, Works.fill("strike_called", {"sector": Works.sector_label(cid)}), "works", 2)
	SysUtil.game_event("works_strike", {"career": cid, "days": days, "cause": cause})
	return true

static func _settle(cid: String) -> void:
	var k: Dictionary = _c("strike")
	var win: bool = rng.randf() < float(k.get("win_chance", 0.6))
	strikes.erase(cid)
	if win:
		var r: Array = (_c("union")).get("wage_bump", [0.03, 0.08])
		raises[cid] = float(raises.get(cid, 0.0)) + rng.randf_range(float(r[0]), float(r[1]))
		_count("win")
		_say(cid, Works.fill("strike_end_win", {"sector": Works.sector_label(cid)}), "works", 1)
	else:
		_say(cid, Works.fill("strike_end_loss", {"sector": Works.sector_label(cid)}), "works", 1)
	SysUtil.game_event("works_strike_over", {"career": cid, "won": win})

# ------------------------------------------------------------------ closures
## The firm closes: residents get severance and lose the job, townies start looking. Returns how many people lost work.
static func close_works(cid: String, cause: String = "") -> int:
	if not Works.is_works(cid):
		return 0
	var k: Dictionary = _c("closure")
	var lost: int = 0
	for f in _residents_of(cid):
		var j: Dictionary = Careers.jobs[int(f.id)]
		var lv: Dictionary = Careers.level_def(cid, int(j["level"]), str(j.get("branch", "")))
		var pay: int = int(float(lv.get("pay", 10)) * float(k.get("severance_hours", 40)))
		Careers.quit_job(f, "laid_off")
		f.add_buff("laid_off")
		Economy.deposit(int(f.household_id), pay, "severance pay")
		SysUtil.notify(Works.fill("closure_resident", {"name": f.name, "sector": Works.sector_label(cid), "pay": pay}), "bad")
		lost += 1
	for t in Story.alive_townies():
		if str(t.get("career", "")) == cid:
			t["career"] = ""
			t["level"] = 1
			t["seeking"] = true
			lost += 1
	strikes.erase(cid)
	cool[cid] = SysUtil.day() + int(k.get("cooldown_days", 40))
	_count("closure")
	ChronicleHook.note("works", Works.fill("closure", {"sector": Works.sector_label(cid)}), [], "town:0", 3, true)
	SysUtil.game_event("works_closure", {"career": cid, "lost": lost, "cause": cause})
	return lost

# ------------------------------------------------------------------ the clock
static func on_day(day: int) -> void:
	if Works.table().is_empty():
		return
	for cid in strikes.keys():
		if day > int(strikes[cid]["end"]):
			_settle(str(cid))
	for cid2 in hurt.keys():
		hurt[cid2] = float(hurt[cid2]) * 0.9
		if float(hurt[cid2]) < 0.05:
			hurt.erase(cid2)
	WorksUnion.on_day()
	var min_n: int = int(_c("strike").get("min_workers", 3))
	for cid3 in Works.career_ids():
		if int(cool.get(cid3, 0)) > day or strikes.has(cid3) or Works.headcount(str(cid3)) < min_n:
			continue
		if rng.randf() < closure_chance(str(cid3)):
			close_works(str(cid3), "slump")
		elif rng.randf() < strike_chance(str(cid3)):
			schedule_strike(str(cid3), -1, "wages")

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"rng_seed": str(rng.seed), "rng_state": str(rng.state), "strikes": strikes.duplicate(true), "raises": raises.duplicate(), "cool": cool.duplicate(),
		"hurt": hurt.duplicate(), "counts": counts.duplicate(), "union": WorksUnion.to_dict()}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	rng.seed = int(str(d.get("rng_seed", SEED)))
	rng.state = int(str(d.get("rng_state", rng.state)))
	var s: Dictionary = d.get("strikes", {})
	for cid in s:
		strikes[str(cid)] = {"start": int(s[cid]["start"]), "end": int(s[cid]["end"]), "cause": str(s[cid].get("cause", ""))}
	for cid2 in d.get("raises", {}):
		raises[str(cid2)] = float(d["raises"][cid2])
	for cid3 in d.get("cool", {}):
		cool[str(cid3)] = int(d["cool"][cid3])
	for cid4 in d.get("hurt", {}):
		hurt[str(cid4)] = float(d["hurt"][cid4])
	for k in d.get("counts", {}):
		counts[str(k)] = int(d["counts"][k])
	WorksUnion.from_dict(d.get("union", {}))
