class_name Family
extends RefCounted
## Family tree + household service. Data: data/family.json.
##  * canonical parent / spouse / ex links for everybody ever seen (residents, townies, the dead) in `parents`,
##    `adoptive`, `spouses`, `exes`; names / ages of people who are no longer on the lot in `people`
##  * relation ids (parent, child, sibling, half_sibling, spouse, fiance, grandparent, grandchild, great_*,
##    aunt_uncle, niece_nephew, cousin, *_in_law, ex_spouse) and display labels by the other person's sex (mother / father, aunt / uncle ...; Sexes.label)
##  * RelationshipService "family" flags + friendship floors are kept in sync (family bits auto-added on every link)
##  * marriage: propose -> engaged (buff `engaged`) -> wedding interaction -> spouse (buff `married`), optional
##    surname sharing, household merge; divorce; moving in / out; adoption of orphan child townies
##  * tree_for(folk_id) -> nested dictionary for the UI
## Public: relation_id(a,b), relation_label(a,b), parents_of, children_of, siblings_of, spouse_of, partner_of,
##   tree_for, invite_to_household, move_out, propose_marriage, marry, divorce, adoptable, adopt, descendants_of.

static var people: Dictionary = {}      # id -> {name, born_day, died_day (-1 alive), died_age_days}
static var parents: Dictionary = {}     # child id -> [parent ids] (biological)
static var adoptive: Dictionary = {}    # child id -> [adoptive parent ids]
static var spouses: Dictionary = {}     # id -> spouse id (current)
static var exes: Dictionary = {}        # id -> [ex spouse ids]
static var engaged: Dictionary = {}     # pair_key -> {a, b, since}
static var trimester: Dictionary = {}   # mother id -> 1..3 (last announced)

static func reset() -> void:
	people.clear()
	parents.clear()
	adoptive.clear()
	spouses.clear()
	exes.clear()
	engaged.clear()
	trimester.clear()

static func cfg() -> Dictionary:
	return SimEnv.data().get_table("family")

# ------------------------------------------------------------------ people store
static func note_person(id: int, nm: String = "", born_day: int = -99999) -> void:
	var p: Dictionary = people.get(id, {})
	if p.is_empty():
		p = {"name": "", "born_day": SysUtil.day(), "died_day": -1, "died_age_days": 0.0}
		people[id] = p
	if nm != "":
		p["name"] = nm
	if SysUtil.folk(id) != null or Story.townies.has(id):
		p["sex"] = Sexes.of(id)           # kept for when they die or leave
	if born_day != -99999:
		p["born_day"] = born_day

static func is_alive(id: int) -> bool:
	if SysUtil.folk(id) != null:
		return true
	if Story.townies.has(id):
		return bool(Story.townies[id]["alive"])
	return int((people.get(id, {}) as Dictionary).get("died_day", -1)) < 0 and people.has(id)

static func name_of(id: int) -> String:
	var f = SysUtil.folk(id)
	if f != null:
		return str(f.name)
	if Story.townies.has(id):
		return str(Story.townies[id]["name"])
	var p: Dictionary = people.get(id, {})
	return str(p.get("name", "Someone"))

static func age_days_of(id: int) -> float:
	if Aging.records.has(id):
		return Aging.age_days(id)
	if Story.townies.has(id):
		return float(Story.townies[id]["age_days"])
	return float((people.get(id, {}) as Dictionary).get("died_age_days", 0.0))

## Everything the systems know about a person, wherever they live: {id, name, traits, appearance, age_days, stage, alive, on_lot, household_id}.
static func person_info(id: int) -> Dictionary:
	var f = SysUtil.folk(id)
	if f != null:
		Genetics.ensure(f)
		return {"id": id, "name": str(f.name), "sex": Sexes.of(id), "traits": f.traits.duplicate(), "appearance": f.appearance, "age_days": age_days_of(id),
			"stage": str(f.age_stage), "alive": true, "on_lot": true, "household_id": int(f.household_id)}
	if Story.townies.has(id):
		var t: Dictionary = Story.townies[id]
		Genetics.ensure(t)
		return {"id": id, "name": str(t["name"]), "sex": Sexes.of_townie(t), "traits": (t["traits"] as Array).duplicate(), "appearance": t["appearance"],
			"age_days": float(t["age_days"]), "stage": Story.stage_of(t), "alive": bool(t["alive"]), "on_lot": false, "household_id": -1}
	var p: Dictionary = people.get(id, {})
	return {"id": id, "name": str(p.get("name", "Someone")), "sex": Sexes.of(id), "traits": [], "appearance": {}, "age_days": float(p.get("died_age_days", 0.0)),
		"stage": Aging.stage_for_days(float(p.get("died_age_days", 0.0))), "alive": false, "on_lot": false, "household_id": -1}

# ------------------------------------------------------------------ linking
static func _push(d: Dictionary, k: int, v: int) -> void:
	var arr: Array = d.get(k, [])
	if not arr.has(v):
		arr.append(v)
	d[k] = arr

## Record `parent` as a parent of `child` and add family bits around them.
static func link_parent(child: int, parent: int, adopted: bool = false, refresh: bool = true) -> void:
	if child == parent or child < 0 or parent < 0:
		return
	_push(adoptive if adopted else parents, child, parent)
	if not people.has(child):
		note_person(child, name_of(child))
	if not people.has(parent):
		note_person(parent, name_of(parent))
	if Aging.records.has(parent):
		var kids: Array = Aging.records[parent]["children"]
		if not kids.has(child):
			kids.append(child)
	if Aging.records.has(child):
		var par: Array = Aging.records[child]["parents"]
		if not par.has(parent):
			par.append(parent)
	if refresh:
		var ring: Array = [child, parent]
		for s in FamilyTree.siblings_of(child):
			ring.append(s)
		for r in ring:
			refresh_bits(int(r))

static func _floor_friendship(a: int, b: int, v: float) -> void:
	for dir in [[a, b], [b, a]]:
		if RelationshipService.value(dir[0], dir[1], "friendship") < v:
			RelationshipService.set_value(dir[0], dir[1], "friendship", v)

## Flag every close relative of `id` as family (RelationshipService bit "family") and lift friendship to a floor.
static func refresh_bits(id: int) -> void:
	var bc: Dictionary = cfg().get("bits", {})
	for rel in relatives(id):
		var o: int = int(rel["id"])
		var kind: String = str(rel["relation"])
		if kind in ["spouse"]:
			continue
		if not RelationshipBits.has_flag(id, o, "family"):
			RelationshipBits.set_flag(id, o, "family", true, false)
		match kind:
			"parent", "child", "adoptive_parent", "adopted_child":
				_floor_friendship(id, o, float(bc.get("parent_friendship", 40)))
			"sibling", "half_sibling":
				_floor_friendship(id, o, float(bc.get("sibling_friendship", 25)))
			"grandparent", "grandchild":
				_floor_friendship(id, o, float(bc.get("grandparent_friendship", 20)))

## Close relatives with the relation id of b relative to `id`: parents, children, siblings, grandparents, grandchildren.
static func relatives(id: int) -> Array:
	var out: Array = []
	var seen: Array = []
	var cands: Array = []
	cands.append_array(FamilyTree.parents_of(id))
	cands.append_array(FamilyTree.children_of(id))
	cands.append_array(FamilyTree.siblings_of(id))
	cands.append_array(FamilyTree.ancestors(id, 2))
	for c in FamilyTree.children_of(id):
		cands.append_array(FamilyTree.children_of(int(c)))
	for o in cands:
		if int(o) == id or seen.has(int(o)):
			continue
		seen.append(int(o))
		var r: String = FamilyTree.relation_id(id, int(o))
		if r in ["parent", "child", "adoptive_parent", "adopted_child", "sibling", "half_sibling", "grandparent", "grandchild"]:
			out.append({"id": int(o), "relation": r})
	return out

# ------------------------------------------------------------------ births
## Called by Aging after a baby was created and registered. Links parents, adds bits, inits baby care.
static func on_birth(baby, mother_id: int, father_id: int) -> void:
	var bid: int = int(baby.id)
	note_person(bid, str(baby.name), SysUtil.day())
	link_parent(bid, mother_id, false, false)
	if father_id >= 0:
		link_parent(bid, father_id, false, false)
	refresh_bits(bid)
	refresh_bits(mother_id)
	if father_id >= 0:
		refresh_bits(father_id)
	trimester.erase(mother_id)
	var m = SysUtil.folk(mother_id)
	var nb: String = str(cfg().get("baby_care", {}).get("new_parent_buff", "new_parent"))
	if m != null:
		m.remove_buff("pregnant_t1")
		m.remove_buff("pregnant_t2")
		m.remove_buff("pregnant_t3")
		m.add_buff(nb)
	var fa = SysUtil.folk(father_id) if father_id >= 0 else null
	if fa != null:
		fa.add_buff(nb)
	BabyCare.on_birth(baby)

## Townie births (Story) record the same links.
static func note_townie_birth(baby_id: int, a: int, b: int) -> void:
	note_person(baby_id, Story.name_of(baby_id), SysUtil.day())
	link_parent(baby_id, a, false, false)
	link_parent(baby_id, b, false, false)
	refresh_bits(baby_id)

# ------------------------------------------------------------------ pregnancy stages
## 0..1 progress of a pregnancy.
static func pregnancy_progress(mother_id: int) -> float:
	var pr: Dictionary = Aging.pregnancies.get(mother_id, {})
	if pr.is_empty():
		return 0.0
	var start_min: float = float(pr.get("started_min", (int(pr["started"]) - 1) * 1440))
	var due_min: float = float(int(pr["due_day"]) - 1) * 1440.0
	return clampf((float(SysUtil.now()) - start_min) / maxf(due_min - start_min, 1.0), 0.0, 1.0)

static func trimester_of(mother_id: int) -> int:
	if not Aging.pregnancies.has(mother_id):
		return 0
	return clampi(int(floor(pregnancy_progress(mother_id) * 3.0)) + 1, 1, 3)

## Set the trimester buff (moods / needs change per stage) and announce transitions.
static func update_pregnancies() -> void:
	var bufs: Array = cfg().get("pregnancy", {}).get("trimester_buffs", ["pregnant_t1", "pregnant_t2", "pregnant_t3"])
	for mid in Aging.pregnancies.keys():
		var f = SysUtil.folk(int(mid))
		if f == null:
			continue
		var tri: int = trimester_of(int(mid))
		for i in bufs.size():
			if i == tri - 1:
				if not f.has_buff(str(bufs[i])):
					f.add_buff(str(bufs[i]))
			elif f.has_buff(str(bufs[i])):
				f.remove_buff(str(bufs[i]))
		if int(trimester.get(int(mid), 0)) != tri:
			trimester[int(mid)] = tri
			if tri > 1:
				SysUtil.notify("%s is in trimester %d." % [f.name, tri], "birthday")
			SysUtil.game_event("trimester", {"folk_id": int(mid), "trimester": tri})

# ------------------------------------------------------------------ events / clock
static func on_hour() -> void:
	update_pregnancies()

static func on_day(_day: int) -> void:
	update_pregnancies()
	var mc: Dictionary = cfg().get("marriage", {})
	for k in engaged.keys():
		var e: Dictionary = engaged[k]
		var v: Dictionary = FamilyMarriage._pair_ro_fr(int(e["a"]), int(e["b"]))
		if float(v["romance"]) < float(mc.get("break_below_romance", 30)):
			FamilyMarriage.break_engagement(int(e["a"]), int(e["b"]), "they drifted apart")
	_toddler_growth()

static func _toddler_growth() -> void:
	var tc: Dictionary = cfg().get("toddler", {})
	for f in SysUtil.residents():
		if str(f.age_stage) == "toddler":
			for s in tc.get("skills", []):
				f.add_skill_xp(str(s), float(tc.get("daily_xp", 15)))

static func toddler_skill_levels(folk_id: int) -> Dictionary:
	var f = SysUtil.folk(folk_id)
	var out: Dictionary = {}
	for s in cfg().get("toddler", {}).get("skills", []):
		out[str(s)] = f.skill_level(str(s)) if f != null else 0
	return out

## Systems-level game events raised by the family interactions. Returns true when handled.
static func on_event(ev_name: String, payload: Dictionary) -> bool:
	var a: int = int(payload.get("folk_id", -1))
	var b: int = int(payload.get("target_id", -1))
	match ev_name:
		"aged_up":
			BabyCare.on_aged_up(a, str(payload.get("from", "")), str(payload.get("to", "")))
			return false
		"wedding":
			if not FamilyMarriage.marry(a, b):
				SysUtil.notify("They are not engaged.", "info")
			return true
		"divorce":
			if not FamilyMarriage.divorce(a, b, b):
				SysUtil.notify("They are not married.", "info")
			return true
		"adopt_child":
			var list: Array = FamilyHousehold.adoptable(true)
			if list.is_empty():
				SysUtil.notify("There are no children to adopt right now.", "info")
			else:
				var res: Dictionary = FamilyHousehold.adopt(int(list[0]["id"]), a)
				if not bool(res["ok"]):
					SysUtil.notify("The adoption didn't go through (%s)." % str(res["reason"]), "info")
			return true
		"move_in_request":
			var tf = SysUtil.folk(b)
			var af = SysUtil.folk(a)
			if tf == null or af == null:
				return true
			var mn: float = float(cfg().get("moving", {}).get("min_friendship", 35))
			var ok: bool = RelationshipService.value(b, a, "friendship") >= mn or FamilyTree.spouse_of(a) == b or FamilyTree.fiance_of(a) == b
			if int(tf.household_id) == int(af.household_id):
				SysUtil.notify("%s already lives here." % tf.name, "info")
			elif ok:
				FamilyHousehold.invite_to_household(b, int(af.household_id))
			else:
				SysUtil.notify("%s isn't ready to move in." % tf.name, "info")
			return true
		"teach_walking", "teach_talking", "teach_potty":
			var tc: Dictionary = cfg().get("toddler", {})
			var sk: String = ev_name.substr(6)
			var kid = SysUtil.folk(b)
			if kid != null:
				kid.add_skill_xp(sk, float(tc.get("lesson_xp", 40)))
			return true
	return false

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"people": SysUtil.str_keys(people).duplicate(true), "parents": SysUtil.str_keys(parents).duplicate(true),
		"adoptive": SysUtil.str_keys(adoptive).duplicate(true), "spouses": SysUtil.str_keys(spouses).duplicate(true),
		"exes": SysUtil.str_keys(exes).duplicate(true), "engaged": engaged.duplicate(true), "trimester": SysUtil.str_keys(trimester)}

static func from_dict(d: Dictionary) -> void:
	reset()
	people = SysUtil.int_keys((d.get("people", {}) as Dictionary).duplicate(true))
	for k in people:
		var p: Dictionary = people[k]
		p["born_day"] = int(p.get("born_day", 0))
		p["died_day"] = int(p.get("died_day", -1))
		p["died_age_days"] = float(p.get("died_age_days", 0.0))
	parents = SysUtil.int_array_dict(d.get("parents", {}))
	adoptive = SysUtil.int_array_dict(d.get("adoptive", {}))
	exes = SysUtil.int_array_dict(d.get("exes", {}))
	for k2 in (d.get("spouses", {}) as Dictionary):
		spouses[int(str(k2))] = int(d["spouses"][k2])
	for k3 in (d.get("engaged", {}) as Dictionary):
		var e: Dictionary = d["engaged"][k3]
		engaged[str(k3)] = {"a": int(e["a"]), "b": int(e["b"]), "since": int(e["since"])}
	for k4 in (d.get("trimester", {}) as Dictionary):
		trimester[int(str(k4))] = int(d["trimester"][k4])

# ---- thin delegates (called from UI / views)
static func relation_label(a: int, b: int) -> String:
	return FamilyTree.relation_label(a, b)

static func tree_for(folk_id: int, up: int = 2, down: int = 3) -> Dictionary:
	return FamilyTree.tree_for(folk_id, up, down)
