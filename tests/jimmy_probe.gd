extends SceneTree
## Reviewer tool (not a test; the runner skips it): a criminal solo life until death. Args: solo <max days> <seed or -1> <storyteller id or spicy>. Clears Players.table so NPC autonomy lives the daily life and this script plays the crimes.
## args: scenario days seed
var _main: Node = null
var _frames := 0
var _scen := "family"
var _days := 56
var _seed := 1
var _log: Array = []
var _counts: Dictionary = {}
var _night: Dictionary = {}     # folk name -> {awake3: n, nights: n, awake_doing: {iid: n}}
var _seen_toast: Dictionary = {}
var _t0 := 0
const QUIET_EVENTS := ["need_low", "interaction_started", "interaction_finished", "left_lot", "returned_lot", "walk_started",
	"walk_arrived", "commute_started", "commute_arrived", "skill_xp", "buff_added", "buff_removed", "mood_changed",
	"autonomy_choice", "mood_contagion", "social_done", "emotional_memory", "knowledge_revealed", "relationship_bit_changed",
	"whim_added", "group_turn", "karaoke_done", "soc_karaoke", "weather_changed", "systems_day", "mood_journal"]

func _clock():
	return root.get_node("Clock")

func _stamp() -> String:
	var c = _clock()
	return "d%d %02d:%02d" % [c.day(), c.hour(), c.minute()]

func _hid() -> int:
	return int(Economy.primary_household())

func _hh() -> Array:
	var hid := _hid()
	var out: Array = []
	for x in root.get_node("World").all_folk():
		if int(x.household_id) == hid:
			out.append(x)
	return out

func _hh_names() -> Array:
	return _hh().map(func(x): return str(x.name))

func _about_household(text: String) -> bool:
	for n in _hh_names():
		if text.contains(str(n).split(" ")[0]):
			return true
	return false

func _note(text: String, kind: String) -> void:
	_counts["toast:" + kind] = int(_counts.get("toast:" + kind, 0)) + 1
	var key := kind + "|" + text
	# keep the log readable: repeated identical toasts are counted, not re-printed
	if _seen_toast.has(key):
		_seen_toast[key] += 1
		return
	_seen_toast[key] = 1
	var who := "HH " if _about_household(text) else "   "
	_log.append("%s %s[%s] %s" % [_stamp(), who, kind, text])
	if who == "HH " or kind in ["death", "story", "bad", "good", "relationship", "birthday"]:
		print("LIVE %s %s[%s] %s" % [_stamp(), who, kind, text])

func _event(name: String, payload: Dictionary) -> void:
	_counts["event:" + name] = int(_counts.get("event:" + name, 0)) + 1
	if name == "chronicle":
		_log.append("%s     CHRONICLE %s" % [_stamp(), str(payload.get("text", payload))])
		print("LIVE %s     CHRONICLE %s" % [_stamp(), str(payload.get("text", payload))])

func _snapshot(day: int) -> void:
	var parts := []
	for f in _hh():
		var low := 999.0
		var lown := ""
		for n in f.needs:
			if float(f.needs[n].value) < low:
				low = float(f.needs[n].value)
				lown = n
		var m = f.get_mood()
		var job := ""
		if Careers.jobs.has(int(f.id)):
			job = str((Careers.jobs[int(f.id)] as Dictionary).get("career", ""))
		parts.append("%s(%s,%s,age %d,%s %d,low %s %d%s)" % [str(f.name).split(" ")[0], f.age_stage, str(m.get("mood", "?")),
			Aging.age_years(int(f.id)), "job" if job != "" else "nojob", 0, lown, int(low), ","+job if job != "" else ""])
	var pid: int = 1
	var head: int = Succession.head_of(pid)
	var hf = SysUtil.folk(head) if head >= 0 else null
	print("DAY %d coins %d townies %d hid %d head %s pending %s | %s" % [day, Economy.balance(_hid()), Story.alive_townies().size(), _hid(), str(hf.name) if hf != null else "-", str(Succession.is_pending(pid)), " ".join(parts)])

func _night_check() -> void:
	var c = _clock()
	if c.hour() != 3 or c.minute() != 0:
		return
	for f in _hh():
		if str(f.age_stage) == "baby":
			continue
		var nm := str(f.name)
		if not _night.has(nm):
			_night[nm] = {"awake3": 0, "nights": 0, "doing": {}}
		var r: Dictionary = _night[nm]
		r["nights"] += 1
		var cur := str(f.current.def_id) if f.current != null else "-"
		var asleep := cur.begins_with("sleep") or cur == "pass_out" or cur == "nap_couch"
		if f.has_meta("away"):
			cur = "away:" + str(f.get_meta("away"))
			asleep = false
		if not asleep:
			r["awake3"] += 1
			r["doing"][cur] = int(r["doing"].get(cur, 0)) + 1

func _process(_d: float) -> bool:
	var args := OS.get_cmdline_user_args()
	if _main == null:
		if args.size() > 0: _scen = args[0]
		if args.size() > 1: _days = int(args[1])
		if args.size() > 2: _seed = int(args[2])
		if _seed < 0:
			randomize()
			_seed = (randi() ^ (OS.get_process_id() * 2654435761)) & 0x7fffffff
		print("ZACK seed %d" % _seed)
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 5:
		var r := RandomNumberGenerator.new()
		r.seed = _seed
		var h := HouseholdSetup.make_household("solo", r)
		var used: Array = []
		var d: Dictionary = HouseholdSetup.random_folk("adult", "none", used, r, [], "male")
		d["name"] = "Jimmy Jam"
		h["folk"] = [d]
		print("ZACK validate: '%s'" % HouseholdSetup.validate(h))
		var start_id := str(Scenario.def("solo").get("start_id", "small"))
		_main.start_new_game(h, start_id, {"scenario": "solo", "difficulty": "normal", "world_seed": _seed, "funds": Scenario.funds_for("solo", "normal")})
	if _frames == 20:
		var a2 := OS.get_cmdline_user_args()
		if a2.size() > 3:
			if a2[3] == "spicy":
				print("ZACK storyteller spicy (custom max frequency and severity, mostly bad, no mercy): %s" % str(Storyteller.set_personality("custom", {"frequency": 1.0, "severity": 1.0, "balance": 0.3, "mercy": 0.0})))
			else:
				print("ZACK storyteller %s: %s" % [a2[3], str(Storyteller.set_personality(a2[3]))])
		print("ZACK storyteller is %s" % Storyteller.personality_id())
		Incidents.set_level("chaotic")
		for x in _hh():
			Aging.set_age_days(x, 80.0)
			print("ZACK crime join %s, age %d" % [str(CrimeLifePath.join(int(x.id), "chose")), Aging.age_years(int(x.id))])
		Players.table.clear()
		print("ZACK players cleared: pawn=%s" % str(Pawn.of()))
		print("ZACK surprises level %s x%.1f" % [Incidents.level_id(), Incidents.surprise_mult()])
	if _frames == 30:
		var ev = root.get_node("Events")
		ev.notification.connect(_note)
		ev.game_event.connect(_event)
		print("SAGA scenario %s seed %d household: %s" % [_scen, _seed, ", ".join(_hh().map(func(x): return "%s [%s] %s" % [x.name, ",".join(x.traits), x.age_stage]))])
		_t0 = Time.get_ticks_msec()
		for x in _hh():
			_zid = int(x.id)
	# one game hour per frame, like real play, so Godot can free nodes between frames
	if _frames > 30 and _zid >= 0 and _died_frame < 0 and SysUtil.folk(_zid) == null:
		_died_frame = _frames
		var lg: Dictionary = Aging.dead.back() if not Aging.dead.is_empty() else {}
		print("ZACKDIED %s cause %s age %d legacy %s" % [_stamp(), str(lg.get("cause", "?")), Aging.age_years(_zid) if false else int((int(lg.get("day", 0)) - int(lg.get("born_day", 0))) / 4), str(lg)])
		_days = int((_frames - 30) / 24) + 3
	if _frames > 30 and _frames <= 30 + _days * 24:
		var c = _clock()
		for m in 60:
			c.advance_minutes(1)
			_night_check()
		_romance_check()
		_crime_driver()
		_stay_home()
		if (_frames - 30) % 24 == 0:
			_snapshot(c.day())
		return false
	if _frames == 31 + _days * 24:
		print("SAGA simulated %d days in %d s" % [_days, (Time.get_ticks_msec() - _t0) / 1000])
		print("ROMANCE violations total: %d" % _viol)
		for line in _log:
			print("STORY " + str(line))
		for nm in _night:
			var r2: Dictionary = _night[nm]
			print("NIGHT %s awake at 03:00 on %d of %d nights; doing: %s" % [nm, r2["awake3"], r2["nights"], str(r2["doing"])])
		var keys := _counts.keys()
		keys.sort_custom(func(a, b): return _counts[a] > _counts[b])
		for k in keys:
			print("COUNT %6d  %s" % [_counts[k], k])
		for k2 in _seen_toast:
			if int(_seen_toast[k2]) >= 5:
				print("REPEAT %4dx %s" % [_seen_toast[k2], k2])
		for f in root.get_node("World").all_folk():
			if int(f.household_id) != 1:
				continue
			var sk := []
			for s in f.skills:
				sk.append("%s %d" % [s, f.skill_level(s)])
			print("FOLK %s [%s] %s age %d skills: %s" % [f.name, ",".join(f.traits), f.age_stage, Aging.age_years(int(f.id)), ", ".join(sk)])
		quit(0)
	return false


var _viol := 0
var _zid := -1
var _died_frame := -1
func _romance_check() -> void:
	var hh := _hh()
	for a in hh:
		for b in hh:
			if a == b:
				continue
			var r := float(RelationshipService.value(int(a.id), int(b.id), "romance"))
			var ok: bool = RomanceRules.allowed(int(a.id), int(b.id))
			if not ok and r > 0.0:
				_viol += 1
				print("VIOLATION %s %s(%s) -> %s(%s) romance %.1f" % [_stamp(), a.name, a.age_stage, b.name, b.age_stage, r])


func _industrial() -> String:
	for c in Careers.career_ids():
		var cs := str(c)
		for k in ["factory", "industrial", "warehouse", "construction", "mechanic", "plant", "dock"]:
			if cs.contains(k):
				return cs
	return "handyperson"

var _quits := 0
func _stay_home() -> void:
	for f in _hh():
		if str(f.name).begins_with("Madrina") and Careers.has_job(int(f.id)):
			_quits += 1
			if _quits == 1 or _quits % 24 == 0:
				print("KEN %s BUG Madrina (homemaker %s) has a job: %s" % [_stamp(), str(Homemaker.is_homemaker(f)), Careers.career_of(int(f.id))])


var _crimes := 0
func _crime_driver() -> void:
	var c = _clock()
	var h: int = int(c.hour())
	if h != 14 and h != 22:
		return
	if _zid < 0 or SysUtil.folk(_zid) == null:
		return
	var f = SysUtil.folk(_zid)
	if CrimePerson.in_custody(_zid) or SysUtil.is_away(f):
		return
	if not CrimeLifePath.is_member(_zid):
		if CrimeLifePath.going_straight(_zid):
			return
		CrimeLifePath.join(_zid, "chose")
	if randf() > 0.55:
		return
	var order := ["store_robbery", "burglary", "car_theft", "scam", "shoplift", "pickpocket"]
	for jid in order:
		if not CrimeLifeJobs.unlocked(_zid, jid):
			continue
		var night: bool = bool(CrimeLifeJobs.job(jid).get("night", false))
		if night != (h == 22):
			continue
		var t: Dictionary = CrimeLifeJobs.pick_target(_zid, jid)
		if t.is_empty():
			continue
		var r: Dictionary = CrimeLifeJobs.start(_zid, jid, t)
		_crimes += 1
		print("LIVE %s HH [crimejob] Jimmy goes out: %s -> %s (%s)" % [_stamp(), jid, str(r.get("msg", "")), str(t.get("label", t.get("name", "")))])
		return
