extends RefCounted
## Outdoor asset kit: every manifest_outdoor.json entry loads as a PackedScene, has its required nodes, and its
## bounds match blender/outdoor/footprints.json. Run: --script res://tests/run_one.gd -- outdoor_assets_test

const MANIFEST := "res://assets/models/manifest_outdoor.json"
const FOOT := "res://blender/outdoor/footprints.json"

func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())

func _find(n: Node, nm: String) -> Node:
	return n.find_child(nm, true, false)

func _bounds(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var a: AABB = t * (n as MeshInstance3D).get_aabb()
		acc.append(a if acc.is_empty() else (acc[0] as AABB).merge(a))
		if acc.size() > 1:
			acc.remove_at(0)
	for c in n.get_children():
		_bounds(c, t, acc)

func _required(id: String) -> Array:
	if id.begins_with("car_") or id == "bus":
		return ["body", "wheel_fl", "wheel_fr", "wheel_rl", "wheel_rr"]
	if id.begins_with("tree_"):
		return ["trunk", "leaves"]
	if id.begins_with("bush_"):
		return ["leaves"]
	if id == "street_lamp":
		return ["pole", "lamp_head"]
	if id in ["house_small_a", "house_medium_a", "house_large_a", "townhouse_a", "cafe_a", "gym_a", "library_a", "market_a", "office_a", "school_a"] \
			or id.contains("_b") and not id.begins_with("bench") and (id.begins_with("house_") or id.begins_with("cafe") or id.begins_with("gym") or id.begins_with("library") or id.begins_with("market") or id.begins_with("office") or id.begins_with("school") or id.begins_with("townhouse")):
		return ["body", "roof"]
	if id == "dog" or id == "cat":
		return ["body", "head", "tail", "leg_fl", "leg_fr", "leg_bl", "leg_br"]
	if id == "bird":
		return ["body", "head", "tail", "wing_l", "wing_r", "leg_l", "leg_r"]
	if id.begins_with("fence_") and id.ends_with("_gate"):
		return ["gate_leaf"]
	if id == "fountain" or id.begins_with("pond_"):
		return ["water"]
	return []

func _kind(id: String) -> String:
	if id.begins_with("road_") or id.begins_with("sidewalk") or id.begins_with("curb_") or id.begins_with("ground_") or id.begins_with("pond_"):
		return "tile"
	if id.begins_with("car_") or id == "bus":
		return "vehicle"
	if id.begins_with("house_") or id.begins_with("townhouse") or id.get_slice("_", 0) in ["cafe", "gym", "library", "market", "office", "school"]:
		return "building"
	if id.begins_with("tree_") or id.begins_with("bush_") or id.begins_with("rock_") or id.begins_with("grass_") or id.begins_with("flower_"):
		return "nature"
	return "other"

func run() -> Array:
	var fails: Array = []
	var man: Variant = _read_json(MANIFEST)
	var foot: Variant = _read_json(FOOT)
	if not (man is Dictionary) or not (foot is Dictionary):
		return ["manifest_outdoor.json or footprints.json missing/invalid"]
	if (man as Dictionary).size() < 90:
		fails.append("manifest has only %d entries" % (man as Dictionary).size())
	for id in man:
		var e: Dictionary = man[id]
		var path: String = e["file"]
		if not ResourceLoader.exists(path):
			fails.append("%s: %s not importable/missing" % [id, path])
			continue
		var ps: Variant = load(path)
		if not (ps is PackedScene):
			fails.append("%s: not a PackedScene" % id)
			continue
		var inst: Node = (ps as PackedScene).instantiate()
		for nm in _required(id):
			if _find(inst, nm) == null and inst.name != nm:
				fails.append("%s: missing node '%s'" % [id, nm])
		if id in ["dog", "cat", "bird"]:
			var ap := inst.find_children("*", "AnimationPlayer", true, false)
			if ap.is_empty():
				fails.append("%s: no AnimationPlayer" % id)
			else:
				for clip in ["Idle", "Walk"]:
					if not (ap[0] as AnimationPlayer).has_animation(clip):
						fails.append("%s: missing clip %s" % [id, clip])
		if not foot.has(id):
			fails.append("%s: not in footprints.json" % id)
		else:
			var acc: Array = []
			_bounds(inst, Transform3D.IDENTITY, acc)
			if acc.is_empty():
				fails.append("%s: no meshes" % id)
			else:
				var bb: AABB = acc[0]
				var fp: Array = foot[id]
				var k := _kind(id)
				var over := 0.5
				var under := 0.5
				if k == "tile":
					over = 0.05; under = 0.05
				elif k == "vehicle":
					over = 0.4; under = 0.4
				elif k == "building":
					over = 2.6; under = 0.2
				elif k == "nature":
					over = 6.0; under = 99.0
				elif k == "other":
					over = 1.6; under = 99.0
				if bb.size.x > float(fp[0]) + over or bb.size.x < float(fp[0]) - under \
						or bb.size.z > float(fp[1]) + over or bb.size.z < float(fp[1]) - under:
					fails.append("%s: bounds %.2fx%.2f vs footprint %sx%s" % [id, bb.size.x, bb.size.z, fp[0], fp[1]])
				if k == "tile" and absf(bb.position.y + bb.size.y) > 0.06 and not id.begins_with("curb_") and id != "road_dead_end" and id != "road_corner" and not id.begins_with("sidewalk") and id != "curb_ramp":
					fails.append("%s: tile top not near y=0" % id)
		inst.free()
	return fails
