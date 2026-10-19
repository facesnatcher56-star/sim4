class_name FamilyHousehold
extends RefCounted
## Moving out / in, adoption and death.

# ------------------------------------------------------------------ households
## Leave the lot: becomes an off-lot townie keeping their id (relationships, family links and age carry over).
static func move_out(folk_id: int, coin_share: float = 0.5, orphan: bool = false) -> bool:
	var f = SysUtil.folk(folk_id)
	if f == null:
		return false
	var hid: int = int(f.household_id)
	var coins: int = 0
	if coin_share > 0.0 and hid > 0:
		coins = int(floor(float(WorldIface.get_coins(hid)) * coin_share))
		if coins > 0:
			WorldIface.add_coins(hid, -coins)
	var age: float = Family.age_days_of(folk_id)
	f.cancel_current("moved out")
	f.clear_queue()
	RelationshipService.sync_folk(f)
	Genetics.ensure(f)
	var t: Dictionary = {"id": folk_id, "name": str(f.name), "sex": Sexes.of(folk_id), "traits": f.traits.duplicate(), "age_days": age, "career": "", "level": 1,
		"coins": coins, "alive": true, "lot": 1, "last_visit_day": SysUtil.day(),
		"appearance": f.appearance.duplicate(true), "moved_out": true}
	if orphan:
		t["orphan"] = true
	Story.townies[folk_id] = t
	Family.note_person(folk_id, str(f.name))
	Careers.forget(folk_id)
	Aging.pregnancies.erase(folk_id)
	Aging.records.erase(folk_id)
	BabyCare.state.erase(folk_id)
	SysUtil.world_remove_folk(folk_id)
	SysUtil.game_event("moved_out", {"folk_id": folk_id, "household_id": hid})
	SysUtil.notify("%s moved out." % t["name"], "story")
	return true

## Move a townie / visitor / folk of another household into `household_id`. Returns true when it happened.
static func invite_to_household(person_id: int, household_id: int) -> bool:
	var f = SysUtil.folk(person_id)
	if f != null and _is_townie_npc(f):
		Crowd.dismiss(f)                 # a townie out in town (crowd NPC / party guest) has no autonomy and no needs care: they come in as a fresh household member
		f = null
	if f != null:
		if int(f.household_id) == household_id:
			return false
		if not SleepPlaces.make_room(household_id, FamilyMarriage._given(str(f.name)), str(f.age_stage)):
			return false
		var was_visitor: bool = f.has_meta("visitor")
		FamilyMarriage._move_household(f, household_id)
		if was_visitor or not Aging.records.has(person_id):
			var tt: Dictionary = Story.townies.get(person_id, {})
			if f.has_meta("townie_id"):
				f.remove_meta("townie_id")
			Aging.register(f, float(tt.get("age_days", -1.0)), FamilyTree.parents_of(person_id))
			if not tt.is_empty():
				tt["alive"] = false
				tt["moved_in"] = true
			Goals.ensure_profile(f)
		_after_move_in(f)
		return true
	var t: Dictionary = Story.townies.get(person_id, {})
	if t.is_empty() or not bool(t["alive"]):
		return false
	if not SleepPlaces.make_room(household_id, FamilyMarriage._given(str(t["name"])), Story.stage_of(t)):
		return false
	var keep_next: int = Folk._next_id
	var nf := Folk.create(str(t["name"]), (t["traits"] as Array).duplicate(), person_id, Sexes.of_townie(t))
	Folk._next_id = keep_next
	nf.household_id = household_id
	nf.age_stage = Story.stage_of(t)
	nf.appearance = Genetics.normalize(Genetics.ensure(t))
	for n in nf.needs:
		(nf.needs[n] as Stat).set_value(SysUtil.rng.randf_range(30.0, 70.0))
	RelationshipService.restore_folk(nf)
	var door: Vector2i = NeighborhoodLots.entry_tile(PlayerLots.home_of_household(household_id))      # the household's own lot (co-op players have theirs)
	SysUtil.world_add_folk(nf, door if door.x >= 0 else StoryVisits.entrance())
	Aging.register(nf, float(t["age_days"]), FamilyTree.parents_of(person_id))
	Goals.ensure_profile(nf)
	t["alive"] = false
	t["moved_in"] = true
	Family.note_person(person_id, str(nf.name))
	_after_move_in(nf)
	return true

## A townie who is out in town as an ambient NPC or a guest (not staff), still waiting in the townie book.
static func _is_townie_npc(f) -> bool:
	if not f.has_meta("visitor") or not f.has_meta("townie_id") or f.has_meta("staff") or f.has_meta("burglar"):
		return false
	var t: Dictionary = Story.townies.get(int(f.get_meta("townie_id")), {})
	return not t.is_empty() and bool(t["alive"])

static func _after_move_in(f) -> void:
	Genetics.ensure(f)
	Family.refresh_bits(int(f.id))
	if str(f.age_stage) in ["baby", "toddler"]:
		BabyCare.on_birth(f, false)
	SysUtil.notify("%s moved in!" % f.name, "story")
	SysUtil.game_event("moved_in", {"folk_id": int(f.id), "household_id": int(f.household_id)})

# ------------------------------------------------------------------ adoption
## Orphan child townies up for adoption (spawns a few when there are none and `spawn_if_empty`).
static func adoptable(spawn_if_empty: bool = false) -> Array:
	var ac: Dictionary = Family.cfg().get("adoption", {})
	var out: Array = []
	for id in Story.townies:
		var t: Dictionary = Story.townies[id]
		if bool(t["alive"]) and bool(t.get("orphan", false)) and (ac.get("stages", []) as Array).has(Story.stage_of(t)):
			out.append(t)
	if out.is_empty() and spawn_if_empty:
		spawn_orphans(int(ac.get("orphans", 3)))
		return adoptable(false)
	return out

static func spawn_orphans(n: int) -> Array:
	var ac: Dictionary = Family.cfg().get("adoption", {})
	var made: Array = []
	for _i in n:
		var days: float = SysUtil.rng.randf_range(float(ac.get("age_days_min", 1)), float(ac.get("age_days_max", 24)))
		var t: Dictionary = Story.add_townie(days, "", [])
		t["traits"] = []
		t["orphan"] = true
		t["career"] = ""
		t["coins"] = 0
		var slots: int = Aging.trait_slots(Story.stage_of(t))
		var pool: Array = Genetics.inherit_traits({}, {}, null, {"cap": slots, "extra": mini(slots, 2)})
		t["traits"] = pool
		made.append(t)
	return made

## Adopt townie `townie_id` into the household of `parent_id` (and the co-parent, default the parent's spouse).
static func adopt(townie_id: int, parent_id: int, co_parent_id: int = -1) -> Dictionary:
	var p = SysUtil.folk(parent_id)
	if p == null or not SysUtil.is_resident(p):
		return {"ok": false, "reason": "no_parent"}
	if not (str(p.age_stage) in ["adult", "elder"]):
		return {"ok": false, "reason": "too_young"}
	var t: Dictionary = Story.townies.get(townie_id, {})
	if t.is_empty() or not bool(t["alive"]):
		return {"ok": false, "reason": "unavailable"}
	if not (Family.cfg().get("adoption", {}).get("stages", []) as Array).has(Story.stage_of(t)):
		return {"ok": false, "reason": "too_old"}
	if co_parent_id < 0:
		var sp: int = FamilyTree.spouse_of(parent_id)
		if sp >= 0 and SysUtil.folk(sp) != null and int(SysUtil.folk(sp).household_id) == int(p.household_id):
			co_parent_id = sp
	var surname: String = FamilyMarriage._surname(str(p.name))
	if not invite_to_household(townie_id, int(p.household_id)):
		return {"ok": false, "reason": "failed"}
	if surname != "":
		FamilyMarriage._set_name(townie_id, "%s %s" % [FamilyMarriage._given(str(t["name"])), surname])
	Family.link_parent(townie_id, parent_id, true, false)
	if co_parent_id >= 0:
		Family.link_parent(townie_id, co_parent_id, true, false)
	Family.refresh_bits(townie_id)
	var fr: float = float(Family.cfg().get("adoption", {}).get("friendship", 30))
	for pid in [parent_id, co_parent_id]:
		if int(pid) >= 0:
			Family._floor_friendship(townie_id, int(pid), fr)
	t.erase("orphan")
	SysUtil.notify("%s was adopted by %s!" % [Family.name_of(townie_id), p.name], "birthday")
	SysUtil.game_event("adopted", {"folk_id": parent_id, "child_id": townie_id, "target_id": townie_id})
	return {"ok": true, "reason": "adopted", "child_id": townie_id}

# ------------------------------------------------------------------ death
static func on_death(folk_id: int, mourners: Array) -> void:
	var p: Dictionary = Family.people.get(folk_id, {})
	if p.is_empty():
		Family.note_person(folk_id, Family.name_of(folk_id))
		p = Family.people[folk_id]
	p["died_day"] = SysUtil.day()
	p["died_age_days"] = Aging.age_days(folk_id)
	p["name"] = Family.name_of(folk_id)
	var sp: int = FamilyTree.spouse_of(folk_id)
	var mc: Dictionary = Family.cfg().get("marriage", {})
	if sp >= 0:
		Family.spouses.erase(sp)
		Family.spouses.erase(folk_id)
		var sf = SysUtil.folk(sp)
		if sf != null:
			sf.remove_buff(str(mc.get("married_buff", "married")))
			sf.remove_buff(str(mc.get("newlywed_buff", "newlywed")))
			sf.add_buff("widowed")
			SysUtil.notify("%s is a widow(er) now." % sf.name, "death")
	var fi: int = FamilyTree.fiance_of(folk_id)
	if fi >= 0:
		Family.engaged.erase(SysUtil.pair_key(fi, folk_id))
		var ff = SysUtil.folk(fi)
		if ff != null:
			ff.remove_buff(str(mc.get("engaged_buff", "engaged")))
	for m in mourners:
		var r: String = FamilyTree.relation_id(int(m), folk_id)
		if r in ["parent", "child", "adoptive_parent", "adopted_child", "sibling"]:
			var mf = SysUtil.folk(int(m))
			if mf != null:
				mf.add_buff("bereaved")
	Family.trimester.erase(folk_id)
	BabyCare.state.erase(folk_id)
