class_name CourtScene
extends RefCounted
## Task 46: a trial played out in the courtroom of the Fernwood Courthouse (map lot "courthouse", level 1). The cast are real people: the judge and the lawyer are
## townies with those careers, the six jurors are townies chosen when the trial opens (JusticeTrial.jury then counts THEM), townie witnesses and the accused are
## walked in too. Townies appear at the street gate as crowd NPCs (Crowd.spawn_npc), climb to the courtroom and sit for the hours of the trial; a resident (the
## player's person) is brought by fast travel and sits at the dock. During the trial a few lines are spoken (a speech bubble over the speaker; a toast when one
## of the player's people is in court), then the verdict is read (JusticeTrial.run).
##   CourtScene.begin(c, hours)     the trial opens: cast, seats, queued steps      CourtScene.step(p)    one queued step (called from CrimeFlow.run_pending)
##   CourtScene.jurors(c)           the stored jurors of the case (townie / resident ids)      CourtScene.available()   is there a courthouse lot to play it in?

const LOT := "courthouse"
const LEVEL := 1
const SIT_DEFS := {"chair": "sit_chair", "dining_chair": "sit_chair", "pew": "sit_chair", "sofa": "sit_sofa", "armchair": "sit_armchair", "judge_bench": "sit_chair"}

static func available() -> bool:
	var w = WorldIface.world()
	return w != null and "regions" in w and w.regions.has_regions() and NeighborhoodLots.rect_of(LOT).size != Vector2i.ZERO

## The seats of the courtroom, nearest the bench first: {bench: obj, seats: [obj ...]} (level-1 furniture inside the lot).
static func seats() -> Dictionary:
	var rc: Rect2i = NeighborhoodLots.rect_of(LOT)
	var bench = null
	var list: Array = []
	for o in WorldIface.objects_near(rc.get_center(), 80):
		if not rc.has_point(o.tile) or int(o.level if "level" in o else 0) != LEVEL:
			continue
		var d: String = str(o.def_id) if "def_id" in o else str(o.def)
		if d == "judge_bench":
			bench = o
		elif SIT_DEFS.has(d):
			list.append(o)
	if bench == null:
		return {"bench": null, "seats": []}
	var at: Vector2i = bench.tile
	list.sort_custom(func(a, b): return a.tile.distance_squared_to(at) < b.tile.distance_squared_to(at))
	return {"bench": bench, "seats": list}

static func _sit(f, obj, minutes: float, level_hint: int = LEVEL) -> bool:
	var d: String = str(obj.def_id) if "def_id" in obj else str(obj.def)
	var ir: Interaction = Interaction.create(str(SIT_DEFS.get(d, "sit_chair")), f, int(obj.id), true)
	if ir == null:
		return false
	ir.def = ir.def.duplicate(true)
	ir.def["duration_min"] = minutes
	ir.def["per_min"] = {}
	ir.def["cooldown_min"] = 0
	f.enqueue(ir)
	return true

## A townie of the court (judge, lawyer, juror, witness) walks in at the gate and sits. Returns the Folk (or null).
static func _seat_townie(tid: int, obj, role: String, minutes: float) -> Folk:
	var t: Dictionary = Story.townies.get(tid, {})
	if t.is_empty():
		return null
	var f: Folk = Crowd.spawn_npc(t, LOT, Venues.type_of_lot(LOT), int(minutes) + 90, true)
	if f == null:
		return null
	f.set_meta("court", role)
	_sit(f, obj, minutes)
	return f

## A resident (the player's person, or any household member who is on trial or a witness): brought to the courthouse at once and sent to a seat.
static func _bring(fid: int, obj, role: String, minutes: float) -> void:
	var f = SysUtil.folk(fid)
	if f == null or not SysUtil.is_resident(f):
		return
	if Away.is_away(fid):
		Away.recall(fid, "court")
	var r: Dictionary = Neighborhood.travel([fid], LOT, {"instant": true, "free": true, "silent": true, "quiet": true})
	if not bool(r.get("ok", false)):
		return
	f.set_meta("court", role)
	_sit(f, obj, minutes)

static func _townie_with_career(career: String) -> int:
	for t in Story.alive_townies():
		if str(t.get("career", "")) == career and Story.stage_of(t) in ["adult", "elder"]:
			return int(t["id"])
	return -1

## Six jurors, picked once when the trial opens (adults who are not the accused, not in custody, not residents the player plays).
static func pick_jurors(c: Dictionary) -> Array:
	if (c.get("jurors", []) as Array).size() > 0:
		return c["jurors"]
	var pid: int = int(c["accused"])
	var pool: Array = CrimePerson.everyone().filter(func(p): return p != pid and CrimePerson.is_adult(p) and not CrimePerson.in_custody(p) and not CrimePerson.is_player(p) and int(p) != int(c.get("victim", -1)))
	var out: Array = []
	var n: int = mini(int(JusticeState.sect("trial").get("jurors", 6)), pool.size())
	for i in n:
		var j: int = int(pool[JusticeState.rng.randi_range(0, pool.size() - 1)])
		pool.erase(j)
		out.append(j)
	c["jurors"] = out
	return out

static func jurors(c: Dictionary) -> Array:
	return c.get("jurors", [])

## The trial opens. Returns true when it is played in the room (the caller then does not hold the player's people away).
static func begin(c: Dictionary, hours: float) -> bool:
	var jur: Array = pick_jurors(c)
	if not available():
		return false
	var minutes: float = hours * 60.0
	var s: Dictionary = seats()
	if s["bench"] == null:
		return false
	var seat_list: Array = (s["seats"] as Array).duplicate()
	var cast: Array = []          # [{id, role}] in the order of the seats after the judge
	var pid: int = int(c["accused"])
	var judge: int = _townie_with_career("judge")
	var lawyer: int = _townie_with_career("lawyer")
	var roles: Array = []
	if lawyer >= 0 and lawyer != pid:
		roles.append({"id": lawyer, "role": "lawyer"})
	roles.append({"id": pid, "role": "accused"})
	for w in (c.get("witnesses", []) as Array):
		if int(w) != pid and not roles.any(func(r): return int(r["id"]) == int(w)):
			roles.append({"id": int(w), "role": "witness"})
	for j in jur:
		if not roles.any(func(r): return int(r["id"]) == int(j)):
			roles.append({"id": int(j), "role": "juror"})
	var seated: Array = []
	if judge >= 0:
		var jf: Folk = _seat_townie(judge, s["bench"], "judge", minutes)
		if jf != null:
			seated.append(judge)
	for r in roles:
		if seat_list.is_empty():
			break
		var who: int = int(r["id"])
		var obj = seat_list.pop_front()
		if SysUtil.folk(who) != null and SysUtil.is_resident(SysUtil.folk(who)):
			_bring(who, obj, str(r["role"]), minutes)
			seated.append(who)
		elif Story.townies.has(who):
			if _seat_townie(who, obj, str(r["role"]), minutes) != null:
				seated.append(who)
	c["court"] = {"seated": seated, "judge": judge, "lawyer": lawyer, "lines": 0}
	var base: int = SysUtil.now()
	JusticeState.queue({"kind": "court_step", "case": int(c["id"]), "step": "open", "due_min": base + 25})
	var tests: Array = (c.get("testimony", []) as Array)
	var k: int = 0
	for e in tests:
		k += 1
		JusticeState.queue({"kind": "court_step", "case": int(c["id"]), "step": "testify", "who": int(e["pid"]), "side": str(e["side"]), "due_min": base + 25 + 20 * k})
	JusticeState.queue({"kind": "court_step", "case": int(c["id"]), "step": "retire", "due_min": base + int(minutes) - 30})
	return true

static func _in_court(c: Dictionary) -> bool:
	for fid in (c.get("court", {}).get("seated", []) as Array):
		if CrimePerson.is_player(int(fid)):
			return true
	return false

static func _speak(c: Dictionary, who: int, line: String) -> void:
	var f = CrimePerson.folk(who)
	if f == null:
		for cf in Crowd.crowd_folk():
			if int(cf.get_meta("townie_id", -1)) == who:
				f = cf
	if f != null:
		SimEnv.emit("speech", int(f.id), line, -1)
	if _in_court(c) or CaseStore.household_involved(c):
		SysUtil.notify("%s: %s" % [CrimePerson.name_of(who), line], "story")

## One queued step of a trial in the room.
static func step(p: Dictionary) -> void:
	var c: Dictionary = CaseStore.get_case(int(p.get("case", -1)))
	if c.is_empty() or str(c["state"]) != "trial":
		return
	var court: Dictionary = c.get("court", {})
	var judge: int = int(court.get("judge", -1))
	var an: String = CrimePerson.name_of(int(c["accused"]))
	match str(p.get("step", "")):
		"open":
			if judge >= 0:
				_speak(c, judge, "Be seated. The court is hearing the case of %s." % an)
		"testify":
			var w: int = int(p["who"])
			_speak(c, w, "I saw what I saw, and I will say so." if str(p.get("side", "")) == "against" else "I have known %s a long time, and this is not like them." % an)
		"retire":
			if judge >= 0:
				_speak(c, judge, "The jury will retire to consider its verdict.")

## The verdict is read: the judge says it, then everybody leaves (crowd NPCs walk out at once, residents go free of the room).
static func verdict_read(c: Dictionary) -> void:
	var court: Dictionary = c.get("court", {})
	if court.is_empty():
		return
	var judge: int = int(court.get("judge", -1))
	var v: String = str(c.get("verdict", ""))
	var line: String = {"guilty": "The jury finds the accused guilty.", "not_guilty": "The jury finds the accused not guilty.", "mistrial": "The jury cannot agree. This is a mistrial.", "plea": "The plea is accepted."}.get(v, "The court is adjourned.")
	if judge >= 0:
		_speak(c, judge, line)
	for cf in Crowd.crowd_folk():
		if str(cf.get_meta("court", "")) != "":
			Crowd.start_leaving(cf)
