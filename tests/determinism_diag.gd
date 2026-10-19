extends RefCounted
## Dev tool (not a test, the runner skips it): finds WHERE two runs of the same seed diverge. Plays the hood game twice minute by minute,
## records every random stream's state, what each person chose and every interaction / game event, and prints the first one that differs.
## Typical causes found this way: a static counter / cache / once-only flag that no reset clears (Crowd._staff_seq, ContentRules._last_spoil_toast,
## SimDirector.ticks), content merged lazily in mid-game (justice careers).
## Output: the first minute where an OBJECT's state differs (the cause) and the first minute where a stream / choice differs (the symptom). Run with
## -Tail 100000 on tools/godot_guard.ps1: the guard prints only the last 40 log lines by default and the DIFF lines are before the PASS line.
##   run_one.gd -- determinism_diag      (docs/COOP.md "Finding a nondeterminism")
const HoodKit := preload("res://tests/hood_kit.gd")
const MINUTES := 4320      # 3 game days

func _sig() -> Array:
	var choices: Array = []
	var dir = HoodKit.root().get_node("SimDirector")
	for f in WorldIface.all_folk():
		var c = dir.last_choice.get(f.id, null)
		choices.append("%d:%s" % [f.id, str((c as Dictionary).get("interaction_id", "")) if c is Dictionary else "-"])
	_objs = _object_states()
	_tops = _top_choices()
	return [[SysUtil.rng.state, Autonomy.get_rng().state, Incidents.rng.state, Genetics.rng.state, Loot.get_rng().state], choices, Autonomy.path_queries]

var _ev: Array = []
var _objs: Dictionary = {}       # object id -> "def {state} {reservations}" of the minute just played
var _tops: Dictionary = {}       # folk id -> "time: best candidates with scores" of the folk's last decision

## Every object's state and slot reservations: the first object that differs is usually the root cause (a choice differs LATER, when a folk looks at it).
func _object_states() -> Dictionary:
	var out: Dictionary = {}
	var w = WorldIface.world()
	for oid in (w.objects as Dictionary):
		var o = w.objects[oid]
		out[int(oid)] = "%s %s %s" % [o.def_id, JSON.stringify(o.state, "", true), JSON.stringify(o.slots_reserved)]
	return out

func _top_choices() -> Dictionary:
	var out: Dictionary = {}
	for fid in Autonomy.last_debug:
		var dbg: Dictionary = Autonomy.last_debug[fid]
		var row: Array = []
		for r in dbg.get("top", []):
			row.append("%s@%s=%.4f" % [r.get("interaction", ""), str(r.get("target_id", "")), float(r.get("score", 0.0))])
		out[int(fid)] = "%s: %s" % [dbg.get("time", ""), ", ".join(row)]
	return out

func _on_start(fid, iid, tid) -> void:
	_ev.append("%d start %d %s %d" % [SimEnv.now_min(), fid, iid, tid])
func _on_fin(fid, iid, ok) -> void:
	_ev.append("%d fin %d %s %s" % [SimEnv.now_min(), fid, iid, str(ok)])
func _on_ge(n, p) -> void:
	_ev.append("%d ge %s %s" % [SimEnv.now_min(), n, JSON.stringify(p).left(80)])

func run() -> Array:
	var sigs: Array = [[], []]
	var evs: Array = [[], []]
	var objs: Array = [[], []]
	var tops: Array = [[], []]
	for i in 2:
		HoodKit.teardown()
		SimSeed.apply(555)
		HoodKit.new_game("classic", 555, 555)
		HoodKit.set_time(1, 7)
		Autonomy.path_queries = 0
		_ev = []
		var ev = SimEnv.events()
		ev.interaction_started.connect(_on_start)
		ev.interaction_finished.connect(_on_fin)
		ev.game_event.connect(_on_ge)
		for m in MINUTES:
			HoodKit.run(1)
			sigs[i].append(_sig())
			objs[i].append(_objs)
			tops[i].append(_tops)
		ev.interaction_started.disconnect(_on_start)
		ev.interaction_finished.disconnect(_on_fin)
		ev.game_event.disconnect(_on_ge)
		evs[i] = _ev
		HoodKit.teardown()
	for k in mini(evs[0].size(), evs[1].size()):
		if evs[0][k] != evs[1][k]:
			print('DIFF EVENT %d: A=%s | B=%s' % [k, evs[0][k], evs[1][k]])
			for j in range(maxi(k - 4, 0), k):
				print('DIFF   before: ', evs[0][j])
			for j in range(k, mini(k + 8, evs[0].size())):
				print('DIFF   A: ', evs[0][j])
				print('DIFF   B: ', evs[1][j])
			break
	for m in MINUTES:
		if objs[0][m] != objs[1][m]:
			print("DIFF first differing object state at minute %d after 07:00 (weather %s):" % [m, Weather.current()])
			var shown := 0
			for oid in objs[0][m]:
				if objs[0][m].get(oid, "") != objs[1][m].get(oid, "") and shown < 8:
					shown += 1
					print("DIFF   object %d A=%s | B=%s" % [oid, objs[0][m].get(oid, "-"), objs[1][m].get(oid, "-")])
			break
	for m in MINUTES:
		if sigs[0][m] != sigs[1][m]:
			print("DIFF first differing minute %d after 07:00" % m)
			for fid in tops[0][m]:
				if tops[0][m][fid] != tops[1][m].get(fid, ""):
					print("DIFF   decision of folk %d A=%s" % [fid, tops[0][m][fid]])
					print("DIFF   decision of folk %d B=%s" % [fid, tops[1][m].get(fid, "-")])
			print("DIFF A ", sigs[0][m])
			print("DIFF B ", sigs[1][m])
			if m > 0:
				print("DIFF prev ", sigs[0][m - 1])
			return []
	print("DIFF none in %d minutes" % MINUTES)
	return []
