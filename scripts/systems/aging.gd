class_name Aging
extends RefCounted
## Life stages, birthdays, trait slots, pregnancy/birth, death, grief, inheritance and legacy summaries.
## Data: data/aging.json. The current stage is stored in Folk.age_stage and mirrored by a permanent marker buff
## `stage_<id>` (so interaction tests can gate on it: {"lacks_buff": "stage_child"}). SysCond also offers
## {"age_stage_is": "adult"} for systems-level checks.

static var records: Dictionary = {}      # folk_id -> {age_days, last_year, parents:[], inherited:[], children:[], born_day}
static var pregnancies: Dictionary = {}  # mother_id -> {father, due_day, started}
static var cooldowns: Dictionary = {}    # folk_id -> day until which they will not try again
static var dead: Array = []              # legacy records
static var lifespan_setting: String = ""  # "" = use data default

static func reset() -> void:
	Pregnancy.reset()
	records.clear()
	pregnancies.clear()
	cooldowns.clear()
	dead.clear()
	lifespan_setting = ""

static func cfg() -> Dictionary:
	return SysUtil.table("aging")

static func stage_table() -> Array:
	var t: Array = cfg().get("stages", [])
	if t.is_empty():
		return [{"id": "adult", "label": "Adult", "from_day": 0, "trait_slots": 4}]
	return t

static func stage_ids() -> Array:
	var out: Array = []
	for s in stage_table():
		out.append(str(s["id"]))
	return out

static func stage_index(stage: String) -> int:
	return stage_ids().find(stage)

static func stage_def(stage: String) -> Dictionary:
	for s in stage_table():
		if str(s["id"]) == stage:
			return s
	return {}

static func stage_for_days(age_days: float) -> String:
	var cur: String = str(stage_table()[0]["id"])
	for s in stage_table():
		if age_days >= float(s["from_day"]):
			cur = str(s["id"])
	return cur

static func trait_slots(stage: String) -> int:
	return int(stage_def(stage).get("trait_slots", 4))

static func days_per_year() -> float:
	return maxf(float(cfg().get("days_per_year", 4)), 0.5)

## Adjustable lifespan: "short" | "normal" | "long" | "epic" (multiplies how fast everyone ages).
static func set_lifespan(setting: String) -> void:
	lifespan_setting = setting

static func lifespan() -> String:
	return lifespan_setting if lifespan_setting != "" else str(cfg().get("lifespan", {}).get("setting", "normal"))

static func age_rate() -> float:
	return float(cfg().get("lifespan", {}).get("age_rate", {}).get(lifespan(), 1.0))

# ------------------------------------------------------------------ records
static func register(f, age_days: float = -1.0, parents: Array = []) -> void:
	var fid: int = int(f.id)
	if records.has(fid):
		return
	if age_days < 0.0:
		age_days = AgingStart.default_age(f)
	records[fid] = {"age_days": age_days, "last_year": int(floor(age_days / days_per_year())), "parents": parents.duplicate(),
		"inherited": [], "children": [], "born_day": SysUtil.day() - int(age_days), "birth_doy": _new_birth_doy(age_days)}
	f.age_stage = stage_for_days(age_days)
	apply_stage_buff(f)

## Born folk (age 0) have their birthday today; starting folk get a random date nobody else has.
static func _new_birth_doy(age: float) -> int:
	if age < 1.0:
		return doy(SysUtil.day())
	var used: Array = []
	for rec in records.values():
		used.append(int((rec as Dictionary).get("birth_doy", -1)))
	var yd: int = year_days()
	var start: int = absi(hash("%d:%d" % [records.size(), int(age * 10.0)])) % yd
	for k in yd:
		var d: int = (start + k) % yd
		if not used.has(d):
			return d
	return start

static func apply_stage_buff(f) -> void:
	for sid in stage_ids():
		var bid: String = "stage_" + str(sid)
		if str(sid) == str(f.age_stage):
			if not f.has_buff(bid):
				f.add_buff(bid)
		elif f.has_buff(bid):
			f.remove_buff(bid)

static func age_days(folk_id: int) -> float:
	return float((records.get(folk_id, {}) as Dictionary).get("age_days", 0.0))

static func age_years(folk_id: int) -> int:
	return int(floor(age_days(folk_id) / days_per_year()))

## Place a folk at an exact age (tests / character creation).
static func set_age_days(f, days: float) -> void:
	register(f, days)
	var rec: Dictionary = records[int(f.id)]
	rec["age_days"] = days
	rec["last_year"] = int(floor(days / days_per_year()))
	var old: String = str(f.age_stage)
	var nw: String = stage_for_days(days)
	f.age_stage = nw
	apply_stage_buff(f)
	if old != nw:
		Careers.on_stage_changed(f, old, nw)

static func can_add_trait(f) -> bool:
	return f.traits.size() < trait_slots(str(f.age_stage))

static func ensure_all() -> void:
	for f in WorldIface.all_folk():
		if not records.has(int(f.id)) and SysUtil.is_resident(f):
			register(f)

# ------------------------------------------------------------------ daily tick
static func on_day(_day: int) -> void:
	ensure_all()
	var rate: float = age_rate()
	for fid in records.keys():
		var f = SysUtil.folk(int(fid))
		if f == null:
			continue
		var rec: Dictionary = records[fid]
		rec["age_days"] = float(rec["age_days"]) + rate
		if is_birthday_today(int(fid)):
			_birthday(f)
		var nw: String = stage_for_days(float(rec["age_days"]))
		if nw != str(f.age_stage):
			_age_up(f, nw)
	_check_births()
	_check_deaths()

## The small yearly celebration (once per calendar year, no age number); growing into a new life stage is the big birthday (_age_up).
static func _birthday(f) -> void:
	if SysUtil.is_resident(f) and bool(cfg().get("birthday_toast", true)):
		SysUtil.notify("It's %s's birthday today!" % f.name, "birthday")
	SysUtil.game_event("birthday", {"folk_id": f.id})
	f.add_buff("cheered_up")

static func year_days() -> int:
	return maxi(4 * Seasons.length(), 4)

static func doy(day: int) -> int:
	return posmod(day - 1, year_days())

## Day of the calendar year (0-based) of this folk's own birthday.
static func birth_doy(folk_id: int) -> int:
	var rec: Dictionary = records.get(folk_id, {})
	if rec.is_empty():
		return -1
	if not rec.has("birth_doy"):
		rec["birth_doy"] = doy(int(rec.get("born_day", 0)))      # old saves
	return int(rec["birth_doy"])

static func is_birthday_today(folk_id: int) -> bool:
	return birth_doy(folk_id) == doy(SysUtil.day())

## "Early" / "mid" / "late" part of the life stage, from age_days.
static func stage_part(age: float, stage: String) -> String:
	var idx: int = stage_index(stage)
	if idx < 0:
		return ""
	var start: float = float(stage_def(stage).get("from_day", 0))
	var nxt: float = float(stage_table()[idx + 1]["from_day"]) if idx + 1 < stage_table().size() else start + 90.0
	var u: float = (age - start) / maxf(nxt - start, 1.0)
	return "early" if u < 0.34 else ("mid" if u < 0.67 else "late")

## Player-facing age: "Late adult" (never a number of years).
static func stage_text(folk_id: int, stage: String = "") -> String:
	var st: String = stage if stage != "" else str((Family.person_info(folk_id) as Dictionary).get("stage", "adult"))
	var lbl: String = str(stage_def(st).get("label", st))
	if st in ["baby", "toddler"] or not records.has(folk_id):
		return lbl
	return "%s %s" % [stage_part(age_days(folk_id), st).capitalize(), lbl.to_lower()]

static func article(stage: String) -> String:
	return "an" if stage in ["adult", "elder"] else "a"

static func _age_up(f, new_stage: String) -> void:
	var old: String = str(f.age_stage)
	f.age_stage = new_stage
	apply_stage_buff(f)
	var label: String = str(stage_def(new_stage).get("label", new_stage))
	SysUtil.notify("%s grew up into %s %s!" % [f.name, article(new_stage), label.to_lower()], "birthday")
	SysUtil.game_event("aged_up", {"folk_id": f.id, "from": old, "to": new_stage})
	if SysUtil.is_resident(f):
		ChronicleHook.note("aged_up", "%s grew up into %s %s." % [f.name, article(new_stage), label.to_lower()], [int(f.id)], "home:%d" % int(f.household_id), 2)
	# New stage, new trait: first the ones inherited at birth, then a random one.
	if can_add_trait(f) and new_stage != "elder":
		_grow_trait(f)
	Careers.on_stage_changed(f, old, new_stage)

static func _grow_trait(f) -> void:
	var rec: Dictionary = records.get(int(f.id), {})
	var cand: Array = []
	for t in rec.get("inherited", []):
		if not f.traits.has(t):
			cand.append(t)
	if cand.is_empty() and can_add_trait(f):
		cand = Genetics.random_pool(f.traits)
	if can_add_trait(f) and not cand.is_empty():
		var t2 = SysUtil.pick(cand)
		f.traits.append(str(t2))
		SysUtil.notify("%s's personality is showing: %s." % [f.name, str(SimEnv.data().trait_def(str(t2)).get("label", t2))], "birthday")

# ------------------------------------------------------------------ pregnancy / birth
## Returns {"ok": bool, "reason": String}. The FEMALE of the pair carries, whichever folk started it (Conception).
static func try_for_baby(actor_id: int, partner_id: int) -> Dictionary:
	var res: Dictionary = Conception.try_for_baby(actor_id, partner_id)
	if bool(res.get("ok", false)):
		Family.update_pregnancies()
	return res

static func _check_births() -> void:
	Pregnancy.on_day()

## Deliver now (tests and the old call sites): PregnancyBirth makes the baby or babies from the record, or one baby without a record.
static func _birth(mother_id: int, father_id: int) -> void:
	if not pregnancies.has(mother_id):
		pregnancies[mother_id] = {"father": father_id, "due_day": SysUtil.day(), "started": SysUtil.day(), "known": true, "kids": 1, "kid_sexes": [Sexes.roll()]}
	PregnancyLabour.finish(mother_id)

static func _surname(full: String) -> String:
	var parts: PackedStringArray = full.split(" ")
	return parts[parts.size() - 1] if parts.size() > 1 else full

static func children_of(folk_id: int) -> Array:
	return (records.get(folk_id, {}) as Dictionary).get("children", [])

# ------------------------------------------------------------------ death
static func _check_deaths() -> void:
	var dc: Dictionary = cfg().get("death", {})
	var start: float = float(dc.get("start_day", 170))
	for fid in records.keys():
		var f = SysUtil.folk(int(fid))
		if f == null or not SysUtil.is_resident(f):
			continue
		var days: float = float(records[fid]["age_days"])
		if days < start:
			continue
		var p: float = float(dc.get("chance_per_day", 0.03)) + float(dc.get("ramp_per_day", 0.004)) * (days - start)
		if days >= float(dc.get("max_day", 230)) or SysUtil.chance(p):
			kill(int(fid), "old age")

## Remove a folk from the world, with grief, inheritance, a grave and a legacy record. Returns the legacy summary.
## `cause` is a death-cause id of data/death_causes.json (or "old age"); every path that kills someone goes through here.
## Works for Story townies too (no Folk on the map): the grief / grave / chronicle logic lives in DeathCauses.kill_townie.
static func kill(folk_id: int, cause: String = "old age") -> Dictionary:
	var f = SysUtil.folk(folk_id)
	if f == null:
		return DeathCauses.kill_townie(folk_id, cause) if Story.is_townie(folk_id) else {}
	var cdef: Dictionary = DeathCauses.def(cause)
	Family.note_person(folk_id, str(f.name))          # remembers the sex for the words that follow the death
	var legacy: Dictionary = legacy_summary(folk_id)
	var rec0: Dictionary = records.get(folk_id, {})
	legacy["cause"] = str(cdef["label"])
	legacy["cause_id"] = str(cdef["id"])
	legacy["day"] = SysUtil.day()
	legacy["born_day"] = int(rec0.get("born_day", 0))
	if str(cdef.get("legacy_text", "")) != "":
		legacy["summary"] = "%s %s" % [legacy["summary"], Sexes.fill(str(cdef["legacy_text"]), folk_id)]
	SysUtil.game_event("folk_collapsing", {"folk_id": folk_id, "cause": str(cdef["id"]), "tile": [f.tile.x, f.tile.y]})
	# relatives and friends grieve (strength / length depend on the cause), kids included
	var mourners: Array = []
	for o in SysUtil.residents():
		if int(o.id) == folk_id:
			continue
		var close: float = DeathCauses.closeness(int(o.id), folk_id)
		if close > 0.0:
			mourners.append(int(o.id))
			DeathCauses.grieve(o, folk_id, str(f.name), cdef, close)
	legacy["mourners"] = mourners
	var succession: Dictionary = Succession.begin(folk_id)          # task 15: the head of a player household? (the spouse link is still there)
	FamilyHousehold.on_death(folk_id, mourners)
	legacy["inheritance"] = _inherit(f, mourners)
	RelationshipService.sync_folk(f)
	f.cancel_current("died")
	f.clear_queue()
	Hospital.patients.erase(folk_id)
	f.remove_buff("in_hospital")
	SysUtil.world_remove_folk(folk_id)
	Graves.place_for(legacy, f, cdef)
	records.erase(folk_id)
	pregnancies.erase(folk_id)
	Careers.forget(folk_id)
	dead.append(legacy)
	if Story.townies.has(folk_id):
		Story.townies[folk_id]["alive"] = false
		Story.townies[folk_id]["died_day"] = SysUtil.day()
	var text: String = DeathCauses.fill(str(cdef.get("text", "")), str(f.name), cdef, str(legacy["summary"]), folk_id)
	SysUtil.notify(text, "death")
	DeathCauses.last_notified = folk_id          # a case that finds the body later does not say it twice
	ChronicleHook.note("death", "%s died (%s)." % [f.name, str(cdef["label"]).to_lower()], [folk_id], "home:%d" % int(f.household_id), int(cdef.get("severity", 3)), true)
	SysUtil.game_event("died", {"folk_id": folk_id, "cause": str(cdef["id"])})
	DeadPools.purge(folk_id)
	Succession.finish(succession)
	return legacy

static func _inherit(f, mourners: Array) -> Dictionary:
	var hid: int = int(f.household_id)
	if not SysUtil.is_resident(f):
		return {"to": -1, "coins": 0, "note": "no estate"}     # visitors / NPCs (household -1) own nothing: never the town's coins or objects
	var survivors: int = 0
	for o in SysUtil.residents():
		if int(o.household_id) == hid and int(o.id) != int(f.id):
			survivors += 1
	if survivors > 0:
		return {"to": hid, "coins": 0, "note": "household keeps everything"}
	var willed: Dictionary = BankWill.apply(f, mourners)       # task 13: a will names the heir
	if not willed.is_empty():
		return willed
	# household ends: the closest own family inherits funds and the household's objects (friends and strangers never do)
	var heir = null
	for rank in ["spouse", "partner", "family", "sweetheart"]:
		for mid in mourners:
			if RelationshipBits.bit_for(int(mid), int(f.id)) == rank:
				heir = SysUtil.folk(int(mid))
				break
		if heir != null:
			break
	if heir == null:
		return {"to": -1, "coins": 0, "note": "no heir"}
	var coins: int = WorldIface.get_coins(hid)
	if coins > 0:
		Economy.deposit(hid, -coins, "inheritance paid out")
		Economy.deposit(int(heir.household_id), coins, "inheritance from %s" % f.name)
	var moved: int = 0
	for o in Economy.objects_of(hid):
		Economy.owner[int(o.id)] = int(heir.household_id)
		moved += 1
	SysUtil.notify("%s inherited %d coins and %d objects from %s." % [heir.name, coins, moved, f.name], "death")
	return {"to": int(heir.household_id), "heir": int(heir.id), "coins": coins, "objects": moved}

static func legacy_summary(folk_id: int) -> Dictionary:
	var f = SysUtil.folk(folk_id)
	var nm: String = str(f.name) if f != null else SysUtil.folk_name(folk_id)
	var years: int = age_years(folk_id)
	var stage_now: String = str(f.age_stage) if f != null else "adult"
	var career_txt: String = "never held a steady job"
	if Careers.jobs.has(folk_id):
		career_txt = "worked as a %s (level %d)" % [Careers.title_of(folk_id), Careers.level_of(folk_id)]
	elif Careers.retired.has(folk_id):
		career_txt = "retired from the %s career at level %d" % [str(Careers.retired[folk_id]["career"]), int(Careers.retired[folk_id]["level"])]
	var best_skill: String = ""
	var best_lvl: int = 0
	if f != null:
		for s in f.skills:
			if int(f.skills[s]["level"]) > best_lvl:
				best_lvl = int(f.skills[s]["level"])
				best_skill = str(s)
	var friends: int = RelationshipBits.count_bit(folk_id, "friend", true)
	var kids: int = children_of(folk_id).size()
	var asp: String = Goals.aspiration_label(folk_id)
	var summary: String = "%s passed away as %s %s, %s, " % [nm, article(stage_now), str(stage_def(stage_now).get("label", stage_now)).to_lower(), career_txt]
	if best_skill != "":
		summary += "mastered %s %d, " % [best_skill, best_lvl]
	summary += "left %d friends and %d children." % [friends, kids]
	var desc: int = FamilyTree.descendants_of(folk_id).size()
	if desc > kids:
		summary += " %d descendants in all." % desc
	return {"folk_id": folk_id, "name": nm, "years": years, "stage": stage_now, "career": career_txt, "best_skill": best_skill, "best_skill_level": best_lvl,
		"friends": friends, "children": kids, "aspiration": asp, "summary": summary,
		"lifetime_points": Goals.lifetime_points(folk_id), "descendants": desc,
		"spouse": Family.name_of(FamilyTree.spouse_of(folk_id)) if FamilyTree.spouse_of(folk_id) >= 0 else "", "traits": f.traits.duplicate() if f != null else []}

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"records": SysUtil.str_keys(records).duplicate(true), "pregnancies": SysUtil.str_keys(pregnancies).duplicate(true),
		"cooldowns": SysUtil.str_keys(cooldowns), "dead": dead.duplicate(true), "lifespan": lifespan_setting, "preg": Pregnancy.to_dict()}

static func from_dict(d: Dictionary) -> void:
	reset()
	records = SysUtil.int_keys((d.get("records", {}) as Dictionary).duplicate(true))
	pregnancies = SysUtil.int_keys((d.get("pregnancies", {}) as Dictionary).duplicate(true))
	cooldowns = SysUtil.int_keys(d.get("cooldowns", {}))
	dead = (d.get("dead", []) as Array).duplicate(true)
	lifespan_setting = str(d.get("lifespan", ""))
	Pregnancy.from_dict(d.get("preg", {}))
	for k in records:
		var r: Dictionary = records[k]
		r["last_year"] = int(r["last_year"])
		r["born_day"] = int(r["born_day"])
		var kids: Array = []
		for c in r.get("children", []):
			kids.append(int(c))
		r["children"] = kids
		var par: Array = []
		for c in r.get("parents", []):
			par.append(int(c))
		r["parents"] = par
	for k in pregnancies:
		pregnancies[k]["father"] = int(pregnancies[k]["father"])
		pregnancies[k]["due_day"] = int(pregnancies[k]["due_day"])
		pregnancies[k]["started"] = int(pregnancies[k]["started"])
		Pregnancy.normalize_loaded(pregnancies[k])
		if pregnancies[k].has("started_min"):
			pregnancies[k]["started_min"] = int(pregnancies[k]["started_min"])