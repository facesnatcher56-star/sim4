extends RefCounted
## Dev tool (not a test, the runner skips it): finds WHERE two runs of the same seed diverge. Plays the hood game twice minute by minute,
## records every random stream's state, what each person chose and every interaction / game event, and prints the first one that differs.
## Typical causes found this way: a static counter / cache / once-only flag that no reset clears (Crowd._staff_seq, ContentRules._last_spoil_toast,
## SimDirector.ticks), content merged lazily in mid-game (justice careers).
##   run_one.gd -- determinism_diag
const HoodKit := preload("res://tests/hood_kit.gd")
const MINUTES := 4320      # 3 game days

func _sig() -> Array:
	var choices: Array = []
	var dir = HoodKit.root().get_node("SimDirector")
	for f in WorldIface.all_folk():
		var c = dir.last_choice.get(f.id, null)
		choices.append("%d:%s" % [f.id, str((c as Dictionary).get("interaction_id", "")) if c is Dictionary else "-"])
	return [[SysUtil.rng.state, Autonomy.get_rng().state, Incidents.rng.state, Genetics.rng.state, Loot.get_rng().state], choices, Autonomy.path_queries]

var _ev: Array = []
func _on_start(fid, iid, tid) -> void:
	_ev.append("%d start %d %s %d" % [SimEnv.now_min(), fid, iid, tid])
func _on_fin(fid, iid, ok) -> void:
	_ev.append("%d fin %d %s %s" % [SimEnv.now_min(), fid, iid, str(ok)])
func _on_ge(n, p) -> void:
	_ev.append("%d ge %s %s" % [SimEnv.now_min(), n, JSON.stringify(p).left(80)])

func run() -> Array:
	var sigs: Array = [[], []]
	var evs: Array = [[], []]
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
		if sigs[0][m] != sigs[1][m]:
			print("DIFF first differing minute %d after 07:00" % m)
			print("DIFF A ", sigs[0][m])
			print("DIFF B ", sigs[1][m])
			if m > 0:
				print("DIFF prev ", sigs[0][m - 1])
			return []
	print("DIFF none in %d minutes" % MINUTES)
	return []
