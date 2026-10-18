extends RefCounted
## VARIETY: every folk model variant (6 age groups) carries all toggleable parts, all 31 clips and the body morph targets;
## FolkRigStyle keeps only what an appearance asks for, tints every named material and sets the morphs.

const REQUIRED_CLIPS := 31
const K = preload("res://tests/systems_kit.gd")


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null


func _names(rig: Node) -> Dictionary:
	var out := {}
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		out[String(mi.name)] = mi
	return out


func run() -> Array:
	var f: Array = []
	var n: Dictionary = GeneticsLook.counts()
	var g := RandomNumberGenerator.new()
	g.seed = 12
	for stage in FolkView.STAGES:
		var path: String = FolkView.variant_path(stage)
		var ps = load(path)
		if not (ps is PackedScene):
			f.append("%s: cannot load %s" % [stage, path])
			continue
		var rig: Node = ps.instantiate()
		var names: Dictionary = _names(rig)
		for grp in [["hair", n["hair_style"], [9]], ["ears", n["ears"], []], ["eyes", 4, []], ["nose", 4, []], ["mouth", n["mouth"], []],
				["brows", n["brows"], []], ["top", n["top"], []], ["bottom", n["bottom"], []], ["shoes", n["shoes"], []]]:
			for i in int(grp[1]):
				if not (i in grp[2]) and not names.has("%s_%d" % [grp[0], i]):
					f.append("%s: missing mesh %s_%d" % [stage, grp[0], i])
		for nm in ["body", "legs_skin", "fhair_1", "fhair_2", "fhair_3", "mark_1", "mark_2", "glasses_1", "glasses_2", "hat_1", "hat_2", "scarf_1", "bag_1", "bag_2"]:
			if not names.has(nm):
				f.append("%s: missing mesh %s" % [stage, nm])
		var ap := _anim_count(rig)
		if ap != REQUIRED_CLIPS:
			f.append("%s: %d clips (want %d)" % [stage, ap, REQUIRED_CLIPS])
		var t0: MeshInstance3D = names.get("top_0")
		if t0 != null:
			for s in FolkRigStyle.SHAPES:
				if t0.find_blend_shape_by_name(s) < 0:
					f.append("%s: top_0 lacks blend shape %s" % [stage, s])
		rig.free()
		# styled instances: only the asked-for parts remain, whatever the look
		for i in 25:
			var look: Dictionary = Genetics.random_appearance(g)
			var r2: Node = ps.instantiate()
			var kept: int = FolkRigStyle.apply(r2, look, stage)
			var nn: Dictionary = _names(r2)
			var want: Dictionary = FolkRigStyle.wanted(look, stage)
			for k in want:
				if not nn.has(k) and k != "hair_9":
					f.append("%s: wanted part %s missing (look %s)" % [stage, k, Genetics.signature(look)])
			if nn.size() > want.size():
				f.append("%s: %d parts left, only %d wanted" % [stage, nn.size(), want.size()])
			if kept > 20:
				f.append("%s: %d mesh nodes per folk is too many" % [stage, kept])
			if _anim_count(r2) != REQUIRED_CLIPS:
				f.append("%s: clips lost after styling" % stage)
			r2.free()
	# tints + morphs
	var ps2: PackedScene = load(FolkView.variant_path("adult"))
	var rig3: Node = ps2.instantiate()
	var look3: Dictionary = Genetics.neutral_appearance()
	look3.merge({"top": 1, "bottom": 2, "accent": "#ff0000", "shirt": "#00ff00", "pants": "#0000ff", "body_type": 2, "frame": 1, "hat": 1, "hair_style": 0,
		"shoes": 3, "shoe_color": "#123456", "skin": "#c68863", "glasses": 1, "scarf": 1, "bag": 1}, true)
	FolkRigStyle.apply(rig3, look3, "adult")
	var cols := {}
	for mi in rig3.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var ov: Material = m.get_surface_override_material(s)
			if ov is BaseMaterial3D:
				cols[str(m.mesh.surface_get_material(s).resource_name)] = (ov as BaseMaterial3D).albedo_color
	for kv in [["accent", "#ff0000"], ["shirt", "#00ff00"], ["pants", "#0000ff"], ["shoes", "#123456"], ["skin", "#c68863"]]:
		if not (cols.has(kv[0]) and (cols[kv[0]] as Color).is_equal_approx(Color(kv[1]))):
			f.append("material %s not tinted %s (%s)" % [kv[0], kv[1], str(cols.get(kv[0]))])
	var top: MeshInstance3D = rig3.find_child("top_1", true, false)
	if top == null or absf(top.get_blend_shape_value(top.find_blend_shape_by_name("broad")) - 1.0) > 0.01 \
			or absf(top.get_blend_shape_value(top.find_blend_shape_by_name("soft")) - 1.0) > 0.01:
		f.append("body morphs (broad + soft) not applied to the top")
	if rig3.find_child("hair_0", true, false) == null or rig3.find_child("hat_1", true, false) == null:
		f.append("short hair + cap expected")
	rig3.free()
	# tall hair never wears a hat
	var tall: Dictionary = Genetics.neutral_appearance()
	tall.merge({"hair_style": 5, "hat": 1}, true)
	if FolkRigStyle.wanted(tall, "adult").has("hat_1"):
		f.append("afro + cap should drop the cap")
	# kids: no beard
	var kid: Dictionary = Genetics.neutral_appearance()
	kid.merge({"facial_hair": 3}, true)
	if FolkRigStyle.wanted(kid, "child").has("fhair_3") or not FolkRigStyle.wanted(kid, "adult").has("fhair_3"):
		f.append("beard only for adults / elders")
	return f


func _anim_count(rig: Node) -> int:
	var a := _find_anim(rig)
	return a.get_animation_list().size() if a != null else 0
