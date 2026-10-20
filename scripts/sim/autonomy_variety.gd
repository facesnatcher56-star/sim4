class_name AutonomyVariety
extends RefCounted
## "Bored of it": a decaying count per Folk of how often they did each interaction (and each kind of object) recently. Autonomy
## multiplies a candidate's score by mult(): repeats get diminishing returns that recover over days. Needs-meeting interactions
## (sleep, eat, toilet, shower...) are exempt. Numbers in data/autonomy_variety.json. Not saved (it decays within days anyway).

static var mem: Dictionary = {}       # folk_id -> {key: [value, minute]}
static var today: Dictionary = {}     # folk_id -> [game day, {interaction id: times started that day}] (the daily cap, task 32c)

static func reset() -> void:
	mem.clear()
	today.clear()

## Times `fid` started `iid` today.
static func count_today(fid: int, iid: String) -> int:
	var e: Variant = today.get(fid, null)
	if e == null or int(e[0]) != SysUtil.day():
		return 0
	return int((e[1] as Dictionary).get(iid, 0))

static func cfg() -> Dictionary:
	return SysUtil.table("autonomy_variety")

static func _value(fid: int, key: String, now: int) -> float:
	var e: Variant = (mem.get(fid, {}) as Dictionary).get(key, null)
	if e == null:
		return 0.0
	var half: float = maxf(float(cfg().get("half_life_days", 1.0)), 0.05) * 1440.0
	return float(e[0]) * pow(0.5, float(now - int(e[1])) / half)

static var _ex_cfg: Dictionary = {}
static var _ex_memo: Dictionary = {}          # iid -> [def it was computed for, exempt?]: the table is static data, Autonomy asks this for every candidate kind of every decision

static func exempt(iid: String, d: Dictionary) -> bool:
	var c: Dictionary = cfg()
	if not is_same(c, _ex_cfg):
		_ex_cfg = c
		_ex_memo = {}
	var m: Variant = _ex_memo.get(iid, null)
	if m != null and is_same((m as Array)[0], d):
		return bool((m as Array)[1])
	var yes := (c.get("exempt_ids", []) as Array).has(iid)
	if not yes:
		for t in d.get("tags", []):
			if (c.get("exempt_tags", []) as Array).has(t):
				yes = true
				break
	_ex_memo[iid] = [d, yes]
	return yes

## Score multiplier in (min_mult, 1].
static func mult(folk, iid: String, d: Dictionary, obj) -> float:
	if mem.is_empty() or not mem.has(int(folk.id)) or exempt(iid, d):
		return 1.0
	var c: Dictionary = cfg()
	var cap: int = int(c.get("daily_cap", 0))
	if cap > 0 and count_today(int(folk.id), iid) >= cap:
		return 0.0                    # enough of this for one day: people move on to something else
	var now: int = SimEnv.now_min()
	var a_i: float = float(c.get("per_interaction", 0.35))
	if str(d.get("target", "object")) == "folk":
		a_i *= float(c.get("social_scale", 0.6))
	var m: float = 1.0 / (1.0 + a_i * _value(int(folk.id), "i:" + iid, now))
	if obj != null:
		m /= 1.0 + float(c.get("per_object_kind", 0.1)) * _value(int(folk.id), "o:" + str(obj.def_id), now)
	return maxf(m, float(c.get("min_mult", 0.12)))

static func _add(fid: int, key: String, now: int) -> float:
	var m: Dictionary = mem.get(fid, {})
	var v: float = _value(fid, key, now) + 1.0
	m[key] = [v, now]
	mem[fid] = m
	return v

## SystemsManager: interaction_started hook.
static func on_started(folk_id: int, iid: String, target_id: int) -> void:
	var d: Dictionary = SimEnv.data().interaction_def(iid)
	if d.is_empty() or exempt(iid, d):
		return
	var now: int = SimEnv.now_min()
	var e: Variant = today.get(folk_id, null)
	if e == null or int(e[0]) != SysUtil.day():
		e = [SysUtil.day(), {}]
		today[folk_id] = e
	(e[1] as Dictionary)[iid] = int((e[1] as Dictionary).get(iid, 0)) + 1
	var v: float = _add(folk_id, "i:" + iid, now)
	if str(d.get("target", "object")) == "object":
		var o = WorldIface.get_object(target_id)
		if o != null:
			_add(folk_id, "o:" + str(o.def_id), now)
	var fu: Dictionary = cfg().get("fed_up", {})
	if v >= float(fu.get("threshold", 5.0)) and SysUtil.chance(float(fu.get("chance", 0.35))):
		var f = SysUtil.folk(folk_id)
		if f != null and SysUtil.is_resident(f):
			f.add_buff(str(fu.get("buff", "fed_up")))
