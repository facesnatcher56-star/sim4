extends RefCounted
## Task 33 (view only, nothing here changes sim state): actions look like what they are. Data: under 15% of all interactions (data/interactions.json plus
## every content table after the installers ran) resolve to a generic clip (Use_Stand, Idle, Talk, Sit_Idle; `generic_ok` in animation_map.json is a tiny
## allow-list), the everyday actions all have a prop or particles, the particle data is complete. View: a watering folk holds a can with a water arc,
## both are gone when the action ends, and a chore finished well plays its burst.

const AK = preload("res://tests/action_visual_kit.gd")
const MAX_GENERIC_SHARE := 0.15
const MAX_GENERIC_OK := 6
## the 12 actions of the owner's screenshot list plus showering, singing and washing up: id -> what must show (a prop, or particles for the shower)
const SHOWN := {
	"water_plant": "watering_can", "cook_meal": "pan", "clean_object": "cloth", "repair_object": "wrench", "check_phone": "phone", "call_friend": "phone",
	"eat_meal": "fork", "plant_seeds": "trowel", "fish_pond": "rod", "paint_canvas": "brush", "lift_weights": "dumbbell", "do_homework": "pencil",
	"feed_baby": "bundle", "brush_teeth": "toothbrush", "karaoke": "mic", "wash_dishes": "sponge", "take_shower": "",
}

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func run() -> Array:
	fails = []
	var rows: Dictionary = AK.rows()
	_share(rows)
	_everyday(rows)
	_paint_is_the_easels(rows)
	AK.Kit.teardown()
	_fx_data()
	_view()
	return fails


func _share(rows: Dictionary) -> void:
	var share := AK.share(rows)
	_check(rows.size() > 300, "only %d interactions audited" % rows.size())
	_check(share < MAX_GENERIC_SHARE, "%.1f%% of %d interactions resolve to a generic clip (limit %.0f%%): %s" % [share * 100.0, rows.size(), MAX_GENERIC_SHARE * 100.0, str(_generic_ids(rows).slice(0, 12))])
	var ok: Array = FolkView.anim_map().get("generic_ok", [])
	_check(ok.size() <= MAX_GENERIC_OK, "generic_ok has %d entries (max %d): it is for walks, markers and plain sitting only" % [ok.size(), MAX_GENERIC_OK])
	for id in ok:
		_check(rows.has(str(id)), "generic_ok names unknown interaction %s" % str(id))


static func _generic_ids(rows: Dictionary) -> Array:
	var l: Array = []
	for id in rows:
		if bool(rows[id]["generic"]):
			l.append(id)
	return l


func _everyday(rows: Dictionary) -> void:
	for id in SHOWN:
		_check(rows.has(id), "interaction %s is gone" % id)
		if not rows.has(id):
			continue
		var r: Dictionary = rows[id]
		_check(not bool(r["generic"]), "%s resolves to %s" % [id, str(r["clips"])])
		var clip: String = str(r["clips"][0])
		var tags: Array = r["tags"]
		var props := FolkProps.props_for(id, tags, clip)
		var fx := FolkFx.fx_for(id, tags, clip)
		if SHOWN[id] != "":
			_check(SHOWN[id] in props, "%s (%s) shows %s, want %s" % [id, clip, str(props), SHOWN[id]])
		else:
			_check(fx != "", "%s (%s) shows no particles" % [id, clip])


## Paint (brush in hand, an easel clip) belongs to the easels only; a doodle is Write with a pen and a notepad (review of 33).
func _paint_is_the_easels(rows: Dictionary) -> void:
	for id in rows:
		var r: Dictionary = rows[id]
		if not ("Paint" in (r["clips"] as Array)):
			continue
		for o in (r["objects"] as Array):
			_check(str(o) in ["easel", "easel_large"], "%s plays the Paint clip at %s (only easels paint)" % [id, str(o)])
		_check(not (r["objects"] as Array).is_empty(), "%s plays the Paint clip with no easel" % id)
	var dc: Dictionary = rows.get("doodle", {})
	_check(not dc.is_empty() and ("Write" in (dc["clips"] as Array)), "doodle plays %s, want Write" % str(dc.get("clips")))
	var props := FolkProps.props_for("doodle", ["idle_life", "creative"], "Write")
	_check("pen" in props and "notepad" in props, "a doodle shows a pen and a notepad, got %s" % str(props))
	_check(FolkProps.props_for("doodle", ["idle_life", "creative"], "Sit_Write").has("notepad"), "a seated doodle shows the notepad")


func _fx_data() -> void:
	var cfg: Dictionary = FolkView.anim_map().get("fx", {})
	var defs: Dictionary = cfg.get("defs", {})
	for sec in ["rules", "done"]:
		for r in (cfg.get(sec, []) as Array):
			_check(defs.has(str(r.get("fx", ""))), "fx %s names '%s' without a definition" % [sec, str(r.get("fx", ""))])
	for k in defs:
		var d: Dictionary = defs[k]
		_check(int(d.get("amount", 0)) > 0 and float(d.get("life", 0.0)) > 0.0 and float(d.get("size", 0.0)) > 0.0, "fx '%s' needs amount, life and size" % k)
		_check(str(d.get("anchor", "root")) in ["root", "hand_R", "hand_L", "chest", "head"], "fx '%s' has anchor %s" % [k, str(d.get("anchor"))])
		_check(int(d.get("amount", 0)) <= 80, "fx '%s' has %d particles (keep folk cheap)" % [k, int(d.get("amount", 0))])
	_check(FolkFx.fx_for("water_plant", ["chore", "plant"], "Pour") == "water_arc", "watering has a water arc")
	_check(FolkFx.fx_for("water_plant", ["chore", "plant"], "Walk") == "", "no water arc while walking")
	_check(FolkFx.fx_for("take_shower", ["clean", "hygiene"], "Shower") == "shower_water", "the shower has water")
	_check(FolkFx.done_for("clean_object", ["chore", "clean"]) == "sparkles", "a clean thing sparkles")
	_check(FolkFx.done_for("repair_object", ["chore", "repair"]) == "sparks", "a fixed thing sparks")
	_check(FolkFx.done_for("chat", ["social"]) == "", "a chat has no burst")
	_check(FolkProps.props_for("feed_baby", ["baby_care"], "Cradle") == ["bundle", "bottle"], "feeding a baby: bundle and bottle")


func _view() -> void:
	var root: Window = Engine.get_main_loop().root
	var W: Node = root.get_node_or_null("World")
	if W == null:
		fails.append("World autoload missing")
		return
	FolkView.reload_map()
	W.reset()
	var holder := Node3D.new()
	root.add_child(holder)
	var f := Folk.create("Gardener")
	f.age_stage = "adult"
	W.add_folk(f, Vector2i(8, 8))
	var fv := FolkView.new()
	holder.add_child(fv)
	fv.setup(f.id)
	if fv._is_placeholder:
		fv.free()
		holder.free()
		W.reset()
		print("action_visuals_test: placeholder rig, view checks skipped")
		return                              # no glb in this run: the capsule person gets no props or particles
	var plant: int = W.place_object("plant", Vector2i(9, 8), 0)
	f.current = Interaction.create("water_plant", f, plant, true)
	f.current.state = "running"
	for i in 14:
		fv._process(0.05)
	_check(fv.clip == "Pour", "watering plays '%s', want Pour" % fv.clip)
	_check(fv._props.has("watering_can") and (fv._props["watering_can"] as Node3D).visible, "watering shows a can")
	_check(fv._fx.has("water_arc") and (fv._fx["water_arc"] as CPUParticles3D).emitting, "watering shows a water arc")
	var ir = f.current
	ir.finish(true)
	f.current = null
	for i in 14:
		fv._process(0.05)
	_check(not (fv._fx["water_arc"] as CPUParticles3D).emitting, "the water arc stops with the action")
	var shown := 0
	for k in fv._props:
		shown += 1 if (fv._props[k] as Node3D).visible else 0
	_check(shown == 0, "%d prop(s) still shown after watering" % shown)
	# a chore finished well sparkles; one that was interrupted does not
	f.current = Interaction.create("clean_object", f, plant, true)
	f.current.state = "running"
	for i in 6:
		fv._process(0.05)
	f.current.finish(true)
	f.current = null
	for i in 3:
		fv._process(0.05)
	_check(fv._fx.has("sparkles"), "a finished wipe-down plays its sparkles")
	fv.free()
	holder.free()
	W.reset()
