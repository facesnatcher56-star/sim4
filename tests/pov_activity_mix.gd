extends SceneTree
## Activity mix (reviewer tool, not a test): per household folk per day, distinct interactions, top non-need repeat, idle share. args: seed. Pass home_state in the opts line to compare empty and furnished.
var _main: Node = null
var _f := 0
var _m := 0
var _days := 3
var _last: Dictionary = {}
var _starts: Dictionary = {}   # "fid|day" -> {act: n}
var _idle: Dictionary = {}     # fid -> idle awake minutes
var _awake: Dictionary = {}
const NEEDS := ["use_toilet", "eat", "sleep", "shower", "snack", "bath", "nap"]
func _process(_d: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_f += 1
	if _f == 5:
		var r := RandomNumberGenerator.new(); r.seed = int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 101
		var h := HouseholdSetup.make_household("family", r)
		_main.start_new_game(h, str(Scenario.def("family").get("start_id", "classic")), {"scenario": "family", "difficulty": "normal", "world_seed": 101})
	if _f > 20 and _m < _days * 1440:
		var c = root.get_node("Clock")
		for i in 60:
			c.advance_minutes(1)
			_m += 1
			var day := int(c.day())
			for fo in root.get_node("World").all_folk():
				if int(fo.household_id) != 1 or fo.has_meta("away"):
					continue
				var fid := int(fo.id)
				var cur := str(fo.current.def_id) if fo.current != null else "-"
				var asleep := cur.begins_with("sleep") or cur.contains("nap")
				if not asleep:
					_awake[fid] = int(_awake.get(fid, 0)) + 1
					if cur == "-" or cur.begins_with("idle") or cur == "daydream":
						_idle[fid] = int(_idle.get(fid, 0)) + 1
				if cur != str(_last.get(fid, "")) and cur != "-":
					var k := "%d|%d|%s" % [fid, day, str(fo.name).split(" ")[0]]
					if not _starts.has(k): _starts[k] = {}
					_starts[k][cur] = int(_starts[k].get(cur, 0)) + 1
				_last[fid] = cur
		return false
	if _f > 20:
		for k in _starts.keys():
			var d: Dictionary = _starts[k]
			var top := ""
			var topn := 0
			for a in d:
				var isneed := false
				for n in NEEDS:
					if str(a).contains(n): isneed = true
				if not isneed and int(d[a]) > topn:
					topn = int(d[a]); top = str(a)
			print("ACT %s distinct %d, top non-need %s x%d" % [k, d.size(), top, topn])
		for fid in _awake:
			print("IDLE folk %d idle %.0f%% of %d awake minutes" % [fid, 100.0 * int(_idle.get(fid, 0)) / max(1, int(_awake[fid])), int(_awake[fid])])
		quit(0)
	return false
