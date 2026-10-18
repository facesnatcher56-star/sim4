extends RefCounted
## No two lots share a layout: every generated home has a floor plan (wall geometry, mirror / rotation invariant) different from
## every other home and from the hand-made classic / small / medium / large templates; every lot (venues too) has a distinct
## layout signature; venue alternates differ clearly from their original and from each other.
const Kit = preload("res://tests/house_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _mirror(t: Dictionary) -> Dictionary:
	# flip x inside a 32-wide lot: walls, objects (footprint anchors move, so only wall-only signatures are compared)
	var out := t.duplicate(true)
	for w in out["walls"]:
		var ax: int = w["a"][0]
		var bx: int = w["b"][0]
		w["a"][0] = 32 - ax
		w["b"][0] = 32 - bx
	return out

func run() -> Array:
	fails = []
	var lots: Dictionary = HouseGenerator.lots()
	var legacy := HouseSignature.legacy_templates()
	var homes: Array = []
	var all: Array = []
	for id in lots:
		all.append(id)
		if str(lots[id].get("kind", "home")) == "home":
			homes.append(id)
	# symmetry invariance of the signature itself
	var probe: Dictionary = lots["medium_02"]
	_check(HouseSignature.plan_sig(probe) == HouseSignature.plan_sig(_mirror(probe)), "plan_sig is mirror invariant")
	_check(HouseSignature.plan_sig(legacy["small"]) != HouseSignature.plan_sig(legacy["medium"]), "plan_sig tells different homes apart")
	# a square footprint: the transposed plan is the same plan
	var sq := {"walls": [{"a": [0, 0], "b": [6, 0], "type": "wall"}, {"a": [0, 6], "b": [6, 6], "type": "wall"}, {"a": [0, 0], "b": [0, 6], "type": "wall"},
		{"a": [6, 0], "b": [6, 6], "type": "wall"}, {"a": [0, 2], "b": [4, 2], "type": "wall"}], "objects": []}
	var sq_t := {"walls": [{"a": [0, 0], "b": [6, 0], "type": "wall"}, {"a": [0, 6], "b": [6, 6], "type": "wall"}, {"a": [0, 0], "b": [0, 6], "type": "wall"},
		{"a": [6, 0], "b": [6, 6], "type": "wall"}, {"a": [2, 0], "b": [2, 4], "type": "wall"}], "objects": []}
	_check(HouseSignature.plan_sig(sq) == HouseSignature.plan_sig(sq_t), "plan_sig is rotation invariant on square footprints")
	# floor plans
	var plan_seen: Dictionary = {}
	for id in legacy:
		if str(legacy[id].get("kind", "home")) == "home":
			plan_seen[HouseSignature.plan_sig(legacy[id])] = "legacy " + str(id)
	var dup_plans := 0
	for id in homes:
		var ps := HouseSignature.plan_sig(lots[id])
		if plan_seen.has(ps):
			dup_plans += 1
			fails.append("%s has the same floor plan as %s" % [id, plan_seen[ps]])
		plan_seen[ps] = id
	# full layouts (homes, venues and the hand-made ones)
	var lay_seen: Dictionary = {}
	for id in legacy:
		lay_seen[HouseSignature.layout_sig(legacy[id])] = "legacy " + str(id)
	var dup_layouts := 0
	for id in all:
		var ls := HouseSignature.layout_sig(lots[id])
		if lay_seen.has(ls):
			dup_layouts += 1
			fails.append("%s repeats the layout of %s" % [id, lay_seen[ls]])
		lay_seen[ls] = id
	# similarity: homes of the same footprint share little interior structure; venue alternates differ from the original
	var worst_home := 0.0
	var worst_pair := ""
	for i in homes.size():
		for j in range(i + 1, homes.size()):
			var s := HouseSignature.similarity(lots[homes[i]], lots[homes[j]])
			if s > worst_home:
				worst_home = s
				worst_pair = "%s/%s" % [homes[i], homes[j]]
	for h in homes:
		for lid in legacy:
			if str(legacy[lid].get("kind", "home")) != "home":
				continue
			var s2 := HouseSignature.similarity(lots[h], legacy[lid])
			if s2 > worst_home:
				worst_home = s2
				worst_pair = "%s/legacy %s" % [h, lid]
	_check(worst_home < 0.45, "two homes are too alike: %s (%.2f)" % [worst_pair, worst_home])
	var worst_venue := 0.0
	for vt in ["cafe", "gym", "library", "market", "office", "school"]:
		var group: Array = [vt]
		for id in all:
			if str(id).begins_with(vt + "_v"):
				group.append(id)
		for i in group.size():
			for j in range(i + 1, group.size()):
				var a: Dictionary = legacy[group[i]] if group[i] == vt else lots[group[i]]
				var b: Dictionary = legacy[group[j]] if group[j] == vt else lots[group[j]]
				var s3 := HouseSignature.similarity(a, b)
				worst_venue = maxf(worst_venue, s3)
				_check(s3 < 0.5, "%s and %s are too alike (%.2f)" % [group[i], group[j], s3])
	# venues must not look like homes: no home furniture-only rooms (beds / toilets) in them
	for id in all:
		if str(lots[id].get("kind", "home")) == "venue":
			var st := Kit.stats(lots[id])
			_check(st["beds"] == 0 and st["toilets"] == 0, "%s looks like a home (beds/toilets)" % id)
	print("---- uniqueness ----")
	print("lots %d (homes %d) | distinct floor plans: %d of %d homes (+%d hand-made) | distinct layouts: %d of %d lots (+%d hand-made)" % [
		all.size(), homes.size(), plan_seen.size() - 4 + dup_plans, homes.size(), 4, lay_seen.size() - legacy.size() + dup_layouts, all.size(), legacy.size()])
	print("duplicate floor plans: %d | duplicate layouts: %d | most similar homes: %s %.2f | most similar venue pair: %.2f" % [dup_plans, dup_layouts, worst_pair, worst_home, worst_venue])
	return fails
