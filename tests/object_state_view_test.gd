extends RefCounted
## Task 33.3: objects show their state. Data check of data/object_visuals.json, every state maps to a visual (ObjectVisualRules.resolve, pure), the look is applied to nodes
## (surface recolours, hidden surfaces, tint, parts, particles, lights), applying twice does nothing, and none of it writes sim state.

var fails: Array = []
var W: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func _ids(def_id: String, state: Dictionary, use: Variant = null) -> Array:
	return ObjectVisualRules.state_ids(def_id, state, W.get_def(def_id).get("state", {}), use)


func _look(def_id: String, state: Dictionary, use: Variant = null) -> Dictionary:
	var d: Dictionary = W.get_def(def_id)
	return ObjectVisualRules.resolve(def_id, state, d.get("state", {}), use, float(d.get("height", 1.0)))


func run() -> Array:
	fails = []
	W = Engine.get_main_loop().root.get_node_or_null("World")
	if W == null:
		return ["World autoload missing"]
	ObjectVisualRules.reload()
	_data_check()
	_plants()
	_garden()
	_dirt_and_broken()
	_appliances()
	_beds_and_easels()
	_nodes()
	_view_only()
	return fails


func _data_check() -> void:
	var objs: Dictionary = ObjectVisualRules.objects()
	_check(objs.size() >= 20, "object_visuals.json lists only %d objects" % objs.size())
	for def_id in objs:
		var d: Dictionary = W.get_def(def_id)
		_check(not d.is_empty(), "visual rules for unknown object '%s'" % def_id)
		var c: Dictionary = objs[def_id]
		if c.has("extends"):
			_check(objs.has(str(c["extends"])), "%s extends unknown '%s'" % [def_id, c["extends"]])
		var keys: Array = ObjectVisualRules._layers_of(def_id)
		for layer in keys:
			for st in (layer.get("states", []) as Array):
				for cond in (st.get("when", []) as Array):
					_check_cond_keys(def_id, cond, d)
				for fx in (st.get("fx", []) as Array):
					_check(not ObjectVisualRules.fx_kind(str(fx.get("kind", ""))).is_empty(), "%s: unknown fx kind '%s'" % [def_id, fx.get("kind", "")])


func _check_cond_keys(def_id: String, cond: Dictionary, d: Dictionary) -> void:
	if cond.has("any"):
		for sub in (cond["any"] as Array):
			_check_cond_keys(def_id, sub, d)
		return
	if cond.has("key"):
		_check((d.get("state", {}) as Dictionary).has(str(cond["key"])), "%s: condition on state '%s' the object does not have" % [def_id, cond["key"]])


func _plants() -> void:
	var st := {"water": 0.5}
	_check("water:wilting" in _ids("plant", st), "water 0.5 should wilt: %s" % str(_ids("plant", st)))
	_check("water:dry" in _ids("plant", {"water": 3.0}), "water 3 should be dry")
	_check("water:moist" in _ids("plant", {"water": 6.0}), "water 6 should be moist")
	_check("water:watered" in _ids("plant", {"water": 9.5}), "water 9.5 should be watered")
	var wilt := _look("plant", {"water": 0.5})
	_check((wilt["scale"] as Vector3).y < 1.0 and float(wilt["tilt"]) > 0.0, "a wilting plant droops (scale %s tilt %s)" % [str(wilt["scale"]), str(wilt["tilt"])])
	_check((wilt["surfaces"] as Dictionary).has("leaf") and (wilt["surfaces"] as Dictionary).has("soil"), "wilting recolours leaf and soil")
	var wet := _look("plant", {"water": 9.5})
	var dry := _look("plant", {"water": 3.0})
	var soil_wet: Color = wet["surfaces"]["soil"]["color"]
	var soil_dry: Color = dry["surfaces"]["soil"]["color"]
	_check(soil_wet.get_luminance() < soil_dry.get_luminance() * 0.5, "watered soil is much darker than dry soil")
	var pour := _look("plant", {"water": 5.0}, ["chore", "plant"])
	_check((pour["fx"] as Array).size() == 1 and str(pour["fx"][0]["kind"]) == "drops", "being watered shows drops")
	_check((_look("plant", {"water": 5.0})["fx"] as Array).is_empty(), "nobody watering: no drops")


func _garden() -> void:
	var base := {"water": 5.0, "weeds": 0.0}
	var seen: Array = []
	for g in [0.0, 2.0, 4.0, 7.0, 9.0]:
		var s := base.duplicate()
		s["growth"] = g
		var l := _look("garden_plot", s)
		var ids := (l["ids"] as Array)
		var crop := ""
		for i in ids:
			if str(i).begins_with("crop:"):
				crop = str(i)
		seen.append(crop)
		_check((l["hide"] as Array).has("crop_*"), "the painted-in crops of the model are hidden")
	_check(seen == ["crop:bare", "crop:sprouts", "crop:growing", "crop:leafy", "crop:ripe"], "crop stages: %s" % str(seen))
	var parts_by_stage: Array = []
	for g in [0.0, 2.0, 7.0, 9.0]:
		var l := _look("garden_plot", {"water": 5.0, "weeds": 0.0, "growth": g})
		parts_by_stage.append((l["parts"] as Array).size())
	_check(parts_by_stage[0] == 0 and parts_by_stage[1] == 10 and parts_by_stage[3] == 30, "crop part counts %s" % str(parts_by_stage))
	_check("crop:wilted" in _ids("garden_plot", {"growth": 5.0, "water": 0.5, "weeds": 0.0}), "an unwatered crop wilts")
	_check("weeds:overgrown" in _ids("garden_plot", {"growth": 0.0, "water": 5.0, "weeds": 8.0}), "weeds show")
	_check("soil:wet" in _ids("garden_plot", {"growth": 0.0, "water": 6.0, "weeds": 0.0}) and "soil:dry" in _ids("garden_plot", {"growth": 0.0, "water": 0.0, "weeds": 0.0}), "soil wet / dry")


func _dirt_and_broken() -> void:
	for def_id in ["toilet", "sink", "stove", "fridge", "shower"]:
		var clean := _look(def_id, {"dirtiness": 0.0, "broken": false, "spoiled": 0.0})
		var dirty := _look(def_id, {"dirtiness": 4.0, "broken": false, "spoiled": 0.0})
		var filthy := _look(def_id, {"dirtiness": 9.0, "broken": false, "spoiled": 0.0})
		_check(clean["overlay"] == null, "%s clean has no grime tint" % def_id)
		_check(dirty["overlay"] != null and filthy["overlay"] != null, "%s dirty and filthy are tinted" % def_id)
		if dirty["overlay"] != null and filthy["overlay"] != null:
			_check((filthy["overlay"] as Color).a > (dirty["overlay"] as Color).a, "%s filthy is dirtier than dirty" % def_id)
	_check(not (_look("toilet", {"dirtiness": 9.0, "broken": false})["parts"] as Array).is_empty(), "a filthy toilet has grime spots")
	_check((_look("toilet", {"dirtiness": 0.0, "broken": false})["parts"] as Array).is_empty(), "a clean toilet has none")
	for def_id in ["tv", "stove", "toilet", "fridge", "sink", "computer"]:
		var ok := _look(def_id, {"broken": false, "dirtiness": 0.0, "on": false})
		var br := _look(def_id, {"broken": true, "dirtiness": 0.0, "on": false})
		var kinds: Array = []
		for f in (br["fx"] as Array):
			kinds.append(str(f["kind"]))
		_check("sparks" in kinds and "smoke" in kinds, "%s broken: sparks + smoke (%s)" % [def_id, str(kinds)])
		_check(br["overlay"] != null, "%s broken: dark tint" % def_id)
		_check((ok["fx"] as Array).is_empty(), "%s working has no sparks" % def_id)
	_check(not (_look("fridge", {"spoiled": 5.0, "dirtiness": 0.0, "broken": false})["fx"] as Array).is_empty(), "spoiled food smells")


func _appliances() -> void:
	var off := _look("stove", {"dirtiness": 0.0, "broken": false})
	var cooking := _look("stove", {"dirtiness": 0.0, "broken": false}, ["food", "cook", "skill"])
	var wiping := _look("stove", {"dirtiness": 0.0, "broken": false}, ["chore", "clean"])
	_check((off["parts"] as Array).is_empty(), "idle stove: no glowing burners")
	var burners := 0
	for p in (cooking["parts"] as Array):
		if float(p["emit"]) > 1.0 and str(p["shape"]) == "cyl":
			burners += 1
	_check(burners == 4, "cooking: four glowing burners, got %d" % burners)
	_check((wiping["parts"] as Array).is_empty(), "wiping the stove does not light the burners")
	var fr_shut := _look("fridge", {"dirtiness": 0.0, "broken": false, "spoiled": 0.0})
	var fr_open := _look("fridge", {"dirtiness": 0.0, "broken": false, "spoiled": 0.0}, ["food"])
	var fr_wipe := _look("fridge", {"dirtiness": 0.0, "broken": false, "spoiled": 0.0}, ["chore", "clean"])
	_check((fr_shut["parts"] as Array).is_empty() and not (fr_open["parts"] as Array).is_empty() and (fr_wipe["parts"] as Array).is_empty(), "fridge door opens only while somebody takes food")
	# tv: off, in use, or switched on => glowing flickering screen; lamps follow "on"
	var tv_off := _look("tv", {"on": false, "broken": false})
	var tv_use := _look("tv", {"on": false, "broken": false}, ["fun", "tv"])
	var tv_on := _look("tv", {"on": true, "broken": false})
	_check((tv_off["surfaces"] as Dictionary).is_empty(), "tv off: plain screen")
	for l in [tv_use, tv_on]:
		var sc: Dictionary = (l["surfaces"] as Dictionary).get("screen", {})
		_check(not sc.is_empty() and float(sc["emit"]) > 1.0 and float(sc["flicker"]) > 0.0, "tv on / in use: glowing, flickering screen")
	var lamp_on := _look("lamp", {"on": true})
	var lamp_off := _look("lamp", {"on": false})
	_check(not (lamp_on["parts"] as Array).is_empty() and ((lamp_on["parts"][0]["light"]) as Array).size() == 2, "lamp on has a bulb and a light")
	_check((lamp_off["parts"] as Array).is_empty() and (lamp_off["surfaces"] as Dictionary).is_empty(), "lamp off: dark")
	_check(not (_look("computer", {"on": false, "broken": false}, ["skill", "work"])["surfaces"] as Dictionary).is_empty(), "computer in use: screen lit")


func _beds_and_easels() -> void:
	var made := _look("bed", {"made": true})
	var unmade := _look("bed", {"made": false})
	_check((made["parts"] as Array).is_empty() and (made["hide"] as Array).is_empty(), "made bed keeps the neat model")
	_check((unmade["parts"] as Array).size() >= 3 and (unmade["hide"] as Array).has("fabric_*"), "unmade bed: neat blanket hidden, rumpled one on top")
	var narrow := _look("single_bed", {"made": false})
	var wide_x := 0.0
	for p in (unmade["parts"] as Array):
		wide_x = maxf(wide_x, absf((p["pos"] as Vector3).x))
	var narrow_x := 0.0
	for p in (narrow["parts"] as Array):
		narrow_x = maxf(narrow_x, absf((p["pos"] as Vector3).x))
	_check(narrow_x < wide_x * 0.7, "single bed part positions are narrowed (%.2f vs %.2f)" % [narrow_x, wide_x])
	var heights: Array = []
	var counts: Array = []
	for pr in [0.0, 30.0, 80.0]:
		var l := _look("easel", {"progress": pr})
		counts.append((l["parts"] as Array).size())
		var wash_h := 0.0
		for p in (l["parts"] as Array):
			if str(p["shape"]) == "box" and (p["color"] as Color).to_html() == "f2d58cff":
				wash_h = (p["size"] as Vector3).y
		heights.append(wash_h)
	_check(heights[0] == 0.0 and heights[1] > 0.0 and heights[2] > heights[1], "the canvas fills in with progress: %s" % str(heights))
	_check(counts[0] == 0 and counts[2] > counts[1], "more detail at 80%% than at 30%%: %s" % str(counts))
	_check(((_look("easel", {"progress": 0.0})["hide"]) as Array).has("paint_*"), "a blank canvas hides the model's paint blobs")


func _surface_mesh(names: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	for n in names:
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := StandardMaterial3D.new()
		mat.resource_name = str(n)
		m.surface_set_material(m.get_surface_count() - 1, mat)
	return m


func _nodes() -> void:
	var node := Node3D.new()
	Engine.get_main_loop().root.add_child(node)      # particles need a tree
	var vis := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _surface_mesh(["pot", "soil", "leaf"])
	vis.add_child(mi)
	node.add_child(vis)
	var look := _look("plant", {"water": 0.5})
	ObjectVisualNodes.apply(node, look)
	_check(mi.get_surface_override_material(1) != null, "soil surface recoloured")
	_check(mi.get_surface_override_material(2) != null, "leaf surface recoloured")
	_check(mi.get_surface_override_material(0) == null, "pot untouched")
	_check(vis.scale.y < 1.0, "wilting plant droops")
	_check(node.get_node_or_null("StateFx") != null and node.get_node("StateFx").get_child_count() >= 2, "fallen-leaf parts exist")
	var fx_before := node.get_node("StateFx")
	ObjectVisualNodes.apply(node, look)
	_check(node.get_node("StateFx") == fx_before, "same look twice does nothing")
	# a dirty, broken toilet: tint + particles + lights follow near / far
	ObjectVisualNodes.apply(node, _look("toilet", {"dirtiness": 9.0, "broken": true}))
	_check(mi.material_overlay != null, "grime / scorch tint applied")
	_check(mi.get_surface_override_material(1) == null, "the plant's recolour is gone")
	_check(vis.scale == Vector3.ONE, "droop undone")
	var ps: Array = []
	for c in node.get_node("StateFx/Near").get_children():
		if c is CPUParticles3D:
			ps.append(c)
	_check(ps.size() == 2 or GameSettings.effects_quality() == 0, "sparks and smoke particles: %d" % ps.size())
	_check(bool(node.get_meta("has_near", false)) or ps.is_empty(), "node knows it has near-only effects")
	ObjectVisualNodes.set_near(node, false)
	_check(not (node.get_node("StateFx/Near") as Node3D).visible, "far from the camera: effects off")
	for p in ps:
		_check(not (p as CPUParticles3D).emitting, "far from the camera: particles stop")
	ObjectVisualNodes.set_near(node, true)
	_check((node.get_node("StateFx/Near") as Node3D).visible, "near again: effects on")
	# back to a plain look: everything is removed
	ObjectVisualNodes.apply(node, {})
	_check(node.get_node_or_null("StateFx") == null and mi.material_overlay == null, "an empty look removes every effect")
	# hidden surfaces: an unmade bed hides the neat blanket
	var bed := Node3D.new()
	Engine.get_main_loop().root.add_child(bed)
	var bvis := Node3D.new()
	var bmi := MeshInstance3D.new()
	bmi.mesh = _surface_mesh(["wood", "fabric_blue", "white"])
	bvis.add_child(bmi)
	bed.add_child(bvis)
	ObjectVisualNodes.apply(bed, _look("bed", {"made": false}))
	_check(bmi.get_surface_override_material(1) is ShaderMaterial and bmi.get_surface_override_material(0) == null, "the neat blanket surface is hidden")
	node.free()
	bed.free()


## The view reads the object's state and writes nothing: the state dictionary and the world's object count are the same before and after.
func _view_only() -> void:
	W.reset()
	var pid: int = W.place_object("plant", Vector2i(6, 6), 0)
	_check(pid >= 0, "could not place a plant")
	var o = W.get_object(pid)
	var before: String = var_to_str(o.state)
	var l1 := ObjectStateView.look_of(o)
	var l2 := ObjectStateView.look_of(o)
	_check(var_to_str(l1) == var_to_str(l2), "same state, same look")
	_check(var_to_str(o.state) == before, "reading the look never changes object state")
	W.set_object_state(pid, "water", 0.5)
	_check("water:wilting" in (ObjectStateView.look_of(o)["ids"] as Array), "the look follows the state of the real object")
	W.reset()
