class_name FolkFx
extends RefCounted
## Particles around a folk while a clip plays, plus a one-shot burst when an interaction finishes well (view only: nothing here touches sim state or
## rng). Data in data/animation_props.json "fx": `rules` (first match: interaction ids / tags / clips, like FolkProps) name a looping effect (water arc
## from the watering can, steam over the pan, shower water from the head, suds, bath bubbles, music notes, dust); `done` rules name a burst for a
## successful finish (sparkles when something is clean, sparks when it is fixed); `defs` describe each effect (anchor bone or `root`, direction, speed,
## gravity, size, colour). Effects are CPUParticles3D built on first use and switched off (not freed) when no rule matches.

const NODE := "Fx"


static func _cfg() -> Dictionary:
	return FolkView.anim_map().get("fx", {})


## The loop effect for what the folk is doing: "" when none.
static func fx_for(def_id: String, tags: Array, clip: String) -> String:
	for r in (_cfg().get("rules", []) as Array):
		if FolkProps.rule_matches(r, def_id, tags, clip):
			return str((r as Dictionary).get("fx", ""))
	return ""


## The burst played when this interaction finishes successfully: "" when none.
static func done_for(def_id: String, tags: Array) -> String:
	for r in (_cfg().get("done", []) as Array):
		if FolkProps.rule_matches(r, def_id, tags, ""):
			return str((r as Dictionary).get("fx", ""))
	return ""


static func _tags(inter: Variant) -> Array:
	return inter.def.get("tags", []) if inter != null and inter.def is Dictionary else []


## Called every frame with the interaction the folk shows (null = none) and the clip being played; cheap when nothing changed.
static func update(fv, inter: Variant, clip: String) -> void:
	if fv._rig == null or fv._is_placeholder:
		return
	var prev: Variant = fv._fx_last
	if inter != prev:
		fv._fx_last = inter
		if prev != null and str(prev.state) == "finished" and bool(prev.success):
			burst(fv, done_for(str(prev.def_id), _tags(prev)))
	var sig: int = (inter.get_instance_id() if inter != null else 0) * 31 + hash(clip)
	if sig == fv._fx_sig:
		return
	fv._fx_sig = sig
	var want := ""
	if inter != null and not fv._moving and fv._waypoints.is_empty():
		want = fx_for(str(inter.def_id), _tags(inter), clip)
	for k in fv._fx:
		var node: CPUParticles3D = fv._fx[k]
		if is_instance_valid(node) and not node.one_shot:
			node.emitting = (k == want)
	if want != "" and not fv._fx.has(want):
		var n := _build(fv, want)
		if n != null:
			fv._fx[want] = n
			n.emitting = true


## Plays a one-shot effect now (a finished chore, a test).
static func burst(fv, name: String) -> void:
	if name == "" or fv._rig == null or fv._is_placeholder:
		return
	var n: CPUParticles3D = fv._fx.get(name, null)
	if n == null or not is_instance_valid(n):
		n = _build(fv, name)
		if n == null:
			return
		fv._fx[name] = n
	n.restart()
	n.emitting = true


## Drops every effect (the body was rebuilt: bone-attached ones went with the skeleton).
static func reset(fv) -> void:
	for k in fv._fx:
		var n = fv._fx[k]
		if is_instance_valid(n) and not (n as Node).is_queued_for_deletion() and (n as Node).get_parent() == fv:
			(n as Node).queue_free()
	fv._fx.clear()
	fv._fx_sig = 0
	fv._fx_last = null


static func _vec(a: Variant, d: Vector3) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return d


static func _build(fv, name: String) -> CPUParticles3D:
	var d: Dictionary = (_cfg().get("defs", {}) as Dictionary).get(name, {})
	if d.is_empty():
		return null
	var parent: Node = fv
	var anchor := str(d.get("anchor", "root"))
	if anchor != "root":
		var sk := FolkProps._find_skeleton(fv._rig)
		if sk == null or sk.find_bone(anchor) < 0:
			return null
		var att := BoneAttachment3D.new()
		att.name = "%s_%s" % [NODE, name]
		att.bone_name = anchor
		sk.add_child(att)
		parent = att
	var p := CPUParticles3D.new()
	p.name = "%s_%s" % [NODE, name]
	var burst_fx := bool(d.get("burst", false))
	p.amount = int(d.get("amount", 12))
	p.lifetime = float(d.get("life", 1.0))
	p.one_shot = burst_fx
	p.explosiveness = 1.0 if burst_fx else 0.0
	p.local_coords = false
	p.direction = _vec(d.get("dir", null), Vector3.UP).normalized()
	p.spread = float(d.get("spread", 20.0))
	var v: Array = d.get("vel", [0.2, 0.5])
	p.initial_velocity_min = float(v[0])
	p.initial_velocity_max = float(v[1])
	p.gravity = _vec(d.get("gravity", null), Vector3.ZERO)
	var sz := float(d.get("size", 0.05))
	p.scale_amount_min = sz * 0.7
	p.scale_amount_max = sz * 1.2
	if d.has("box"):
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = _vec(d["box"], Vector3.ZERO) * 0.5
	var col := FolkView.color_of(d.get("color", "#ffffff"), Color.WHITE)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col.r, col.g, col.b, col.a))
	ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = ramp
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = _vec(d.get("pos", null), Vector3.ZERO)
	p.emitting = false
	parent.add_child(p)
	return p
