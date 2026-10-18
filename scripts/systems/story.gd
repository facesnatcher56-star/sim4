class_name Story
extends RefCounted
## Story progression: a statistical simulation of ~12 off-lot townies (jobs, friendships, marriage, births, moves,
## old age) plus visitors who arrive as full Folk on the lot for a few hours (Situation-lite state machine:
## roles host/guest, states scheduled -> arrive -> mingle -> leave -> done, party score reward), party invites
## that take a resident off-lot, and a modest night-time burglar. Data: data/story.json.

static var townies: Dictionary = {}     # id -> townie dict
static var situations: Array = []       # visit/party situations
static var invites: Array = []          # {id, townie_id, folk_id, expires_min, state}
static var news: Array = []             # {day, text}
static var next_id: int = 0
static var _seq: int = 1
static var auto_accept_invites: bool = true
static var spawn_tile: Vector2i = Vector2i(-999, -999)   # lot entrance; (-999,-999) = use config default
static var burglaries: int = 0

static func reset() -> void:
	townies.clear()
	situations.clear()
	invites.clear()
	news.clear()
	next_id = 0
	_seq = 1
	auto_accept_invites = true
	spawn_tile = Vector2i(-999, -999)
	burglaries = 0

static func cfg() -> Dictionary:
	return SysUtil.table("story")

# ------------------------------------------------------------------ townie roster
static func is_townie(id: int) -> bool:
	return townies.has(id)

static func name_of(id: int) -> String:
	return str((townies.get(id, {}) as Dictionary).get("name", "Someone"))

static func traits_of(id: int) -> Array:
	return (townies.get(id, {}) as Dictionary).get("traits", [])

static func alive_townies() -> Array:
	var out: Array = []
	for id in townies:
		if bool(townies[id]["alive"]):
			out.append(townies[id])
	return out

static func _log(text: String) -> void:
	news.append({"day": SysUtil.day(), "text": text})
	while news.size() > 60:
		news.pop_front()

static func recent_news(n: int = 10) -> Array:
	return news.slice(maxi(news.size() - n, 0))

static func _new_name() -> String:
	var c: Dictionary = cfg()
	for _i in 40:
		var nm: String = "%s %s" % [str(SysUtil.pick(c.get("first_names", ["Sam"]))), str(SysUtil.pick(c.get("last_names", ["Doe"])))]
		var taken: bool = false
		for id in townies:
			if townies[id]["name"] == nm:
				taken = true
		if not taken:
			return nm
	return "Visitor %d" % next_id

static func add_townie(age_days: float = -1.0, nm: String = "", traits: Array = [], career: String = "", level: int = 1) -> Dictionary:
	var c: Dictionary = cfg()
	if next_id <= 0:
		next_id = int(c.get("first_id", 1000))
	var id: int = next_id
	next_id += 1
	if nm == "":
		nm = _new_name()
	if traits.is_empty():
		var pool: Array = (c.get("trait_pool", []) as Array).duplicate()
		for _i in 2:
			if pool.is_empty():
				break
			var t = SysUtil.pick(pool)
			pool.erase(t)
			traits.append(str(t))
	if age_days < 0.0:
		age_days = SysUtil.rng.randf_range(float(Aging.stage_def("adult").get("from_day", 44)) + 2.0, float(Aging.stage_def("elder").get("from_day", 140)) - 10.0)
	var t: Dictionary = {"id": id, "name": nm, "traits": traits.duplicate(), "age_days": age_days, "career": career, "level": level,
		"coins": SysUtil.rng.randi_range(100, 800), "alive": true, "lot": SysUtil.rng.randi_range(1, 6), "last_visit_day": -99,
		"appearance": Genetics.unique_appearance(GeneticsUnique.registry())}
	townies[id] = t
	return t

static func generate_townies(count: int = -1) -> void:
	var c: Dictionary = cfg()
	if count < 0:
		count = int(c.get("townie_count", 12))
	var careers: Array = c.get("careers", [])
	for i in count:
		var tn: Dictionary = add_townie()
		if i % 3 != 2 and not careers.is_empty():
			tn["career"] = str(SysUtil.pick(careers))
			tn["level"] = SysUtil.rng.randi_range(1, 3)
			var role: String = FolkOutfits.role_for(str(tn["career"]), "adult")
			if role != "":
				tn["appearance"] = FolkOutfits.dress(tn["appearance"], role, GeneticsUnique.registry_without(tn["appearance"]), Genetics.rng)
	# a teen and an elder for variety
	if count >= 4:
		var ids: Array = townies.keys()
		(townies[ids[0]] as Dictionary)["age_days"] = SysUtil.rng.randf_range(float(Aging.stage_def("teen").get("from_day", 28)) + 1.0, 42.0)
		(townies[ids[0]] as Dictionary)["career"] = ""
		var tt: Dictionary = townies[ids[0]]
		tt["appearance"] = FolkOutfits.dress(tt["appearance"], "student", GeneticsUnique.registry_without(tt["appearance"]), Genetics.rng)
		(townies[ids[1]] as Dictionary)["age_days"] = float(Aging.stage_def("elder").get("from_day", 140)) + 6.0
		(townies[ids[1]] as Dictionary)["career"] = ""
	# starting social web: friendships, one couple, one family
	var adults: Array = []
	for t2 in alive_townies():
		if stage_of(t2) in ["adult", "elder"]:
			adults.append(int(t2["id"]))
	for _k in count:
		var a = SysUtil.pick(adults)
		var b = SysUtil.pick(adults)
		if a != null and b != null and a != b:
			RelationshipService.add_both(int(a), int(b), "friendship", SysUtil.rng.randf_range(8.0, 45.0))
	if adults.size() >= 4:
		RelationshipService.add_both(adults[2], adults[3], "friendship", 60.0)
		RelationshipService.add_both(adults[2], adults[3], "romance", 70.0)
		RelationshipBits.set_flag(adults[2], adults[3], "partner", true, false)
		if adults.size() >= 6:
			RelationshipService.add_both(adults[4], adults[5], "friendship", 50.0)
			RelationshipBits.set_flag(adults[4], adults[5], "family", true, false)

static func stage_of(t: Dictionary) -> String:
	return Aging.stage_for_days(float(t["age_days"]))

# ------------------------------------------------------------------ daily advance
static func on_day(day: int) -> void:
	if townies.is_empty():
		generate_townies()
	var c: Dictionary = cfg()
	var dc: Dictionary = c.get("daily", {})
	var rate: float = Aging.age_rate()
	var dcfg: Dictionary = Aging.cfg().get("death", {})
	for t in alive_townies():
		t["age_days"] = float(t["age_days"]) + rate
		var st: String = stage_of(t)
		if st == "elder" and str(t["career"]) != "":
			t["career"] = ""
			_log("%s retired." % t["name"])
		elif st == "adult":
			if str(t["career"]) == "":
				if SysUtil.chance(float(dc.get("job_chance", 0.12))):
					t["career"] = str(SysUtil.pick(c.get("careers", [])))
					t["level"] = 1
					_log("%s started a new job." % t["name"])
			else:
				var lmax: int = Careers.max_level(str(t["career"]))
				if SysUtil.chance(float(dc.get("promote_chance", 0.04))) and int(t["level"]) < lmax:
					t["level"] = int(t["level"]) + 1
					_log("%s got promoted to level %d." % [t["name"], t["level"]])
				elif SysUtil.chance(float(dc.get("demote_chance", 0.015))):
					t["level"] = int(t["level"]) - 1
					if int(t["level"]) < 1:
						t["career"] = ""
						t["level"] = 1
						_log("%s lost their job." % t["name"])
				if str(t["career"]) != "":
					t["coins"] = int(t["coins"]) + int(dc.get("coins_per_level", 40)) * int(t["level"])
		var dstart: float = float(dcfg.get("start_day", 170))
		if float(t["age_days"]) >= dstart and SysUtil.chance(float(dcfg.get("chance_per_day", 0.03)) + float(dcfg.get("ramp_per_day", 0.004)) * (float(t["age_days"]) - dstart)):
			_townie_dies(t)
	_pair_events(dc)
	_life_events(dc)
	StoryVisits._visits_and_invites(day)

static func _townie_dies(t: Dictionary) -> void:
	Aging.kill(int(t["id"]), "old age")      # grief, grave, chronicle and the news line live in DeathCauses.kill_townie

static func _pair_events(dc: Dictionary) -> void:
	var adults: Array = []
	for t in alive_townies():
		if stage_of(t) in ["teen", "adult", "elder"]:
			adults.append(int(t["id"]))
	if adults.size() < 2:
		return
	for _i in int(dc.get("pair_events", 6)):
		var a: int = int(SysUtil.pick(adults))
		var b: int = int(SysUtil.pick(adults))
		if a == b:
			continue
		var compat: float = RelationshipBits.compatibility(a, b)
		var hot: bool = traits_of(a).has("hot_headed")
		if SysUtil.chance(0.12 + (0.18 if hot else 0.0) - compat * 0.1):
			RelationshipService.add_both(a, b, "friendship", -SysUtil.rng.randf_range(3.0, 8.0))
			RelationshipService.add_history(a, b, "insult", -0.8, a)
		else:
			RelationshipService.add_both(a, b, "friendship", SysUtil.rng.randf_range(1.0, 4.0) * (1.0 + compat * 0.5))
			RelationshipService.add_history(a, b, "chat", 0.3, a)
			if stage_of(townies[a]) != "teen" and stage_of(townies[b]) != "teen" and compat > 0.1 and RelationshipService.value(a, b, "friendship") > 25.0:
				RelationshipService.add_both(a, b, "romance", SysUtil.rng.randf_range(1.0, 4.0))
		RelationshipService.touch(a, b)
		RelationshipBits.auto_status(a, b)

static func _life_events(dc: Dictionary) -> void:
	var c: Dictionary = cfg()
	# marriage
	for key in RelationshipService.pairs.keys():
		var p: Dictionary = RelationshipService.pairs[key]
		var a: int = int(p["lo"])
		var b: int = int(p["hi"])
		if not (townies.has(a) and townies.has(b)) or not (bool(townies[a]["alive"]) and bool(townies[b]["alive"])):
			continue
		var fl: Dictionary = p["flags"]
		if fl.get("partner", false) and not fl.get("spouse", false):
			if RelationshipService.value(a, b, "romance") >= 80.0 and SysUtil.chance(float(dc.get("marry_chance", 0.12))):
				RelationshipBits.set_flag(a, b, "spouse", true, false)
				_log("%s and %s got married!" % [name_of(a), name_of(b)])
				ChronicleHook.note("wedding", "%s and %s got married." % [name_of(a), name_of(b)], [a, b], "town:%d" % int(townies[a].get("lot", 0)), 2, true)
				_tell_residents_about(a, b, "%s and %s got married!" % [name_of(a), name_of(b)])
		elif fl.get("spouse", false) or fl.get("partner", false):
			if alive_townies().size() < int(c.get("max_population", 20)) and SysUtil.chance(float(dc.get("baby_chance", 0.05))):
				var baby: Dictionary = add_townie(0.0, "", [])
				baby["name"] = "%s %s" % [str(SysUtil.pick(Aging.cfg().get("name_pool", ["Pip"]))), name_of(a).split(" ")[-1]]
				RelationshipBits.set_flag(int(baby["id"]), a, "family", true, false)
				RelationshipBits.set_flag(int(baby["id"]), b, "family", true, false)
				baby["appearance"] = Genetics.inherit(Family.person_info(a), Family.person_info(b))["appearance"]
				Family.note_townie_birth(int(baby["id"]), a, b)
				_log("%s and %s had a baby, %s." % [name_of(a), name_of(b), baby["name"]])
				ChronicleHook.note("birth", "%s was born to %s and %s." % [baby["name"], name_of(a), name_of(b)], [int(baby["id"]), a, b], "town:%d" % int(townies[a].get("lot", 0)), 2, true)
	# moving away / arriving
	for t in alive_townies():
		if SysUtil.chance(float(dc.get("move_away_chance", 0.01))) and stage_of(t) == "adult":
			t["alive"] = false
			t["moved"] = true
			_log("%s moved out of town." % t["name"])
	if alive_townies().size() < int(c.get("townie_count", 12)) and SysUtil.chance(float(dc.get("arrive_chance", 0.12))):
		var n: Dictionary = add_townie()
		n["career"] = str(SysUtil.pick(c.get("careers", [])))
		_log("%s moved to town." % n["name"])

static func _tell_residents_about(a: int, b: int, text: String) -> void:
	for r in SysUtil.residents():
		var rid: int = int(r.id)
		if RelationshipService.knows(rid, a) or RelationshipService.knows(rid, b):
			SysUtil.notify(text, "story")
			return

# ------------------------------------------------------------------ visits & invites
# ------------------------------------------------------------------ burglar
static func on_hour(hour: int) -> void:
	var b: Dictionary = cfg().get("burglar", {})
	if hour < int(b.get("hour_min", 1)) or hour > int(b.get("hour_max", 5)):
		return
	if not SysUtil.chance(float(b.get("chance", 0.06))):
		return
	try_burglary(true)

## Everyone asleep + no lamp on -> a burglar steals coins. `force` skips the dice (tests).
static func try_burglary(force: bool = false) -> int:
	var res: Array = SysUtil.residents()
	if res.is_empty():
		return 0
	if not Neighborhood.everyone_home():
		return 0      # somebody is out and about: no burglary
	for f in res:
		if SysUtil.is_away(f):
			continue
		var asleep: bool = f.current != null and (str(f.current.def_id).begins_with("sleep") or str(f.current.def_id) == "pass_out" or f.posture == "lie")
		if not asleep:
			return 0
	for o in SysUtil.all_world_objects():
		if str(o.def_id) == "lamp" and Neighborhood.lot_at(o.tile) == Neighborhood.HOME and bool(WorldIface.state_get(o, "on", false)):
			return 0
	if not force:
		pass
	var b: Dictionary = cfg().get("burglar", {})
	var hid: int = int((res[0] as Folk).household_id)
	var bal: int = WorldIface.get_coins(hid)
	var amount: int = clampi(int(float(bal) * float(b.get("steal_rate", 0.1))), int(b.get("steal_min", 20)), int(b.get("steal_max", 300)))
	amount = mini(amount, bal)
	if amount <= 0:
		return 0
	Economy.deposit(hid, -amount, "burglary")
	burglaries += 1
	SysUtil.notify("A burglar broke in during the night and stole %d coins! Leave a lamp on or stay up late." % amount, "bad")
	SysUtil.game_event("burglary", {"household_id": hid, "stolen": amount})
	_log("Burglary: %d coins stolen." % amount)
	return amount

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"townies": SysUtil.str_keys(townies).duplicate(true), "situations": situations.duplicate(true), "invites": invites.duplicate(true),
		"news": news.duplicate(true), "next_id": next_id, "seq": _seq, "auto_accept": auto_accept_invites, "burglaries": burglaries}

static func from_dict(d: Dictionary) -> void:
	reset()
	townies = SysUtil.int_keys((d.get("townies", {}) as Dictionary).duplicate(true))
	for k in townies:
		var t: Dictionary = townies[k]
		t["id"] = int(t["id"])
		t["level"] = int(t["level"])
		t["coins"] = int(t["coins"])
		t["lot"] = int(t.get("lot", 1))
		t["last_visit_day"] = int(t.get("last_visit_day", -99))
	situations = (d.get("situations", []) as Array).duplicate(true)
	for s in situations:
		for key in ["id", "arrive_min", "end_min"]:
			s[key] = int(s[key])
		if s.has("leave_done_min"):
			s["leave_done_min"] = int(s["leave_done_min"])
		for lk in ["host_ids", "guest_ids", "spawned"]:
			var arr: Array = []
			for x in s[lk]:
				arr.append(int(x))
			s[lk] = arr
	invites = (d.get("invites", []) as Array).duplicate(true)
	for inv in invites:
		for key2 in ["id", "townie_id", "folk_id", "created_min", "expires_min"]:
			inv[key2] = int(inv[key2])
	news = (d.get("news", []) as Array).duplicate(true)
	next_id = int(d.get("next_id", 0))
	_seq = int(d.get("seq", 1))
	auto_accept_invites = bool(d.get("auto_accept", true))
	burglaries = int(d.get("burglaries", 0))

# ---- thin delegates (called from UI / views)
static func invite_to_venue(townie_id: int, host_id: int, lot_id: String, delay: int = 40, duration: int = 120) -> Dictionary:
	return StoryVisits.invite_to_venue(townie_id, host_id, lot_id, delay, duration)
