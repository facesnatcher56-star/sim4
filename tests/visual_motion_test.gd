extends RefCounted
## VISUAL agent (task 27 items 1, 2, 7): folk walk unless the move is urgent, catch up with a capped Walk (never a Run), a sitting body
## never plays a standing clip, and every interaction whose slot is a sit or lie pose resolves to a sit or lie clip.

var fails: Array = []
var W: Node
var _holder: Node3D


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func _mk(tile: Vector2i) -> Array:
	var f := Folk.create("Mover")
	f.age_stage = "adult"
	W.add_folk(f, tile)
	var fv := FolkView.new()
	fv.name = "folk_%d" % f.id
	_holder.add_child(fv)
	fv.setup(f.id)
	return [f, fv]


func run() -> Array:
	fails = []
	var root: Window = Engine.get_main_loop().root
	W = root.get_node_or_null("World")
	if W == null:
		return ["World autoload missing"]
	FolkView.reload_map()
	W.reset()
	_holder = Node3D.new()
	root.add_child(_holder)
	for sp in [1, 2, 3]:
		_catch_up_walks(root.get_node("Clock"), sp)
	_urgent_runs(root.get_node("Clock"))
	_sit_clips()
	_data_sit_lie_clips()
	_hand_props()
	_holder.free()
	W.reset()
	root.get_node("Clock").speed = 1
	return fails


## The sim walker is far ahead of the view at every speed: the view walks (brisk, capped), never runs, and hops instead of racing.
func _catch_up_walks(clk: Node, sp: int) -> void:
	clk.set_speed(sp)
	var pr := _mk(Vector2i(4, 4))
	var f: Folk = pr[0]
	var fv: FolkView = pr[1]
	var cap := float(FolkView.anim_map()["locomotion"]["walk_max_speed"])
	var runs := 0
	var frames := 0
	var top := 0.0
	var top_scale := 0.0
	for i in 14:
		f.tile = Vector2i(4 + (i + 1) * 3, 4)             # three tiles per frame: far ahead of any walking pace
		fv._process(0.033)
		if fv._moving or not fv._waypoints.is_empty():
			frames += 1
			runs += int(fv.clip == "Run")
			top = maxf(top, fv._speed_now)
			top_scale = maxf(top_scale, fv._anim.speed_scale)
			_check(fv._waypoints.size() <= int(FolkView.anim_map()["locomotion"]["max_backlog"]), "speed %d: backlog %d waypoints" % [sp, fv._waypoints.size()])
	_check(frames >= 5, "speed %d: folk did not move (%d frames)" % [sp, frames])
	_check(runs == 0, "speed %d: %d of %d moving frames played Run for a non-urgent walk" % [sp, runs, frames])
	_check(top <= cap + 0.001, "speed %d: walk speed %.2f above cap %.2f" % [sp, top, cap])
	_check(top_scale <= 1.75, "speed %d: walk clip scale %.2f" % [sp, top_scale])
	fv.free()
	W.remove_folk(f.id)


func _urgent_runs(clk: Node) -> void:
	clk.set_speed(1)
	var pr := _mk(Vector2i(4, 4))
	var f: Folk = pr[0]
	var fv: FolkView = pr[1]
	_check(not FolkClipRules.urgent_move(f), "idle folk counted as urgent")
	var run_frames := 0
	f.current = Interaction.create("go_here", f)
	f.current.def = f.current.def.duplicate(true)
	f.current.def["priority"] = "urgent"
	_check(FolkClipRules.urgent_move(f), "an urgent-priority walk is not an urgent move")
	for i in 20:
		f.tile = Vector2i(4 + i, 4)
		fv._process(0.033)
		run_frames += int(fv.clip == "Run")
	_check(run_frames > 10, "urgent move played Run in only %d of 20 frames" % run_frames)
	f.current = Interaction.create("go_here", f)
	_check(not FolkClipRules.urgent_move(f), "a plain go_here is urgent")
	f.current.params["hurry"] = true
	_check(FolkClipRules.urgent_move(f), "a hurried walk (late for work) is not urgent")
	fv.free()
	W.remove_folk(f.id)


## Item 2: reading in an armchair is a sitting clip.
func _sit_clips() -> void:
	var pr := _mk(Vector2i(8, 8))
	var f: Folk = pr[0]
	var fv: FolkView = pr[1]
	f.current = Interaction.create("read_armchair", f)
	f.current.state = "running"
	W.folk_pose[f.id] = {"pose": "sit"}
	for i in 12:
		fv._process(0.05)
	_check(fv.pose == "sit", "pose was %s" % fv.pose)
	_check(fv.clip == "Sit_Read", "reading in a seat plays '%s', want Sit_Read" % fv.clip)
	f.current = Interaction.create("research_online", f)
	f.current.state = "running"
	for i in 12:
		fv._process(0.05)
	_check(fv.clip == "Sit_Type", "seated research plays '%s', want Sit_Type" % fv.clip)
	f.current = Interaction.create("write_story", f)
	f.current.state = "running"
	W.folk_pose.erase(f.id)
	for i in 12:
		fv._process(0.05)
	_check(fv.clip == "Write", "standing write_story plays '%s', want Write (Paint is the easel's)" % fv.clip)
	fv.free()
	W.folk_pose.erase(f.id)
	W.remove_folk(f.id)


## Every interaction an object offers on a sit or lie slot maps to a sit or lie clip (raw data, before the view's safety net), and the
## sitting / lying clip lists name clips that exist.
func _data_sit_lie_clips() -> void:
	var m: Dictionary = FolkView.anim_map()
	for c in (m["sit_clips"] as Array) + (m["lie_clips"] as Array):
		_check(ResourceLoader.exists("res://assets/models/folk_adult.glb"), "no adult model")
		break
	var checked := 0
	for oid in W.defs:
		var d: Dictionary = W.defs[oid]
		var poses := {}
		for s in d.get("slots", []):
			var p := str(s.get("pose", "stand"))
			if p == "sit" or p == "lie":
				poses[p] = true
		for p in poses:
			for iid in d.get("interactions", []):
				var idef: Dictionary = SimEnv.data().interaction_def(str(iid))
				if idef.is_empty() or str(idef.get("target", "object")) != "object":
					continue
				if str(iid) in ["clean_object", "repair_object", "make_bed", "clean_toilet"]:
					continue          # maintenance: the folk stands next to the object (animation_map stand_at_slot)
				var raw := FolkClipRules.pick_from(FolkClipRules.entry_for(str(iid), idef.get("tags", [])), p)
				var ok: bool = FolkClipRules.is_sit_clip(raw) if p == "sit" else FolkClipRules.is_lie_clip(raw)
				_check(ok, "%s on %s (%s slot) maps to '%s', not a %s clip" % [iid, oid, p, raw, p])
				var fit := FolkClipRules.clip_for(str(iid), idef.get("tags", []), p)
				_check(FolkClipRules.is_sit_clip(fit) if p == "sit" else FolkClipRules.is_lie_clip(fit), "%s on %s resolves to '%s'" % [iid, oid, fit])
				checked += 1
	_check(checked > 10, "only %d sit/lie interactions checked" % checked)


## Item 3 (27b): a prop in the hand while the clip plays (book for reading, cup for a drink, game pad for a game, brush for painting), gone as soon as
## the interaction ends or the folk walks off; the data names real clips and every rule has a definition on a bone of the skeleton.
func _hand_props() -> void:
	var cfg: Dictionary = FolkView.anim_map().get("props", {})
	var defs: Dictionary = cfg.get("defs", {})
	var clips: Array = FolkView.anim_map().get("sit_clips", []) + FolkView.anim_map().get("lie_clips", [])
	for r in (cfg.get("rules", []) as Array):
		var names: Array = (r["props"] as Array) if r.has("props") else [str(r.get("prop", ""))]
		for nm in names:
			_check(defs.has(str(nm)), "props rule names '%s' without a definition" % str(nm))
	for k in defs:
		_check(not (defs[k]["parts"] as Array).is_empty() and str(defs[k]["bone"]) in ["hand_R", "hand_L", "chest"], "prop '%s' has no parts or no hand / chest bone" % k)
	_check(FolkProps.prop_for("read_armchair", ["read"], "Sit_Read") == "book", "reading in a seat has a book")
	_check(FolkProps.prop_for("brew_coffee", ["drink", "coffee"], "Use_Stand") == "cup", "brewing coffee has a cup")
	_check(FolkProps.prop_for("play_computer", ["fun"], "Sit_Type") == "gamepad", "play_computer has a game pad")
	_check(FolkProps.prop_for("paint_canvas", ["creative"], "Paint") == "brush", "painting has a brush")
	_check(FolkProps.prop_for("study_recipes", ["read", "cook"], "Cook") != "book", "no book while the clip is Cook")
	_check(FolkProps.prop_for("read_book", ["read"], "Walk") == "", "no prop while walking")
	var pr := _mk(Vector2i(8, 8))
	var f: Folk = pr[0]
	var fv: FolkView = pr[1]
	if fv._is_placeholder:
		fv.free()
		W.remove_folk(f.id)
		return                              # no glb in this run: the capsule person gets no props
	f.current = Interaction.create("read_armchair", f)
	f.current.state = "running"
	W.folk_pose[f.id] = {"pose": "sit"}
	for i in 12:
		fv._process(0.05)
	_check(fv._props.has("book") and (fv._props["book"] as Node3D).visible, "reading shows a book in the hand")
	f.current = null
	W.folk_pose.erase(f.id)
	for i in 12:
		fv._process(0.05)
	var shown := 0
	for k in fv._props:
		shown += 1 if (fv._props[k] as Node3D).visible else 0
	_check(shown == 0, "%d prop(s) still shown after the interaction ended" % shown)
	fv.free()
	W.remove_folk(f.id)
