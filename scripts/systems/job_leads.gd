class_name JobLeads
extends RefCounted
## Task 51: finding work in person (data/job_leads.json). A business with an opening in a job done there (careers.json workplace = the lot's type) has a
## "Help wanted" card in its window (HelpWantedView); anyone working there can be asked, and they answer for real. People the pawn knows mention openings
## in a chat. Either one is a lead: that job can be applied for in person for a few days, phone or not (PhoneJobs.why_not reads it).
##   JobLeads.hiring_at(lot) -> [cid]   JobLeads.has(fid, cid)   JobLeads.careers(fid)   JobLeads.person_entries(f, target)   JobLeads.on_social_done(a, b, iid)

static var leads: Dictionary = {}          # fid -> {cid: last day it holds}
static var _told: Dictionary = {}          # pair key -> day a lead was last mentioned (not saved: a cooldown)

static func reset() -> void:
	leads = {}
	_told = {}

static func cfg() -> Dictionary:
	return SysUtil.table("job_leads")

static func _line(k: String, vars: Dictionary) -> String:
	var lines: Array = (cfg().get("lines", {}) as Dictionary).get(k, [""])
	var t: String = str(lines[PlayerPrompt._pick("leads|" + k, lines.size())])
	for v in vars:
		t = t.replace("{%s}" % v, str(vars[v]))
	return t

## The job in a few plain words, with its article ("a barista", "an athlete").
static func _job(cid: String) -> String:
	var w: String = str((cfg().get("job_words", {}) as Dictionary).get(cid, str(Careers.career_def(cid).get("label", cid)).to_lower()))
	return ("an " if w.left(1) in ["a", "e", "i", "o"] else "a ") + w

## Jobs done at this lot that have an opening this week.
static func hiring_at(lot: String) -> Array:
	var vt: String = Venues.type_of_lot(lot)
	if lot == "" or vt in ["home", ""]:
		return []
	EduJobs.refresh(SysUtil.day())
	return Careers.career_ids().filter(func(c): return str(Careers.career_def(str(c)).get("workplace", "")) == vt and EduJobs.openings(str(c)) > 0)

static func add(fid: int, cid: String) -> void:
	var m: Dictionary = leads.get(fid, {})
	m[cid] = SysUtil.day() + int(cfg().get("lead_days", 3)) - 1
	leads[fid] = m

static func has(fid: int, cid: String) -> bool:
	return int((leads.get(fid, {}) as Dictionary).get(cid, -1)) >= SysUtil.day()

static func careers(fid: int) -> Array:
	return (leads.get(fid, {}) as Dictionary).keys().filter(func(c): return has(fid, str(c)))

# ------------------------------------------------------------------ asking at the counter
static func person_entries(f, target) -> Array:
	if f == null or target == null or not Pawn.is_pawn(f) or not (target is Folk) or str(target.get_meta("staff", "")) == "":
		return []
	return [{"id": "ask_hiring", "label": "Ask if they're hiring", "category": "Ask", "enabled": true, "reason": "",
		"action": func(): WalkThen.go(f, WalkThen.near(target.tile), func(): ask(f, target))}]

static func ask(f, target) -> void:
	var fid: int = int(f.id)
	var who: String = str(target.name).get_slice(" (", 0)
	var open: Array = hiring_at(Neighborhood.lot_of(target))
	if open.is_empty():
		SysUtil.notify(_line("not_hiring", {"who": who}), "story")
		return
	var rows: Array = EduJobs.board_for(f).filter(func(r): return open.has(str(r["career"])))
	var cid: String = str(rows[0]["career"]) if not rows.is_empty() else str(open[0])
	add(fid, cid)
	var p: Dictionary = cfg().get("prompt", {})
	var text: String = _line("hiring", {"who": who, "job": _job(cid)})
	var opts: Array = [{"id": "apply", "label": str(p.get("apply", "Ask for the job"))}, {"id": "later", "label": str(p.get("later", "Not now"))}]
	JusticePlayer.ask(fid, str(p.get("title", "A job going")), text, opts, func(c):
		if str(c) == "apply":
			_apply(fid, cid, who), "later")

static func _apply(fid: int, cid: String, who: String) -> void:
	var r: Dictionary = EduJobs.apply(fid, cid)
	if not bool(r.get("ok", false)):
		SysUtil.notify(_line("turned_down", {"who": who}) if str(r.get("reason", "")).begins_with("Not yet") else str(r.get("reason", "")), "story")

# ------------------------------------------------------------------ word of mouth
## A chat with someone the pawn knows: now and then they mention an opening (their own workplace first, else anywhere in town).
static func on_social_done(a: int, b: int, iid: String) -> void:
	var wm: Dictionary = cfg().get("word_of_mouth", {})
	if not (wm.get("interactions", []) as Array).has(iid):
		return
	var pawn: int = a if CrimePerson.is_player(a) else (b if CrimePerson.is_player(b) else -1)
	var other: int = b if pawn == a else a
	if pawn < 0 or other < 0 or RelationshipService.value(pawn, other, "friendship") < float(wm.get("min_friendship", 15)):
		return
	var pk: String = SysUtil.pair_key(pawn, other)
	if SysUtil.day() - int(_told.get(pk, -999)) < int(wm.get("pair_cooldown_days", 3)) or SysUtil.rng.randf() >= float(wm.get("chance", 0.15)):
		return
	EduJobs.refresh(SysUtil.day())
	var pool: Array = Careers.career_ids().filter(func(c): return EduJobs.openings(str(c)) > 0 and str(c) != Careers.career_of(pawn) and not has(pawn, str(c)))
	if pool.is_empty():
		return
	var own: String = Careers.career_of(other)
	var cid: String = own if pool.has(own) else str(pool[SysUtil.rng.randi_range(0, pool.size() - 1)])
	_told[pk] = SysUtil.day()
	add(pawn, cid)
	var vt: String = str(Careers.career_def(cid).get("workplace", ""))
	var place: String = str((cfg().get("place_words", {}) as Dictionary).get(vt, Venues.label(vt).to_lower()))
	SysUtil.notify(_line("mention_own" if cid == own else "mention", {"who": SysUtil.folk_name(other).get_slice(" ", 0), "job": _job(cid), "place": place}), "story")

static func to_dict() -> Dictionary:
	return leads.duplicate(true)

static func from_dict(d: Dictionary) -> void:
	leads = {}
	for k in d:
		var m: Dictionary = {}
		for c in (d[k] as Dictionary):
			m[str(c)] = int(d[k][c])
		leads[int(k)] = m
