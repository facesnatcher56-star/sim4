class_name SoloOpening
extends RefCounted
## Task 61A: the first week of a solo game, made of systems that already exist (data/solo.json "opening"). Each moment is said once:
##   the landlord's note on the first morning (the real first rent and its day), the neighbour who knocks to say hello (a StoryVisits visit),
##   a Help wanted card at the business nearest home (a real opening there), and one moment from the background picked at creation: a loan's
##   first payment, a probation check-in in the calendar, the Kiln Quarter contact, or a job lead someone passes on.
## Task 61c: in week 2 each background's moment has a second beat that depends on what the player did (follow); the neighbour comes back with a
## reason (a word about the landlord, an invitation); and the storyteller tilts one real early problem (a burst pipe, a cold) for a few days.
##   SoloOpening.begin(hid)   on_hour(h)   on_minute() (the check-in only)   said: also holds SoloTeach's first-time lines

static var start_day: int = 1
static var said: Dictionary = {}          # moment id -> day it happened
static var neighbour: int = -1
static var checkin: Dictionary = {}       # {day, hours, lot} while a probation check-in is pending

static func reset() -> void:
	start_day = 1
	said = {}
	neighbour = -1
	checkin = {}

static func cfg() -> Dictionary:
	return (SoloCfg.sect("opening") as Dictionary)

static func once(id: String) -> bool:
	if said.has(id):
		return false
	said[id] = SysUtil.day()
	return true

static func _fill(t: String, vars: Dictionary) -> String:
	for v in vars:
		t = t.replace("{%s}" % v, str(vars[v]))
	return t

static func _first(name: String) -> String:
	return name.get_slice(" ", 0)

# ------------------------------------------------------------------ the start
static func begin(hid: int) -> void:
	reset()
	start_day = SysUtil.day()
	neighbour = _nearest_neighbour()
	_help_wanted_near_home()

## The adult townie living closest to the pawn's home lot.
static func _nearest_neighbour() -> int:
	var home: Rect2i = NeighborhoodLots.rect_of(Neighborhood.HOME)
	var best: int = -1
	var best_d: float = INF
	for t in Story.alive_townies():
		if not (Story.stage_of(t) in ["adult", "elder"]):
			continue
		var lot: String = str(HousingProps.get_prop(str(t.get("home_prop", ""))).get("lot", ""))
		if lot == "" or lot == Neighborhood.HOME:
			continue
		var d: float = Vector2(NeighborhoodLots.rect_of(lot).get_center()).distance_to(Vector2(home.get_center()))
		if d < best_d:
			best_d = d
			best = int(t["id"])
	return best

## The business nearest home that has staff at the front and does a job someone new can start in: it is hiring this week.
static func _help_wanted_near_home() -> void:
	var home: Vector2 = Vector2(NeighborhoodLots.rect_of(Neighborhood.HOME).get_center())
	var best: String = ""
	var best_cid: String = ""
	var best_d: float = INF
	for lot in Neighborhood.lot_ids():
		var vt: String = Venues.type_of_lot(str(lot))
		if vt in ["home", ""] or StaffPosts.front(str(lot)).is_empty():
			continue
		for cid in Careers.career_ids():
			if str(Careers.career_def(str(cid)).get("workplace", "")) != vt or not (Careers.level_def(str(cid), 1).get("requires", {}) as Dictionary).is_empty():
				continue
			var d: float = Vector2(NeighborhoodLots.rect_of(str(lot)).get_center()).distance_to(home)
			if d < best_d:
				best_d = d
				best = str(lot)
				best_cid = str(cid)
	if best_cid != "":
		EduJobs.refresh(SysUtil.day())
		EduState.board["openings"][best_cid] = maxi(EduJobs.openings(best_cid), 1)

# ------------------------------------------------------------------ the clock
static func on_hour(h: int) -> void:
	if not SoloHome.active:
		return
	var fid: int = Pawn.of()
	var f = SysUtil.folk(fid)
	if f == null:
		return
	var d: int = SysUtil.day() - start_day
	var c: Dictionary = cfg()
	var ll: Dictionary = c.get("landlord", {})
	if d >= int(ll.get("day", 0)) and h >= int(ll.get("hour", 9)) and d <= 1 and once("landlord"):
		_landlord_note(ll)          # rent is real and due: the one fixed moment left (task 66)

## Task 66: the background's moments are no longer on fixed days. They are situations the involvement director (Involve) may pick, weighted
## to early in the game: the first one once a day has passed, its follow-up some days after the first was said. [] = none waiting.
static func beats(fid: int) -> Array:
	var out: Array = []
	var d: int = SysUtil.day() - start_day
	var moments: Dictionary = cfg().get("moments", {})
	var keys: Array = [str((Creation.picks.get(fid, {}) as Dictionary).get("background", ""))] + ((Creation.picks.get(fid, {}) as Dictionary).get("flaws", []) as Array)
	for k in keys:
		var m: Dictionary = moments.get(str(k), {})
		if m.is_empty():
			continue
		if not said.has("bg_" + str(k)):
			if d >= mini(int(m.get("day", 1)), 1):
				out.append("bg_" + str(k))
		elif not (m.get("follow", {}) as Dictionary).is_empty() and not said.has("bgf_" + str(k)) and SysUtil.day() - int(said["bg_" + str(k)]) >= 3:
			out.append("bgf_" + str(k))
	return out

static func fire_beat(fid: int, beat: String) -> bool:
	var k: String = beat.trim_prefix("bgf_") if beat.begins_with("bgf_") else beat.trim_prefix("bg_")
	var m: Dictionary = (cfg().get("moments", {}) as Dictionary).get(k, {})
	if m.is_empty() or not once(beat):
		return false
	if beat.begins_with("bgf_"):
		_follow(fid, m.get("follow", {}))
	else:
		_moment(fid, m)
	return true

static func _landlord_note(ll: Dictionary) -> void:
	var p: Dictionary = SoloHome.prop()
	if p.is_empty() or str(p.get("tenant_kind", "")) != "player":
		return
	var who: String = Story.name_of(int(p.get("owner", -1))) if str(p.get("owner_kind", "")) == "townie" else "the letting agent"
	var due_day: int = HousingRent.next_cycle + 3
	var paid_all: bool = not p.has("first_rent_share") and HousingRent.next_cycle - SysUtil.day() >= 7
	var line: String = str(ll.get("line_paid" if paid_all else "line", ""))
	var due: String = Seasons.weekday_long(HousingRent.next_cycle if paid_all else due_day)
	SysUtil.notify(_fill(line, {"who": who, "due": due, "amount": int(p.get("rent", 0)) if paid_all else SoloRent.next_rent(p)}), "bill")

static func _moment(fid: int, m: Dictionary) -> void:
	match str(m.get("kind", "")):
		"loan":
			for l in BankAccounts.loans:
				if int(l["hid"]) == SoloHome.hid() and str(l["kind"]) == str(m.get("lender", "")):
					SysUtil.notify(_fill(str(m["line"]), {"pay": int(round(float(l["payment"]))), "due": Seasons.weekday_long(int(l["next_due"]))}), "bill")
					return
		"probation":
			var day: int = start_day + int(m.get("on_day", 3))
			var hrs: Array = m.get("hours", [10, 16])
			checkin = {"day": day, "hours": hrs, "lot": str(m.get("lot", "police")), "done": str(m.get("done", "")), "missed": str(m.get("missed", "")),
				"warning": str(m.get("warning", "")), "every": int(m.get("every_days", 7)), "misses": 0, "over": str(m.get("over", "")),
				"label": "Probation check-in, %d:00-%d:00" % [int(hrs[0]), int(hrs[1])]}
			if int(JusticeState.probation.get(fid, -1)) < SysUtil.day():
				JusticeState.probation[fid] = SysUtil.day() + int(m.get("probation_days", 60))          # the sentence's probation, now on file
			CalendarBook.add(fid, day, float(hrs[0]), str(checkin["lot"]), "Probation check-in, %d:00-%d:00" % [int(hrs[0]), int(hrs[1])], "probation")
			SysUtil.notify(_fill(str(m["line"]), {"when": "%s, %d:00-%d:00" % [Seasons.weekday_long(day), int(hrs[0]), int(hrs[1])]}), "story")
		"contact":
			var cid: int = int((Creation.picks.get(fid, {}) as Dictionary).get("contact_id", -1))
			if cid < 0:
				return
			var line: String = str(m["line"]) if PhoneOwn.block(fid) == "" else str(m.get("line_no_phone", m["line"]))
			SysUtil.notify(_fill(line, {"who": _first(Story.name_of(cid))}), "story")
		"lead":
			var career: String = str(m.get("career", ""))
			if Careers.career_def(career).is_empty():
				return
			EduJobs.refresh(SysUtil.day())
			EduState.board["openings"][career] = maxi(EduJobs.openings(career), 1)
			JobLeads.add(fid, career)
			var who: int = neighbour if str(m.get("who", "")) == "neighbour" else _someone(fid)
			var vt: String = str(Careers.career_def(career).get("workplace", ""))
			var place: String = str((JobLeads.cfg().get("place_words", {}) as Dictionary).get(vt, Venues.label(vt).to_lower()))
			SysUtil.notify(_fill(str(m["line"]), {"who": _first(Story.name_of(who)) if who >= 0 else "Someone", "place": place}), "story")

## The second beat of a background's week: only when what the player did (or did not do) calls for it.
static func _follow(fid: int, fl: Dictionary) -> void:
	match str(fl.get("kind", "")):
		"loan_due":          # the loan's first payment went out (a missed one has the bank's own line)
			for l in BankAccounts.loans:
				if int(l["hid"]) == SoloHome.hid() and str(l["kind"]) == str(fl.get("lender", "")) and int(l.get("missed", 0)) == 0 and int(l["next_due"]) > SysUtil.day() - 1:
					SysUtil.notify(_fill(str(fl["line"]), {"pay": int(round(float(l["payment"])))}), "bill")
					return
		"lender_again":
			for l in BankAccounts.loans:
				if int(l["hid"]) == SoloHome.hid() and str(l["kind"]) == str(fl.get("lender", "")):
					SysUtil.notify(_fill(str(fl["line"]), {"pay": int(round(float(l["payment"]))), "due": Seasons.weekday_long(int(l["next_due"]))}), "warn")
					return
		"old_boss":          # task 62: the apprentice owes a day's unpaid work, or the reference (the hiring bonus) is gone
			if not checkin.is_empty():
				return
			var day: int = SysUtil.day() + int(fl.get("on_day", 2))
			var hrs: Array = fl.get("hours", [8, 12])
			var when: String = "%s, %d:00" % [Seasons.weekday_long(day), int(hrs[0])]
			JusticePlayer.ask(fid, "Your old boss", _fill(str(fl["ask"]), {"when": when}), [{"id": "yes", "label": str(fl.get("yes", "Yes"))}, {"id": "no", "label": str(fl.get("no", "No"))}],
				func(ch):
					if str(ch) != "yes":
						checkin = {"kind": "old_boss", "lost": str(fl.get("lost", ""))}
						_old_boss_lost()
						return
					checkin = {"kind": "old_boss", "day": day, "hours": hrs, "lot": str(fl.get("lot", "works")), "minutes": int(fl.get("minutes", 480)),
						"kept": str(fl.get("kept", "")), "lost": str(fl.get("lost", ""))}
					CalendarBook.add(fid, day, float(hrs[0]), str(fl.get("lot", "works")), "A day's work for your old boss", "probation"), "no")
		"contact_visit":          # the contact was never looked up: they turn up at the door
			var cid: int = int((Creation.picks.get(fid, {}) as Dictionary).get("contact_id", -1))
			if cid < 0 or RelationshipService.value(fid, cid, "friendship") >= float(fl.get("met_above", 22)):
				return
			var sv: Dictionary = StoryVisits.schedule_visit([cid], fid, SysUtil.now() + 15, int(fl.get("minutes", 60)), "visit")
			sv["line"] = _fill(str(fl["line"]), {"who": _first(Story.name_of(cid))})

static func _old_boss_kept(f) -> void:
	SysUtil.notify(str(checkin.get("kept", "")), "good")
	Away.send(f, float(checkin.get("minutes", 480)), "errand", {"label": "A day's work for the old boss"})
	checkin = {}

static func _old_boss_lost() -> void:
	var fid: int = Pawn.of()
	if Creation.picks.has(fid):
		Creation.picks[fid]["no_reference"] = true
	SysUtil.notify(str(checkin.get("lost", "")), "warn")
	checkin = {}

## An adult townie (the creation contact, else the neighbour, else anyone): who passes a lead on.
static func _someone(fid: int) -> int:
	var cid: int = int((Creation.picks.get(fid, {}) as Dictionary).get("contact_id", -1))
	if cid >= 0:
		return cid
	if neighbour >= 0:
		return neighbour
	for t in Story.alive_townies():
		if Story.stage_of(t) == "adult":
			return int(t["id"])
	return -1

## The probation check-in: kept by being at the police station in its hours that day, missed after.
static func on_minute() -> void:
	if checkin.is_empty():
		return
	var f = SysUtil.folk(Pawn.of())
	var day: int = int(checkin["day"])
	var hrs: Array = checkin["hours"]
	var h: float = SysUtil.hour_f()
	if f != null and SysUtil.day() == day and h >= 8.0 and h < float(hrs[1]) and int(checkin.get("nudged", -1)) != day and str(checkin.get("kind", "")) != "old_boss":
		checkin["nudged"] = day          # task 63: a morning reminder on the day
		SysUtil.notify("Probation check-in today at the %s, %d:00-%d:00." % [Neighborhood.label_of(str(checkin["lot"])), int(hrs[0]), int(hrs[1])], "story")
	if f != null and SysUtil.day() == day and h >= float(hrs[0]) and h < float(hrs[1]) and NeighborhoodLots.lot_at(f.tile) == str(checkin["lot"]):
		CalendarBook.appts = CalendarBook.appts.filter(func(a): return str(a["kind"]) != "probation")
		if str(checkin.get("kind", "")) == "old_boss":
			_old_boss_kept(f)
			return
		var next: int = day + int(checkin.get("every", 7))          # task 62: kept every week to the end of the term, probation is over
		if next > int(JusticeState.probation.get(int(f.id), -1)):
			SysUtil.notify(str(checkin.get("over", checkin["done"])), "good")
			JusticeState.probation.erase(int(f.id))
			checkin = {}
			return
		SysUtil.notify(str(checkin["done"]), "story")
		checkin["day"] = next
		checkin["misses"] = 0
		CalendarBook.add(int(f.id), next, float(hrs[0]), str(checkin["lot"]), str(checkin.get("label", "Probation check-in")), "probation")
	elif SysUtil.day() > day or (SysUtil.day() == day and h >= float(hrs[1])):
		CalendarBook.appts = CalendarBook.appts.filter(func(a): return str(a["kind"]) != "probation")
		if str(checkin.get("kind", "")) == "old_boss":
			_old_boss_lost()
			return
		checkin["misses"] = int(checkin.get("misses", 0)) + 1
		if int(checkin["misses"]) >= 2 and f != null:
			SysUtil.notify(str(checkin["missed"]), "warn")
			checkin = {}
			_violation(int(f.id))
			return
		var next: int = SysUtil.day() + int(checkin.get("every", 7))          # the first miss: a warning and a new date
		checkin["day"] = next
		CalendarBook.add(Pawn.of(), next, float(hrs[0]), str(checkin["lot"]), "Probation check-in, %d:00-%d:00" % [int(hrs[0]), int(hrs[1])], "probation")
		SysUtil.notify(_fill(str(checkin.get("warning", checkin["missed"])), {"when": "next %s, %d:00-%d:00" % [Seasons.weekday_long(next), int(hrs[0]), int(hrs[1])]}), "warn")          # task 63: not "Thursday" again on a Thursday

## The second missed check-in: the probation office passes it to the police, a probation violation case against the pawn (arrest, charge, trial).
static func _violation(pid: int) -> void:
	var c: Dictionary = CaseStore.create("probation_violation", pid, -1, CrimePerson.home_key(pid), {"witnessed": true, "trace": 1.0, "public": false})
	c["charge_hint"] = "probation_violation"
	c["state"] = "reported"
	c["disc_day"] = SysUtil.day()
	JusticeProcess.arrest(c, pid)

static func busy() -> bool:
	return not checkin.is_empty()

static func to_dict() -> Dictionary:
	return {"start_day": start_day, "said": said.duplicate(), "neighbour": neighbour, "checkin": checkin.duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	reset()
	start_day = int(d.get("start_day", 1))
	said = (d.get("said", {}) as Dictionary).duplicate()
	neighbour = int(d.get("neighbour", -1))
	checkin = (d.get("checkin", {}) as Dictionary).duplicate(true)
