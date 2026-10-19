class_name CrimeLifeCasing
extends RefCounted
## Task 21: CASING a target. Watching a place builds up knowledge (0..1) of its guard rounds, cameras, alarm and safe. Knowledge makes the job
## easier (CrimeLifeRoll: fewer failures, less chance of being noticed, and an alert guard's gaps are known), fades after a while, and a careless
## watcher can be noticed doing it (heat). Knowledge is per person and target; the target string is the roll scene ("biz:bank", "town:3").

static func cfg() -> Dictionary:
	return CrimeLifeState.sect("casing")

static func amount(pid: int, target: String) -> float:
	return CrimeLifeRoll.cased(pid, target)

## Start casing as a Folk: takes time away from home. Returns {ok, msg}.
static func start(pid: int, target: String) -> Dictionary:
	var f = CrimePerson.folk(pid)
	if f == null or not CrimePerson.is_player(pid) or SysUtil.is_away(f) or CrimePerson.in_custody(pid):
		return {"ok": false, "msg": "Not right now."}
	if not CrimeLifePath.is_member(pid):
		CrimeLifePath.join(pid, "chose")
	var mins: int = int(cfg().get("minutes", 90))
	Away.send(f, float(mins), "errand", {"label": "Watching a place"})
	CrimeLifeState.queue({"kind": "case", "pid": pid, "target": target, "due_min": SysUtil.now() + mins})
	return {"ok": true, "msg": "%s goes to watch the place." % f.name}

## One session of casing, applied now (also used for townies and the tests). Returns {gain, amount, spotted}.
static func session(pid: int, target: String) -> Dictionary:
	var k: Dictionary = cfg()
	var g: Array = k.get("gain", [0.18, 0.3])
	var gain: float = CrimeLifeState.rng.randf_range(float(g[0]), float(g[1])) + float(k.get("stealth_gain", 0.03)) * float(CrimeLifePath.skill(pid, "stealth"))
	var rec: Dictionary = CrimeLifeState.cased.get(CrimeLifeRoll.cased_key(pid, target), {})
	var now_amt: float = CrimeLifeRoll.cased(pid, target)
	rec["amount"] = clampf(now_amt + gain, 0.0, 1.0)
	rec["day"] = SysUtil.day()
	CrimeLifeState.cased[CrimeLifeRoll.cased_key(pid, target)] = rec
	CrimeLifePath.train(pid, "stealth", 3.0)
	var spotted: bool = CrimeLifeState.chance(float(k.get("spotted", 0.07)) * (1.0 - 0.07 * float(CrimeLifePath.skill(pid, "stealth"))))
	var m: Dictionary = CrimeLifePath.member(pid)
	if spotted and not m.is_empty():
		m["heat"] = float(m.get("heat", 0.0)) + float(k.get("spotted_heat", 2.0))
	if CrimePerson.is_player(pid):
		SysUtil.notify("%s watched %s. Knowledge of the place: %s.%s" % [CrimePerson.name_of(pid), label(target), word(float(rec["amount"])), " Someone may have noticed." if spotted else ""], "warn" if spotted else "info")
	return {"gain": gain, "amount": float(rec["amount"]), "spotted": spotted}

static func word(a: float) -> String:
	if a < 0.2:
		return "next to nothing"
	if a < 0.5:
		return "a fair idea"
	if a < 0.8:
		return "good"
	return "every habit of the place"

static func label(target: String) -> String:
	if target.begins_with("biz:"):
		var key: String = target.get_slice(":", 1)
		var t: Dictionary = (CrimeLifeState.sect("heists").get("targets", {}) as Dictionary).get(key, {})
		return str(t.get("label", "the " + key))
	if target.begins_with("town:"):
		return CaseStore.house_label(target)
	return "the place"

## What casing has taught so far, in plain lines (gated by how well the place is known).
static func report(pid: int, target: String) -> Array:
	var a: float = amount(pid, target)
	var p: Dictionary = CrimeSecurity.profile_for(target)
	var out: Array = []
	if a >= 0.2:
		out.append("Locks: %s." % ["none to speak of", "basic", "reinforced", "high-security"][int(p["lock"])])
	if a >= 0.35:
		out.append("Cameras: %d." % int(p["cameras"]) if int(p["cameras"]) > 0 else "No cameras.")
	if a >= 0.5:
		out.append("Alarm: %s." % ("monitored by a company" if bool(p["monitored"]) else ("yes" if bool(p["alarm"]) else "none")))
	if a >= 0.65 and int(p["guards"]) > 0:
		out.append("Guards: %d. Their round leaves a gap you can use." % int(p["guards"]))
	elif a >= 0.65:
		out.append("Nobody guards it.")
	if a >= 0.8 and int(p["safe"]) > 0:
		out.append("The safe is %s." % ("a simple one" if int(p["safe"]) == 1 else "a vault"))
	return out
