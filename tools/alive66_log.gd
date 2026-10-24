extends SceneTree
## Task 66 log (not a test suite): two game days of a solo start on Normal, played like a person would (out in the day, home in the evening, asleep
## at night; prompts answered like a decent person). Writes coord/shots/66/log.md: every time the player was pulled in (what, who), the town's
## own events, the toasts per kind, and the longest awake stretch with nothing open.
##   <godot> --headless --path . --script res://tools/alive66_log.gd
const Kit := preload("res://tests/start_kit.gd")
const OUT := "res://coord/shots/66b/log.md"
const PLAN := {9: "cafe", 12: "park", 15: "market", 18: "home"}
const LIKE := ["answer", "in", "lend", "yes", "go", "comfort", "step", "watch", "yes", "tell", "take", "return", "sorry", "help", "ambulance", "talk"]
var _done := false
var lines: Array = []
var toasts: Dictionary = {}
var prompts: Array = []

func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	TestFixture.isolate_user_files()
	var folk: Array = Kit.new_game("solo", "normal", {}, -1, {"world_seed": 7171, "home_state": "empty"})
	var f: Folk = folk[0]
	var spec: Dictionary = (Creation.picks.get(int(f.id), Creation.empty_spec()) as Dictionary)
	spec["background"] = "ex_con"          # a real background, so its first-week moment can land (the default "nobody" has none)
	Creation.picks[int(f.id)] = spec
	SimEnv.events().notification.connect(func(text, kind):
		toasts[kind] = int(toasts.get(kind, 0)) + 1
		lines.append("- %s  toast (%s): %s" % [_t(), kind, text]))
	SimEnv.events().game_event.connect(func(n, p):
		if n == "involve_pull":
			lines.append("- **%s  PULL%s: %s** (%s)" % [_t(), " (stakes)" if bool(p.get("stakes", false)) else "", str(p.get("what", "")), ", ".join(Involve.log[-1]["people"]) if not Involve.log.is_empty() else ""])
		elif n == "street_scene":
			lines.append("- %s  scene in front of the player: %s" % [_t(), str(p.get("kind", ""))]))
	JusticePlayer.ask_fn = func(pid, title, text, options, cb, def):
		var ids: Array = options.map(func(o): return str(o["id"]))
		var pick: String = str(def)
		for want in LIKE:
			if ids.has(want):
				pick = want
				break
		prompts.append(title)
		lines.append("- %s  asked \"%s\": %s -> %s" % [_t(), title, text, pick])
		cb.call(pick)
	var hours: int = 48
	var idle_now: int = -1
	var longest: int = 0
	var longest_at: String = ""
	for h in hours:
		var hr: int = Kit.clock().hour()
		if PLAN.has(hr) and not SysUtil.is_away(f):
			Commands.run({"player_id": 1, "folk_id": f.id, "action": "travel", "args": {"folk_ids": [f.id], "lot_id": PLAN[hr]}})
		if hr == 13 or hr == 19:          # eat something: the counter, or the vending machine at home
			f.add_to_stat("hunger", 60.0)
		if hr == 23:
			var sl := Interaction.create("sleep_floor", f, -1, true)
			if sl != null:
				f.enqueue(sl)
		for m in 6:
			Kit.run(10)
			var awake: bool = not CrimePlace.is_asleep(f) and not SysUtil.is_away(f) and Kit.clock().hour() >= 7 and Kit.clock().hour() < 23
			if awake and Involve.open_count(f) == 0:
				if idle_now < 0:
					idle_now = SysUtil.now()
				if SysUtil.now() - idle_now > longest:
					longest = SysUtil.now() - idle_now
					longest_at = "ending %s" % _t()
			else:
				idle_now = -1
	var out: Array = ["# Task 66b: two game days, solo start on Normal (seed 7171)", "",
		"Played like a person would: out to the cafe at 9, the park at 12, the market at 15, home at 18, asleep 23:00-07:00; every prompt answered like a decent person.", "",
		"- Pulls (the director): %d, with stakes: %d" % [Involve.log.size(), Involve.log.filter(func(e): return bool(e.get("stakes", false))).size()],
		"- Town events off-screen (TownLife, heard of only through people): %d; told as gossip: %d" % [TownLife.recent.size(), TownLife.recent.filter(func(e): return bool(e["told"])).size()],
		"- Prompts: %d" % prompts.size(),
		"- Longest awake stretch with nothing open: %d min (%s); the director's own count: %d min" % [longest, longest_at, Involve.longest_idle],
		"- Toasts: %d over two days (%s)" % [toasts.values().reduce(func(a, b): return a + b, 0), str(toasts)], "",
		"## Everything, in order", ""]
	out.append_array(lines)
	var off: Array = ["", "## The town's own events (off-screen)", ""]
	for e in TownLife.recent:
		off.append("- day %d: %s, %s%s at %s%s" % [int(e["day"]), str(e["kind"]), Story.name_of(int(e["a"])), (" / " + Story.name_of(int(e["b"]))) if int(e["b"]) >= 0 else "", Neighborhood.label_of(str(e["lot"])), " (told)" if bool(e["told"]) else ""])
	out.append_array(off)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://coord/shots/66b"))
	var fa := FileAccess.open(OUT, FileAccess.WRITE)
	fa.store_string("\n".join(out) + "\n")
	fa.close()
	print("LOG pulls=%d town=%d prompts=%d longest_idle=%d toasts=%s" % [Involve.log.size(), TownLife.recent.size(), prompts.size(), longest, str(toasts)])
	JusticePlayer.ask_fn = Callable()
	Kit.teardown()
	quit()
	return true

func _t() -> String:
	return "d%d %02d:%02d" % [Kit.clock().day(), Kit.clock().hour(), Kit.clock().minute()]
