extends RefCounted
## Thought-bubble voice (pov32 item 4): rate, variety, no repeats, tone, context lines naming people / places / events, chat topics, emergency lines.
## Convention: run() -> Array of failure strings. The 3-day household measure lives in thought_voice_longrun_test.gd.

const K = preload("res://tests/systems_kit.gd")

var _got: Array = []     # [folk_id, text]

func _cap(fid: int, text: String) -> void:
	_got.append([fid, text])

func _texts(fid: int) -> Array:
	var out: Array = []
	for g in _got:
		if int(g[0]) == fid:
			out.append(str(g[1]))
	return out

func run() -> Array:
	var fails: Array = []
	var w := K.setup()
	ThoughtVoice.reset()
	var a := K.make_folk(w, "Aino Test", ["optimist"])
	var b := K.make_folk(w, "Bram Test", ["pessimist"])
	SimEnv.events().thought.connect(_cap)
	var data: Dictionary = ThoughtVoice.cfg()
	K.expect(fails, not data.is_empty(), "data/thought_voice.json loads")
	for cid in data.get("categories", {}):
		var lines: Dictionary = data["categories"][cid]["lines"]
		K.expect(fails, (lines["any"] as Array).size() + (lines["grumpy"] as Array).size() >= 8, "category %s has a pool of at least 8 lines for a grumpy folk" % cid)
		K.expect(fails, (lines["any"] as Array).size() + (lines["cheerful"] as Array).size() >= 8, "category %s has a pool of at least 8 lines for a cheerful folk" % cid)
	for tid in data.get("topics", {}):
		K.expect(fails, (data["topics"][tid] as Array).size() >= 5, "topic %s has several lines" % tid)

	# rate: three need thoughts in a row inside one gap -> the first shows, the rest are dropped
	K.set_time(2, 8)
	_got.clear()
	for t in ["I should find a toilet.", "I'm hungry...", "So sleepy..."]:
		SimEnv.emit("thought", a.id, t)
	K.expect(fails, _texts(a.id).size() == 1, "only one bubble inside the rate gap (got %d)" % _texts(a.id).size())
	# need lines are re-voiced from the pool, not echoed (the toilet pool never contains the sleepy text)
	K.expect(fails, ThoughtVoice.category_of("I NEED the bathroom!") == "toilet" and ThoughtVoice.category_of("A coffee would be lovely.") == "coffee", "need lines map to categories")

	# never the same line twice within a day, daily cap respected, many distinct lines over a day
	_got.clear()
	var minute := SimEnv.now_min()
	for i in 200:
		K.set_time(2, 6 + (i * 2) / 60, (i * 2) % 60)
		SimEnv.emit("thought", a.id, "I should find a toilet.")
		SimEnv.emit("thought", a.id, "I'm hungry...")
		SimEnv.emit("thought", a.id, "Turn it up!")
	var seen: Dictionary = {}
	for t in _texts(a.id):
		seen[t] = int(seen.get(t, 0)) + 1
	var worst := 0
	for t in seen:
		worst = maxi(worst, int(seen[t]))
	K.expect(fails, worst <= 1, "no line twice in a day (worst %d)" % worst)
	K.expect(fails, _texts(a.id).size() <= int(ThoughtVoice.conf().get("max_per_day", 16)), "daily cap (%d lines)" % _texts(a.id).size())
	K.expect(fails, _texts(a.id).size() >= 3, "a folk still talks now and then (%d lines)" % _texts(a.id).size())

	# higher game speed means fewer bubbles
	ThoughtVoice.reset()
	var slow_n := _count_over_day(a.id, 1)
	ThoughtVoice.reset()
	var fast_n := _count_over_day(a.id, 3)
	K.expect(fails, fast_n < slow_n, "fewer bubbles at speed 3 (%d) than speed 1 (%d)" % [fast_n, slow_n])

	# emergency lines are never dropped by the rate gate (but a spammed repeat is)
	ThoughtVoice.reset()
	_got.clear()
	SimEnv.emit("thought", b.id, "I should find a toilet.")
	ThoughtVoice.urgent(b.id, "Fire! Everybody out!")
	ThoughtVoice.urgent(b.id, "Fire! Everybody out!")
	K.expect(fails, _texts(b.id).has("Fire! Everybody out!") and _texts(b.id).count("Fire! Everybody out!") == 1, "an emergency line passes the gate once, a repeat inside 10 minutes is dropped")

	# determinism and the sim rng: same inputs, same line; the sim rng stream is untouched
	SysUtil.seed_rng(77)
	var before := SysUtil.rng.state
	ThoughtVoice.reset()
	K.set_time(3, 9)
	_got.clear()
	SimEnv.emit("thought", a.id, "I'm hungry...")
	var first: Array = _texts(a.id).duplicate()
	ThoughtVoice.reset()
	K.set_time(3, 9)
	_got.clear()
	SimEnv.emit("thought", a.id, "I'm hungry...")
	K.expect(fails, first == _texts(a.id) and not first.is_empty(), "same state gives the same line")
	K.expect(fails, SysUtil.rng.state == before, "thought gate does not consume the sim rng")

	# tone: grumpy and cheerful folk draw from different pools
	var cheer_pool: Array = (data["categories"]["lonely"]["lines"]["cheerful"] as Array)
	var grump_pool: Array = (data["categories"]["lonely"]["lines"]["grumpy"] as Array)
	K.expect(fails, ThoughtVoice.tone_of(a) == "cheerful" and ThoughtVoice.tone_of(b) == "grumpy", "optimist is cheerful, pessimist is grumpy")
	K.expect(fails, cheer_pool.size() >= 3 and grump_pool.size() >= 3 and cheer_pool[0] != grump_pool[0], "tone pools differ")

	# context: events name people; a death makes kin miss them
	ThoughtVoice.reset()
	K.set_time(4, 9)
	_got.clear()
	b.household_id = a.household_id
	SysUtil.game_event("baby_born", {"folk_id": a.id, "baby_id": b.id, "target_id": -1})
	var named := false
	for t in _texts(a.id) + _texts(b.id):
		if str(t).find("Bram") >= 0:
			named = true
	K.expect(fails, named, "a birth makes the household talk about the baby by name")
	ThoughtContext.reset()
	K.set_time(5, 9)
	_got.clear()
	SysUtil.game_event("fire_started", {"lot": "x", "folk_id": -1})
	K.expect(fails, not _got.is_empty(), "a fire in town makes someone react")
	var line := ThoughtContext.line(a, ThoughtVoice._state(a.id, SimEnv.now_min(), SysUtil.day()), SysUtil.day(), 3)
	K.expect(fails, line.find("fire") >= 0 or line.find("smoke") >= 0 or line.find("Fire") >= 0 or line.find("everyone") >= 0, "a recent fire is recalled (%s)" % line)

	# chat: both speakers show a topic line, the gossip topic names a third person
	ThoughtVoice.reset()
	K.set_time(6, 10)
	var c := K.make_folk(w, "Cass Test", [])
	RelationshipService.add_both(a.id, b.id, "friendship", 60.0)
	RelationshipService.add_both(a.id, c.id, "friendship", 60.0)
	_got.clear()
	ThoughtVoice.chat(a.id, b.id, "gossip")
	K.expect(fails, _texts(a.id).size() == 1 and _texts(b.id).size() == 1, "both chat partners speak (%s)" % str(_got))
	K.expect(fails, not (str(_texts(a.id)[0]) if not _texts(a.id).is_empty() else "").begins_with("Let's talk about"), "no generic 'Let's talk about' line")

	# names and templates are rationed per day: nobody is nmd more than twice, no template more than twice
	ThoughtVoice.reset()
	K.set_time(7, 10)
	var st2 := ThoughtVoice._state(a.id, SimEnv.now_min(), SysUtil.day())
	var nmd: Dictionary = {}
	for i in 40:
		var l := ThoughtContext.line(a, st2, SysUtil.day(), i * 37)
		st2["used"] = {}
		for nm in ["Bram", "Cass"]:
			if l.find(nm) >= 0:
				nmd[nm] = int(nmd.get(nm, 0)) + 1
	K.expect(fails, int(nmd.get("Bram", 0)) <= 2 and int(nmd.get("Cass", 0)) <= 2, "a friend is nmd at most twice a day (%s)" % str(nmd))
	for t in (st2["tmpl"] as Dictionary):
		K.expect(fails, int(st2["tmpl"][t]) <= 2, "template used at most twice a day: %s" % t)

	SimEnv.events().thought.disconnect(_cap)
	K.teardown()
	return fails

func _count_over_day(fid: int, speed: int) -> int:
	SimEnv.clock().speed = speed
	_got.clear()
	for i in 360:
		K.set_time(8, 6 + i / 60, i % 60)
		SimEnv.emit("thought", fid, "Whim number %d." % i)
	SimEnv.clock().speed = 1
	return _texts(fid).size()
