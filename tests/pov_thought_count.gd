extends SceneTree
## Thought count (reviewer tool, not a test): counts thought lines over N game days, one game hour per frame.
var _main: Node = null
var _f := 0
var _h := 0
var _days := 3
var _counts: Dictionary = {}
var _total := 0
var _by_folk: Dictionary = {}
func _th(folk_id: int, text: String) -> void:
	var v := ThoughtText.vary(text)
	_counts[v] = int(_counts.get(v, 0)) + 1
	_total += 1
	_by_folk[folk_id] = int(_by_folk.get(folk_id, 0)) + 1
func _process(_d: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_f += 1
	if _f == 5:
		var r := RandomNumberGenerator.new(); r.seed = 101
		var h := HouseholdSetup.make_household("family", r)
		_main.start_new_game(h, str(Scenario.def("family").get("start_id", "classic")), {"scenario": "family", "difficulty": "normal", "world_seed": 101})
	if _f == 20:
		root.get_node("Events").thought.connect(_th)
	if _f > 20 and _h < _days * 24:
		var c = root.get_node("Clock")
		for m in 60: c.advance_minutes(1)
		_h += 1
		return false
	if _f > 20:
		var keys := _counts.keys()
		keys.sort_custom(func(a, b): return _counts[a] > _counts[b])
		print("THOUGHTS total %d distinct %d over %d days; per folk %s" % [_total, keys.size(), _days, str(_by_folk)])
		for k in keys.slice(0, 25):
			print("TH %4d  %s" % [_counts[k], k])
		quit(0)
	return false
