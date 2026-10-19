class_name CrimeSecurityFootage
extends RefCounted
## Security cameras keep a FOOTAGE LOG per place. A crime on a watched place may be caught on camera: `footage` (0..0.9) on the case is HARD
## evidence only the real culprit leaves (CaseEvidence.hard), so it raises identification, arrest and conviction. Skilled thieves can dodge the
## camera (stealth, a mask) or erase the recording (handiness, logic) - but a gap in the recording is itself a clue and tells the owner.
## The owner (or a guard) reviews the footage at a camera: that is how a hidden break-in gets noticed.

static func cfg() -> Dictionary:
	return CrimeSecurity.cfg().get("footage", {})

static func log_of(scene: String) -> Array:
	return CrimeLifeState.footage.get(scene, [])

## A crime happens at `scene`. Returns {"cameras", "caught", "clarity", "gap"}; the case gets `footage` (and a bit more trace for a gap).
static func capture(c: Dictionary, scene: String, culprit: int, masked: bool = false, tools: bool = false) -> Dictionary:
	var p: Dictionary = CrimeSecurity.profile_for(scene)
	var cams: int = int(p.get("cameras", 0))
	if cams <= 0 or culprit < 0:
		return {"cameras": 0, "caught": false, "clarity": 0.0, "gap": false}
	var k: Dictionary = cfg()
	var fx: Dictionary = CrimeSecurity.effects(p)
	var stealth: float = float(CrimeLifePath.skill(culprit, "stealth"))
	var dodge: float = minf(stealth * float(k.get("dodge_stealth", 0.06)), 0.6) + (float(k.get("dodge_mask", 0.5)) if masked else 0.0)
	var caught: bool = CrimeLifeState.chance(float(fx["footage"]) * (1.0 - clampf(dodge, 0.0, 0.95)))
	var clarity: float = 0.0
	var gap: bool = false
	if caught:
		var erase: float = minf(float(CrimeLifePath.skill(culprit, "handiness")) * float(k.get("erase_handiness", 0.05)) + float(CrimeLifePath.skill(culprit, "logic")) * float(k.get("erase_logic", 0.03))
			+ (0.15 if tools else 0.0), float(k.get("erase_cap", 0.7)))
		if CrimeLifeState.chance(erase):
			gap = true
			c["trace"] = minf(float(c.get("trace", 0.2)) + float(k.get("gap_tip", 0.12)), 1.0)
		else:
			clarity = clampf(float(k.get("quality", 0.55)) * CrimeLifeState.rng.randf_range(0.85, 1.15) + 0.1 * float(cams - 1), 0.1, 0.9)
			c["footage"] = clarity
	var entry: Dictionary = {"day": SysUtil.day(), "minute": SysUtil.now(), "case": int(c["id"]), "clarity": clarity, "gap": gap, "seen": caught}
	var lg: Array = CrimeLifeState.footage.get(scene, [])
	lg.append(entry)
	var cap: int = int(CrimeLifeState.sect("general").get("footage_cap", 24))
	while lg.size() > cap:
		lg.pop_front()
	CrimeLifeState.footage[scene] = lg
	return {"cameras": cams, "caught": caught and not gap, "clarity": clarity, "gap": gap}

## The owner looks at the recordings of `scene`: a hidden case with a clip (or a gap) is noticed and reported. Returns the cases noticed.
static func review(scene: String, reviewer: int) -> Array:
	var seen: Array = []
	for e in log_of(scene):
		var c: Dictionary = CaseStore.get_case(int(e.get("case", -1)))
		if c.is_empty() or bool(e.get("reviewed", false)):
			continue
		e["reviewed"] = true
		if float(e.get("clarity", 0.0)) > 0.0 or bool(e.get("gap", false)):
			if str(c["state"]) == "hidden":
				CaseDiscovery.report(c, reviewer, "noticed")
			if bool(e.get("gap", false)):
				CaseStore.note(c, "The camera recording has a gap exactly when it happened.")
			else:
				CaseStore.note(c, "A camera caught someone on the night.")
			seen.append(int(c["id"]))
	return seen

## Interaction hook (review_footage at a camera): the folk's own home lot.
static func on_review(folk_id: int) -> void:
	var hid: int = CrimePerson.hid(folk_id)
	if hid <= 0:
		return
	var found: Array = review("home:%d" % hid, folk_id)
	if found.is_empty():
		SysUtil.notify("Nothing odd on the recordings.", "info")
	else:
		SysUtil.notify("The recordings show something: the police have been told.", "warn")

## Plain lines for the dialog: "day 12, 02:10 - someone on camera (clear)".
static func lines(scene: String) -> Array:
	var out: Array = []
	for e in log_of(scene):
		var m: int = int(e["minute"]) % 1440
		var when: String = "day %d, %02d:%02d" % [int(e["day"]), m / 60, m % 60]
		if bool(e.get("gap", false)):
			out.append("%s - the recording is missing for a stretch" % when)
		elif float(e.get("clarity", 0.0)) > 0.0:
			out.append("%s - someone on camera (%s)" % [when, "clear" if float(e["clarity"]) > 0.55 else "blurry"])
		else:
			out.append("%s - something moved, nothing useful" % when)
	return out
