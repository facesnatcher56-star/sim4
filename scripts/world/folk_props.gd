class_name FolkProps
extends RefCounted
## Small props in a folk's hands while a clip plays (view only, never touches sim state): a book for reading, a cup for a drink, a game pad for video games,
## a fork and plate for a meal, a brush for painting, a phone, a newspaper; task 33: watering can, pan, cloth, broom, wrench, trowel, rod, weights, pen,
## toothbrush, mic, baby bundle and bottle, guitar, ... All data in data/animation_map.json "props": `defs` (bone + a few primitive parts each) and
## `rules` (first match wins: interaction ids / tags / clips). The prop hangs on a BoneAttachment3D of the folk's skeleton and is hidden as soon as no rule
## matches (the clip ended, the folk walks off). Rigs without a skeleton (the placeholder capsule person) get none.

const NODE := "HandProp"


static func _cfg() -> Dictionary:
	return FolkView.anim_map().get("props", {})


## Does a rule (props or fx) apply to this interaction id / tags and the clip being played? ids OR tags (none of both = any); `clips` must contain the clip.
static func rule_matches(rule: Dictionary, def_id: String, tags: Array, clip: String) -> bool:
	if rule.has("clips") and not (clip in (rule["clips"] as Array)):
		return false
	var ok := not (rule.has("ids") or rule.has("tags"))
	if rule.has("ids") and def_id in (rule["ids"] as Array):
		ok = true
	if not ok and rule.has("tags"):
		for t in (rule["tags"] as Array):
			if str(t) in tags:
				ok = true
				break
	return ok


## The props for what the folk is doing (first matching rule: `prop` or `props`): [] when none. `tags` are the tags of the running interaction.
static func props_for(def_id: String, tags: Array, clip: String) -> Array:
	for r in (_cfg().get("rules", []) as Array):
		var rule: Dictionary = r
		if rule_matches(rule, def_id, tags, clip):
			if rule.has("props"):
				return (rule["props"] as Array).duplicate()
			return [str(rule.get("prop", ""))] if str(rule.get("prop", "")) != "" else []
	return []


## The first prop name for what the folk is doing: "" when none.
static func prop_for(def_id: String, tags: Array, clip: String) -> String:
	var l := props_for(def_id, tags, clip)
	return str(l[0]) if not l.is_empty() else ""


## Shows the prop that goes with the interaction + clip the folk is playing, hides the rest. Called every frame; cheap when nothing changed.
static func update(fv, inter: Variant, clip: String) -> void:
	if fv._rig == null or fv._is_placeholder:
		return
	var sig: int = (inter.get_instance_id() if inter != null else 0) * 31 + hash(clip)
	if sig == fv._prop_sig:
		return
	fv._prop_sig = sig
	var want: Array = []
	if inter != null and not fv._moving and fv._waypoints.is_empty():
		var tags: Array = inter.def.get("tags", []) if inter.def is Dictionary else []
		want = props_for(str(inter.def_id), tags, clip)
	for k in fv._props:
		(fv._props[k] as Node3D).visible = (k in want)
	for w in want:
		if not fv._props.has(w):
			var n := _build(fv, str(w))
			if n != null:
				fv._props[w] = n


static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s != null:
			return s
	return null


static func _build(fv, name: String) -> Node3D:
	var d: Dictionary = (_cfg().get("defs", {}) as Dictionary).get(name, {})
	var sk := _find_skeleton(fv._rig)
	if d.is_empty() or sk == null:
		return null
	var bone := str(d.get("bone", "hand_R"))
	if sk.find_bone(bone) < 0:
		return null
	var att := BoneAttachment3D.new()
	att.name = "%s_%s" % [NODE, name]
	att.bone_name = bone
	sk.add_child(att)
	var root := Node3D.new()
	var o: Array = d.get("pos", [0, 0, 0])
	var r: Array = d.get("rot", [0, 0, 0])
	root.position = Vector3(float(o[0]), float(o[1]), float(o[2]))
	root.rotation_degrees = Vector3(float(r[0]), float(r[1]), float(r[2]))
	att.add_child(root)
	for p in (d.get("parts", []) as Array):
		var mi := MeshInstance3D.new()
		var pos: Array = p.get("pos", [0, 0, 0])
		if p.has("box"):
			var b := BoxMesh.new()
			var s: Array = p["box"]
			b.size = Vector3(float(s[0]), float(s[1]), float(s[2]))
			mi.mesh = b
		else:
			var c := CylinderMesh.new()
			var s2: Array = p.get("cyl", [0.03, 0.1])
			c.top_radius = float(s2[0])
			c.bottom_radius = float(p.get("cyl_bottom", s2[0]))
			c.height = float(s2[1])
			c.radial_segments = 8
			c.rings = 1
			mi.mesh = c
		var rot: Array = p.get("rot", [0, 0, 0])
		mi.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		mi.rotation_degrees = Vector3(float(rot[0]), float(rot[1]), float(rot[2]))
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.html(str(p.get("color", "#888888")))
		m.roughness = 0.8
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return att
