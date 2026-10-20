class_name PlaceAutoGate
extends RefCounted
## The code checks behind the `gate` of an outing kind (task 14b, data/life/95_auto.json). A gate answers a Dictionary:
##   mult      factor on the kind's chance (0 = not now)
##   services  the service ids to try, when the kind does not list them (a lecture of the person's major, the club they belong to ...)
##   ctx       small facts kept in the plan (the pet to take to the vet, the invitation to answer ...)
##   claim     only one person of a household makes this plan on a day (the vet trip, the wedding)
## Everything a gate reads is state that already exists (Health, HealthLife, Counselling, PetState, EduState, ClubState, LeagueState, EventServices.check, PhoneState).

const NO := {"mult": 0.0}

static func eval(gate: String, f, kind: String, d: Dictionary, day: int) -> Dictionary:
	var fid: int = int(f.id)
	var stage: String = str(f.age_stage)
	match gate:
		"bare":
			var bf: float = HomeBare.factor(f)                 # free park outings only for a home with little to do in (task 32f)
			return {"mult": bf} if bf >= 0.3 and stage not in ["baby", "toddler"] else NO
		"ill":
			return {"mult": 1.0} if _sick(f) else NO          # once the doctor has seen them they rest for a couple of days
		"checkup":
			if stage in ["baby", "toddler", "child"]:
				return NO
			var cd: int = int(HealthLife.peek(fid).get("checkup_day", -1))
			return {"mult": 1.5 if cd < 0 else clampf(float(day - cd) / 28.0, 0.15, 2.5)}
		"teeth":
			if stage in ["baby", "toddler"]:
				return NO
			var dn: float = float(HealthLife.peek(fid).get("dental", 80.0))
			if f.has_buff(str(HealthLife.cfg().get("dental", {}).get("toothache_buff", "toothache"))):
				return {"mult": 20.0, "services": ["dental_fix"]}
			if dn >= 80.0:
				return NO
			return {"mult": clampf(pow((100.0 - dn) / 50.0, 2.0), 0.3, 3.0), "services": ["dental_clean"]}
		"help":
			return {"mult": 1.0} if stage in ["teen", "adult", "elder"] and Counselling.needs_help(f) else NO
		"refill":
			var sv: Array = []
			for cid in HealthCond.defs():
				if HealthCond.diagnosed(fid, str(cid)) and HealthCond.doses(fid, str(cid)) <= 1 and Places.find_service("refill_" + str(cid)).size() > 0:
					sv.append("refill_" + str(cid))
			return {"mult": 1.0, "services": sv} if not sv.is_empty() else NO
		"vet":
			return _vet(f, day)
		"preschool":
			return _preschool(f)
		"homework":
			return {"mult": 1.0} if Careers.school.has(fid) and EduSchool.homework_due(fid) else NO
		"lecture":
			return _lecture(f)
		"night_class":
			return _night_class(f)
		"library_course":
			return _library_course(f)
		"league":
			return _league(f)
		"club":
			return _club(f)
		"wedding":
			return {"mult": 1.0, "claim": "wedding"} if stage == "adult" and EventServices.check("wedding", f, "", "", {}) == "" else NO
		"birthday":
			return {"mult": 1.0} if stage in ["teen", "adult", "elder"] and EventServices.check("birthday_party", f, "", "", {}) == "" else NO
		"shower":
			return {"mult": 1.0, "claim": "shower"} if stage in ["adult", "elder"] and EventServices.check("baby_shower", f, "", "", {}) == "" else NO
		"funeral":
			return {"mult": 1.0, "claim": "funeral"} if stage in ["teen", "adult", "elder"] and EventServices.check("funeral", f, "", "", {}) == "" else NO
		"reunion":
			return {"mult": 1.0} if stage in ["teen", "adult", "elder"] and EventServices.check("reunion", f, "", "", {}) == "" else NO
		"invite":
			return _invite(f)
	return NO

## Ill or hurt enough to see the doctor (a cold or a sprain is waited out at home): data config.auto.doctor.
static func _sick(f) -> bool:
	if Health.is_collapsed(f) or Hospital.is_in(int(f.id)) or SysUtil.day() - PlaceAuto.was_done(int(f.id), "clinic_sick") < int(PlaceAuto.cfg().get("doctor", {}).get("again_days", 2)):
		return false                # (medicine from the bathroom cabinet is not the doctor: they still go)
	var dc: Dictionary = PlaceAuto.cfg().get("doctor", {})
	if Health.is_ill(f):
		var ill: Dictionary = Health.illness_of(f)
		var after: float = float(dc.get("%s_after_hours" % str(ill["kind"]), dc.get("ill_after_hours", 0.0))) * 60.0
		if int(ill["severity"]) >= 2 or float(SysUtil.now() - int(ill["since"])) >= after:
			return true
	return Health.is_injured(f) and Health.injury_severity(f) >= int(dc.get("injury_min_severity", 2))

# ------------------------------------------------------------------ pets
static func _vet(f, day: int) -> Dictionary:
	if str(f.age_stage) in ["baby", "toddler", "child"]:
		return NO
	var hid: int = int(f.household_id)
	var days: int = int(PlaceAuto.cfg().get("pet", {}).get("vet_checkup_days", 24))
	var best: Dictionary = {}
	for p in PetState.of_household(hid):
		if bool(p["sick"]):
			return {"mult": 20.0, "services": ["vet_treat"], "ctx": {"target": int(p["id"])}, "claim": "vet"}
		if best.is_empty() and day - int(p["vet_day"]) > days and PetState.age_days(p) > 5:
			best = p
	return {"mult": 1.0, "services": ["vet_checkup"], "ctx": {"target": int(best["id"])}, "claim": "vet"} if not best.is_empty() else NO

# ------------------------------------------------------------------ school and study
static func _preschool(f) -> Dictionary:
	if str(f.age_stage) != "toddler" or bool(EduState.peek(int(f.id)).get("preschool", false)):
		return NO
	var has_adult := false
	for m in SysUtil.residents():
		if int(m.household_id) == int(f.household_id) and str(m.age_stage) in ["adult", "elder"]:
			has_adult = true
	var fee: int = int(round(float(EduState.cfg().get("preschool", {}).get("cost", 14)) * 5.0))
	return {"mult": 1.0} if has_adult and Economy.can_afford(int(f.household_id), fee) else NO

static func _ambitious(f, group: String) -> bool:
	for t in PlaceAuto.cfg().get(group, {}).get("traits", []):
		if f.has_trait(str(t)):
			return true
	return false

static func _lecture(f) -> Dictionary:
	var fid: int = int(f.id)
	if not str(f.age_stage) in ["adult", "elder"]:
		return NO
	var r: Dictionary = EduState.peek(fid)
	var col: Dictionary = r.get("college", {})
	var major: String = str(col.get("major", ""))
	var mult := 1.6
	if major == "":
		var applied: String = str(r.get("applied", ""))
		var cc: Dictionary = PlaceAuto.cfg().get("college", {})
		if applied != "" and not EduState.has_degree(fid, applied):
			major = applied
			mult = 1.2
		elif _ambitious(f, "college") and EduState.degrees(fid).size() < 2:
			major = _pick_major(f)
			mult = float(cc.get("start_chance", 0.35))
	if major == "" or EduCollege.why_not(f, major) != "":
		return NO
	return {"mult": mult, "services": ["lecture_" + major]}

static func _skill_best(f, major: String) -> int:
	var best := 0
	for s in EduCollege.major_def(major).get("skills", []):
		best = maxi(best, f.skill_level(str(s)))
	return best

static func _pick_major(f) -> String:
	var ids: Array = []
	for m in LifeDefs.section("majors"):
		if not EduState.has_degree(int(f.id), str(m)) and not Places.find_service("lecture_" + str(m)).is_empty():
			ids.append(str(m))
	ids.sort()
	var ws: Array = ids.map(func(m): return 1.0 + float(_skill_best(f, str(m))))
	var pick: Variant = _weighted(ids, ws)
	return "" if pick == null else str(pick)

static func _weighted(items: Array, weights: Array) -> Variant:
	var total := 0.0
	for w in weights:
		total += maxf(float(w), 0.0)
	if items.is_empty() or total <= 0.0:
		return null
	var roll: float = PlaceAuto.rng.randf() * total
	for i in items.size():
		roll -= maxf(float(weights[i]), 0.0)
		if roll <= 0.0:
			return items[i]
	return items[items.size() - 1]

static func _courses_at(f, place: String) -> Array:
	var ids: Array = []
	var ws: Array = []
	var fid: int = int(f.id)
	var boost: float = float(PlaceAuto.cfg().get("night_class", {}).get("progress_boost", 4.0))
	for c in LifeDefs.section("courses"):
		var cd: Dictionary = LifeDefs.get_in("courses", str(c))
		if str(cd.get("place", "")) != place or EduCourses.why_not(f, str(c)) != "":
			continue
		var sid: String = "course_" + str(c)
		if Places.find_service(sid).is_empty():
			continue
		ids.append(sid)
		ws.append(boost if EduCourses.progress(fid, str(c)) > 0 else 1.0)
	return [ids, ws]

static func _course_pick(f, place: String) -> Array:
	var ow: Array = _courses_at(f, place)
	var ids: Array = ow[0]
	var order: Array = range(ids.size())
	order.sort_custom(func(a, b): return str(ids[a]) < str(ids[b]))
	var sorted_ids: Array = []
	var sorted_w: Array = []
	for i in order:
		sorted_ids.append(ids[i])
		sorted_w.append((ow[1] as Array)[i])
	var pick: Variant = _weighted(sorted_ids, sorted_w)
	return [] if pick == null else [str(pick)]

static func _night_class(f) -> Dictionary:
	if not str(f.age_stage) in ["adult", "elder"]:
		return NO
	var sv: Array = _course_pick(f, "night_school")
	if sv.is_empty():
		return NO
	var started: bool = not (EduState.peek(int(f.id)).get("courses", {}) as Dictionary).is_empty()
	var ambitious: bool = _ambitious(f, "night_class")
	return {"mult": (1.5 if started else 1.0) if (ambitious or started) else 0.25, "services": sv}

static func _library_course(f) -> Dictionary:
	if not str(f.age_stage) in ["teen", "adult", "elder"]:
		return NO
	var sv: Array = _course_pick(f, "library_courses")
	return {"mult": 0.6 if _ambitious(f, "night_class") else 0.2, "services": sv} if not sv.is_empty() else NO

# ------------------------------------------------------------------ leagues and clubs
static func _league(f) -> Dictionary:
	if not str(f.age_stage) in ["teen", "adult"]:
		return NO
	if LeagueState.team_of(int(f.id)) != "":
		return {"mult": 2.0, "services": ["league_play"]}
	return {"mult": 0.25, "services": ["league_join"]}

static func _club(f) -> Dictionary:
	var fid: int = int(f.id)
	if not str(f.age_stage) in ["child", "teen", "adult", "elder"]:
		return NO
	var mine: Array = ClubState.clubs_of(fid)
	var sv: Array = []
	for c in mine:
		sv.append(str(c) + "_meeting")
	if not sv.is_empty():
		return {"mult": 1.0, "services": sv}
	var pref := {"book_club": ["bookworm", "creative", "shy"], "chess_club": ["perfectionist", "competitive", "gamer"], "garden_club": ["green_thumb", "outdoorsy", "easygoing"]}
	var clubs: Array = (ClubState.defs() as Dictionary).keys()
	clubs.sort()
	var ws: Array = []
	for c2 in clubs:
		var w := 1.0
		for t in pref.get(str(c2), []):
			if f.has_trait(str(t)):
				w += 1.5
		ws.append(w)
	var pick: Variant = _weighted(clubs, ws)
	return {"mult": 0.3, "services": ["join_" + str(pick)]} if pick != null else NO

# ------------------------------------------------------------------ phone
static func _invite(f) -> Dictionary:
	var fid: int = int(f.id)
	if str(f.age_stage) in ["baby", "toddler", "child"]:
		return NO
	var cfg: Dictionary = PlaceAuto.cfg()
	for m in PhoneState.inbox_of(fid):
		var o: Dictionary = PhoneCmd.outing_by_id(str(m["service"]))
		if o.is_empty() or PhoneCmd.unreachable(int(m["from"])) != "":
			continue
		var p: float = float(cfg.get("invite_yes_base", 0.6)) + float(cfg.get("invite_yes_per_friendship", 0.004)) * RelationshipService.value(fid, int(m["from"]), "friendship")
		if f.has_trait("social"):
			p += 0.15
		if f.has_trait("loner") or f.has_trait("shy"):
			p -= 0.2
		return {"mult": clampf(p, 0.1, 1.0), "services": o.get("services", []), "ctx": {"invite": int(m["id"]), "from": int(m["from"]), "outing": str(o["id"])}}
	return NO
