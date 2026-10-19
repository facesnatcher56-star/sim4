extends SceneTree
## Not a unit test: boots the real game, runs N game days and prints how the week reads (the reviewer's 7-day story log, measurable).
## godot --headless --path . --script res://tests/story_log_probe.gd -- days [seed]
## Prints: toast counts by kind, chronicle counts by kind, relationship toasts about strangers, duplicate first names, top repeated
## activities per household folk, spoilage toasts, mood shares per folk, coins trend, lowest needs, forecasts vs events, story beats.
var _main: Node = null
var _frames := 0
var _days := 7
var _nojobs := false
var _toasts: Array = []        # [day, text, kind]
var _chron: Dictionary = {}
var _acts: Dictionary = {}     # "folk|interaction" -> count
var _moods: Dictionary = {}    # folk name -> {mood: samples}
var _low: Dictionary = {}      # folk name -> {need: min}
var _events: Dictionary = {}
var _karaoke: Dictionary = {}
var _buffs: Dictionary = {}    # buff id -> samples (household folk)
var _coins: Array = []

func _process(_d: float) -> bool:
	var args := OS.get_cmdline_user_args()
	if _main == null:
		if args.size() > 0: _days = int(args[0])
		if args.size() > 1 and args[1] == "nojobs": _nojobs = true
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 5:
		_main.start_new_game(_main.default_household())
		var ev = root.get_node("Events")
		ev.notification.connect(func(t, k): _toasts.append([int(root.get_node("Clock").day()), str(t), str(k)]))
		ev.game_event.connect(_on_event)
		ev.interaction_started.connect(_on_act)
	if _frames == 30:
		var clock = root.get_node("Clock")
		var t0 := Time.get_ticks_msec()
		if _nojobs:
			Careers.settings()["offer_chance_per_day"] = 0.0
		if _nojobs:
			Careers.settings()["offer_chance_per_day"] = 0.0
		_coins.append(Economy.balance(1))
		for m in range(_days * 1440):
			clock.advance_minutes(1)
			if m % 30 == 0:
				_sample()
			if m % 1440 == 1439:
				_coins.append(Economy.balance(1))
		print("simulated %d days in %d ms" % [_days, Time.get_ticks_msec() - t0])
		_report()
		quit(0)
	return false

func _on_event(ev: String, p: Dictionary) -> void:
	if ev == "chronicle":
		var k: String = str(p.get("kind", "?"))
		_chron[k] = int(_chron.get(k, 0)) + 1
	_events[ev] = int(_events.get(ev, 0)) + 1
	if ev == "karaoke_done":
		var kf = SysUtil.folk(int(p.get("folk_id", -1)))
		var kk: String = "%s (hh %d)" % [kf.name if kf != null else "?", int(kf.household_id) if kf != null else -9]
		_karaoke[kk] = int(_karaoke.get(kk, 0)) + 1

func _on_act(fid: int, iid: String, _t: int) -> void:
	var f = SysUtil.folk(fid)
	if f == null or int(f.household_id) != 1:
		return
	var k := "%s|%s" % [f.name, iid]
	_acts[k] = int(_acts.get(k, 0)) + 1

func _sample() -> void:
	for f in root.get_node("World").all_folk():
		if int(f.household_id) != 1 or bool(f.has_meta("visitor")):
			continue
		var mm: Dictionary = _moods.get(f.name, {})
		var md: String = str(Mood.compute(f)["mood"])
		mm[md] = int(mm.get(md, 0)) + 1
		_moods[f.name] = mm
		for b in f.buffs:
			_buffs[b["id"]] = int(_buffs.get(b["id"], 0)) + 1
		var lw: Dictionary = _low.get(f.name, {})
		for n in f.needs:
			lw[n] = minf(float(lw.get(n, 100.0)), float(f.needs[n].value))
		_low[f.name] = lw

func _report() -> void:
	var bykind: Dictionary = {}
	for t in _toasts:
		bykind[t[2]] = int(bykind.get(t[2], 0)) + 1
	print("== toasts by kind: ", bykind, " total ", _toasts.size())
	print("== chronicle by kind: ", _chron)
	var rel_total := 0
	var rel_strangers := 0
	var bad := 0
	var fridge_days: Dictionary = {}
	var fc := []
	for t in _toasts:
		if t[2] == "relationship":
			rel_total += 1
			if not _household_involved(str(t[1])):
				rel_strangers += 1
		if str(t[1]).find("went bad") >= 0:
			bad += 1
			fridge_days[t[0]] = true
		if t[2] == "weather" and (str(t[1]).find("possible") >= 0 or str(t[1]).find("chance") >= 0 or str(t[1]).find("likely") >= 0 or str(t[1]).find("forecast") >= 0):
			fc.append(t)
	print("== relationship toasts: %d, none involving the household: %d" % [rel_total, rel_strangers])
	print("== spoilage toasts: %d on %d days" % [bad, fridge_days.size()])
	print("== forecast toasts: %d" % fc.size())
	for t in fc: print("   d%d %s" % [t[0], t[1]])
	var names: Dictionary = {}
	var dup := 0
	var seen := 0
	var by_id: Dictionary = {}
	for f in root.get_node("World").all_folk():
		by_id[int(f.id)] = str(f.name)
	for t in Story.alive_townies():
		by_id[int(t["id"])] = str(Story.name_of(int(t["id"])))
	for fid in by_id:
		var fn: String = str(by_id[fid]).get_slice(" ", 0)
		names[fn] = int(names.get(fn, 0)) + 1
	for n in names:
		seen += 1
		if int(names[n]) > 1:
			dup += int(names[n]) - 1
	print("== first names: %d distinct, %d duplicates (world folk + alive townies)" % [seen, dup])
	var tops: Array = _acts.keys()
	tops.sort_custom(func(a, b): return int(_acts[a]) > int(_acts[b]))
	print("== top repeated activities (household, whole run):")
	for i in range(mini(12, tops.size())):
		print("   %s x%d" % [tops[i], _acts[tops[i]]])
	for fname in _moods:
		var mm: Dictionary = _moods[fname]
		var tot := 0
		for k in mm: tot += int(mm[k])
		var parts := []
		for k2 in mm:
			parts.append("%s %d%%" % [k2, int(round(100.0 * float(mm[k2]) / float(maxi(tot, 1))))])
		print("== mood %s: %s" % [fname, ", ".join(parts)])
		var lows := []
		for n in _low[fname]: lows.append("%s:%d" % [n, int(_low[fname][n])])
		print("   need lows: ", " ".join(lows))
	var bk: Array = _buffs.keys()
	bk.sort_custom(func(a, b): return int(_buffs[a]) > int(_buffs[b]))
	print("== buff samples (top): ", bk.slice(0, 14).map(func(k): return "%s:%d" % [k, _buffs[k]]))
	print("== karaoke by singer: ", _karaoke)
	print("== coins per day: ", _coins)
	print("== story pacing sources: ", StoryPacing.sources)
	var inc: Dictionary = {}
	for h in Incidents.history(400):
		var k3: String = str(h.get("id", h.get("kind", "?")))
		inc[k3] = int(inc.get(k3, 0)) + 1
	print("== incidents: ", inc)

func _household_involved(text: String) -> bool:
	for f in root.get_node("World").all_folk():
		if int(f.household_id) == 1 and not bool(f.has_meta("visitor")) and text.find(str(f.name)) >= 0:
			return true
	return false
