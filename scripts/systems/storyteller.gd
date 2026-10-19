class_name Storyteller
extends RefCounted
## The Storyteller (task 29): a layer on top of the incident dice, crime, chaos, city and story threads that adds irregular, readable unpredictability.
## It never reuses the rhythm of a wave: each household, each district, each townie lot and the town hold a hidden CHAOS LEVEL (a noisy random walk with
## sudden jumps, StorytellerChaos) that fills a DRAMA BUDGET (StorytellerBudget). When the budget can pay, a card is drawn from the deck
## (StorytellerDeck, data/storyteller_cards.json: every existing good and bad incident plus new twists, city events and chain events) and played
## (StorytellerPlay). Most cards happen SOMEWHERE in the town and ripple outward by distance, relationship and news (StorytellerRipple); one event raises the
## odds of related ones nearby (heat, chains). Arcs (StorytellerArcs) are multi-day stories on top of StoryThreads, cycles (StorytellerCycles) are town eras.
##
## Personalities: calm | classic (default) | chaotic | custom (four sliders). The HOST's choice applies in co-op (commands from other players are refused).
## Hard rules: murder, serial killers, child abuse and the disasters are never in the deck; their rates only get a capped multiplier (hard_mult(), data hard_cap);
## "Mature life events" and every category (Storyteller.cat_on) can be switched off; nothing sexual, no trafficking.
##
## Tier behaviour: player households FULL (real incidents, choices, buffs, toasts); townie lots STATISTICAL (one line, the incident's own statistical outcome);
## districts and the town are numbers plus one event at a time, rippling into the player households by distance.
## Cadence: one daily row (SimRegistry "day/Storyteller.on_day"), O(households + townie lots + zones), a few comparisons each; nothing per minute.
## Active set: the keys list rebuilt each day. Caps: log 120, queue 40, choices 6, entries one per key.
## Randomness: its own seeded stream (SimSeed master seed ^ salt), saved with the incidents block (Incidents.to_dict()["storyteller"]).
##
## API: personality_id() / set_personality(id, custom) / cat_on(cat) / log_lines(n, hid) / log_entries(n) / hard_mult() / incident_mult(id) / ripple_count(hid).

const KEY_TOWN := "town"
const TIERS_LOCAL := ["small", "medium", "big"]

static var master_seed: int = 0              # set by SimSeed.apply, survives reset()
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()
static var enabled: bool = true              # statistical rate tests switch the storyteller off to measure "today's" numbers
static var personality: String = ""
static var custom: Dictionary = {}           # frequency, severity, balance, mercy (0..1)
static var off_cats: Dictionary = {}         # category -> true when the player turned it off
static var entries: Dictionary = {}          # key -> budget record (StorytellerBudget)
static var heat: Dictionary = {}             # zone -> {tag: value}
static var queue: Array = []                 # [{due, kind, ...}] chains, ripple follow-ups, foreshadowed cards (StorytellerQueue)
static var choices: Array = []               # open player choices
static var ripples: Dictionary = {}          # hid -> {near, know, town}
static var played: Dictionary = {}           # "key|card" -> day
static var playing: bool = false             # true while a card runs: chronicle lines it causes are not charged to the budget twice
static var stats: Dictionary = {}            # counters for tests and the debug view
static var _mult_cache: Dictionary = {}

static func reset() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = master_seed ^ int(cfg().get("seed_salt", 2929)) if master_seed != 0 else int(cfg().get("seed_salt", 2929))
	enabled = true
	personality = _settings_personality()
	custom = (cfg().get("custom", {}).get("defaults", {}) as Dictionary).duplicate()
	off_cats.clear()
	entries.clear()
	heat.clear()
	queue.clear()
	choices.clear()
	ripples.clear()
	played.clear()
	stats.clear()
	playing = false
	_mult_cache.clear()
	StorytellerLog.reset()
	StorytellerArcs.reset()
	StorytellerCycles.reset()

static func cfg() -> Dictionary:
	return SysUtil.table("storyteller")

static func bump(stat: String, n: int = 1) -> void:
	stats[stat] = int(stats.get(stat, 0)) + n

# ------------------------------------------------------------------ personality
static func _settings_personality() -> String:
	var p: String = GameSettings.get_str("storyteller")
	return p if (cfg().get("personalities", {}) as Dictionary).has(p) else str(cfg().get("default", "classic"))

static func personality_id() -> String:
	return personality if personality != "" else _settings_personality()

static func personality_ids() -> Array:
	return (cfg().get("personalities", {}) as Dictionary).keys()

static func label(id: String = "") -> String:
	return str(((cfg().get("personalities", {}) as Dictionary).get(id if id != "" else personality_id(), {}) as Dictionary).get("label", id))

static func blurb(id: String = "") -> String:
	return str(((cfg().get("personalities", {}) as Dictionary).get(id if id != "" else personality_id(), {}) as Dictionary).get("blurb", ""))

## Change the personality (and the Custom sliders, 0..1 each). Not a command: use StorytellerCmd for player orders.
static func set_personality(id: String, sliders: Dictionary = {}) -> bool:
	if not (cfg().get("personalities", {}) as Dictionary).has(id):
		return false
	personality = id
	for k in ["frequency", "severity", "balance", "mercy"]:
		if sliders.has(k):
			custom[k] = clampf(float(sliders[k]), 0.0, 1.0)
	_mult_cache.clear()
	return true

static func set_cat(cat: String, on: bool) -> void:
	if on:
		off_cats.erase(cat)
	else:
		off_cats[cat] = true
	_mult_cache.clear()

static func cat_on(cat: String) -> bool:
	return cat == "" or not off_cats.has(cat)

## The resolved numbers of the current personality (Custom interpolates its sliders through data "custom").
static func params() -> Dictionary:
	var id: String = personality_id()
	var ps: Dictionary = cfg().get("personalities", {})
	if id != "custom":
		return (ps.get(id, ps.get("classic", {})) as Dictionary)
	var cu: Dictionary = cfg().get("custom", {})
	var f: float = float(custom.get("frequency", 0.5))
	var s: float = float(custom.get("severity", 0.5))
	var b: float = float(custom.get("balance", 0.5))
	var m: float = float(custom.get("mercy", 0.5))
	var calm: Dictionary = ps["calm"]
	var chaotic: Dictionary = ps["chaotic"]
	var classic: Dictionary = ps["classic"]
	var sizes: Dictionary = {}
	for k in TIERS_LOCAL:
		sizes[k] = lerpf(float(calm["sizes"][k]), float(chaotic["sizes"][k]), s)
	var w: Dictionary = {"mean": lerpf(float(cu["mean"][0]), float(cu["mean"][1]), f), "noise": lerpf(float(cu["noise"][0]), float(cu["noise"][1]), s),
		"revert": float(classic["walk"]["revert"]), "jump_chance": lerpf(float(calm["walk"]["jump_chance"]), float(chaotic["walk"]["jump_chance"]), s),
		"jump_size": lerpf(float(cu["jump_size"][0]), float(cu["jump_size"][1]), s)}
	return {"label": "Custom", "walk": w, "sizes": sizes, "good_share": lerpf(float(cu["good_share"][0]), float(cu["good_share"][1]), b),
		"mercy": m, "mercy_days": int(round(lerpf(float(cu["mercy_days"][0]), float(cu["mercy_days"][1]), m))),
		"max_quiet_days": int(round(lerpf(float(cu["max_quiet_days"][0]), float(cu["max_quiet_days"][1]), f))),
		"big_gap_days": int(round(lerpf(float(cu["big_gap_days"][0]), float(cu["big_gap_days"][1]), s))), "bad_big_gap_days": int(round(lerpf(float(cu["big_gap_days"][0]), float(cu["big_gap_days"][1]), s))),
		"hard_mult": lerpf(float(cu["hard_mult"][0]), float(cu["hard_mult"][1]), s), "crime_mult": lerpf(float(cu["crime_mult"][0]), float(cu["crime_mult"][1]), s),
		"foreshadow": lerpf(float(cu["foreshadow"][0]), float(cu["foreshadow"][1]), s)}

static func param(k: String, d = 0.0):
	return params().get(k, d)

# ------------------------------------------------------------------ hard rules: capped rate multipliers
## The multiplier the storyteller puts on the rarest, worst things (murder, serial killers, child abuse, disasters). Never above data hard_cap.
static func hard_mult() -> float:
	if not enabled:
		return 1.0
	return clampf(float(param("hard_mult", 1.0)) * StorytellerCycles.mult("_hard"), 0.0, float(cfg().get("hard_cap", 1.5)))

## Per-incident rate multiplier (IncidentChecks._roll): hard incidents get hard_mult(), crimes crime_mult() times an active crime wave, cycles (flu) their own.
static func incident_mult(id: String) -> float:
	if not enabled:
		return 1.0
	if _mult_cache.has(id):
		return float(_mult_cache[id])
	var c: Dictionary = cfg()
	var m: float = 1.0
	if (c.get("hard_incidents", []) as Array).has(id):
		m = hard_mult()
	else:
		if (c.get("crime_incidents", []) as Array).has(id):
			m = float(param("crime_mult", 1.0))
		m *= StorytellerCycles.mult(id)
	_mult_cache[id] = m
	return m

## Weighted pick from the storyteller's own stream.
static func pick_weighted(items: Array, weights: Array):
	var total: float = 0.0
	for w in weights:
		total += maxf(float(w), 0.0)
	if items.is_empty() or total <= 0.0:
		return null
	var roll: float = rng.randf() * total
	for i in items.size():
		roll -= maxf(float(weights[i]), 0.0)
		if roll <= 0.0:
			return items[i]
	return items[items.size() - 1]

static func clear_mult_cache() -> void:
	_mult_cache.clear()

# ------------------------------------------------------------------ the daily pass
static func on_day(day: int) -> void:
	if not enabled or SysUtil.table("storyteller").is_empty():
		return
	var tp := PerfProf.start()
	StorytellerChaos.decay_heat()
	var keys: Array = StorytellerBudget.keys()
	for k in keys:
		StorytellerChaos.step(str(k))
	PerfProf.stop("story/chaos+keys", tp)
	tp = PerfProf.start()
	StorytellerCycles.on_day(day)
	StorytellerArcs.on_day(day)
	StorytellerQueue.on_day(day)
	PerfProf.stop("story/cycles+arcs+queue", tp)
	tp = PerfProf.start()
	for k in keys:
		StorytellerBudget.day(str(k), day)
	PerfProf.stop("story/budget", tp)

static func on_game_event(ev: String, p: Dictionary) -> void:
	if not enabled:
		return
	if ev == "chronicle":
		StorytellerBudget.on_chronicle(p)

# ------------------------------------------------------------------ the log (Town panel API)
## Plain-word lines, newest last: "Day 12: A break-in on the east side. (Money was tight.)". hid > 0 keeps only what touched that household.
static func log_lines(n: int = 12, hid: int = 0) -> Array:
	return StorytellerLog.lines(n, hid)

static func log_entries(n: int = 20) -> Array:
	return StorytellerLog.recent(n)

static func ripple_count(hid: int) -> int:
	var r: Dictionary = ripples.get(hid, {})
	return int(r.get("near", 0)) + int(r.get("know", 0))

## Card `when.pets`: the pet system (task 14) is there and this household has room for another pet.
static func pets_exist(hid: int = 0) -> bool:
	if (PetState.cfg().get("species", {}) as Dictionary).is_empty():
		return false
	return hid <= 0 or PetState.of_household(hid).size() < int(PetState.cfg().get("max_per_household", 3))

# ------------------------------------------------------------------ save (nested in Incidents.to_dict()["storyteller"])
static func to_dict() -> Dictionary:
	return {"personality": personality_id(), "custom": custom.duplicate(), "off": off_cats.keys(), "rng_seed": str(rng.seed), "rng_state": str(rng.state),
		"entries": entries.duplicate(true), "heat": heat.duplicate(true), "queue": queue.duplicate(true), "choices": choices.duplicate(true), "ripples": ripples.duplicate(true),
		"played": played.duplicate(), "stats": stats.duplicate(), "log": StorytellerLog.to_dict(), "arcs": StorytellerArcs.to_dict(), "cycles": StorytellerCycles.to_dict()}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	var p: String = str(d.get("personality", personality))
	if (cfg().get("personalities", {}) as Dictionary).has(p):
		personality = p
	custom = (d.get("custom", custom) as Dictionary).duplicate()
	off_cats.clear()
	for c in d.get("off", []):
		off_cats[str(c)] = true
	rng.seed = int(str(d.get("rng_seed", rng.seed)))
	rng.state = int(str(d.get("rng_state", rng.state)))
	entries = _entries_in(d.get("entries", {}))
	heat = (d.get("heat", {}) as Dictionary).duplicate(true)
	queue = _rows_in(d.get("queue", []))
	choices = _rows_in(d.get("choices", []))
	ripples = {}
	for k in d.get("ripples", {}):
		ripples[int(k)] = _ints(d["ripples"][k])
	played = _ints(d.get("played", {}))
	stats = _ints(d.get("stats", {}))
	StorytellerLog.from_dict(d.get("log", {}))
	StorytellerArcs.from_dict(d.get("arcs", {}))
	StorytellerCycles.from_dict(d.get("cycles", {}))

static func _ints(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in src:
		out[k] = int(src[k])
	return out

static func _entries_in(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in src:
		var e: Dictionary = (src[k] as Dictionary).duplicate(true)
		SysUtil.ints_in(e, ["last_notable", "last_big", "last_bad_big", "mercy_until", "last_spend"])
		e["want"] = str(e.get("want", ""))
		out[str(k)] = e
	return out

static func _rows_in(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		var q: Dictionary = (r as Dictionary).duplicate(true)
		SysUtil.ints_in(q, ["due", "hid", "folk_id", "other", "lot", "day", "id"])
		if q.get("ctx") is Dictionary:           # a foreshadowed card carries its ctx: ints again after JSON (floats), so a second save is identical
			SysUtil.ints_in(q["ctx"], ["hid", "folk_id", "other", "lot", "who"])
		out.append(q)
	return out
