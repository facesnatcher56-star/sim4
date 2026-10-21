class_name CrimeIntrusion
extends RefCounted
## Physical access for crimes against a person (owner rule, 34 / 43): a murder or an attack only happens where BOTH people are. A killer who is not
## where the victim is has to get there, and to a home has to get IN: three steps (approach, entry, reaching the victim), each stopped or not by the
## home's security (locks, alarm and monitoring, cameras, dog, guard, lights, a neighbourhood watch, people awake) set against the culprit's DETERMINATION
## (the rage, a vengeful or hot-headed nature, the criminal path, a hired professional). Security beats an ordinary angry person almost always; only
## a very determined culprit has a real chance. Nothing here warns anybody: a failed attempt leaves a trace (a chronicle line, an alarm that rang) after the fact.
## Numbers: data/justice.json "intrusion". Callers: CrimeMurder.execute, CrimeSerial._kill_one.
##   CrimeIntrusion.gate(culprit, victim, opts{determination: 0..1}) -> {ok, scene, reason, entry}

static func cfg() -> Dictionary:
	return JusticeState.sect("intrusion")

## 0..1: how far this culprit will go.
static func determination(culprit: int, victim: int, opts: Dictionary = {}) -> float:
	if opts.has("determination"):
		return clampf(float(opts["determination"]), 0.0, 1.0)
	var c: Dictionary = cfg()
	var d: float = float(c.get("base", 0.25)) + float(c.get("rage_weight", 0.5)) * clampf(CrimeMurder.rage_of(culprit, victim) / 100.0, 0.0, 1.0)
	for t in (c.get("traits", {}) as Dictionary):
		if CrimePerson.has_trait(culprit, str(t)):
			d += float(c["traits"][t])
	if CrimeLifePath.is_member(culprit):
		d += float(c.get("path_member", 0.2))
	return clampf(d, 0.05, 1.0)

static func gate(culprit: int, victim: int, opts: Dictionary = {}) -> Dictionary:
	var wv: String = CrimePlace.where_now(victim)
	var wc: String = CrimePlace.where_now(culprit)
	if wv in ["work", "away", "unknown"]:
		return {"ok": false, "scene": "", "reason": "the victim is not anywhere the culprit can reach"}
	if CrimePerson.in_custody(culprit) or Hospital.is_in(culprit):
		return {"ok": false, "scene": "", "reason": "the culprit cannot go anywhere"}
	if CrimePlace.same_place(wc, wv) and wc not in ["work", "away", "unknown"]:
		return {"ok": true, "scene": wv, "reason": "", "entry": "together"}
	if wv == "street" or wv.begins_with("venue:"):
		return {"ok": true, "scene": wv, "reason": "", "entry": "public"}          # a public place: anyone can walk there
	return _break_in(culprit, victim, wv, opts)

## Approach, entry, reach: each step is stopped with chance s / (s + determination x k) where s is what the home puts in the way at that step.
static func _break_in(culprit: int, victim: int, scene: String, opts: Dictionary) -> Dictionary:
	var c: Dictionary = cfg()
	var d: float = determination(culprit, victim, opts)
	var night: bool = SysUtil.hour_f() >= 21.0 or SysUtil.hour_f() < 6.0
	var prof: Dictionary = CrimeSecurity.profile_for(scene)
	var fx: Dictionary = CrimeSecurity.effects(prof, night)
	var detect: float = float(fx["detect"]) - 1.0
	var awake: int = _awake_others(scene, victim)
	var steps: Array = [
		["approach", float(fx["abort"]) + (float(c.get("watch", 0.4)) if CrimeRate.watch_active() else 0.0) + float(c.get("patrol", 0.2)) * (1.0 - clampf(Police.patrol_factor(), 0.0, 1.0))],
		["entry", float(fx["difficulty"]) + 0.6 * detect],
		["reach", float(c.get("awake_each", 0.5)) * float(awake) + 0.4 * detect + (0.3 if CrimePlace.is_asleep(CrimePerson.folk(victim)) == false and CrimePerson.folk(victim) != null else 0.0)]]
	var k: float = float(c.get("k", 1.5))
	for st in steps:
		var s: float = float(st[1])
		if s > 0.0 and JusticeState.chance(s / (s + d * k)):
			_failed(culprit, victim, scene, str(st[0]), fx)
			return {"ok": false, "scene": "", "reason": "stopped at the %s" % str(st[0])}
	return {"ok": true, "scene": scene, "reason": "", "entry": "forced", "determination": d}

## People awake at the target other than the victim (their own sleep makes the reach easier).
static func _awake_others(scene: String, victim: int) -> int:
	if scene.begins_with("home:"):
		var n := 0
		for pid in CrimePlace.awake_at_home(int(scene.get_slice(":", 1))):
			if int(pid) != victim:
				n += 1
		return n
	return 0

## A failed attempt leaves a trace, never a warning: an alarm that rang is something people sense; the rest is found out later.
static func _failed(culprit: int, victim: int, scene: String, step: String, fx: Dictionary) -> void:
	var what: String = {"approach": "was seen off outside", "entry": "tried to force a way in", "reach": "got in but was driven off"}.get(step, "tried to get in")
	JusticeState.count("intrusion_stopped")
	SysUtil.game_event("intrusion_stopped", {"culprit": culprit, "victim": victim, "scene": scene, "step": step})
	if bool(fx.get("alarm", false)) and step != "approach" and scene.begins_with("home:") and CrimePerson.is_player(victim):
		SysUtil.notify("The alarm went off in the night. Whoever it was is gone.", "warn")
	ChronicleHook.note("attempt", "Someone %s at %s." % [what, "a house"], [], scene, 2, false)
