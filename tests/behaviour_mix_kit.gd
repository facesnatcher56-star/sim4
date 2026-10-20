extends RefCounted
## Helper for the behaviour tests (no run()): tallies, per folk and per game day, which interactions started and how many awake minutes
## were spent with nothing to do. Needs interactions (AutonomyVariety.exempt: sleep, toilet, meals, hygiene, work) are listed apart.

var days: Dictionary = {}         # "folk_id:day" -> {iid: count}
var idle_min: Dictionary = {}     # folk_id -> awake minutes with no interaction
var awake_min: Dictionary = {}    # folk_id -> awake minutes
var idle_hours: Dictionary = {}   # folk_id -> {hour: idle minutes}
var recent: Dictionary = {}       # folk_id -> last 14 starts as "day hh:mm iid"
var _folk: Array = []

func watch(folk: Array) -> void:
	_folk = folk
	SimEnv.events().interaction_started.connect(_on_started)
	if not SimEnv.events().interaction_started.is_connected(AutonomyVariety.on_started):
		SimEnv.events().interaction_started.connect(AutonomyVariety.on_started)      # the game wires this in SystemsManager; a stub world has none

func unwatch() -> void:
	var ev = SimEnv.events()
	if ev.interaction_started.is_connected(_on_started):
		ev.interaction_started.disconnect(_on_started)
	if ev.interaction_started.is_connected(AutonomyVariety.on_started):
		ev.interaction_started.disconnect(AutonomyVariety.on_started)

func _on_started(folk_id: int, iid: String, _target: int) -> void:
	var rl: Array = recent.get(folk_id, [])
	rl.append("d%d %02d:%02d %s" % [SysUtil.day(), int(SysUtil.hour_f()), int(fposmod(SysUtil.hour_f(), 1.0) * 60.0), iid])
	if rl.size() > 14:
		rl.pop_front()
	recent[folk_id] = rl
	var k := "%d:%d" % [folk_id, SysUtil.day()]
	var m: Dictionary = days.get(k, {})
	m[iid] = int(m.get(iid, 0)) + 1
	days[k] = m

## Call once per game minute, after the sim tick.
func sample() -> void:
	for f in _folk:
		var id := int(f.id)
		var asleep: bool = f.current != null and (f.current.def_id.contains("sleep") or f.current.def_id.contains("nap"))
		if asleep:
			continue
		awake_min[id] = int(awake_min.get(id, 0)) + 1
		if f.current == null and f.queue.is_empty():
			idle_min[id] = int(idle_min.get(id, 0)) + 1
			var ih: Dictionary = idle_hours.get(id, {})
			var hh := int(SysUtil.hour_f())
			ih[hh] = int(ih.get(hh, 0)) + 1
			idle_hours[id] = ih

static func is_need(iid: String) -> bool:
	return AutonomyVariety.exempt(iid, SimEnv.data().interaction_def(iid))

## {"distinct": n, "worst_repeat": n, "worst_iid": s} for the non-need interactions of one folk-day.
func day_summary(folk_id: int, day: int) -> Dictionary:
	var m: Dictionary = days.get("%d:%d" % [folk_id, day], {})
	var distinct := 0
	var worst := 0
	var worst_iid := ""
	for iid in m:
		var autonomous: bool = bool(SimEnv.data().interaction_def(str(iid)).get("autonomous", true))
		if not autonomous:
			continue                      # walks, queued reactions and calls are not picks of autonomy
		distinct += 1
		if not is_need(str(iid)) and int(m[iid]) > worst:
			worst = int(m[iid])
			worst_iid = str(iid)
	return {"distinct": distinct, "worst_repeat": worst, "worst_iid": worst_iid, "all": m}

func idle_share(folk_id: int) -> float:
	return float(idle_min.get(folk_id, 0)) / maxf(float(awake_min.get(folk_id, 0)), 1.0)
