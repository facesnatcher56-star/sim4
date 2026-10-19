class_name FamilyTree
extends RefCounted
## Family graph queries (parents, siblings, relation labels) and the tree view data.

# ------------------------------------------------------------------ graph queries
static func bio_parents_of(id: int) -> Array:
	return SysUtil.to_ints(Family.parents.get(id, []))

static func parents_of(id: int) -> Array:
	var out: Array = bio_parents_of(id)
	for p in Family.adoptive.get(id, []):
		if not out.has(int(p)):
			out.append(int(p))
	return out

static func children_of(id: int) -> Array:
	var out: Array = []
	for c in Family.parents:
		if (Family.parents[c] as Array).has(id) and not out.has(int(c)):
			out.append(int(c))
	for c2 in Family.adoptive:
		if (Family.adoptive[c2] as Array).has(id) and not out.has(int(c2)):
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
	return int(Family.spouses.get(id, -1))

static func fiance_of(id: int) -> int:
	for k in Family.engaged:
		var e: Dictionary = Family.engaged[k]
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
	for o in RelationshipBits.romantic_partners(id):
		for st in ["partner", "sweetheart"]:
			if RelationshipBits.has_flag(id, int(o), st):
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
	if (Family.adoptive.get(a, []) as Array).has(b):
		return "adoptive_parent"
	if bio_parents_of(b).has(a):
		return "child"
	if (Family.adoptive.get(b, []) as Array).has(a):
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
	if (Family.exes.get(a, []) as Array).has(b):
		return "ex_spouse"
	return ""

static func relation_label(a: int, b: int) -> String:
	var rid: String = relation_id(a, b)
	if rid == "":
		return ""
	return str(Family.cfg().get("labels", {}).get(rid, rid.capitalize()))

static func is_kin(a: int, b: int) -> bool:
	var r: String = relation_id(a, b)
	return r != "" and r not in ["ex_spouse", "fiance"]

# ------------------------------------------------------------------ tree for the UI
static func node(id: int) -> Dictionary:
	var info: Dictionary = Family.person_info(id)
	var ay: int = int(floor(float(info["age_days"]) / Aging.days_per_year()))
	return {"id": id, "name": info["name"], "stage": info["stage"], "age_years": ay, "stage_text": Aging.stage_text(id, str(info["stage"])), "alive": info["alive"], "on_lot": info["on_lot"],
		"household_id": info["household_id"]}

static func _up(id: int, depth: int) -> Dictionary:
	var n: Dictionary = node(id)
	var ps: Array = []
	if depth > 0:
		for p in parents_of(id):
			var pn: Dictionary = _up(int(p), depth - 1)
			pn["adoptive"] = (Family.adoptive.get(id, []) as Array).has(int(p))
			ps.append(pn)
	n["parents"] = ps
	return n

static func _down(id: int, depth: int) -> Dictionary:
	var n: Dictionary = node(id)
	var kids: Array = []
	if depth > 0:
		for c in children_of(id):
			var cn: Dictionary = _down(int(c), depth - 1)
			cn["adopted"] = (Family.adoptive.get(int(c), []) as Array).has(id)
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
	for e in Family.exes.get(folk_id, []):
		ex_nodes.append(node(int(e)))
	t["exes"] = ex_nodes
	t["descendants"] = descendants_of(folk_id).size()
	return t