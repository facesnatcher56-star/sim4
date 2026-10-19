class_name StoryPacing
extends RefCounted
## Story pacing: a light layer that watches each household's recent "drama" (decayed sum of story beats from game events and the
## chronicle) and nudges the odds of EXISTING story events: calm for too long -> flirtations, gossip, visits, job offers and small
## mishaps get likelier; too much drama -> they ease off. It never creates events and never touches deaths, crimes or disasters:
## only the whitelisted kinds in data/story_pacing.json have a multiplier (everything else is 1.0).
##   StoryPacing.mult(kind, household_id)            the multiplier for a story kind
##   StoryPacing.incident_mult(incident_id, subject) mishap incidents (IncidentRisk calls it)
##   StoryPacing.interaction_mult(folk, def)         social autonomy (Autonomy calls it)
## Hooks (SystemsManager): on_game_event, on_day, reset. Threads (follow-ups of earlier events) live in StoryThreads.

const TOWN := 0

static var level: Dictionary = {}       # hid -> [value, day of value]
static var beats: Dictionary = {}       # hid -> Array of days (one entry per beat, last 14 days)
static var last_week_day: int = 0
static var enabled: bool = true         # statistical rate tests switch the pacing off (calm households would otherwise raise the rates)
static var sources: Dictionary = {}     # event / chronicle kind -> beats (debug, tests, probes)

static func reset() -> void:
	level.clear()
	beats.clear()
	last_week_day = 0
	sources.clear()
	enabled = true
	_today.clear()
	StoryThreads.reset()

static func cfg() -> Dictionary:
	return SysUtil.table("story_pacing")

# ------------------------------------------------------------------ drama level
static func drama(hid: int) -> float:
	var e: Variant = level.get(hid, null)
	if e == null:
		return 0.0
	var half: float = maxf(float(cfg().get("half_life_days", 2.0)), 0.1)
	return float(e[0]) * pow(0.5, float(SysUtil.day() - int(e[1])) / half)

static var _today: Dictionary = {}      # "hid|source" -> [day, count]: one source (an event, a chronicle kind) adds only a few beats a day

static func add_beat(hid: int, weight: float, source: String = "") -> void:
	if weight <= 0.0:
		return
	if source != "":
		var k: String = "%d|%s" % [hid, source]
		var e: Array = _today.get(k, [-1, 0])
		if int(e[0]) != SysUtil.day():
			e = [SysUtil.day(), 0]
		if int(e[1]) >= int(cfg().get("daily_cap_per_source", 2)):
			return
		e[1] = int(e[1]) + 1
		_today[k] = e
	level[hid] = [drama(hid) + weight, SysUtil.day()]
	var b: Array = beats.get(hid, [])
	b.append(SysUtil.day())
	if b.size() > 200:
		b = b.slice(b.size() - 200)
	beats[hid] = b

## Beats in the last `days` days (default a week).
static func beat_count(hid: int, days: int = 7) -> int:
	var n := 0
	for d in beats.get(hid, []):
		if SysUtil.day() - int(d) < days:
			n += 1
	return n

# ------------------------------------------------------------------ multipliers
static func mult(kind: String, hid: int) -> float:
	if not enabled:
		return 1.0
	var c: Dictionary = cfg()
	var kd: Dictionary = (c.get("kinds", {}) as Dictionary).get(kind, {})
	if kd.is_empty():
		return 1.0
	var l: float = drama(hid)
	var calm: float = float(c.get("calm_below", 3.0))
	var busy: float = float(c.get("busy_above", 9.0))
	var f: float = 1.0
	if l < calm:
		f = 1.0 + float(c.get("max_boost", 1.6)) * clampf((calm - l) / maxf(calm, 0.1), 0.0, 1.0)
	elif l > busy:
		f = 1.0 - float(c.get("max_cut", 0.6)) * clampf((l - busy) / maxf(busy, 0.1), 0.0, 1.0)
	return lerpf(1.0, f, float(kd.get("scale", 1.0)))

static func household_of_subject(subj) -> int:
	if int(subj.household_id) > 0:
		return int(subj.household_id)
	if str(subj.lot_key).begins_with("home:"):
		return int(str(subj.lot_key).get_slice(":", 1))
	return -1

static func incident_mult(incident_id: String, subj) -> float:
	var kd: Dictionary = (cfg().get("kinds", {}) as Dictionary).get("mishap", {})
	if not (kd.get("incidents", []) as Array).has(incident_id):
		return 1.0
	var hid: int = household_of_subject(subj)
	return mult("mishap", hid) if hid > 0 else 1.0

## `memo` (optional): one decision's cache (Autonomy passes its profile cache): the drama multiplier of a kind does not change within a decision.
static func interaction_mult(folk, d: Dictionary, memo: Dictionary = {}) -> float:
	if str(d.get("target", "object")) != "folk" or int(folk.household_id) <= 0:
		return 1.0
	var tags: Array = d.get("tags", [])
	var kinds: Dictionary = cfg().get("kinds", {})
	var m: float = 1.0
	for k in kinds:
		for t in (kinds[k] as Dictionary).get("tags", []):
			if tags.has(t):
				var mk: String = "#sp|" + str(k)
				if not memo.has(mk):
					memo[mk] = mult(str(k), int(folk.household_id))
				m *= float(memo[mk])
				break
	return m

# ------------------------------------------------------------------ beats from events
static func _hid_of(id: int) -> int:
	var f = SysUtil.folk(id)
	return int(f.household_id) if SysUtil.is_resident(f) else TOWN

static func on_game_event(ev: String, p: Dictionary) -> void:
	var c: Dictionary = cfg()
	if ev == "chronicle":
		_chronicle_beat(c, p)
		StoryThreads.on_chronicle(p)
		return
	var w: float = float((c.get("events", {}) as Dictionary).get(ev, 0.0))
	if w <= 0.0:
		return
	if ev == "relationship_bit_changed" and not (c.get("bit_beats", []) as Array).has(str(p.get("bit", ""))):
		return
	var a: int = _hid_of(int(p.get("folk_id", -1)))
	var b: int = _hid_of(int(p.get("target_id", -1)))
	sources[ev] = int(sources.get(ev, 0)) + 1
	if a != TOWN:
		add_beat(a, w, ev)
	if b != TOWN and b != a:
		add_beat(b, w, ev)
	if a == TOWN and b == TOWN and p.has("folk_id"):
		add_beat(TOWN, w, ev)
	StoryThreads.on_event(ev, p)

static func _chronicle_beat(c: Dictionary, p: Dictionary) -> void:
	var ck: Dictionary = c.get("chronicle", {})
	var kind: String = str(p.get("kind", ""))
	if (ck.get("ignore", []) as Array).has(kind):
		return
	var w: float = float((ck.get("kinds", {}) as Dictionary).get(kind, 0.0))
	if w <= 0.0 and int(p.get("severity", 1)) >= int(ck.get("default_min_severity", 2)):
		w = 1.0
	if w <= 0.0:
		return
	sources[kind] = int(sources.get(kind, 0)) + 1
	var seen: Dictionary = {}
	for s in p.get("subjects", []):
		var h: int = _hid_of(int(s))
		if not seen.has(h):
			seen[h] = true
			add_beat(h, w, kind)
	if seen.is_empty():
		add_beat(TOWN, w, kind)

# ------------------------------------------------------------------ daily
static func on_day(day: int) -> void:
	OpportunityTaker.on_day(day)
	StoryMilestones.on_day(day)
	StorySingles.on_day(day)
	StoryThreads.on_day(day)
	if day - last_week_day >= 7:
		if last_week_day > 0:
			_weekly_line()
		last_week_day = day

static func _weekly_line() -> void:
	var rs: Array = SysUtil.residents()
	if rs.is_empty():
		return
	var hid: int = int(rs[0].household_id)
	var n: int = beat_count(hid, 7)
	var wc: Dictionary = cfg().get("weekly", {})
	var line: String = "A quiet week." if n < int(wc.get("quiet_below", 6)) else ("A busy week." if n > int(wc.get("busy_above", 18)) else "")
	if line != "":
		SysUtil.notify(line, "info")
	SysUtil.game_event("story_week", {"household_id": hid, "beats": n, "drama": drama(hid)})
