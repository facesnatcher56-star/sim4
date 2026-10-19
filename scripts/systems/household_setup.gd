class_name HouseholdSetup
extends RefCounted
## Builds, validates and wires up the starting household of a new game (no UI).
##
## Household dictionary: {name, folk: [{name, sex, stage, traits[], aspiration, appearance{}, rel}]}   sex = female | male
##   stage = child | teen | adult | elder;  aspiration "" = fitted to the traits;
##   rel = relation to the FIRST member: none | partner | spouse | child | parent | sibling.
## Flow: make_household / validate -> create_folk (before the systems reset, so Aging reads the stage) ->
## SystemsManager.new_game -> apply(h, folk) (aspirations, relationships, family links, child looks).

const STAGES := ["child", "teen", "adult", "elder"]
const STAGE_LABELS := {"child": "Child", "teen": "Teen", "adult": "Adult", "elder": "Elder"}
const REL_LABELS := {"none": "Unrelated", "partner": "Partner", "spouse": "Spouse", "child": "Child of the first Folk",
	"parent": "Parent of the first Folk", "sibling": "Sibling of the first Folk"}
const REL_ORDER := ["none", "partner", "spouse", "child", "parent", "sibling"]
const MAX_FOLK := 6
const SIBLING_PARENT_BASE := 880000

static func trait_count(stage: String) -> int:
	return mini(3, maxi(Aging.trait_slots(stage), 1))

static func rng_or_new(r: RandomNumberGenerator) -> RandomNumberGenerator:
	if r != null:
		return r
	var n := RandomNumberGenerator.new()
	n.randomize()
	return n

static func random_name(used: Array, r: RandomNumberGenerator = null, sex: String = "") -> String:
	return Names.pick_first(used, rng_or_new(r), sex)

## `count` distinct traits that do not conflict with each other.
static func random_traits(count: int, r: RandomNumberGenerator = null) -> Array:
	var g := rng_or_new(r)
	var all: Array = SimEnv.data().traits().keys()
	all.sort()
	var out: Array = []
	var guard := 0
	while out.size() < count and not all.is_empty() and guard < 200:
		guard += 1
		var t: String = str(all[g.randi_range(0, all.size() - 1)])
		if out.has(t):
			continue
		var bad := false
		var td: Dictionary = SimEnv.data().trait_def(t)
		for o in out:
			if (td.get("conflicts", []) as Array).has(o) or (SimEnv.data().trait_def(str(o)).get("conflicts", []) as Array).has(t):
				bad = true
		if not bad:
			out.append(t)
	return out

static func random_folk(stage: String, rel: String, used: Array, r: RandomNumberGenerator = null, looks: Array = [], sex: String = "") -> Dictionary:
	var g := rng_or_new(r)
	if not Sexes.valid(sex):
		sex = Sexes.roll(g)
	return {"name": random_name(used, g, sex), "sex": sex, "stage": stage, "rel": rel, "traits": random_traits(trait_count(stage), g),
		"aspiration": "", "appearance": Genetics.unique_appearance(looks + GeneticsUnique.registry(), g, sex)}

## The preset household of a scenario (random names / traits / looks). Children get a look inherited from their parents.
static func make_household(scenario_id: String, r: RandomNumberGenerator = null) -> Dictionary:
	var g := rng_or_new(r)
	var specs: Array = Scenario.def(scenario_id).get("folk", [{"stage": "adult", "rel": "none"}])
	var used: Array = []
	var folk: Array = []
	var looks: Array = []
	for s in specs:
		var fd := random_folk(str(s.get("stage", "adult")), str(s.get("rel", "none")), used, g, looks)
		used.append(fd["name"])
		looks.append(fd["appearance"])
		folk.append(fd)
	var h := {"name": "Fernwood", "folk": folk}
	inherit_child_looks(h, g)
	return h

## Give "child of the first Folk" members a look inherited from the first Folk and their partner.
static func inherit_child_looks(h: Dictionary, r: RandomNumberGenerator = null) -> void:
	var folk: Array = h["folk"]
	if folk.is_empty():
		return
	var mate: int = _mate_index(folk)
	for i in range(1, folk.size()):
		if str(folk[i].get("rel", "")) == "child":
			var pb = folk[mate] if mate >= 0 else folk[0]
			var kin: Array = []
			for j in folk.size():
				if j != i:
					kin.append(folk[j]["appearance"])
			var res: Dictionary = Genetics.inherit(folk[0], pb, r, {"others": kin + GeneticsUnique.registry(), "sex": str(folk[i].get("sex", ""))})
			folk[i]["appearance"] = res["appearance"]

static func _mate_index(folk: Array) -> int:
	for i in range(1, folk.size()):
		if str(folk[i].get("rel", "")) in ["partner", "spouse"]:
			return i
	return -1

static func stage_rank(stage: String) -> int:
	return STAGES.find(stage)

## "" when the household is playable, else a plain-language reason.
static func validate(h: Dictionary) -> String:
	var folk: Array = h.get("folk", [])
	if folk.is_empty():
		return "Add at least one Folk."
	if folk.size() > MAX_FOLK:
		return "A household has room for %d Folk at most." % MAX_FOLK
	var seen := {}
	var grown := false
	var tcount: int = SimEnv.data().traits().size()
	for i in folk.size():
		var fd: Dictionary = folk[i]
		var nm: String = str(fd.get("name", "")).strip_edges()
		if nm == "":
			return "Every Folk needs a name."
		if seen.has(nm.to_lower()):
			return "Names must be different: two Folk are called %s." % nm
		seen[nm.to_lower()] = true
		var stage: String = str(fd.get("stage", "adult"))
		if not STAGES.has(stage):
			return "%s has an unknown age group." % nm
		if stage in ["adult", "elder"]:
			grown = true
		var want: int = trait_count(stage)
		if (fd.get("traits", []) as Array).size() < want and tcount >= want:
			return "Pick %d different traits for %s." % [want, nm]
		var rel_err := _rel_error(folk, i)
		if rel_err != "":
			return rel_err
	if not grown:
		return "There must be at least one adult or elder to look after the household."
	return ""

static func _rel_error(folk: Array, i: int) -> String:
	if i == 0:
		return ""
	var rel: String = str(folk[i].get("rel", "none"))
	var nm: String = str(folk[i]["name"])
	var a: int = stage_rank(str(folk[0].get("stage", "adult")))
	var b: int = stage_rank(str(folk[i].get("stage", "adult")))
	match rel:
		"partner", "spouse":
			if a < 2 or b < 2:
				return "%s and %s: partners need to be adults or elders." % [folk[0]["name"], nm]
		"child":
			if b >= a:
				return "%s can only be a child of %s if they are younger." % [nm, folk[0]["name"]]
		"parent":
			if b <= a:
				return "%s can only be a parent of %s if they are older." % [nm, folk[0]["name"]]
	return ""

## Create the Folk objects (stage + look set). Call BEFORE World.add_folk and SystemsManager.new_game.
static func create_folk(h: Dictionary) -> Array:
	var out: Array = []
	for fd in h["folk"]:
		var f := Folk.create(str(fd["name"]), fd.get("traits", []), -1, str(fd.get("sex", "")))
		fd["sex"] = f.sex
		f.age_stage = str(fd.get("stage", "adult"))
		if Genetics.is_valid(fd.get("appearance", {})):
			f.appearance = (fd["appearance"] as Dictionary).duplicate(true)
		if not fd.has("color"):
			fd["color"] = Genetics.ui_color(f)
		out.append(f)
	return out

## After SystemsManager.new_game: aspirations, relationships and family links between the new household members.
static func apply(h: Dictionary, folk: Array) -> void:
	var specs: Array = h["folk"]
	if not folk.is_empty() and str(h.get("name", "")) != "":
		Aging.house_names[int(folk[0].household_id)] = str(h["name"])
	for i in folk.size():
		var asp: String = str(specs[i].get("aspiration", ""))
		if asp != "":
			Goals.set_aspiration(int(folk[i].id), asp)
		if bool(specs[i].get("homemaker", false)):
			Homemaker.set_role(folk[i], true)
	var mate: int = _mate_index(specs)
	var sib_parent: int = -1
	for i in range(1, folk.size()):
		var a: int = int(folk[0].id)
		var b: int = int(folk[i].id)
		match str(specs[i].get("rel", "none")):
			"partner":
				_bond(a, b)
				RelationshipBits.set_flag(a, b, "partner", true, false)
				AgingStart.settle_partner(folk[0], folk[i])
			"spouse":
				_bond(a, b)
				FamilyMarriage.marry(a, b, "", true)
				folk[0].remove_buff("newlywed")
				folk[i].remove_buff("newlywed")
				AgingStart.settle_partner(folk[0], folk[i])
			"parent":
				Family.link_parent(a, b)
			"sibling":
				if sib_parent < 0:
					sib_parent = SIBLING_PARENT_BASE + a
					Family.note_person(sib_parent, "Parent")
					Family.link_parent(a, sib_parent)
				Family.link_parent(b, sib_parent)
	for i in range(1, folk.size()):
		if str(specs[i].get("rel", "none")) == "child":
			Family.link_parent(int(folk[i].id), int(folk[0].id))
			if mate >= 0:
				Family.link_parent(int(folk[i].id), int(folk[mate].id))

static func _bond(a: int, b: int) -> void:
	for dir in [[a, b], [b, a]]:
		RelationshipService.set_value(dir[0], dir[1], "friendship", 55.0)
		RelationshipService.set_value(dir[0], dir[1], "romance", 55.0)

## `count` standing tiles: the lot's spawn tiles first, then free walkable tiles next to them (large households on small homes).
static func spawn_tiles(count: int, base: Array) -> Array:
	var out: Array = []
	for i in mini(count, base.size()):
		out.append(base[i])
	var w = WorldIface.world()
	var ring: int = 1
	while out.size() < count and ring < 6:
		for b in base:
			for d in [Vector2i(ring, 0), Vector2i(-ring, 0), Vector2i(0, ring), Vector2i(0, -ring), Vector2i(ring, ring), Vector2i(-ring, -ring)]:
				var t: Vector2i = b + d
				if out.size() < count and not out.has(t) and w != null and w.is_walkable(t) and w.has_path(base[0], t):
					out.append(t)
		ring += 1
	while out.size() < count:
		out.append(base[out.size() % base.size()])
	return out

## One plain sentence about what a trait does (its description, or composed from its likes / dislikes / need rates).
static func trait_blurb(tid: String) -> String:
	var d: Dictionary = SimEnv.data().trait_def(tid)
	if str(d.get("description", "")) != "":
		return str(d["description"])
	var parts: Array = []
	var likes: Array = (d.get("likes", []) as Array).map(func(x): return str(x).trim_prefix("tag:").replace("_", " "))
	var dislikes: Array = (d.get("dislikes", []) as Array).map(func(x): return str(x).trim_prefix("tag:").replace("_", " "))
	if not likes.is_empty():
		parts.append("Likes %s." % ", ".join(likes))
	if not dislikes.is_empty():
		parts.append("Dislikes %s." % ", ".join(dislikes))
	var rates: Dictionary = d.get("need_decay_mult", {})
	for need in rates:
		var m: float = float(rates[need])
		if m > 1.0:
			parts.append("%s drops faster." % str(need).capitalize())
		elif m < 1.0:
			parts.append("%s drops slower." % str(need).capitalize())
	var refuses: Array = d.get("refuses", [])
	if not refuses.is_empty():
		parts.append("Refuses some activities.")
	return " ".join(parts) if not parts.is_empty() else "Shapes how they behave."