class_name Folk
extends RefCounted
## A simulated character. Pure logic, no visuals.

const SKILLS: Array[String] = ["cooking", "fitness", "logic", "charisma", "handiness", "painting"]
const MAX_SKILL_LEVEL := 10
const XP_TAPER_FROM := 3          # from this level on every further level takes longer: mastering 10 is rare
const XP_TAPER_STEP := 0.45
const MEMORY_HALF_LIFE_MIN := 1.5 * 1440.0
const MEMORY_MAX_ENTRIES := 80
const MEMORY_BIAS_LIMIT := 0.5
const NEED_EMIT_STEP := 0.5

static var _next_id: int = 1

## Test / new-game helper: start handing out ids from 1 again.
static func reset_ids() -> void:
	_next_id = 1

var id: int = 0
var name: String = ""
var age_stage: String = "adult"
var sex: String = ""            # "female" | "male" (Sexes). "" = not decided yet: Sexes.of() fills it in from the name / id
var traits: Array[String] = []
var needs: Dictionary = {}      # String -> Stat
var skills: Dictionary = {}     # String -> {"xp": float, "level": int}
var buffs: Array = []           # [{"id": String, "remaining": float (minutes, -1 = until removed)}]
var tile: Vector2i = Vector2i.ZERO
var level: int = 0              # floor of the building the folk is on (0 = ground, negative = basement); tile + level = position
var queue: Array = []           # Array of Interaction, highest effective priority first
var current: Interaction = null
var household_id: int = 0
## Look (see the APPEARANCE CONTRACT at the top of scripts/systems/genetics.gd). {} = not generated yet.
var appearance: Dictionary = {}
var posture: String = "stand"   # stand | sit | lie  (set by the running interaction; UI reads it)
var work_start: float = -1.0    # hour of day the job starts, -1 = no job (careers system sets these)
var work_end: float = -1.0
var memory: Array = []          # [{"key": String, "value": float, "t": int}]
var relationships: Dictionary = {}   # other_id -> {track -> float}
var routine_log: Dictionary = {}     # "routine:day:interaction" -> true
var history: Array = []         # last finished interaction ids (newest last)
var history_counts: Dictionary = {}  # interaction id -> times finished successfully
var cooldowns: Dictionary = {}   # interaction id -> game minute until which autonomy skips it
var idle_until_min: int = 0     # autonomy cooldown when nothing was available
var last_thought_min: int = -1000
var mood_name: String = "neutral"
var mood_intensity: int = 0
var _last_emit: Dictionary = {}

func _init(p_name: String = "", p_id: int = -1) -> void:
	if p_id < 0:
		id = _next_id
		_next_id += 1
	else:
		id = p_id
		_next_id = maxi(_next_id, p_id + 1)
	name = p_name
	for s in SKILLS:
		skills[s] = {"xp": 0.0, "level": 0}
	setup_needs()

## Convenience factory.
static func create(p_name: String, p_traits: Array = [], p_id: int = -1, p_sex: String = "") -> Folk:
	var f := Folk.new(p_name, p_id)
	for t in p_traits:
		f.traits.append(str(t))
	f.sex = p_sex if Sexes.valid(p_sex) else Sexes.guess(p_name, f.id)
	f.appearance = Genetics.random_appearance(null, f.sex)
	return f

func setup_needs() -> void:
	needs.clear()
	var defs: Dictionary = SimEnv.data().needs()
	for nid in defs:
		var s := Stat.from_def(str(nid), defs[nid])
		needs[nid] = s
		_last_emit[nid] = s.value

# ---------- traits ----------
func has_trait(t: String) -> bool:
	return traits.has(t)

var _td_hash: int = 0
var _td_cache: Array = []
var _td_data = null

## Definitions of this folk's traits. Memoised (autonomy asks hundreds of times per decision): rebuilt when the trait list
## or the data tables change.
func trait_defs() -> Array:
	var data = SimEnv.data()
	var h := traits.hash()
	if h == _td_hash and is_same(data, _td_data):
		return _td_cache
	var out: Array = []
	for t in traits:
		var d: Dictionary = data.trait_def(t)
		if not d.is_empty():
			out.append(d)
	_td_hash = h
	_td_data = data
	_td_cache = out
	return out

# ---------- stats ----------
func get_stat_value(stat_name: String) -> float:
	if needs.has(stat_name):
		return (needs[stat_name] as Stat).value
	if skills.has(stat_name):
		return float(skills[stat_name]["level"])
	return 0.0

func add_to_stat(stat_name: String, delta: float) -> void:
	if needs.has(stat_name):
		(needs[stat_name] as Stat).add(delta)
		_emit_need(stat_name)

func _emit_need(nid: String, force: bool = false) -> void:
	var v: float = (needs[nid] as Stat).value
	if force or absf(v - float(_last_emit.get(nid, v + 100.0))) >= NEED_EMIT_STEP:
		_last_emit[nid] = v
		SimEnv.emit("need_changed", id, nid, v)

## Product of trait + buff + running-interaction decay multipliers for a need.
func decay_mult(need: String) -> float:
	return _decay_mult(need, _decay_maps(), Scenario.need_drain() if household_id > 0 else 1.0)

## The per-need decay multiplier tables of the traits and buffs (looked up once per tick, not once per need).
func _decay_maps() -> Array:
	var maps: Array = []
	for td in trait_defs():
		maps.append(td.get("need_decay_mult", {}))
	for b in buffs:
		maps.append(SimEnv.data().buff_def(str(b["id"])).get("need_decay_mult", {}))
	return maps

func _decay_mult(need: String, maps: Array, drain: float) -> float:
	var m := 1.0
	for mp in maps:
		m *= float((mp as Dictionary).get(need, 1.0))
	if current != null and current.state == "running":
		m *= current.decay_mult_for(need)
	if household_id > 0:
		m *= drain      # new-game difficulty (1.0 on Normal), household members only
	return m

func tick_needs(minutes: float) -> void:
	var maps := _decay_maps()
	var drain: float = Scenario.need_drain() if household_id > 0 else 1.0
	for nid in needs:
		var s: Stat = needs[nid]
		if s.decay_per_min != 0.0:
			s.tick(minutes, _decay_mult(nid, maps, drain))
		_emit_need(nid)

# ---------- buffs ----------
func has_buff(buff_id: String) -> bool:
	for b in buffs:
		if b["id"] == buff_id:
			return true
	return false

## `caused` = the buff came from something the folk did (an interaction outcome), so a bad one is remembered.
func add_buff(buff_id: String, caused: bool = false, _from_trait: bool = false) -> bool:
	var def: Dictionary = SimEnv.data().buff_def(buff_id)
	if def.is_empty():
		push_warning("Folk.add_buff: unknown buff '%s'" % buff_id)
		return false
	var dur: float = float(def.get("duration_min", 0.0))
	var remaining: float = dur if dur > 0.0 else -1.0
	for b in buffs:
		if b["id"] == buff_id:
			if remaining > 0.0:
				b["remaining"] = maxf(float(b["remaining"]), remaining)
			return false
	buffs.append({"id": buff_id, "remaining": remaining})
	SimEnv.emit("buff_added", id, buff_id)
	var th: String = str(def.get("thought", ""))
	var now := SimEnv.now_min()
	if th != "" and now - last_thought_min >= 20:
		last_thought_min = now
		SimEnv.emit("thought", id, th)
	if caused and current != null and Mood.buff_valence(buff_id) < 0.0:
		current.note_bad_outcome(0.15)
	if not _from_trait:
		for td in trait_defs():
			var mapped: Variant = (td.get("buffs_on", {}) as Dictionary).get(buff_id, null)
			if mapped != null:
				add_buff(str(mapped), false, true)
	refresh_mood()
	return true

func remove_buff(buff_id: String) -> bool:
	for i in buffs.size():
		if buffs[i]["id"] == buff_id:
			buffs.remove_at(i)
			SimEnv.emit("buff_removed", id, buff_id)
			refresh_mood()
			return true
	return false

func tick_buffs(minutes: float) -> void:
	var expired: Array = []
	for b in buffs:
		if float(b["remaining"]) >= 0.0:
			b["remaining"] = float(b["remaining"]) - minutes
			if float(b["remaining"]) <= 0.0:
				expired.append(b["id"])
	for e in expired:
		remove_buff(str(e))

## Fire / clear need-threshold buffs ("while-condition" buffs).
func update_thresholds() -> void:
	for nid in needs:
		var s: Stat = needs[nid]
		var active := s.active_threshold_buffs()
		for bid in s.all_threshold_buffs():
			if active.has(bid):
				add_buff(str(bid), false)
			elif has_buff(str(bid)):
				remove_buff(str(bid))

func buff_ids() -> Array:
	var out: Array = []
	for b in buffs:
		out.append(b["id"])
	return out

# ---------- mood ----------
func get_mood() -> Dictionary:
	return Mood.compute(self)

func refresh_mood() -> void:
	var m := Mood.compute(self)
	if m["mood"] != mood_name or int(m["intensity"]) != mood_intensity:
		mood_name = str(m["mood"])
		mood_intensity = int(m["intensity"])
		SimEnv.emit("mood_changed", id, mood_name, mood_intensity)

# ---------- skills ----------
static func xp_for_level(level: int) -> float:
	return 50.0 * level * (level + 1)

func skill_level(skill: String) -> int:
	if skills.has(skill):
		return int(skills[skill]["level"])
	return 0

func add_skill_xp(skill: String, xp: float) -> void:
	if not skills.has(skill):
		skills[skill] = {"xp": 0.0, "level": 0}
	var sk: Dictionary = skills[skill]
	if xp > 0.0:
		xp /= 1.0 + XP_TAPER_STEP * maxf(float(sk["level"]) - XP_TAPER_FROM, 0.0)
	sk["xp"] = float(sk["xp"]) + xp
	var lvl := int(sk["level"])
	while lvl < MAX_SKILL_LEVEL and float(sk["xp"]) >= xp_for_level(lvl + 1):
		lvl += 1
	if lvl != int(sk["level"]):
		sk["level"] = lvl
		SimEnv.emit("skill_changed", id, skill, lvl)

# ---------- jobs ----------
func has_job() -> bool:
	return work_start >= 0.0

# ---------- relationships ----------
func get_rel(other_id: int, track: String) -> float:
	return float((relationships.get(other_id, {}) as Dictionary).get(track, 0.0))

func add_rel(other_id: int, track: String, delta: float) -> void:
	if track == "romance" and delta > 0.0 and not RomanceRules.allowed(id, other_id):    # minors and family never gain romance
		return
	if not relationships.has(other_id):
		relationships[other_id] = {}
	var r: Dictionary = relationships[other_id]
	r[track] = clampf(float(r.get(track, 0.0)) + delta, -100.0, 100.0)
	SimEnv.emit("relationship_changed", id, other_id, track)

# ---------- memory ----------
## Record an outcome for a key such as "obj:12" or "folk:3". value in about -1..1.
func remember(key: String, value: float) -> void:
	memory.append({"key": key, "value": value, "t": SimEnv.now_min()})
	if memory.size() > MEMORY_MAX_ENTRIES:
		memory = memory.slice(memory.size() - MEMORY_MAX_ENTRIES)

## Decayed sum of remembered outcomes for a key, clamped to [-0.5, 0.5].
func memory_bias(key: String) -> float:
	var now := SimEnv.now_min()
	var total := 0.0
	for m in memory:
		if m["key"] == key:
			var age := float(now - int(m["t"]))
			total += float(m["value"]) * pow(0.5, maxf(age, 0.0) / MEMORY_HALF_LIFE_MIN)
	return clampf(total, -MEMORY_BIAS_LIMIT, MEMORY_BIAS_LIMIT)

## memory_bias() of every key at once (one pass over the memory): key -> unclamped sum. clampf(sum, -MEMORY_BIAS_LIMIT, MEMORY_BIAS_LIMIT)
## is exactly memory_bias(key); keys that are not in the map have no bias.
func memory_bias_map() -> Dictionary:
	var now := SimEnv.now_min()
	var sums: Dictionary = {}
	for m in memory:
		var age := float(now - int(m["t"]))
		sums[m["key"]] = float(sums.get(m["key"], 0.0)) + float(m["value"]) * pow(0.5, maxf(age, 0.0) / MEMORY_HALF_LIFE_MIN)
	return sums

func prune_memory() -> void:
	var now := SimEnv.now_min()
	var keep: Array = []
	for m in memory:
		var age := float(now - int(m["t"]))
		if absf(float(m["value"])) * pow(0.5, age / MEMORY_HALF_LIFE_MIN) > 0.01:
			keep.append(m)
	memory = keep

# ---------- interaction queue ----------
## Add an interaction. Higher effective priority (player commands win) preempts the current one.
func enqueue(inter: Interaction) -> void:
	if not Pawn.allows(self, inter):          # one-character play: the pawn only does what the player ordered or what the body / world forces
		return
	var eff := inter.effective_priority()
	if current != null and eff > current.effective_priority() and current.is_interruptible():
		current.cancel("preempted")
	var idx := queue.size()
	for i in queue.size():
		if (queue[i] as Interaction).effective_priority() < eff:
			idx = i
			break
	queue.insert(idx, inter)
	SimEnv.emit("queue_changed", id)

func clear_queue() -> void:
	queue.clear()
	SimEnv.emit("queue_changed", id)

func cancel_current(reason: String = "cancelled") -> void:
	if current != null:
		current.cancel(reason)

func on_cooldown(def_id: String) -> bool:
	return SimEnv.now_min() < int(cooldowns.get(def_id, -1))

func is_idle() -> bool:
	return current == null and queue.is_empty()

# ---------- save / load ----------
func to_dict() -> Dictionary:
	var nd: Dictionary = {}
	for nid in needs:
		nd[nid] = (needs[nid] as Stat).value
	var bl: Array = []
	for b in buffs:
		bl.append({"id": b["id"], "remaining": b["remaining"]})
	var rel: Dictionary = {}
	for k in relationships:
		rel[str(k)] = relationships[k].duplicate()
	return {
		"id": id, "name": name, "sex": sex, "age_stage": age_stage, "traits": traits.duplicate(),
		"needs": nd, "skills": skills.duplicate(true), "buffs": bl,
		"tile": [tile.x, tile.y], "level": level, "household_id": household_id,
		"work_start": work_start, "work_end": work_end,
		"memory": memory.duplicate(true), "relationships": rel,
		"history_counts": history_counts.duplicate(),
		"appearance": appearance.duplicate(true),
	}

static func from_dict(d: Dictionary) -> Folk:
	var f := Folk.new(str(d.get("name", "")), int(d.get("id", -1)))
	f.age_stage = str(d.get("age_stage", "adult"))
	f.sex = str(d.get("sex", ""))
	if not Sexes.valid(f.sex):
		f.sex = Sexes.guess(f.name, f.id)           # saves from before two sexes
	for t in d.get("traits", []):
		f.traits.append(str(t))
	var nd: Dictionary = d.get("needs", {})
	for nid in nd:
		if f.needs.has(nid):
			(f.needs[nid] as Stat).set_value(float(nd[nid]))
			f._last_emit[nid] = (f.needs[nid] as Stat).value
	var sk: Dictionary = d.get("skills", {})
	for s in sk:
		f.skills[s] = {"xp": float(sk[s].get("xp", 0.0)), "level": int(sk[s].get("level", 0))}
	for b in d.get("buffs", []):
		f.buffs.append({"id": str(b["id"]), "remaining": float(b.get("remaining", -1.0))})
	var tl: Array = d.get("tile", [0, 0])
	f.tile = Vector2i(int(tl[0]), int(tl[1]))
	f.level = int(d.get("level", 0))
	f.household_id = int(d.get("household_id", 0))
	f.work_start = float(d.get("work_start", -1.0))
	f.work_end = float(d.get("work_end", -1.0))
	f.memory = (d.get("memory", []) as Array).duplicate(true)
	var rel: Dictionary = d.get("relationships", {})
	for k in rel:
		f.relationships[int(k)] = (rel[k] as Dictionary).duplicate()
	f.history_counts = (d.get("history_counts", {}) as Dictionary).duplicate()
	f.appearance = Genetics.normalize(d.get("appearance", {}))
	f.refresh_mood()
	return f
