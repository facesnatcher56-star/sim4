extends SceneTree
## Thought count (reviewer tool, not a test): counts thought lines over N game days, one game hour per frame.
var _main: Node = null
var _f := 0
var _h := 0
var _days := 3
var _counts: Dictionary = {}
var _total := 0
var _by_folk: Dictionary = {}
var _per: Dictionary = {}     # "fid|day|text" -> n
var _folk_texts: Dictionary = {}
var _ref := 0
var _hh := 0
var _names: Array = []
func _th(folk_id: int, text: String) -> void:
	var v := text
	var day: int = int(root.get_node("Clock").day())
	var k := "%d|%d|%s" % [folk_id, day, text]
	_per[k] = int(_per.get(k, 0)) + 1
	if not _folk_texts.has(folk_id): _folk_texts[folk_id] = {}
	_folk_texts[folk_id][text] = true
	for n in _names:
		if text.find(n) >= 0:
			_ref += 1
			break
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
		for fo in SysUtil.residents():
			_names.append(str(fo.name).split(" ")[0])
			_hh = int(fo.household_id) if _hh == 0 else _hh
		for t in Story.alive_townies():
			_names.append(str(t.get("name", "?")).split(" ")[0])
		for lid in Neighborhood.lot_ids():
			_names.append(Neighborhood.label_of(str(lid)))
		for w in ["fire", "smoke", "election", "mayor", "party", "wedding", "storm", "That bus", "the bus", "birthday"]:
			_names.append(w)
	if _f > 20 and _h < _days * 24:
		var c = root.get_node("Clock")
		for m in 60: c.advance_minutes(1)
		_h += 1
		return false
	if _f > 20:
		var keys := _counts.keys()
		keys.sort_custom(func(a, b): return _counts[a] > _counts[b])
		print("THOUGHTS total %d distinct %d over %d days; per folk %s" % [_total, keys.size(), _days, str(_by_folk)])
		for k in keys.slice(0, 400):
			print("TH %4d  %s" % [_counts[k], k])
		var worst := 0
		for k in _per:
			worst = maxi(worst, int(_per[k]))
		var ratios: Array = []
		for fid in _by_folk:
			var fo = SysUtil.folk(int(fid))
			if fo != null and int(fo.household_id) == _hh:
				ratios.append("%d:%.2f(%d)" % [fid, float((_folk_texts[fid] as Dictionary).size()) / float(_by_folk[fid]), _by_folk[fid]])
		print("THOUGHT_METRICS household distinct/total %s; max repeats per folk-day %d; referencing a name %.1f%%" % [str(ratios), worst, 100.0 * _ref / maxf(1.0, _total)])
		quit(0)
	return false
