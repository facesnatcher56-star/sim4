class_name CrimeSerial
extends RefCounted
## The serial killer (one of the rarest events: ~0.001 per game year per town). An ordinary-looking townie picks ISOLATED targets: loners, the
## jobless, people with few friends. Disappearances are noticed slowly, but the system spots a PATTERN (several isolated people reported
## missing or found in a short time): a special investigation (more police, patrols), town-wide fear, headlines. Every killing raises the chance
## of a mistake (a witness, a link); the run ends in an arrest at the latest at `victim_cap`. Everything stays low-detail background drama.
## State lives in JusticeState.serial = {pid, victims[], cases[], start_day, next_kill, mistakes, hunt, pattern_day, caught}.

static func cfg() -> Dictionary:
	return JusticeState.sect("serial")

static func active() -> bool:
	return bool(JusticeState.serial.get("active", false))

## Handler of incident `serial_killer` (town scope, ~0.001 / year). Also callable directly by tests.
static func on_incident(ctx: Dictionary, _args: Dictionary) -> Dictionary:
	if JusticeState.enabled:
		start(-1)
	return {"text": ""}

## A townie becomes the killer. Returns the person id or -1.
static func start(pid: int = -1) -> int:
	if active():
		return -1
	if pid < 0:
		var ids: Array = []
		var w: Array = []
		for p in CrimePerson.townies_only():
			if not CrimePerson.is_adult(p) or CrimePerson.stage(p) == "elder" or CrimePerson.folk(p) != null:
				continue
			ids.append(p)
			w.append(1.0 + (1.0 if CrimePerson.has_trait(p, "loner") else 0.0) + (0.5 if not CrimePerson.has_job(p) else 0.0))
		var i: int = JusticeState.pick_index(w)
		if i < 0:
			return -1
		pid = int(ids[i])
	JusticeState.serial = {"pid": pid, "active": true, "victims": [], "cases": [], "start_day": SysUtil.day(), "next_kill": SysUtil.day() + JusticeState.rng.randi_range(3, 8),
		"mistakes": 0.0, "hunt": false, "pattern_day": -1, "caught": false}
	if Story.townies.has(pid):
		Story.townies[pid]["archetype"] = "serial"
	JusticeState.count("serial_starts")
	return pid

## 0..1: how few connections someone has (1 = nobody would miss them for long).
static func isolation(pid: int) -> float:
	var close: int = CrimePerson.close_alive(pid).size()
	var friends: int = CrimePerson.friends(pid).size()
	var s: float = 1.0 / (1.0 + float(close) * 1.5 + float(friends) * 0.4 + (1.2 if CrimePerson.has_job(pid) else 0.0))
	if CrimePerson.has_trait(pid, "loner"):
		s *= 1.3
	return clampf(s, 0.0, 1.0)

static func on_day() -> void:
	if not active():
		return
	var s: Dictionary = JusticeState.serial
	var killer: int = int(s["pid"])
	if not CrimePerson.alive(killer) or CrimePerson.in_custody(killer):
		s["active"] = false
		return
	if SysUtil.day() >= int(s["next_kill"]):
		_kill_one(s, killer)
	if not active():
		return
	# a chance each day that a mistake catches up with them; the hunt doubles it
	var p: float = float(s["mistakes"]) * float(cfg().get("catch_per_mistake", 0.12)) * (2.0 if bool(s["hunt"]) else 0.12)
	if (s["victims"] as Array).size() >= 1 and JusticeState.chance(p):
		caught()

static func _kill_one(s: Dictionary, killer: int) -> void:
	var ids: Array = []
	var w: Array = []
	for p in CrimePerson.everyone():
		if p == killer or not CrimePerson.is_adult(p) or CrimePerson.in_custody(p) or (s["victims"] as Array).has(p):
			continue
		if CrimePerson.career(p) in ["police_officer", "detective"]:
			continue
		var iso: float = isolation(p)
		if CrimePerson.is_player(p):
			iso *= float(cfg().get("player_mult", 0.3))
		ids.append(p)
		w.append(pow(iso, 2.0))
	var i: int = JusticeState.pick_index(w)
	if i < 0:
		s["active"] = false
		return
	var victim: int = int(ids[i])
	var scene: String = "street" if JusticeState.chance(0.5) else CrimePerson.home_key(victim)
	var c: Dictionary = CrimeMurder.kill(killer, victim, scene, "serial", {})
	c["serial"] = 1
	(s["victims"] as Array).append(victim)
	(s["cases"] as Array).append(int(c["id"]))
	s["mistakes"] = float(s["mistakes"]) + JusticeState.rng.randf_range(float(cfg().get("mistake_min", 0.15)), float(cfg().get("mistake_max", 0.4)))
	s["next_kill"] = SysUtil.day() + JusticeState.rng.randi_range(int(cfg().get("gap_min", 4)), int(cfg().get("gap_max", 12)))
	# each killing leaves a little more for the police to find in every earlier case
	for cid in s["cases"]:
		var cc: Dictionary = CaseStore.get_case(int(cid))
		if not cc.is_empty():
			cc["tips"] = minf(float(cc["tips"]) + 0.05, 0.6)
	if (s["victims"] as Array).size() >= int(cfg().get("victim_cap", 5)):
		caught()

## Called by CaseDiscovery on every missing report or body found: spots the pattern.
static func on_missing_report(c: Dictionary) -> void:
	var k: Dictionary = cfg()
	var window: int = int(k.get("pattern_window_days", 45))
	var n: int = 0
	var iso_sum: float = 0.0
	for o in CaseStore.in_state(["open", "cold", "arrested", "charged", "trial"]):
		if str(o["kind"]) in ["murder", "serial", "manslaughter"] and SysUtil.day() - int(o.get("disc_day", -999)) <= window and int(o["victim"]) >= 0:
			var iso: float = isolation(int(o["victim"]))
			if iso >= float(k.get("isolated_at", 0.45)):
				n += 1
				iso_sum += iso
	if n >= int(k.get("pattern_count", 3)) and int(JusticeState.serial.get("pattern_day", -1)) < 0:
		_pattern_found(n)

static func _pattern_found(n: int) -> void:
	if not JusticeState.serial.has("pid"):
		JusticeState.serial = {"pid": -1, "active": false, "victims": [], "cases": [], "start_day": SysUtil.day(), "mistakes": 0.0, "caught": false}
	JusticeState.serial["pattern_day"] = SysUtil.day()
	JusticeState.serial["hunt"] = true
	JusticeState.uneasy_until = maxi(JusticeState.uneasy_until, SysUtil.day() + int(cfg().get("fear_days", 30)))
	for r in SysUtil.residents():
		r.add_buff("uneasy_at_night")
	var text: String = "Police link %d disappearances: lonely people seem to be targeted. Folk are told to stay in after dark." % n
	ChronicleHook.note("serial_pattern", text, [], "", 5, true)
	SysUtil.notify(text, "warn")
	SysUtil.game_event("serial_pattern", {"count": n})

static func is_killer(pid: int) -> bool:
	return JusticeState.serial.has("pid") and int(JusticeState.serial["pid"]) == pid and not bool(JusticeState.serial.get("caught", false))

## The killer was arrested (by the pattern hunt, a mistake or the ordinary investigation of one case): the run is over and every
## killing joins that one major case.
static func mark_caught(main: Dictionary) -> void:
	var s: Dictionary = JusticeState.serial
	s["active"] = false
	s["caught"] = true
	s["hunt"] = false
	var joined: Array = []
	for cid in s.get("cases", []):
		if int(cid) != int(main["id"]):
			joined.append(int(cid))
			var o: Dictionary = CaseStore.get_case(int(cid))
			if not o.is_empty():
				if not bool(o.get("found", true)):
					CaseDiscovery._found(o, "search")
				if str(o["state"]) == "hidden":
					o["state"] = "open"
	main["joined"] = joined
	main["counts"] = (s.get("cases", []) as Array).size()
	main["tips"] = 1.0
	main["progress"] = 1.0
	if not bool(main.get("found", true)):
		CaseDiscovery._found(main, "search")
	if str(main["state"]) == "hidden":
		main["state"] = "open"
	var killer: int = int(s["pid"])
	var text: String = "%s has been arrested for the disappearances. The town can breathe again." % CrimePerson.name_of(killer)
	ChronicleHook.note("serial_arrest", text, [killer], "", 5, true)
	SysUtil.notify(text, "story")
	JusticeState.uneasy_until = SysUtil.day()
	for r in SysUtil.residents():
		r.remove_buff("uneasy_at_night")

## Caught by a mistake (or the victim cap): one arrest for the whole run.
static func caught() -> void:
	var s: Dictionary = JusticeState.serial
	if not bool(s.get("active", false)):
		return
	var cases: Array = s.get("cases", [])
	if cases.is_empty():
		s["active"] = false
		return
	var main: Dictionary = CaseStore.get_case(int(cases[cases.size() - 1]))
	if main.is_empty():
		s["active"] = false
		return
	JusticeProcess.arrest(main, int(s["pid"]))
