extends RefCounted
## ANIMATION agent: FolkView instantiates for every body variant, plays Idle/Walk, tolerates missing appearance / missing
## models, tints from appearance, and drives social partners. Convention: run() -> Array of failure strings.

var fails: Array = []
var W: Node
var _holder: Node3D


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func _mk_folk(stage: String, tile: Vector2i, appearance: Variant = null) -> Folk:
	var f := Folk.create("T_" + stage)
	f.age_stage = stage
	if appearance is Dictionary:
		f.appearance = appearance
	W.add_folk(f, tile)
	return f


func _mk_view(f: Folk) -> FolkView:
	var fv := FolkView.new()
	fv.name = "folk_%d" % f.id
	_holder.add_child(fv)
	fv.setup(f.id)
	return fv


func _step(fv: FolkView, n: int, dt: float = 0.05) -> void:
	for i in n:
		fv._process(dt)


func _find_mesh(n: Node, nm: String) -> MeshInstance3D:
	if n is MeshInstance3D and n.name == nm:
		return n
	for c in n.get_children():
		var r := _find_mesh(c, nm)
		if r != null:
			return r
	return null


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
	_test_variants()
	_test_appearance()
	_test_missing_model()
	_test_social()
	_test_mood_icon()
	_holder.free()
	W.reset()
	FolkView.reload_map()
	return fails


func _test_variants() -> void:
	for stage in ["baby", "toddler", "child", "teen", "adult", "elder"]:
		var f := _mk_folk(stage, Vector2i(8, 8), {})   # empty appearance = not generated yet
		var fv := _mk_view(f)
		_check(fv.variant == stage, "variant for %s was %s" % [stage, fv.variant])
		_check(not fv._is_placeholder, "%s: placeholder used although model exists" % stage)
		_check(fv._anim != null, "%s: no AnimationPlayer" % stage)
		_step(fv, 6)
		var idle_expected := "Baby_Idle" if stage == "baby" else "Idle"
		_check(fv.clip == idle_expected, "%s idle clip is '%s', want %s" % [stage, fv.clip, idle_expected])
		# walk: logical tile moves one step
		f.tile = Vector2i(9, 8)
		_step(fv, 4)
		var walk_expected := "Baby_Crawl" if stage == "baby" else "Walk"
		_check(fv.clip == walk_expected, "%s walk clip is '%s', want %s" % [stage, fv.clip, walk_expected])
		_check(fv._anim.speed_scale > 0.0, "%s walk speed_scale %f" % [stage, fv._anim.speed_scale])
		_step(fv, 80)
		_check(fv.clip == idle_expected, "%s did not return to idle ('%s')" % [stage, fv.clip])
		fv.free()
		W.remove_folk(f.id)
	# stage change at runtime rebuilds the rig
	var f2 := _mk_folk("child", Vector2i(8, 8), {})
	var fv2 := _mk_view(f2)
	f2.age_stage = "teen"
	_step(fv2, 25)
	_check(fv2.variant == "teen", "runtime aging did not swap the body variant")
	fv2.free()
	W.remove_folk(f2.id)


func _test_appearance() -> void:
	var ap := {"skin": "#ff0000", "hair_style": 3, "hair_color": "#00ff00", "eye_color": "#0000ff", "shirt": "#ffff00",
		"pants": "#00ffff", "height": 1.1, "build": 0.9}
	var f := _mk_folk("adult", Vector2i(8, 8), ap)
	var fv := _mk_view(f)
	var found := {}
	for mi in fv._rig.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var base: Material = m.mesh.surface_get_material(s)
			var ov: Material = m.get_surface_override_material(s)
			if ov is BaseMaterial3D and not found.has(str(base.resource_name)):
				found[str(base.resource_name)] = (ov as BaseMaterial3D).albedo_color
	_check(found.get("skin", Color.BLACK).is_equal_approx(Color("#ff0000")), "skin not tinted: %s" % str(found.get("skin")))
	_check(found.get("shirt", Color.BLACK).is_equal_approx(Color("#ffff00")), "shirt not tinted")
	_check(found.get("pants", Color.BLACK).is_equal_approx(Color("#00ffff")), "pants not tinted")
	_check(found.get("hair", Color.BLACK).is_equal_approx(Color("#00ff00")), "hair not tinted")
	_check(found.get("eyes", Color.BLACK).is_equal_approx(Color("#0000ff")), "eyes not tinted")
	# only the chosen hair style is kept (unused variant meshes are freed)
	for i in 16:
		var h := fv._rig.find_child("hair_%d" % i, true, false) as Node3D
		_check((h != null) == (i == 3), "hair_%d presence wrong (style 3 expected)" % i)
	_check(absf(fv._rig.scale.y - 1.1) < 0.001 and absf(fv._rig.scale.x - 0.99) < 0.001, "height/build scale wrong: %s" % str(fv._rig.scale))
	# changing appearance retints live
	f.appearance = {"skin": "#00ff00", "hair_style": 1}
	_step(fv, 25)
	var h1 := fv._rig.find_child("hair_1", true, false) as Node3D
	_check(h1 != null and h1.visible and fv._rig.find_child("hair_3", true, false) == null, "appearance change did not switch hair style")
	fv.free()
	W.remove_folk(f.id)
	# partial / garbage appearance must not crash
	for bad in [{}, {"skin": "nonsense"}, {"hair_style": 99, "height": "x"}, {"shirt": 5, "pants": null}]:
		var fb := _mk_folk("adult", Vector2i(8, 8), bad)
		var fvb := _mk_view(fb)
		_step(fvb, 3)
		_check(fvb._rig != null, "no rig for appearance %s" % str(bad))
		fvb.free()
		W.remove_folk(fb.id)


func _test_missing_model() -> void:
	var m: Dictionary = FolkView.anim_map()
	var saved: Dictionary = (m["variant_files"] as Dictionary).duplicate()
	# variant model missing -> falls back to folk.glb
	(m["variant_files"] as Dictionary)["elder"] = "res://assets/models/does_not_exist.glb"
	var f := _mk_folk("elder", Vector2i(8, 8), {})
	var fv := _mk_view(f)
	_check(fv._rig != null and not fv._is_placeholder, "missing variant should fall back to folk.glb")
	fv.free()
	W.remove_folk(f.id)
	# everything missing -> capsule placeholder, still animates without crashing
	(m["variant_files"] as Dictionary)["fallback"] = "res://assets/models/does_not_exist_either.glb"
	var f2 := _mk_folk("elder", Vector2i(8, 8), {"shirt": "#ff0000"})
	var fv2 := _mk_view(f2)
	_check(fv2._is_placeholder, "expected capsule placeholder")
	_step(fv2, 5)
	f2.tile = Vector2i(9, 8)
	_step(fv2, 10)
	f2.posture = "sit"
	_step(fv2, 5)
	fv2.free()
	W.remove_folk(f2.id)
	m["variant_files"] = saved
	# unknown clip names resolve to something that exists
	var f3 := _mk_folk("adult", Vector2i(8, 8), {})
	var fv3 := _mk_view(f3)
	var r: String = fv3._resolve_clip("Definitely_Not_A_Clip")
	_check(fv3._anim.has_animation(r), "fallback clip '%s' does not exist" % r)
	fv3.free()
	W.remove_folk(f3.id)


func _test_social() -> void:
	var a := _mk_folk("adult", Vector2i(8, 8), {})
	var b := _mk_folk("adult", Vector2i(8, 8), {})
	var va := _mk_view(a)
	var vb := _mk_view(b)
	var ir := Interaction.create("chat", a, b.id, true)
	_check(ir != null, "chat interaction not creatable")
	if ir != null:
		ir.state = "running"
		a.current = ir
		a.posture = "stand"
		a.tile = b.tile
		_step(va, 12)
		_step(vb, 12)
		_check(va._partner_role == "actor" and vb._partner_role == "target", "partner roles: %s / %s" % [va._partner_role, vb._partner_role])
		_check(va.clip in ["Talk", "Laugh", "Wave"], "actor clip '%s' not social" % va.clip)
		_check(vb.clip in ["Talk", "Laugh", "Wave"], "target clip '%s' not social" % vb.clip)
		_step(va, 60)
		_step(vb, 60)
		var d := va.position.distance_to(vb.position)
		_check(d > 0.4 and d < 1.2, "face-to-face distance %f" % d)
		# they look at each other: model -Z points to the partner
		var fwd_a := Vector2(-sin(va.rotation.y), -cos(va.rotation.y))
		var to_b := Vector2(vb.position.x - va.position.x, vb.position.z - va.position.z).normalized()
		_check(fwd_a.dot(to_b) > 0.9, "actor not facing partner (dot %f)" % fwd_a.dot(to_b))
		var fwd_b := Vector2(-sin(vb.rotation.y), -cos(vb.rotation.y))
		_check(fwd_b.dot(-to_b) > 0.9, "target not facing actor (dot %f)" % fwd_b.dot(-to_b))
		a.current = null
	va.free()
	vb.free()
	W.remove_folk(a.id)
	W.remove_folk(b.id)


func _test_mood_icon() -> void:
	var f := _mk_folk("adult", Vector2i(8, 8), {})
	var fv := _mk_view(f)
	f.mood_name = "angry"
	f.mood_intensity = 3
	_step(fv, 3)
	_check(fv._mood_icon != null and fv._mood_icon.visible, "mood icon should show for strong mood")
	f.mood_name = "neutral"
	f.mood_intensity = 0
	_step(fv, 3)
	_check(not fv._mood_icon.visible, "mood icon should hide for neutral")
	fv.free()
	W.remove_folk(f.id)
