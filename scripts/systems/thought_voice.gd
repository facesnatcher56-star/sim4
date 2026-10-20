class_name ThoughtVoice
extends RefCounted
## Thought-bubble voice (VIEW / FLAVOUR ONLY). Every Events.thought line passes through `filter` (called from SimEnv.emit):
##  * rate: one bubble per folk per gap_min game minutes (x speed_gap_mult at higher speeds), a daily cap, need lines may come a bit sooner;
##  * no line repeats within lookback_days for the same folk;
##  * lines about a need ("I should find a toilet.") are re-voiced from a big pool chosen by the folk's tone (mood, then traits);
##  * now and then a line names a friend, partner, child, parent, place or a recent event (ThoughtContext).
## Nothing here touches the sim rng streams or sim state: picks are a hash of (folk, minute, text); state is static and never saved.
## Numbers and every line live in data/thought_voice.json.

static var _st: Dictionary = {}          # folk id -> {last, day, count, cats:{cat:n}, used:{line:day}}
static var _urgent: bool = false         # true while emitting an emergency line
static var _raw: bool = false            # true while emitting a line this class already vetted
static var _urgent_last: Dictionary = {} # "fid|text" -> game minute (spam guard for emergency lines)

static func cfg() -> Dictionary:
	return SysUtil.table("thought_voice")

static func conf() -> Dictionary:
	return cfg().get("config", {})

static func reset() -> void:
	_st.clear()
	_urgent_last.clear()
	ThoughtContext.reset()

# ------------------------------------------------------------------ emitting
## Emergency lines (fire, gas, death, incident warnings, "I can't do that"): never rate-limited, only de-spammed.
static func urgent(fid, text: String) -> void:
	_urgent = true
	SimEnv.emit("thought", fid, text)
	_urgent = false

## Emit a line this class has already vetted (bypasses `filter`).
static func emit_raw(fid: int, text: String) -> void:
	_raw = true
	SimEnv.emit("thought", fid, text)
	_raw = false

# ------------------------------------------------------------------ gate
## Called by SimEnv.emit for every "thought". Returns the text to show, or "" to drop it.
static func filter(fid, text: String) -> String:
	var c: Dictionary = conf()
	if _raw or c.is_empty() or text == "":
		return text
	var id := int(fid)
	var now := SimEnv.now_min()
	if _urgent:
		var k := "%d|%s" % [id, text]
		if now - int(_urgent_last.get(k, -1000)) < int(c.get("urgent_repeat_min", 10)) and now >= int(_urgent_last.get(k, -1000)):
			return ""
		_urgent_last[k] = now
		return text
	var day := SysUtil.day()
	var st := _state(id, now, day)
	var cat := category_of(text)
	var need: float = _gap(c) * (float(c.get("category_gap_frac", 0.5)) if cat != "" else 1.0)
	if float(now - int(st["last"])) < need or int(st["count"]) >= int(c.get("max_per_day", 16)):
		return ""
	var f = SysUtil.folk(id)
	var roll := pick_index(id, now, text, 1000)
	var line := ""
	if f != null and float(roll) / 1000.0 < float(c.get("context_chance", 0.4)):
		line = ThoughtContext.line(f, st, day, roll)
	if line == "" and cat != "":
		line = _category_line(f, cat, st, day, now)
		if line == "":
			return ""
	if line == "":
		if cat == "" and day - int((st["used"] as Dictionary).get(text, -99)) < int(c.get("pass_lookback_days", 2)):
			return ""
		line = text
	record(st, line, day, now)
	if cat != "":
		(st["cats"] as Dictionary)[cat] = int((st["cats"] as Dictionary).get(cat, 0)) + 1
	return line

static func record(st: Dictionary, line: String, day: int, now: int) -> void:
	st["last"] = now
	st["count"] = int(st["count"]) + 1
	(st["used"] as Dictionary)[line] = day

## True if this folk may speak `line` now (not used within the lookback). event_frac scales the rate gap.
static func can_say(st: Dictionary, line: String, day: int, now: int, gap_frac: float) -> bool:
	var c: Dictionary = conf()
	if float(now - int(st["last"])) < _gap(c) * gap_frac or int(st["count"]) >= int(c.get("max_per_day", 16)):
		return false
	return day - int((st["used"] as Dictionary).get(line, -99)) >= int(c.get("lookback_days", 2))

## Vetted event / chat line for a folk (rate gap fraction + no-repeat), emitted if it passes. Returns true when shown.
static func say(fid: int, line: String, gap_frac: float) -> bool:
	if line == "":
		return false
	var now := SimEnv.now_min()
	var day := SysUtil.day()
	var st := _state(fid, now, day)
	if not can_say(st, line, day, now, gap_frac):
		return false
	record(st, line, day, now)
	emit_raw(fid, line)
	return true

static func _gap(c: Dictionary) -> float:
	var sp := int(SimEnv.clock().speed)
	var mult: Array = c.get("speed_gap_mult", [1, 1, 2, 3])
	return float(c.get("gap_min", 20)) * float(mult[clampi(sp, 0, mult.size() - 1)])

static func _state(id: int, now: int, day: int) -> Dictionary:
	var st: Dictionary = _st.get(id, {})
	if st.is_empty() or now < int(st["last"]) - 5000:
		st = {"last": -1000, "day": day, "count": 0, "cats": {}, "used": {}}
		_st[id] = st
	if int(st["day"]) != day:
		st["day"] = day
		st["count"] = 0
		st["cats"] = {}
		var used: Dictionary = st["used"]
		var keep := int(conf().get("lookback_days", 2)) + 1
		for k in used.keys():
			if day - int(used[k]) > keep:
				used.erase(k)
	return st

# ------------------------------------------------------------------ categories
static func category_of(text: String) -> String:
	var low := text.to_lower()
	var cats: Dictionary = cfg().get("categories", {})
	for cid in cats:
		for m in (cats[cid] as Dictionary).get("match", []):
			if low.find(str(m)) >= 0:
				return str(cid)
	return ""

static func _category_line(f, cat: String, st: Dictionary, day: int, now: int) -> String:
	var def: Dictionary = (cfg().get("categories", {}) as Dictionary).get(cat, {})
	if int((st["cats"] as Dictionary).get(cat, 0)) >= int(def.get("daily_cap", 3)):
		return ""
	var lines: Dictionary = def.get("lines", {})
	var pool: Array = (lines.get("any", []) as Array).duplicate()
	var tone := tone_of(f)
	if tone != "any":
		pool.append_array(lines.get(tone, []))
	return pick_fresh(pool, st, day, hash([now, cat, -1 if f == null else int(f.id)]))

## First line (starting at a hashed index) not used within the lookback; "" if all are fresh-less.
static func pick_fresh(pool: Array, st: Dictionary, day: int, h: int) -> String:
	if pool.is_empty():
		return ""
	var look := int(conf().get("lookback_days", 2))
	var used: Dictionary = st["used"]
	var start := absi(h) % pool.size()
	for i in pool.size():
		var line := str(pool[(start + i) % pool.size()])
		if day - int(used.get(line, -99)) >= look:
			return line
	return ""

## "cheerful" | "grumpy" | "anxious" | "any": mood first, then traits.
static func tone_of(f) -> String:
	if f == null:
		return "any"
	var c: Dictionary = cfg()
	var moods: Dictionary = c.get("tone_moods", {})
	for tone in moods:
		if (moods[tone] as Array).has(str(f.mood_name)):
			return str(tone)
	var tr: Dictionary = c.get("tone_traits", {})
	for tone in tr:
		for t in tr[tone]:
			if f.has_trait(str(t)):
				return str(tone)
	return "any"

## Deterministic 0..n-1 from (folk, minute, text): no rng stream involved.
static func pick_index(id: int, now: int, text: String, n: int) -> int:
	return absi(hash([id, now, text])) % maxi(1, n)

# ------------------------------------------------------------------ conversation
## Two folk start chatting: the actor opens on a topic, the other replies. Names the people and subjects from data/thought_voice.json.
static func chat(actor: int, other: int, topic: String) -> void:
	var topics: Dictionary = cfg().get("topics", {})
	if topics.is_empty():
		return
	var now := SimEnv.now_min()
	var key := topic
	var fr := 50.0
	if RelationshipService.knows(actor, other):
		fr = RelationshipService.value(actor, other, "friendship")
	else:
		fr = 0.0
	var extra := ThoughtContext.chat_override(actor, other, now)
	if extra != "":
		key = extra
	elif fr < 12.0 and pick_index(actor, now, "stranger", 100) < 60:
		key = "_stranger"
	if not topics.has(key):
		key = "_default"
	var third := ThoughtContext.third_party(actor, other, now)
	var vars := {"other": SysUtil.folk_name(third) if third >= 0 else "", "child": ThoughtContext.child_name(actor, other), "you": SysUtil.folk_name(other)}
	var lines := _fill_pool(topics[key], vars)
	if lines.is_empty():
		lines = _fill_pool(topics["_default"], vars)
	var day := SysUtil.day()
	for who in [actor, other]:
		var st := _state(int(who), now, day)
		var line := pick_fresh(lines, st, day, hash([now, who, key]))
		if line != "":
			say(int(who), line, float(conf().get("category_gap_frac", 0.5)))

static func _fill_pool(pool: Array, vars: Dictionary) -> Array:
	var out: Array = []
	for l in pool:
		var s := str(l)
		var ok := true
		for k in vars:
			if s.find("{%s}" % k) >= 0:
				if str(vars[k]) == "":
					ok = false
				else:
					s = s.replace("{%s}" % k, str(vars[k]))
		if ok and s.find("{") < 0:
			out.append(s)
	return out
