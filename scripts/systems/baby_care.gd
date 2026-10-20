class_name BabyCare
extends RefCounted
## Babies: needs only ADULTS (adult / elder) can satisfy through the injected interactions
## (feed_baby, change_diaper, rock_to_sleep, play_with_baby, hold_baby - see FamilyContent). Data: data/family.json "baby_care".
##  * every `check_every_min` game minutes each resident baby is evaluated:
##      - a need under `cry_below` makes the baby cry (buff `crying` on the baby, `baby_crying` on the household adults)
##      - a need under its `severe_below` counts as severe neglect; the neglect meter grows while neglected and shrinks
##        (recover_factor x faster) while the baby is cared for. `warn_hours` -> child-services warning,
##        `remove_hours` -> the baby is taken away (becomes an adoptable orphan townie).
##      - auto care: an adult of the household is sent to the baby (idle adults for mild needs, any interruptible adult
##        when the baby is crying) by queueing the matching interaction.
## Babies sleep in a crib (object `crib`, interaction `sleep_crib`) or are rocked to sleep.

static var state: Dictionary = {}     # baby_id -> {neglect: float minutes, warned: bool, crying: bool}
static var removed: Array = []        # [{day, baby_id, name, reason}]

const NEED_KEYS := ["hunger", "bladder", "hygiene", "energy", "fun", "social"]

static func reset() -> void:
	state.clear()
	removed.clear()

static func cfg() -> Dictionary:
	return SimEnv.data().get_table("family").get("baby_care", {})

static func on_birth(baby, fresh: bool = true) -> void:
	var c: Dictionary = cfg()
	state[int(baby.id)] = {"neglect": 0.0, "warned": false, "crying": false}
	if fresh:
		for n in NEED_KEYS:
			if baby.needs.has(n):
				(baby.needs[n] as Stat).set_value(float(c.get("start_need", 60)))

static func babies() -> Array:
	var out: Array = []
	for f in SysUtil.residents():
		if str(f.age_stage) == "baby":
			out.append(f)
	return out

static func neglect_minutes(baby_id: int) -> float:
	return float((state.get(baby_id, {}) as Dictionary).get("neglect", 0.0))

static func is_crying(baby_id: int) -> bool:
	return bool((state.get(baby_id, {}) as Dictionary).get("crying", false))

## Adults who can look after a baby: same household, adult/elder, home.
static func caregivers_for(baby) -> Array:
	var out: Array = []
	for f in SysUtil.residents():
		if int(f.household_id) != int(baby.household_id) or int(f.id) == int(baby.id):
			continue
		if not (str(f.age_stage) in ["adult", "elder"]) or SysUtil.is_away(f):
			continue
		out.append(f)
	return out

static func _need(f, n: String) -> float:
	return (f.needs[n] as Stat).value if f.needs.has(n) else 100.0

## {cry: bool, severe: bool, worst: need id, worst_value}
static func severity(baby) -> Dictionary:
	var c: Dictionary = cfg()
	var cry_below: float = float(c.get("cry_below", -45))
	var sev: Dictionary = c.get("severe_below", {})
	var cry: bool = false
	var severe: bool = false
	var worst: String = ""
	var wv: float = 1000.0
	for n in NEED_KEYS:
		var v: float = _need(baby, n)
		if v < wv:
			wv = v
			worst = n
		if v < cry_below:
			cry = true
		if sev.has(n) and v < float(sev[n]):
			severe = true
	return {"cry": cry, "severe": severe, "worst": worst, "worst_value": wv}

## Toddlers and young children (they walk and eat on their own, but a parent still has to step in; no crying / removal here, that is
## ChaosNeglect's job and this keeps it from ever starting).
static func kids() -> Array:
	var out: Array = []
	var stages: Array = cfg().get("kid_care", {}).get("stages", [])
	for f in SysUtil.residents():
		if str(f.age_stage) in stages:
			out.append(f)
	return out

static func _is_kid(f) -> bool:
	return str(f.age_stage) != "baby"

static func _sleeping(f) -> bool:
	return f.current != null and str(f.current.def_id).begins_with("sleep")

## Ordered wishes [{iid, need, gap}] - most pressing first.
static func wanted_care(baby) -> Array:
	var kc: Dictionary = cfg().get("kid_care", {})
	var kid: bool = _is_kid(baby)
	var teen: bool = str(baby.age_stage) == "teen"          # a teen feeds themselves; an adult at home steps in only when it has gone too far
	var below: Dictionary = (kc.get("teen_below", {}) if teen else kc.get("below", {})) if kid else cfg().get("care_below", {})
	var out: Array = []
	var map: Dictionary = {"hunger": "feed_baby", "bladder": "change_diaper", "hygiene": "change_diaper", "energy": "rock_to_sleep",
		"fun": "play_with_baby", "social": "hold_baby"}
	for n in map:
		if kid and str(baby.age_stage) == "child" and not (kc.get("child_needs", []) as Array).has(n):
			continue
		if teen and not (kc.get("teen_needs", []) as Array).has(n):
			continue
		if kid and n == "energy" and _sleeping(baby):
			continue
		var v: float = _need(baby, n)
		var th: float = float(below.get(n, -30))
		if v < th:
			out.append({"iid": map[n], "need": n, "gap": th - v})
	out.sort_custom(func(a, b): return float(a["gap"]) > float(b["gap"]))
	return out

static func _is_care(iid: String) -> bool:
	return iid in ["feed_baby", "change_diaper", "rock_to_sleep", "play_with_baby", "hold_baby"]

static func care_pending(baby_id: int) -> bool:
	for f in SysUtil.residents():
		if f.current != null and _is_care(str(f.current.def_id)) and int(f.current.target_id) == baby_id:
			return true
		for q in f.queue:
			if _is_care(str((q as Interaction).def_id)) and int((q as Interaction).target_id) == baby_id:
				if _stale(f, q as Interaction):
					return false          # queued but never started: let another adult take it
				return true
	return false

## A care job that has sat in somebody's queue for a while behind something else.
static func _stale(f, ir: Interaction) -> bool:
	if f.current == null or _is_care(str(f.current.def_id)):
		return false
	var born: int = int(ir.get_meta("queued_at", SysUtil.now()))
	if not ir.has_meta("queued_at"):
		ir.set_meta("queued_at", born)
	return SysUtil.now() - born >= int(cfg().get("stale_after_min", 20))

## Queue the next needed care on a suitable adult. Returns the caregiver id or -1.
static func assign_care(baby) -> int:
	if care_pending(int(baby.id)):
		return -1
	var wants: Array = wanted_care(baby)
	if wants.is_empty():
		return -1
	var urgent: bool = is_crying(int(baby.id)) or str((wants[0] as Dictionary)["need"]) == "hunger"      # a hungry baby comes before the adults' own needs, asleep or not
	if _is_kid(baby):
		urgent = (cfg().get("kid_care", {}).get("urgent_needs", []) as Array).has(str((wants[0] as Dictionary)["need"]))    # real care beats the adults' whims
	var cands: Array = caregivers_for(baby)
	cands.sort_custom(func(a, b):
		var ba: int = 0 if (a.current == null and a.queue.is_empty()) else 1
		var bb: int = 0 if (b.current == null and b.queue.is_empty()) else 1
		if ba != bb:
			return ba < bb
		var da: int = absi(a.tile.x - baby.tile.x) + absi(a.tile.y - baby.tile.y)
		var db: int = absi(b.tile.x - baby.tile.x) + absi(b.tile.y - baby.tile.y)
		if da != db:
			return da < db
		return int(a.id) < int(b.id))
	for c in cands:
		var busy: bool = c.current != null or not c.queue.is_empty()
		if busy:
			if not urgent:
				continue
			if c.current != null and (not c.current.is_interruptible() or c.current.effective_priority() >= Interaction.PRIORITY["urgent"]):
				continue
		for w in wants:
			var ir := Interaction.create(str(w["iid"]), c, int(baby.id), false)
			if ir != null and ir.can_run(c):
				c.enqueue(ir)
				return int(c.id)
	return -1

## Advance baby evaluation by `step` game minutes (called by on_minute every check_every_min).
static func evaluate(step: float) -> void:
	var c: Dictionary = cfg()
	for baby in babies():
		var bid: int = int(baby.id)
		if not state.has(bid):
			state[bid] = {"neglect": 0.0, "warned": false, "crying": false}
		var s: Dictionary = state[bid]
		var sev: Dictionary = severity(baby)
		_set_crying(baby, s, bool(sev["cry"]))
		if bool(sev["severe"]):
			s["neglect"] = float(s["neglect"]) + step
		else:
			s["neglect"] = maxf(0.0, float(s["neglect"]) - step * float(c.get("recover_factor", 2.0)))
			if float(s["neglect"]) < float(c.get("warn_hours", 6)) * 30.0:
				s["warned"] = false
		if float(s["neglect"]) >= float(c.get("warn_hours", 6)) * 60.0 and not bool(s["warned"]):
			s["warned"] = true
			SysUtil.notify("Child services has noticed that %s is not being cared for. Look after the baby soon!" % baby.name, "warn")
			SysUtil.game_event("child_services_warning", {"folk_id": bid})
		if float(s["neglect"]) >= float(c.get("remove_hours", 12)) * 60.0:
			remove_baby(baby, "neglect")
			continue
		if bool(c.get("auto_care", true)):
			assign_care(baby)
	if bool(c.get("auto_care", true)):
		for kid in kids():
			assign_care(kid)

static func _set_crying(baby, s: Dictionary, on: bool) -> void:
	var c: Dictionary = cfg()
	var cb: String = str(c.get("cry_buff", "crying"))
	if on:
		if not baby.has_buff(cb):
			baby.add_buff(cb)
		var hb: String = str(c.get("household_buff", "baby_crying"))
		for a in caregivers_for(baby):
			a.add_buff(hb)
	elif baby.has_buff(cb):
		baby.remove_buff(cb)
	s["crying"] = on

## Child services takes the baby away. It becomes an orphan townie (adoptable again).
static func remove_baby(baby, reason: String = "neglect") -> void:
	var bid: int = int(baby.id)
	var nm: String = str(baby.name)
	var grievers: Array = []
	for r in SysUtil.residents():
		if int(r.household_id) == int(baby.household_id) and int(r.id) != bid and str(r.age_stage) in ["adult", "elder"]:
			grievers.append(r)
	baby.remove_buff(str(cfg().get("cry_buff", "crying")))
	if FamilyHousehold.move_out(bid, 0.0, true):
		removed.append({"day": SysUtil.day(), "baby_id": bid, "name": nm, "reason": reason})
		for a in grievers:
			a.add_buff("grieving")
			a.add_to_stat("fun", -20.0)
		SysUtil.notify("Child services has taken %s away because of neglect." % nm, "bad")
		SysUtil.game_event("child_removed", {"folk_id": bid, "reason": reason})

## Called when a folk's life stage changed.
static func on_aged_up(folk_id: int, from_stage: String, to_stage: String) -> void:
	var f = SysUtil.folk(folk_id)
	if f == null:
		return
	if to_stage != "baby":
		state.erase(folk_id)
		f.remove_buff(str(cfg().get("cry_buff", "crying")))
	if from_stage == "toddler" and to_stage == "child":
		var lv: Dictionary = Family.toddler_skill_levels(folk_id)
		var all_ok: bool = not lv.is_empty()
		for k in lv:
			if int(lv[k]) < 1:
				all_ok = false
		if all_ok:
			var pb: String = str(SimEnv.data().get_table("family").get("toddler", {}).get("proud_buff", "proud_parent"))
			for p in FamilyTree.parents_of(folk_id):
				var pf = SysUtil.folk(int(p))
				if pf != null:
					pf.add_buff(pb)
			SysUtil.notify("%s learned to walk, talk and use the potty - proud parents!" % f.name, "birthday")

# ------------------------------------------------------------------ clock
static func on_minute() -> void:
	var every: int = maxi(int(cfg().get("check_every_min", 10)), 1)
	if SysUtil.now() % every == 0:
		evaluate(float(every))

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"state": SysUtil.str_keys(state).duplicate(true), "removed": removed.duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	reset()
	state = SysUtil.int_keys((d.get("state", {}) as Dictionary).duplicate(true))
	for k in state:
		state[k]["neglect"] = float(state[k]["neglect"])
	removed = (d.get("removed", []) as Array).duplicate(true)
	for r in removed:
		r["day"] = int(r["day"])
		r["baby_id"] = int(r["baby_id"])
