class_name Habits
extends RefCounted
## Task 55: a daily habit from a flaw (creation.json effects.habit {need, item, cost_per_day}): the smoker. Packs of cigarettes are a real item
## (sold at the market, a stack in the Inventory). "Have a cigarette" uses one. Some waking hours without one bring the craving (a buff that
## lowers mood and focus) until the next. The cost is the packs bought.
##   Habits.on_hour()   Habits.self_entries(f)

const CRAVE_AFTER_HOURS := 5
const CRAVE_BUFF := "restless"
static var last: Dictionary = {}          # pid -> minute of the last cigarette

static func reset() -> void:
	last = {}

static func habit(pid: int) -> Dictionary:
	for e in Creation._effects(pid):
		if (e as Dictionary).has("habit"):
			return e["habit"]
	return {}

static func busy() -> bool:
	for pid in Creation.picks:
		if not habit(int(pid)).is_empty():
			return true
	return false

static func self_entries(f) -> Array:
	if f == null or habit(int(f.id)).is_empty():
		return []
	var item: String = str(habit(int(f.id)).get("item", "cigarettes"))
	if Inventory.count(int(f.id), item) <= 0:
		return []
	return [{"id": "habit_smoke", "label": "Have a cigarette", "category": "Myself", "enabled": true, "reason": "", "action": func(): use(f)}]

static func use(f) -> void:
	var fid: int = int(f.id)
	var item: String = str(habit(fid).get("item", "cigarettes"))
	if Inventory.take(fid, item).is_empty():
		return
	last[fid] = SysUtil.now()
	f.remove_buff(CRAVE_BUFF)
	f.add_to_stat("fun", 4.0)

static func on_hour(_hour: int = -1) -> void:
	for pid in Creation.picks.keys():
		var h: Dictionary = habit(int(pid))
		if h.is_empty():
			continue
		var f = SysUtil.folk(int(pid))
		if f == null or CrimePlace.is_asleep(f):
			continue
		if not last.has(int(pid)):
			last[int(pid)] = SysUtil.now()
		if SysUtil.now() - int(last[int(pid)]) >= CRAVE_AFTER_HOURS * 60:
			f.add_buff(CRAVE_BUFF)

static func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for k in last:
		out[str(k)] = last[k]
	return out

static func from_dict(d: Dictionary) -> void:
	last = {}
	for k in d:
		last[int(k)] = int(d[k])
