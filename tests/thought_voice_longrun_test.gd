extends RefCounted
## SLOW tier (pov32 item 4): the full family-101 game for 3 game days. For the household's folk: distinct lines / total >= 0.5, no line more than
## 5 times per folk per day, at least 20% of lines name a person, a place or a recent event. (Reviewer's counting tool: tests/pov_thought_count.gd.)

var _total := 0
var _by_folk: Dictionary = {}       # folk id -> [total, {text: true}]
var _per_day: Dictionary = {}       # "fid|day|text" -> n
var _refs := 0
var _hh_lines := 0
var _words: Array = []
var _hh: Dictionary = {}

func _cap(fid: int, text: String) -> void:
	if not _hh.has(fid):
		return
	_hh_lines += 1
	var e: Array = _by_folk.get(fid, [0, {}])
	e[0] = int(e[0]) + 1
	(e[1] as Dictionary)[text] = true
	_by_folk[fid] = e
	var k := "%d|%d|%s" % [fid, SysUtil.day(), text]
	_per_day[k] = int(_per_day.get(k, 0)) + 1
	for wd in _words:
		if text.find(wd) >= 0:
			_refs += 1
			break

func run() -> Array:
	var fails: Array = []
	var root: Window = Engine.get_main_loop().root
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var r := RandomNumberGenerator.new()
	r.seed = 101
	var h := HouseholdSetup.make_household("family", r)
	main.start_new_game(h, str(Scenario.def("family").get("start_id", "classic")), {"scenario": "family", "difficulty": "normal", "world_seed": 101})
	ThoughtVoice.reset()
	for f in SysUtil.residents():
		_hh[int(f.id)] = true
		_words.append(str(f.name).split(" ")[0])
	for t in Story.alive_townies():
		_words.append(str(t.get("name", "?")).split(" ")[0])
	for lid in Neighborhood.lot_ids():
		_words.append(Neighborhood.label_of(str(lid)))
	for wd in ["fire", "smoke", "election", "mayor", "party", "wedding", "storm", "That bus", "the bus", "birthday"]:
		_words.append(wd)
	root.get_node("Events").thought.connect(_cap)
	var clock = root.get_node("Clock")
	for hour in 72:
		for m in 60:
			clock.advance_minutes(1)
	root.get_node("Events").thought.disconnect(_cap)
	var worst := 0
	for k in _per_day:
		worst = maxi(worst, int(_per_day[k]))
	if worst > 5:
		fails.append("a line was said %d times by one folk in a day (max 5)" % worst)
	var ratios: Array = []
	for fid in _by_folk:
		var e: Array = _by_folk[fid]
		if int(e[0]) < 10:
			continue
		var ratio: float = float((e[1] as Dictionary).size()) / float(e[0])
		ratios.append("%d:%.2f(%d)" % [fid, ratio, e[0]])
		if ratio < 0.5:
			fails.append("folk %d distinct/total %.2f < 0.5 (%d lines)" % [fid, ratio, e[0]])
	var share: float = float(_refs) / maxf(1.0, float(_hh_lines))
	if share < 0.2:
		fails.append("only %.0f%% of lines name a person, place or recent event (need 20%%)" % (share * 100.0))
	if _hh_lines < 30:
		fails.append("household barely spoke (%d lines in 3 days)" % _hh_lines)
	print("thought_voice_longrun: household lines %d, distinct/total %s, max per folk-day %d, references %.0f%%" % [_hh_lines, str(ratios), worst, share * 100.0])
	main.queue_free()
	return fails
