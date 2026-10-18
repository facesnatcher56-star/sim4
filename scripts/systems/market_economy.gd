class_name MarketEconomy
extends RefCounted
## The town's living economy (task 13, slice 1). One prosperity number drifts with booms and recessions; prices, rents and wages follow it
## on top of a slow inflation. Unemployment comes from the townies' jobs (layoffs in a recession, hiring in a boom).
## Tier: town-wide, DAILY, O(townies). Active set: none (pure numbers + Story.townies). Caps: history 12 entries, rng seeded.
## Data: data/shops.json "economy". Switched on by SystemsManager.new_game / a loaded save (`enabled`); tests without it see 1.0 everywhere.

static var enabled: bool = false
static var prosperity: float = 0.0       # -1 .. 1
static var phase: String = "normal"      # normal | boom | recession
static var phase_left: int = 0
static var base_level: float = 1.0       # slow money inflation
static var price_idx: float = 1.0
static var rent_idx: float = 1.0
static var wage_idx: float = 1.0
static var inflation: float = 0.0        # per game year, as a fraction
static var unemployment: float = 0.0
static var history: Array = []           # [{day, prosperity, price, unemployment}]
static var last_report: int = 0
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func reset() -> void:
	enabled = false
	prosperity = 0.0
	phase = "normal"
	phase_left = 0
	base_level = 1.0
	price_idx = 1.0
	rent_idx = 1.0
	wage_idx = 1.0
	inflation = 0.0
	unemployment = 0.0
	history.clear()
	last_report = 0
	rng = RandomNumberGenerator.new()
	rng.seed = 130013

static func cfg() -> Dictionary:
	return SysUtil.table("shops").get("economy", {})

static func start() -> void:
	enabled = true

# ------------------------------------------------------------------ multipliers other systems read
static func price_mult() -> float:
	return price_idx if enabled else 1.0

static func rent_mult() -> float:
	return rent_idx if enabled else 1.0

static func wage_mult() -> float:
	return wage_idx if enabled else 1.0

static func phase_label() -> String:
	return {"boom": "Boom", "recession": "Recession"}.get(phase, "Steady")

# ------------------------------------------------------------------ daily
static func on_day(day: int) -> void:
	if not enabled:
		return
	var c: Dictionary = cfg()
	_phase(c, day)
	var target: float = float(c.get("boom_target", 0.7)) if phase == "boom" else (float(c.get("recession_target", -0.7)) if phase == "recession" else 0.0)
	var noise: float = float(c.get("noise", 0.04))
	prosperity = clampf(prosperity + (target - prosperity) * float(c.get("pull", 0.12)) + rng.randf_range(-noise, noise), -1.0, 1.0)
	inflation = float(c.get("base_inflation", 0.03)) + float(c.get("prosperity_inflation", 0.05)) * prosperity
	var yd: float = maxf(float(c.get("year_days", 28)), 1.0)
	base_level = clampf(base_level * pow(1.0 + inflation, 1.0 / yd), float(c.get("level_min", 0.6)), float(c.get("level_max", 3.0)))
	price_idx = lerpf(price_idx, base_level * (1.0 + float(c.get("price_swing", 0.1)) * prosperity), float(c.get("price_follow", 0.25)))
	rent_idx = lerpf(rent_idx, base_level * (1.0 + float(c.get("rent_swing", 0.12)) * prosperity), float(c.get("rent_follow", 0.08)))
	wage_idx = lerpf(wage_idx, base_level * (1.0 + float(c.get("wage_swing", 0.06)) * prosperity), float(c.get("wage_follow", 0.1)))
	_townie_jobs(c)
	unemployment = _measure_unemployment()
	if day - last_report >= int(c.get("report_days", 28)):
		last_report = day
		_report(day, c)

static func _phase(c: Dictionary, day: int) -> void:
	if phase != "normal":
		phase_left -= 1
		if phase_left <= 0:
			_note_end()
			phase = "normal"
		return
	if rng.randf() >= float(c.get("phase_chance", 0.025)):
		return
	var span: Array = c.get("phase_days", [12, 30])
	phase_left = rng.randi_range(int(span[0]), int(span[1]))
	# a town that has been shrinking tends to recover, one that has been growing tends to cool off
	var boom_p: float = clampf(0.5 - prosperity * 0.3, 0.2, 0.8)
	phase = "boom" if rng.randf() < boom_p else "recession"
	if phase == "boom":
		ChronicleHook.note("economy", "The town is booming: shops are busy and jobs are easy to find.", [], "town:0", 2, true)
	else:
		ChronicleHook.note("economy", "A recession has hit the town: prices bite and jobs are being cut.", [], "town:0", 3, true)
	SysUtil.game_event("economy_phase", {"phase": phase, "day": day})

static func _note_end() -> void:
	ChronicleHook.note("economy", "The %s has passed; the town economy is steady again." % ("boom" if phase == "boom" else "recession"), [], "town:0", 1, true)

## Layoffs in a recession, hiring in a boom (townies; households use MarketWork.maybe_layoff).
static func _townie_jobs(c: Dictionary) -> void:
	var laid: Array = []
	for t in Story.alive_townies():
		if Story.stage_of(t) != "adult":
			continue
		var job: String = str(t.get("career", ""))
		if job != "" and prosperity < float(c.get("layoff_below", -0.3)):
			if rng.randf() < float(c.get("layoff_chance", 0.02)) * (-prosperity):
				t["career"] = ""
				t["level"] = 1
				laid.append(str(t["name"]))
		elif job == "" and not t.has("job_biz") and prosperity > float(c.get("hire_above", 0.1)):
			if rng.randf() < float(c.get("hire_chance", 0.12)) * prosperity:
				var careers: Array = Story.cfg().get("careers", [])
				if not careers.is_empty():
					t["career"] = str(careers[rng.randi_range(0, careers.size() - 1)])
					t["level"] = 1
	if laid.size() >= 2:
		ChronicleHook.note("economy", "%d people lost their jobs in the cuts." % laid.size(), [], "town:0", 2, true)
	elif laid.size() == 1:
		Story._log("%s was laid off." % laid[0])

static func _measure_unemployment() -> float:
	var workers: int = 0
	var jobless: int = 0
	for t in Story.alive_townies():
		if Story.stage_of(t) != "adult":
			continue
		workers += 1
		if str(t.get("career", "")) == "" and not t.has("job_biz") and not bool(t.get("owner_biz", false)):
			jobless += 1
	for f in SysUtil.residents():
		if f.age_stage == "adult":
			workers += 1
			if not Careers.has_job(int(f.id)) and not MarketWork.is_self_employed(int(f.id)):
				jobless += 1
	return float(jobless) / float(maxi(workers, 1))

static func _report(day: int, c: Dictionary) -> void:
	history.append({"day": day, "prosperity": snappedf(prosperity, 0.01), "price": snappedf(price_idx, 0.001), "unemployment": snappedf(unemployment, 0.001)})
	while history.size() > int(c.get("history_size", 12)):
		history.pop_front()
	ChronicleHook.note("economy_report", "Town economy: %s. %s" % [phase_label(), headline()], [], "town:0", 1, true)

# ------------------------------------------------------------------ town stats (Chronicle, newspaper, dialogs)
static func headline() -> String:
	return "Prices %s %.1f%% a year, unemployment %d%%." % ["up" if inflation >= 0.0 else "down", absf(inflation) * 100.0, int(round(unemployment * 100.0))]

static func stats() -> Dictionary:
	return {"phase": phase, "label": phase_label(), "prosperity": prosperity, "price_index": price_idx, "rent_index": rent_idx, "wage_index": wage_idx,
		"inflation": inflation, "unemployment": unemployment, "budget": town_budget(), "history": history.duplicate(true)}

## Task 12 (city infrastructure) owns the town budget; until it exists this reports a stub of 0.
static func town_budget() -> int:
	return 0

static func lines() -> Array:
	var out: Array = []
	out.append("The economy is %s." % phase_label().to_lower())
	out.append(headline())
	out.append("Rents are %s, wages are %s." % [_idx_text(rent_idx), _idx_text(wage_idx)])
	return out

static func _idx_text(v: float) -> String:
	return "%+d%% on the start of the game" % int(round((v - 1.0) * 100.0))

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"enabled": enabled, "prosperity": prosperity, "phase": phase, "phase_left": phase_left, "base_level": base_level, "price_idx": price_idx,
		"rent_idx": rent_idx, "wage_idx": wage_idx, "inflation": inflation, "unemployment": unemployment, "history": history.duplicate(true),
		"last_report": last_report, "rng_seed": str(rng.seed), "rng_state": str(rng.state)}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	enabled = bool(d.get("enabled", false))
	prosperity = float(d.get("prosperity", 0.0))
	phase = str(d.get("phase", "normal"))
	phase_left = int(d.get("phase_left", 0))
	base_level = float(d.get("base_level", 1.0))
	price_idx = float(d.get("price_idx", 1.0))
	rent_idx = float(d.get("rent_idx", 1.0))
	wage_idx = float(d.get("wage_idx", 1.0))
	inflation = float(d.get("inflation", 0.0))
	unemployment = float(d.get("unemployment", 0.0))
	history = (d.get("history", []) as Array).duplicate(true)
	last_report = int(d.get("last_report", 0))
	rng.seed = int(str(d.get("rng_seed", "130013")))
	rng.state = int(str(d.get("rng_state", str(rng.state))))
