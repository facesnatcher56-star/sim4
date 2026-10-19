extends SceneTree
## Not a test (no _test suffix: not discovered by run_all): boots the real game with a scenario household and seed, plays N game days one game hour per frame and logs the 19e / 19f
## leftovers: a mood journal line of 90 percent or more (with the person's buffs and needs at that moment), everyone who is shivering,
## hypothermic or collapsed in the cold (where they are, what they are doing), trait picks at births and age-ups, and days on which one
## person gets two death toasts.
##   godot --headless --path . --script res://tests/saga_probe.gd -- <scenario> <days> <seed>

var _main: Node = null
var _frames := 0
var _scen := "family"
var _days := 168
var _seed := 101
var _deaths: Dictionary = {}       # day -> {name: [texts]}
var _acts: Dictionary = {}         # folk id -> last interaction ids
var _cold_logged: Dictionary = {}  # "id|day|hour" -> true
var _hour_moods: Dictionary = {}   # name -> {mood: n} from my own hourly samples (compared with the journal)
var _t0 := 0

func _process(_d: float) -> bool:
	var args := OS.get_cmdline_user_args()
	if _main == null:
		if args.size() > 0: _scen = str(args[0])
		if args.size() > 1: _days = int(args[1])
		if args.size() > 2: _seed = int(args[2])
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 5:
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed
		var h: Dictionary = HouseholdSetup.make_household(_scen, rng)
		var def: Dictionary = Scenario.def(_scen)
		var sid := str(def.get("start_id", "classic"))
		var diff := Scenario.default_difficulty()
		_main.start_new_game(h, sid, {"scenario": _scen, "difficulty": diff, "start_id": sid, "funds": Scenario.funds_for(_scen, diff),
			"household": h, "home_template": LotPicker.home_for(sid, _seed), "world_seed": _seed})
		var ev = root.get_node("Events")
		ev.notification.connect(_on_note)
		ev.game_event.connect(_on_event)
		ev.interaction_started.connect(_on_act)
		var names: Array = []
		for f in SysUtil.residents():
			names.append("%s (%s, %s)" % [f.name, f.age_stage, ",".join(f.traits)])
		print("PROBE %s seed %d: %s" % [_scen, _seed, "; ".join(names)])
		_t0 = Time.get_ticks_msec()
		return false
	if _frames < 8:
		return false
	var clock = root.get_node("Clock")
	for _m in 60:
		clock.advance_minutes(1)
	_hourly(clock)
	if int(clock.day()) > _days:
		print("PROBE done: %d days in %d s" % [_days, (Time.get_ticks_msec() - _t0) / 1000])
		quit(0)
	return false

func _stamp(clock) -> String:
	return "d%d %02d:%02d" % [int(clock.day()), int(clock.hour()), int(clock.minute())]

func _where(f) -> String:
	var W = root.get_node("World")
	var cur: String = str(f.current.def_id) if f.current != null else "-"
	var r: Dictionary = Health.rec_of(int(f.id))
	return "%s(%s)@%s L%d lot=%s outdoor=%s outside=%s away=%s cur=%s last=%s cold_min=%.0f feels=%.1f" % [f.name, f.age_stage, str(f.tile), int(f.level),
		str(Neighborhood.lot_of_folk(f)), str(W.is_outdoor(f.tile, int(f.level))), str(WeatherFolk.is_outside(f)), str(f.get_meta("away", "")), cur,
		str(_acts.get(int(f.id), [])), float(r.get("cold_min", 0.0)), Weather.feels_like()]

func _hourly(clock) -> void:
	for f in SysUtil.residents():
		var mm: Dictionary = _hour_moods.get(f.name, {})
		var md: String = str(Mood.compute(f)["mood"])
		mm[md] = int(mm.get(md, 0)) + 1
		_hour_moods[f.name] = mm
		for b in ["shivering", "hypothermia", "collapsed"]:
			if f.has_buff(b):
				var k := "%d|%d|%d" % [int(f.id), int(clock.day()), int(clock.hour())]
				if not _cold_logged.has(k):
					_cold_logged[k] = true
					print("COLD %s %s %s" % [_stamp(clock), b, _where(f)])
				break

func _on_act(fid: int, iid: String, _t: int) -> void:
	var a: Array = _acts.get(fid, [])
	a.append(iid)
	while a.size() > 4:
		a.pop_front()
	_acts[fid] = a

func _on_note(t: String, k: String) -> void:
	var clock = root.get_node("Clock")
	if k == "death" or t.find(" dead") >= 0 or t.find("died") >= 0 or t.find("found dead") >= 0:
		var d: int = int(clock.day())
		var byname: Dictionary = _deaths.get(d, {})
		for f in SysUtil.residents():
			pass
		# key by the first two words (the name)
		var parts: PackedStringArray = t.split(" ")
		var nm: String = parts[0] + (" " + parts[1] if parts.size() > 1 else "")
		var arr: Array = byname.get(nm, [])
		arr.append(t)
		byname[nm] = arr
		_deaths[d] = byname
		if arr.size() >= 2:
			print("DOUBLE DEATH TOAST %s %s: %s" % [_stamp(clock), nm, str(arr)])
	elif t.begins_with("Mood journal"):
		print("JOURNAL %s %s" % [_stamp(clock), t])

func _on_event(ev: String, p: Dictionary) -> void:
	var clock = root.get_node("Clock")
	match ev:
		"mood_journal":
			for line in p.get("lines", []):
				var s := str(line)
				var pct_at := s.find("(")
				var pct: int = int(s.substr(pct_at + 1, 3)) if pct_at >= 0 else 0
				if pct >= 90:
					var nm: String = s.substr(0, s.find(" was mostly"))
					for f in SysUtil.residents():
						if f.name == nm:
							var bl: Array = []
							for b in f.buffs:
								var def: Dictionary = SimEnv.data().buff_def(str(b["id"]))
								bl.append("%s%s%s" % [b["id"], ("/" + str(def.get("mood", {}))) if not def.get("mood", {}).is_empty() else "", ("/rem" + str(int(float(b.get("remaining", -1))))) if b.has("remaining") else ""])
							var nl: Array = []
							for n in f.needs:
								nl.append("%s=%d" % [n, int((f.needs[n] as Stat).value)])
							print("STUCK %s %s | mood now=%s/%d | hourly samples=%s | buffs=%s | needs=%s | %s" % [_stamp(clock), s, f.mood_name, f.mood_intensity, str(_hour_moods.get(nm, {})), str(bl), str(nl), _where(f)])
			_hour_moods.clear()
		"aged_up":
			var f = SysUtil.folk(int(p.get("folk_id", -1)))
			if f != null and SysUtil.is_resident(f):
				print("AGE %s %s -> %s traits=%s inherited=%s" % [_stamp(clock), f.name, str(p.get("to", "")), ",".join(f.traits), str((Aging.records.get(int(f.id), {}) as Dictionary).get("inherited", []))])
		"baby_born":
			var b = SysUtil.folk(int(p.get("baby_id", -1)))
			if b != null:
				print("BIRTH %s %s inherited=%s" % [_stamp(clock), b.name, str((Aging.records.get(int(b.id), {}) as Dictionary).get("inherited", []))])
		"health_collapsed":
			var f2 = SysUtil.folk(int(p.get("folk_id", -1)))
			if f2 != null:
				print("COLLAPSE %s kind=%s %s" % [_stamp(clock), str(p.get("kind", "")), _where(f2)])
		"health_rescued":
			var f3 = SysUtil.folk(int(p.get("folk_id", -1)))
			if f3 != null:
				print("RESCUE %s kind=%s helper=%s %s" % [_stamp(clock), str(p.get("kind", "")), str(p.get("helper", -1)), _where(f3)])
