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
		var sd: Dictionary = stage_def(str(f.age_stage))
		var start: float = float(sd.get("from_day", 44))
		var idx: int = stage_index(str(f.age_stage))
		var nxt: float = start + 8.0
		if idx >= 0 and idx + 1 < stage_table().size():
			nxt = float(stage_table()[idx + 1]["from_day"])
		age_days = start + (nxt - start) * 0.35
	records[fid] = {"age_days": age_days, "last_year": int(floor(age_days / days_per_year())), "parents": parents.duplicate(),
		"inherited": [], "children": [], "born_day": SysUtil.day() - int(age_days)}
	f.age_stage = stage_for_days(age_days)
	apply_stage_buff(f)

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
		var years: int = int(floor(float(rec["age_days"]) / days_per_year()))
		if years > int(rec["last_year"]):
			rec["last_year"] = years
			_birthday(f, years)
		var nw: String = stage_for_days(float(rec["age_days"]))
		if nw != str(f.age_stage):
			_age_up(f, nw)
	_check_births()
	_check_deaths()

static func _birthday(f, years: int) -> void:
	SysUtil.notify("It's %s's birthday! They are now %d." % [f.name, years], "birthday")
	SysUtil.game_event("birthday", {"folk_id": f.id, "age": years})
	f.add_buff("cheered_up")

static func _age_up(f, new_stage: String) -> void:
	var old: String = str(f.age_stage)
	f.age_stage = new_stage
	apply_stage_buff(f)
	var label: String = str(stage_def(new_stage).get("label", new_stage))
	SysUtil.notify("%s grew up into a %s!" % [f.name, label.to_lower()], "birthday")
	SysUtil.game_event("aged_up", {"folk_id": f.id, "from": old, "to": new_stage})
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
		for t in SimEnv.data().traits():
			if not f.traits.has(t):
				cand.append(t)
	if can_add_trait(f) and not cand.is_empty():
		var t2 = SysUtil.pick(cand)
		f.traits.append(str(t2))
		SysUtil.notify("%s's personality is showing: %s." % [f.name, str(SimEnv.data().trait_def(str(t2)).get("label", t2))], "birthday")

# ------------------------------------------------------------------ pregnancy / birth
## Returns {"ok": bool, "reason": String}. `actor_id` carries the pregnancy.
static func try_for_baby(actor_id: int, partner_id: int) -> Dictionary:
	var a = SysUtil.folk(actor_id)
	var b = SysUtil.folk(partner_id)
	var pc: Dictionary = cfg().get("pregnancy", {})
	if a == null or b == null:
		return {"ok": false, "reason": "missing"}
	var min_idx: int = stage_index(str(pc.get("min_stage", "adult")))
	if stage_index(str(a.age_stage)) < min_idx or stage_index(str(b.age_stage)) < min_idx:
		return {"ok": false, "reason": "too_young"}
	if pregnancies.has(actor_id) or pregnancies.has(partner_id) or a.has_buff("pregnant"):
		return {"ok": false, "reason": "already_pregnant"}
	if SysUtil.day() < int(cooldowns.get(actor_id, 0)):
		return {"ok": false, "reason": "cooldown"}
	var rom: float = minf(RelationshipService.value(actor_id, partner_id, "romance"), RelationshipService.value(partner_id, actor_id, "romance"))
	if rom < float(pc.get("min_romance", 45)):
		return {"ok": false, "reason": "not_romantic_enough"}
	if not (RelationshipBits.bit_for(actor_id, partner_id) in ["sweetheart", "partner", "spouse"]):
		return {"ok": false, "reason": "not_a_couple"}
	cooldowns[actor_id] = SysUtil.day() + int(pc.get("cooldown_days", 4))
	if not SysUtil.chance(float(pc.get("success_chance", 0.45))):
		return {"ok": false, "reason": "no_luck"}
	pregnancies[actor_id] = {"father": partner_id, "due_day": SysUtil.day() + int(pc.get("days", 3)), "started": SysUtil.day(), "started_min": SysUtil.now()}
	a.add_buff("pregnant")
	Family.update_pregnancies()
	SysUtil.notify("%s is expecting a baby!" % a.name, "birthday")
	SysUtil.game_event("pregnant", {"folk_id": actor_id, "target_id": partner_id})
	return {"ok": true, "reason": "pregnant"}

static func _check_births() -> void:
	for mid in pregnancies.keys():
		if SysUtil.day() >= int(pregnancies[mid]["due_day"]):
			_birth(int(mid), int(pregnancies[mid]["father"]))
			pregnancies.erase(mid)

static func _birth(mother_id: int, father_id: int) -> void:
	var m = SysUtil.folk(mother_id)
	if m == null:
		return
	var pc: Dictionary = cfg().get("pregnancy", {})
	var father = SysUtil.folk(father_id)
	var gen: Dictionary = Genetics.inherit(Family.person_info(mother_id), Family.person_info(father_id), null,
		{"chance": float(pc.get("inherit_chance", 0.35)), "cap": int(pc.get("max_inherited", 2))})
	var inherited: Array = gen["traits"]
	var names: Array = cfg().get("name_pool", ["Pip"])
	var baby_name: String = str(SysUtil.pick(names)) + " " + _surname(str(m.name))
	var baby := Folk.create(baby_name, [])
	baby.appearance = gen["appearance"]
	baby.household_id = int(m.household_id)
	baby.age_stage = "baby"
	register(baby, 0.0, [mother_id, father_id])
	(records[int(baby.id)] as Dictionary)["inherited"] = inherited
	for pid in [mother_id, father_id]:
		if records.has(pid):
			(records[pid]["children"] as Array).append(int(baby.id))
	SysUtil.world_add_folk(baby, m.tile)
	m.remove_buff("pregnant")
	Family.on_birth(baby, mother_id, father_id)
	for pid2 in [mother_id, father_id]:
		RelationshipBits.set_flag(int(baby.id), int(pid2), "family", true, false)
		RelationshipService.add_both(int(baby.id), int(pid2), "friendship", 40.0)
	RelationshipBits.set_flag(mother_id, father_id, "family", true, false)
	SysUtil.notify("%s was born to %s!" % [baby_name, m.name], "birthday")
	SysUtil.game_event("baby_born", {"folk_id": mother_id, "baby_id": baby.id, "target_id": father_id})

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
	var legacy: Dictionary = legacy_summary(folk_id)
	var rec0: Dictionary = records.get(folk_id, {})
	legacy["cause"] = str(cdef["label"])
	legacy["cause_id"] = str(cdef["id"])
	legacy["day"] = SysUtil.day()
	legacy["born_day"] = int(rec0.get("born_day", 0))
	if str(cdef.get("legacy_text", "")) != "":
		legacy["summary"] = "%s %s" % [legacy["summary"], cdef["legacy_text"]]
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
	var text: String = DeathCauses.fill(str(cdef.get("text", "")), str(f.name), cdef, str(legacy["summary"]))
	SysUtil.notify(text, "death")
	ChronicleHook.note("death", "%s died (%s)." % [f.name, str(cdef["label"]).to_lower()], [folk_id], "home:%d" % int(f.household_id), int(cdef.get("severity", 3)), true)
	SysUtil.game_event("died", {"folk_id": folk_id, "cause": str(cdef["id"])})
	return legacy

static func _inherit(f, mourners: Array) -> Dictionary:
	var hid: int = int(f.household_id)
	var survivors: int = 0
	for o in SysUtil.residents():
		if int(o.household_id) == hid and int(o.id) != int(f.id):
			survivors += 1
	if survivors > 0:
		return {"to": hid, "coins": 0, "note": "household keeps everything"}
	# household ends: closest heir inherits funds and the lot's objects
	var heir = null
	for rank in ["spouse", "partner", "family", "sweetheart", "best_friend"]:
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
	var summary: String = "%s lived %d years, %s, " % [nm, years, career_txt]
	if best_skill != "":
		summary += "mastered %s %d, " % [best_skill, best_lvl]
	summary += "left %d friends and %d children." % [friends, kids]
	var desc: int = FamilyTree.descendants_of(folk_id).size()
	if desc > kids:
		summary += " %d descendants in all." % desc
	return {"folk_id": folk_id, "name": nm, "years": years, "career": career_txt, "best_skill": best_skill, "best_skill_level": best_lvl,
		"friends": friends, "children": kids, "aspiration": asp, "summary": summary,
		"lifetime_points": Goals.lifetime_points(folk_id), "descendants": desc,
		"spouse": Family.name_of(FamilyTree.spouse_of(folk_id)) if FamilyTree.spouse_of(folk_id) >= 0 else "", "traits": f.traits.duplicate() if f != null else []}

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"records": SysUtil.str_keys(records).duplicate(true), "pregnancies": SysUtil.str_keys(pregnancies).duplicate(true),
		"cooldowns": SysUtil.str_keys(cooldowns), "dead": dead.duplicate(true), "lifespan": lifespan_setting}

static func from_dict(d: Dictionary) -> void:
	reset()
	records = SysUtil.int_keys((d.get("records", {}) as Dictionary).duplicate(true))
	pregnancies = SysUtil.int_keys((d.get("pregnancies", {}) as Dictionary).duplicate(true))
	cooldowns = SysUtil.int_keys(d.get("cooldowns", {}))
	dead = (d.get("dead", []) as Array).duplicate(true)
	lifespan_setting = str(d.get("lifespan", ""))
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
		if pregnancies[k].has("started_min"):
			pregnancies[k]["started_min"] = int(pregnancies[k]["started_min"])
