extends RefCounted
## Murder is never random: a built-up motive + traits + opportunity. Warning signs (thought, gossip, a clear prompt for a player folk who is the
## culprit or the target) and the chance to step in. Kind folk never do it. Assault from a screaming argument. Street robbery. The serial killer:
## isolated targets, pattern detection, caught within the victim cap.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_feud_ends_in_murder(f)
	_gentle_never(f)
	_player_prompt(f)
	_assault(f)
	_robbery(f)
	_serial(f)
	return f

func _feud_ends_in_murder(f: Array) -> void:
	var w := C.town(10)
	C.quiet_witnesses()
	var ids: Array = C.adults()
	var a: int = int(ids[0])
	var b: int = int(ids[1])
	Story.townies[a]["traits"] = ["hot_headed", "jealous"]
	Story.townies[b]["traits"] = ["forgiving"]
	var warned: bool = false
	var days_to: int = -1
	K.set_time(2, 12, 0)
	JusticeState.sect("murder")["daily_chance"] = 0.3          # the real rate is tiny; here we only follow the story once it happens
	for d in 200:
		C.feud(a, b, 60.0)                           # the feud is kept alive (no time to cool off in a headless sim)
		SimEnv.clock().total_minutes += 1440
		CrimeMurder.on_day()
		C.drain_pending()
		warned = warned or RelationshipKnowledge.gossip_for(int(RelationshipBits.all_known(a)[0])).size() > 0 or K.count_events("murder_warning") > 0
		if JusticeState.counter("murder") > 0:
			days_to = d
			break
	K.expect(f, K.count_events("murder_warning") >= 1, "warning signs came first (warning event fired)")
	K.expect(f, days_to >= int(JusticeState.sect("murder").get("min_days", 6)), "murder needs a built-up motive: took %d days" % days_to)
	var c: Dictionary = JusticeState.cases[JusticeState.cases.keys()[0]] if not JusticeState.cases.is_empty() else {}
	K.expect(f, not c.is_empty() and int(c["culprit"]) == a and int(c["victim"]) == b and str(c["kind"]) == "murder", "the case names the real killer and victim")
	K.expect(f, not CrimePerson.alive(b), "the victim is gone from the town")
	K.expect(f, str(c["state"]) == "hidden" or str(c["state"]) == "open", "hidden or witnessed (%s)" % str(c["state"]))
	K.teardown()

func _gentle_never(f: Array) -> void:
	var w := C.town(10)
	C.quiet_witnesses()
	var ids: Array = C.adults()
	var a: int = int(ids[0])
	var b: int = int(ids[1])
	Story.townies[a]["traits"] = ["forgiving", "easygoing"]
	Story.townies[b]["traits"] = ["forgiving", "easygoing"]
	K.set_time(2, 12, 0)
	for d in 300:
		C.feud(a, b, 60.0)
		SimEnv.clock().total_minutes += 1440
		CrimeMurder.on_day()
	K.expect(f, JusticeState.counter("murder") == 0, "forgiving, easy-going folk never go that far in 300 days of feuding")
	# nobody is angry: nothing
	var w2 := C.town(10)
	for d2 in 300:
		SimEnv.clock().total_minutes += 1440
		CrimeMurder.on_day()
	K.expect(f, JusticeState.counter("murder") == 0, "a calm town has no murders")
	K.teardown()

func _player_prompt(f: Array) -> void:
	var w := C.town(10)
	C.quiet_witnesses()
	var ada = w.get_folk(1)
	ada.traits.append("hot_headed")
	ada.traits.append("jealous")
	var tid: int = int(C.adults()[0])
	JusticePlayer.auto = "step_in"
	K.set_time(2, 12, 0)
	for d in 120:
		C.feud(1, tid, 70.0)
		SimEnv.clock().total_minutes += 1440
		CrimeMurder.on_day()
		if CrimeMurder.rage_of(1, tid) >= 45.0 and JusticePlayer.log.size() > 0:
			break
	var asked: bool = false
	for e in JusticePlayer.log:
		if str(e["title"]).find("grudge") >= 0 and (e["options"] as Array).has("step_in"):
			asked = true
	K.expect(f, asked, "a player folk who is consumed by rage gets a clear warning prompt with a way to step in")
	K.expect(f, CrimeMurder.rage_of(1, tid) < 45.0 and ada.has_buff("calmed_down"), "stepping in calms things down (rage %.0f)" % CrimeMurder.rage_of(1, tid))
	K.expect(f, JusticeState.counter("murder") == 0, "no murder happened")
	# ignoring the final warning: the countdown is queued and the prompt shows up; defusing before it is due averts it
	JusticePlayer.auto = "ignore"
	JusticePlayer.log.clear()
	JusticeState.grudges[CrimeMurder.key(1, tid)] = {"rage": 90.0, "since": 1, "warned": 1, "vow": true}
	CrimeMurder._begin(1, tid)
	K.expect(f, JusticeState.pending.size() == 1 and str(JusticeState.pending[0]["kind"]) == "murder_due", "a last countdown starts")
	CrimeMurder.defuse(1, tid)
	JusticeState.pending[0]["due_min"] = SysUtil.now()
	CrimeFlow.on_minute()
	K.expect(f, JusticeState.counter("murder") == 0 and K.count_events("murder_averted") == 1, "stepping in before the deadline averts it")
	K.teardown()

func _assault(f: Array) -> void:
	var w := C.town(10)
	var ids: Array = C.adults()
	var a: int = int(ids[0])
	var b: int = int(ids[1])
	Story.townies[a]["traits"] = ["hot_headed"]
	C.feud(a, b, 80.0)
	var made: int = 0
	JusticeState.sect("assault")["police_called"] = 1.0
	for i in 400:
		CrimeAssault.on_argument(a, b, 4)
		if JusticeState.counter("assault") > 0:
			made += 1
			break
	K.expect(f, made == 1, "a screaming argument between hot-headed enemies can end in a fight")
	var c: Dictionary = JusticeState.cases[JusticeState.cases.keys()[0]]
	K.expect(f, str(c["kind"]) == "assault" and int(c["culprit"]) == a and str(c["state"]) == "open", "assault case: culprit known, police called")
	K.expect(f, RelationshipService.value(a, b, "friendship") < -80.0 or RelationshipService.value(a, b, "trust") < 0.0, "relationships suffer")
	JusticeState.cases.clear()
	JusticeState.counters.clear()
	var calm: int = 0
	for i in 400:
		CrimeAssault.on_argument(a, b, 1)
		calm += JusticeState.counter("assault")
	K.expect(f, calm == 0, "mere bickering never turns violent")
	K.teardown()

func _robbery(f: Array) -> void:
	var w := C.town(10)
	var ids: Array = C.adults()
	var v: int = int(ids[0])
	Story.townies[v]["coins"] = 400
	var before: int = CrimePerson.coins(v)
	var robber: int = CrimeBurglary.pick_burglar("street", [v])
	K.expect(f, robber >= 1000 and robber != v, "a townie is picked as the robber")
	var c: Dictionary = CrimeStreet._resolve(v, robber, "hand", true)
	K.expect(f, CrimePerson.coins(v) < before and str(c["kind"]) == "robbery" and int(c["stolen_coins"]) > 0, "handing over loses coins (%d -> %d)" % [before, CrimePerson.coins(v)])
	# the player is offered the choice
	JusticePlayer.log.clear()
	JusticePlayer.auto = "run"
	var r: Dictionary = CrimeStreet.on_incident({"subject": IncidentSubject.of_folk(w.get_folk(1)), "statistical": false, "forced": true, "folk": w.get_folk(1)}, {})
	var asked: bool = false
	for e in JusticePlayer.log:
		if (e["options"] as Array).has("hand") and (e["options"] as Array).has("run") and (e["options"] as Array).has("fight"):
			asked = true
	K.expect(f, asked and r.has("text"), "a player folk chooses: hand over / run / fight")
	K.teardown()

func _serial(f: Array) -> void:
	var pattern_runs: int = 0
	var caught_in_cap: int = 0
	var runs: int = 4
	var max_victims: int = 0
	for round in runs:
		var w := C.town(14)
		JusticeState.seed_rng(900 + round)
		var killer: int = int(C.adults()[0])
		CrimeSerial.start(killer)
		K.set_time(2, 8, 0)
		for d in 200:
			if not CrimeSerial.active():
				break
			C.days(1)
		var s: Dictionary = JusticeState.serial
		var n: int = (s["victims"] as Array).size()
		max_victims = maxi(max_victims, n)
		if bool(s.get("caught", false)) and n <= int(JusticeState.sect("serial").get("victim_cap", 5)):
			caught_in_cap += 1
		if int(s.get("pattern_day", -1)) >= 0:
			pattern_runs += 1
		K.teardown()
	K.expect(f, caught_in_cap == runs, "the serial killer is caught within the victim cap (%d of %d, most victims %d)" % [caught_in_cap, runs, max_victims])
	K.expect(f, pattern_runs >= 1, "pattern detection fired in %d of %d runs" % [pattern_runs, runs])