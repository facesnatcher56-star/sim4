class_name Family
extends RefCounted
## Family tree + household service. Data: data/family.json.
##  * canonical parent / spouse / ex links for everybody ever seen (residents, townies, the dead) in `parents`,
##    `adoptive`, `spouses`, `exes`; names / ages of people who are no longer on the lot in `people`
##  * relation ids (parent, child, sibling, half_sibling, spouse, fiance, grandparent, grandchild, great_*,
##    aunt_uncle, niece_nephew, cousin, *_in_law, ex_spouse) and neutral display labels (Folk have no gender)
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

static func age_years_of(id: int) -> int:
	return int(floor(age_days_of(id) / Aging.days_per_year()))

## Everything the systems know about a person, wherever they live: {id, name, traits, appearance, age_days, stage, alive, on_lot, household_id}.
static func person_info(id: int) -> Dictionary:
	var f = SysUtil.folk(id)
	if f != null:
		Genetics.ensure(f)
		return {"id": id, "name": str(f.name), "traits": f.traits.duplicate(), "appearance": f.appearance, "age_days": age_days_of(id),
			"stage": str(f.age_stage), "alive": true, "on_lot": true, "household_id": int(f.household_id)}
	if Story.townies.has(id):
		var t: Dictionary = Story.townies[id]
		Genetics.ensure(t)
		return {"id": id, "name": str(t["name"]), "traits": (t["traits"] as Array).duplicate(), "appearance": t["appearance"],
			"age_days": float(t["age_days"]), "stage": Story.stage_of(t), "alive": bool(t["alive"]), "on_lot": false, "household_id": -1}
	var p: Dictionary = people.get(id, {})
	return {"id": id, "name": str(p.get("name", "Someone")), "traits": [], "appearance": {}, "age_days": float(p.get("died_age_days", 0.0)),
		"stage": Aging.stage_for_days(float(p.get("died_age_days", 0.0))), "alive": false, "on_lot": false, "household_id": -1}

# ------------------------------------------------------------------ graph queries
static func _ints(a) -> Array:
	var out: Array = []
	for x in a:
		out.append(int(x))
	return out

static func bio_parents_of(id: int) -> Array:
	return _ints(parents.get(id, []))

static func parents_of(id: int) -> Array:
	var out: Array = bio_parents_of(id)
	for p in adoptive.get(id, []):
		if not out.has(int(p)):
			out.append(int(p))
	return out

static func children_of(id: int) -> Array:
	var out: Array = []
	for c in parents:
		if (parents[c] as Array).has(id) and not out.has(int(c)):
			out.append(int(c))
	for c2 in adoptive:
		if (adoptive[c2] as Array).has(id) and not out.has(int(c2)):
			out.append(int(c2))
	out.sort()
	return out

## Full and half siblings (share at least one parent).
static func siblings_of(id: int) -> Array:
	var out: Array = []
	for p in parents_of(id):
		for c in children_of(int(p)):
			if int(c) != id and not out.has(int(c)):
				out.append(int(c))
	out.sort()
	return out

static func is_full_sibling(a: int, b: int) -> bool:
	var pa: Array = parents_of(a)
	var pb: Array = parents_of(b)
	if pa.size() < 2 or pb.size() < 2:
		return false
	for p in pa:
		if not pb.has(p):
			return false
	return true

static func spouse_of(id: int) -> int:
	return int(spouses.get(id, -1))

static func fiance_of(id: int) -> int:
	for k in engaged:
		var e: Dictionary = engaged[k]
		if int(e["a"]) == id:
			return int(e["b"])
		if int(e["b"]) == id:
			return int(e["a"])
	return -1

## Romantic partner id and status ("spouse" | "fiance" | "partner" | "sweetheart"), or {}.
static func partner_of(id: int) -> Dictionary:
	var s: int = spouse_of(id)
	if s >= 0:
		return {"id": s, "status": "spouse"}
	var fi: int = fiance_of(id)
	if fi >= 0:
		return {"id": fi, "status": "fiance"}
	for o in RelationshipService.romantic_partners(id):
		for st in ["partner", "sweetheart"]:
			if RelationshipService.has_flag(id, int(o), st):
				return {"id": int(o), "status": st}
	return {}

static func ancestors(id: int, depth: int) -> Array:
	var level: Array = [id]
	var seen: Array = []
	for _d in depth:
		var nxt: Array = []
		for x in level:
			for p in parents_of(int(x)):
				if not nxt.has(p):
					nxt.append(p)
		level = nxt
	seen = level
	return seen

static func descendants_of(id: int) -> Array:
	var out: Array = []
	var stack: Array = children_of(id)
	while not stack.is_empty():
		var c: int = int(stack.pop_back())
		if out.has(c):
			continue
		out.append(c)
		for g in children_of(c):
			stack.append(g)
	out.sort()
	return out

## What is b to a? Returns a relation id ("" when unrelated).
static func relation_id(a: int, b: int) -> String:
	if a == b:
		return "self"
	if spouse_of(a) == b:
		return "spouse"
	if fiance_of(a) == b:
		return "fiance"
	if bio_parents_of(a).has(b):
		return "parent"
	if (adoptive.get(a, []) as Array).has(b):
		return "adoptive_parent"
	if bio_parents_of(b).has(a):
		return "child"
	if (adoptive.get(b, []) as Array).has(a):
		return "adopted_child"
	if siblings_of(a).has(b):
		return "sibling" if is_full_sibling(a, b) else "half_sibling"
	if ancestors(a, 2).has(b):
		return "grandparent"
	if ancestors(b, 2).has(a):
		return "grandchild"
	if ancestors(a, 3).has(b):
		return "great_grandparent"
	if ancestors(b, 3).has(a):
		return "great_grandchild"
	for p in parents_of(a):
		if siblings_of(int(p)).has(b):
			return "aunt_uncle"
	for p2 in parents_of(b):
		if siblings_of(int(p2)).has(a):
			return "niece_nephew"
	for pa in parents_of(a):
		for pb in parents_of(b):
			if siblings_of(int(pa)).has(pb):
				return "cousin"
	var sa: int = spouse_of(a)
	if sa >= 0 and parents_of(sa).has(b):
		return "parent_in_law"
	var sb: int = spouse_of(b)
	if sb >= 0 and parents_of(sb).has(a):
		return "child_in_law"
	if sa >= 0 and siblings_of(sa).has(b):
		return "sibling_in_law"
	if sb >= 0 and siblings_of(a).has(sb):
		return "sibling_in_law"
	if (exes.get(a, []) as Array).has(b):
		return "ex_spouse"
	return ""

static func relation_label(a: int, b: int) -> String:
	var rid: String = relation_id(a, b)
	if rid == "":
		return ""
	return str(cfg().get("labels", {}).get(rid, rid.capitalize()))

static func is_kin(a: int, b: int) -> bool:
	var r: String = relation_id(a, b)
	return r != "" and r not in ["ex_spouse", "fiance"]

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
		for s in siblings_of(child):
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
		if not RelationshipService.has_flag(id, o, "family"):
			RelationshipService.set_flag(id, o, "family", true, false)
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
	cands.append_array(parents_of(id))
	cands.append_array(children_of(id))
	cands.append_array(siblings_of(id))
	cands.append_array(ancestors(id, 2))
	for c in children_of(id):
		cands.append_array(children_of(int(c)))
	for o in cands:
		if int(o) == id or seen.has(int(o)):
			continue
		seen.append(int(o))
		var r: String = relation_id(id, int(o))
		if r in ["parent", "child", "adoptive_parent", "adopted_child", "sibling", "half_sibling", "grandparent", "grandchild"]:
			out.append({"id": int(o), "relation": r})
	return out

# ------------------------------------------------------------------ tree for the UI
static func node(id: int) -> Dictionary:
	var info: Dictionary = person_info(id)
	var ay: int = int(floor(float(info["age_days"]) / Aging.days_per_year()))
	return {"id": id, "name": info["name"], "stage": info["stage"], "age_years": ay, "alive": info["alive"], "on_lot": info["on_lot"],
		"household_id": info["household_id"]}

static func _up(id: int, depth: int) -> Dictionary:
	var n: Dictionary = node(id)
	var ps: Array = []
	if depth > 0:
		for p in parents_of(id):
			var pn: Dictionary = _up(int(p), depth - 1)
			pn["adoptive"] = (adoptive.get(id, []) as Array).has(int(p))
			ps.append(pn)
	n["parents"] = ps
	return n

static func _down(id: int, depth: int) -> Dictionary:
	var n: Dictionary = node(id)
	var kids: Array = []
	if depth > 0:
		for c in children_of(id):
			var cn: Dictionary = _down(int(c), depth - 1)
			cn["adopted"] = (adoptive.get(int(c), []) as Array).has(id)
			kids.append(cn)
	n["children"] = kids
	return n

## {id,name,stage,age_years,alive,on_lot, partner:{...,status}|{}, spouse:{}|node, exes:[node], parents:[nested up],
##  siblings:[node+half], children:[nested down], grandchildren_count}
static func tree_for(folk_id: int, up: int = 2, down: int = 3) -> Dictionary:
	var t: Dictionary = node(folk_id)
	t["parents"] = _up(folk_id, up)["parents"]
	t["children"] = _down(folk_id, down)["children"]
	var sibs: Array = []
	for s in siblings_of(folk_id):
		var sn: Dictionary = node(int(s))
		sn["half"] = not is_full_sibling(folk_id, int(s))
		sibs.append(sn)
	t["siblings"] = sibs
	var sp: int = spouse_of(folk_id)
	t["spouse"] = node(sp) if sp >= 0 else {}
	var pt: Dictionary = partner_of(folk_id)
	if pt.is_empty():
		t["partner"] = {}
	else:
		var pn2: Dictionary = node(int(pt["id"]))
		pn2["status"] = str(pt["status"])
		t["partner"] = pn2
	var ex_nodes: Array = []
	for e in exes.get(folk_id, []):
		ex_nodes.append(node(int(e)))
	t["exes"] = ex_nodes
	t["descendants"] = descendants_of(folk_id).size()
	return t

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

# ------------------------------------------------------------------ marriage
static func _pair_ro_fr(a: int, b: int) -> Dictionary:
	return {"romance": minf(RelationshipService.value(a, b, "romance"), RelationshipService.value(b, a, "romance")),
		"friendship": minf(RelationshipService.value(a, b, "friendship"), RelationshipService.value(b, a, "friendship"))}

static func is_engaged(a: int, b: int) -> bool:
	return engaged.has(SysUtil.pair_key(a, b))

## Handles the `propose` interaction: partner -> engaged; everything else keeps the old sweetheart -> partner path.
## Returns "engaged" | "already_engaged" | "already_married" | "declined" | "too_soon" | "no_bond" | "accepted" (became partners).
static func on_propose(a: int, b: int) -> String:
	if spouse_of(a) == b:
		return "already_married"
	if is_engaged(a, b):
		return "already_engaged"
	if RelationshipService.has_flag(a, b, "partner"):
		return propose_marriage(a, b)
	return RelationshipService.propose(a, b)

static func propose_marriage(a: int, b: int) -> String:
	if spouse_of(a) == b:
		return "already_married"
	if is_engaged(a, b):
		return "already_engaged"
	if not RelationshipService.has_flag(a, b, "partner"):
		return "no_bond"
	if spouse_of(a) >= 0 or spouse_of(b) >= 0 or fiance_of(a) >= 0 or fiance_of(b) >= 0:
		return "declined"
	var mc: Dictionary = cfg().get("marriage", {})
	var v: Dictionary = _pair_ro_fr(a, b)
	if float(v["romance"]) < float(mc.get("min_romance", 70)) or float(v["friendship"]) < float(mc.get("min_friendship", 50)):
		return "too_soon" if float(v["romance"]) >= 50.0 else "declined"
	engaged[SysUtil.pair_key(a, b)] = {"a": a, "b": b, "since": SysUtil.day()}
	for x in [a, b]:
		var f = SysUtil.folk(int(x))
		if f != null:
			f.add_buff(str(mc.get("engaged_buff", "engaged")))
	SysUtil.notify("%s and %s are engaged!" % [name_of(a), name_of(b)], "relationship")
	SysUtil.game_event("engaged", {"folk_id": a, "target_id": b})
	return "engaged"

static func break_engagement(a: int, b: int, reason: String = "") -> void:
	var k: String = SysUtil.pair_key(a, b)
	if not engaged.has(k):
		return
	engaged.erase(k)
	var eb: String = str(cfg().get("marriage", {}).get("engaged_buff", "engaged"))
	for x in [a, b]:
		var f = SysUtil.folk(int(x))
		if f != null:
			f.remove_buff(eb)
	SysUtil.notify("%s and %s called off the engagement.%s" % [name_of(a), name_of(b), (" (" + reason + ")") if reason != "" else ""], "relationship")
	SysUtil.game_event("engagement_broken", {"folk_id": a, "target_id": b})

static func _surname(full: String) -> String:
	var parts: PackedStringArray = full.split(" ")
	return parts[parts.size() - 1] if parts.size() > 1 else ""

static func _given(full: String) -> String:
	var parts: PackedStringArray = full.split(" ")
	return parts[0]

static func _set_name(id: int, new_name: String) -> void:
	var f = SysUtil.folk(id)
	if f != null:
		f.name = new_name
	elif Story.townies.has(id):
		Story.townies[id]["name"] = new_name
	note_person(id, new_name)

## modes: "none" | "actor" (the other takes the actor's surname) | "target" | "hyphen" (actor's surname hyphenated with the other's).
static func apply_surname(a: int, b: int, mode: String) -> void:
	var na: String = name_of(a)
	var nb: String = name_of(b)
	var sa: String = _surname(na)
	var sb: String = _surname(nb)
	match mode:
		"actor":
			if sa != "":
				_set_name(b, "%s %s" % [_given(nb), sa])
		"target":
			if sb != "":
				_set_name(a, "%s %s" % [_given(na), sb])
		"hyphen":
			if sa != "" and sb != "" and sa != sb:
				_set_name(b, "%s %s-%s" % [_given(nb), sa, sb])

## Wedding. `a` is the proposer / actor. Returns true when they are now married.
static func marry(a: int, b: int, surname_mode: String = "", force: bool = false) -> bool:
	var mc: Dictionary = cfg().get("marriage", {})
	var key: String = SysUtil.pair_key(a, b)
	if not engaged.has(key) and not force:
		return false
	if spouse_of(a) >= 0 or spouse_of(b) >= 0:
		return false
	engaged.erase(key)
	spouses[a] = b
	spouses[b] = a
	for x in [a, b]:
		var f = SysUtil.folk(int(x))
		if f != null:
			f.remove_buff(str(mc.get("engaged_buff", "engaged")))
			f.add_buff(str(mc.get("married_buff", "married")))
			f.add_buff(str(mc.get("newlywed_buff", "newlywed")))
	RelationshipService.add_both(a, b, "romance", float(mc.get("wedding_romance", 10)))
	RelationshipService.add_both(a, b, "friendship", float(mc.get("wedding_friendship", 10)))
	RelationshipService.set_flag(a, b, "spouse", true, false)
	if surname_mode == "":
		surname_mode = str(mc.get("surname", "none"))
	apply_surname(a, b, surname_mode)
	if bool(mc.get("merge_households", true)):
		_merge_households(a, b)
	SysUtil.notify("%s and %s are married!" % [name_of(a), name_of(b)], "relationship")
	SysUtil.game_event("married", {"folk_id": a, "target_id": b})
	return true

## The partner who does not live with the other moves into the actor's household.
static func _merge_households(a: int, b: int) -> void:
	var fa = SysUtil.folk(a)
	var fb = SysUtil.folk(b)
	if fa != null and fb != null:
		if int(fa.household_id) == int(fb.household_id):
			return
		var hid: int = int(fa.household_id)
		if int(fb.household_id) > 0 and not SysUtil.is_resident(fa):
			return
		_move_household(fb, hid)
	elif fa != null and fb == null and Story.townies.has(b):
		invite_to_household(b, int(fa.household_id))
	elif fb != null and fa == null and Story.townies.has(a):
		invite_to_household(a, int(fb.household_id))

## Change a folk's household, carrying coins / objects when their old household becomes empty.
static func _move_household(f, new_hid: int) -> void:
	var old: int = int(f.household_id)
	f.household_id = new_hid
	if f.has_meta("visitor"):
		f.remove_meta("visitor")
	if old > 0 and old != new_hid:
		var left: int = 0
		for o in SysUtil.residents():
			if int(o.household_id) == old:
				left += 1
		if left == 0:
			var coins: int = WorldIface.get_coins(old)
			if coins > 0:
				WorldIface.add_coins(old, -coins)
				WorldIface.add_coins(new_hid, coins)
			for ob in Economy.objects_of(old):
				Economy.owner[int(ob.id)] = new_hid

static func divorce(a: int, b: int, mover: int = -1) -> bool:
	if spouse_of(a) != b:
		return false
	var dc: Dictionary = cfg().get("divorce", {})
	spouses.erase(a)
	spouses.erase(b)
	_push(exes, a, b)
	_push(exes, b, a)
	var mb: String = str(cfg().get("marriage", {}).get("married_buff", "married"))
	var nl: String = str(cfg().get("marriage", {}).get("newlywed_buff", "newlywed"))
	for x in [a, b]:
		var f = SysUtil.folk(int(x))
		if f != null:
			f.remove_buff(mb)
			f.remove_buff(nl)
			f.add_buff(str(dc.get("buff", "divorced")))
	RelationshipService.set_flag(a, b, "spouse", false, false)
	RelationshipService.add_both(a, b, "friendship", -float(dc.get("friendship_loss", 35)))
	RelationshipService.add_both(a, b, "romance", -float(dc.get("romance_loss", 80)))
	RelationshipService.add_history(a, b, "divorce", -1.0, a)
	SysUtil.notify("%s and %s got divorced." % [name_of(a), name_of(b)], "relationship")
	SysUtil.game_event("divorced", {"folk_id": a, "target_id": b})
	# one of them moves out when they shared a home
	var fa = SysUtil.folk(a)
	var fb = SysUtil.folk(b)
	if fa != null and fb != null and int(fa.household_id) == int(fb.household_id) and int(fa.household_id) > 0:
		var leaver: int = mover if mover in [a, b] else b
		move_out(leaver, float(dc.get("coin_share", 0.5)))
	return true

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
	var age: float = age_days_of(folk_id)
	f.cancel_current("moved out")
	f.clear_queue()
	RelationshipService.sync_folk(f)
	Genetics.ensure(f)
	var t: Dictionary = {"id": folk_id, "name": str(f.name), "traits": f.traits.duplicate(), "age_days": age, "career": "", "level": 1,
		"coins": coins, "alive": true, "lot": 1, "last_visit_day": SysUtil.day(),
		"appearance": f.appearance.duplicate(true), "moved_out": true}
	if orphan:
		t["orphan"] = true
	Story.townies[folk_id] = t
	note_person(folk_id, str(f.name))
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
	if f != null:
		if int(f.household_id) == household_id:
			return false
		var was_visitor: bool = f.has_meta("visitor")
		_move_household(f, household_id)
		if was_visitor or not Aging.records.has(person_id):
			var tt: Dictionary = Story.townies.get(person_id, {})
			if f.has_meta("townie_id"):
				f.remove_meta("townie_id")
			Aging.register(f, float(tt.get("age_days", -1.0)), parents_of(person_id))
			if not tt.is_empty():
				tt["alive"] = false
				tt["moved_in"] = true
			Goals.ensure_profile(f)
		_after_move_in(f)
		return true
	var t: Dictionary = Story.townies.get(person_id, {})
	if t.is_empty() or not bool(t["alive"]):
		return false
	var keep_next: int = Folk._next_id
	var nf := Folk.create(str(t["name"]), (t["traits"] as Array).duplicate(), person_id)
	Folk._next_id = keep_next
	nf.household_id = household_id
	nf.age_stage = Story.stage_of(t)
	nf.appearance = Genetics.normalize(Genetics.ensure(t))
	for n in nf.needs:
		(nf.needs[n] as Stat).set_value(SysUtil.rng.randf_range(30.0, 70.0))
	RelationshipService.restore_folk(nf)
	SysUtil.world_add_folk(nf, Story.entrance())
	Aging.register(nf, float(t["age_days"]), parents_of(person_id))
	Goals.ensure_profile(nf)
	t["alive"] = false
	t["moved_in"] = true
	note_person(person_id, str(nf.name))
	_after_move_in(nf)
	return true

static func _after_move_in(f) -> void:
	Genetics.ensure(f)
	refresh_bits(int(f.id))
	if str(f.age_stage) in ["baby", "toddler"]:
		BabyCare.on_birth(f, false)
	SysUtil.notify("%s moved in!" % f.name, "story")
	SysUtil.game_event("moved_in", {"folk_id": int(f.id), "household_id": int(f.household_id)})

# ------------------------------------------------------------------ adoption
## Orphan child townies up for adoption (spawns a few when there are none and `spawn_if_empty`).
static func adoptable(spawn_if_empty: bool = false) -> Array:
	var ac: Dictionary = cfg().get("adoption", {})
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
	var ac: Dictionary = cfg().get("adoption", {})
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
	if not (cfg().get("adoption", {}).get("stages", []) as Array).has(Story.stage_of(t)):
		return {"ok": false, "reason": "too_old"}
	if co_parent_id < 0:
		var sp: int = spouse_of(parent_id)
		if sp >= 0 and SysUtil.folk(sp) != null and int(SysUtil.folk(sp).household_id) == int(p.household_id):
			co_parent_id = sp
	var surname: String = _surname(str(p.name))
	if not invite_to_household(townie_id, int(p.household_id)):
		return {"ok": false, "reason": "failed"}
	if surname != "":
		_set_name(townie_id, "%s %s" % [_given(str(t["name"])), surname])
	link_parent(townie_id, parent_id, true, false)
	if co_parent_id >= 0:
		link_parent(townie_id, co_parent_id, true, false)
	refresh_bits(townie_id)
	var fr: float = float(cfg().get("adoption", {}).get("friendship", 30))
	for pid in [parent_id, co_parent_id]:
		if int(pid) >= 0:
			_floor_friendship(townie_id, int(pid), fr)
	t.erase("orphan")
	SysUtil.notify("%s was adopted by %s!" % [name_of(townie_id), p.name], "birthday")
	SysUtil.game_event("adopted", {"folk_id": parent_id, "child_id": townie_id, "target_id": townie_id})
	return {"ok": true, "reason": "adopted", "child_id": townie_id}

# ------------------------------------------------------------------ death
static func on_death(folk_id: int, mourners: Array) -> void:
	var p: Dictionary = people.get(folk_id, {})
	if p.is_empty():
		note_person(folk_id, name_of(folk_id))
		p = people[folk_id]
	p["died_day"] = SysUtil.day()
	p["died_age_days"] = Aging.age_days(folk_id)
	p["name"] = name_of(folk_id)
	var sp: int = spouse_of(folk_id)
	var mc: Dictionary = cfg().get("marriage", {})
	if sp >= 0:
		spouses.erase(sp)
		spouses.erase(folk_id)
		var sf = SysUtil.folk(sp)
		if sf != null:
			sf.remove_buff(str(mc.get("married_buff", "married")))
			sf.remove_buff(str(mc.get("newlywed_buff", "newlywed")))
			sf.add_buff("widowed")
			SysUtil.notify("%s is a widow(er) now." % sf.name, "death")
	var fi: int = fiance_of(folk_id)
	if fi >= 0:
		engaged.erase(SysUtil.pair_key(fi, folk_id))
		var ff = SysUtil.folk(fi)
		if ff != null:
			ff.remove_buff(str(mc.get("engaged_buff", "engaged")))
	for m in mourners:
		var r: String = relation_id(int(m), folk_id)
		if r in ["parent", "child", "adoptive_parent", "adopted_child", "sibling"]:
			var mf = SysUtil.folk(int(m))
			if mf != null:
				mf.add_buff("bereaved")
	trimester.erase(folk_id)
	BabyCare.state.erase(folk_id)

# ------------------------------------------------------------------ events / clock
static func on_hour() -> void:
	update_pregnancies()

static func on_day(_day: int) -> void:
	update_pregnancies()
	var mc: Dictionary = cfg().get("marriage", {})
	for k in engaged.keys():
		var e: Dictionary = engaged[k]
		var v: Dictionary = _pair_ro_fr(int(e["a"]), int(e["b"]))
		if float(v["romance"]) < float(mc.get("break_below_romance", 30)):
			break_engagement(int(e["a"]), int(e["b"]), "they drifted apart")
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
			if not marry(a, b):
				SysUtil.notify("They are not engaged.", "info")
			return true
		"divorce":
			if not divorce(a, b, b):
				SysUtil.notify("They are not married.", "info")
			return true
		"adopt_child":
			var list: Array = adoptable(true)
			if list.is_empty():
				SysUtil.notify("There are no children to adopt right now.", "info")
			else:
				var res: Dictionary = adopt(int(list[0]["id"]), a)
				if not bool(res["ok"]):
					SysUtil.notify("The adoption didn't go through (%s)." % str(res["reason"]), "info")
			return true
		"move_in_request":
			var tf = SysUtil.folk(b)
			var af = SysUtil.folk(a)
			if tf == null or af == null:
				return true
			var mn: float = float(cfg().get("moving", {}).get("min_friendship", 35))
			var ok: bool = RelationshipService.value(b, a, "friendship") >= mn or spouse_of(a) == b or fiance_of(a) == b
			if int(tf.household_id) == int(af.household_id):
				SysUtil.notify("%s already lives here." % tf.name, "info")
			elif ok:
				invite_to_household(b, int(af.household_id))
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

static func _int_arrays(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d:
		out[int(str(k))] = _ints(d[k])
	return out

static func from_dict(d: Dictionary) -> void:
	reset()
	people = SysUtil.int_keys((d.get("people", {}) as Dictionary).duplicate(true))
	for k in people:
		var p: Dictionary = people[k]
		p["born_day"] = int(p.get("born_day", 0))
		p["died_day"] = int(p.get("died_day", -1))
		p["died_age_days"] = float(p.get("died_age_days", 0.0))
	parents = _int_arrays(d.get("parents", {}))
	adoptive = _int_arrays(d.get("adoptive", {}))
	exes = _int_arrays(d.get("exes", {}))
	for k2 in (d.get("spouses", {}) as Dictionary):
		spouses[int(str(k2))] = int(d["spouses"][k2])
	for k3 in (d.get("engaged", {}) as Dictionary):
		var e: Dictionary = d["engaged"][k3]
		engaged[str(k3)] = {"a": int(e["a"]), "b": int(e["b"]), "since": int(e["since"])}
	for k4 in (d.get("trimester", {}) as Dictionary):
		trimester[int(str(k4))] = int(d["trimester"][k4])
