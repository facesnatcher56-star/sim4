class_name FolkRigStyle
extends RefCounted
## Applies a Genetics appearance dictionary to an instanced folk_<stage>.glb: keeps only the toggleable child meshes the
## appearance asks for (the rest are freed, so a folk costs ~12 mesh nodes, not ~90), tints the named materials and
## blends the body-shape morph targets. Shared by FolkView (the world) and FolkPreview (the creator).
## Node names (see blender/folk_head.py / folk_body.py): body, legs_skin (always); hair_N, ears_N, eyes_N, brows_N, nose_N,
## mouth_N, fhair_N, mark_N, glasses_N, hat_N, scarf_1, bag_N, top_N, bottom_N, shoes_N (one or none of each group).

const ALWAYS := ["body", "legs_skin"]
const GROUPS := ["hair", "ears", "eyes", "brows", "nose", "mouth", "fhair", "mark", "glasses", "hat", "scarf", "bag", "top", "bottom", "shoes"]
const SHAPES := ["slim", "broad", "soft", "angular"]
const DRESS_TOP := 4


## Child-node names to keep for this appearance and age stage.
static func wanted(ap: Dictionary, stage: String) -> Dictionary:
	var a: Dictionary = Genetics.normalize(ap) if not ap.is_empty() else Genetics.neutral_appearance()
	var keep := {}
	for n in ALWAYS:
		keep[n] = true
	var style: int = int(a["hair_style"])
	var kid: bool = stage in ["baby", "toddler"]
	var grown: bool = stage in ["adult", "elder"]
	keep["hair_%d" % style] = true
	keep["ears_%d" % int(a["ears"])] = true
	keep["eyes_%d" % (int(a["face"]) % 4)] = true
	keep["nose_%d" % (int(a["face"]) / 4)] = true
	keep["mouth_%d" % int(a["mouth"])] = true
	keep["brows_%d" % int(a["brows"])] = true
	if grown and int(a["facial_hair"]) > 0:
		keep["fhair_%d" % int(a["facial_hair"])] = true
	if int(a["mark"]) > 0:
		keep["mark_%d" % int(a["mark"])] = true
	if int(a["glasses"]) > 0:
		keep["glasses_%d" % int(a["glasses"])] = true
	if int(a["hat"]) > 0 and not (style in Genetics.HAT_BLOCK) and stage != "baby":
		keep["hat_%d" % int(a["hat"])] = true
	if int(a["scarf"]) > 0:
		keep["scarf_1"] = true
	if int(a["bag"]) > 0 and not kid:
		keep["bag_%d" % int(a["bag"])] = true
	var top: int = int(a["top"])
	keep["top_%d" % top] = true
	if top != DRESS_TOP:
		keep["bottom_%d" % int(a["bottom"])] = true
	keep["shoes_%d" % int(a["shoes"])] = true
	return keep


static func tints(ap: Dictionary, fallback_shirt: Color = Color(0.3, 0.5, 0.8)) -> Dictionary:
	var a: Dictionary = Genetics.normalize(ap) if not ap.is_empty() else Genetics.neutral_appearance()
	var skin: Color = _col(a.get("skin", null), Color(0.90, 0.70, 0.56))
	return {
		"skin": skin,
		"hair": _col(a.get("hair_color", null), Color(0.25, 0.15, 0.10)),
		"eyes": _col(a.get("eye_color", null), Color(0.20, 0.30, 0.45)),
		"shirt": _col(a.get("shirt", null), fallback_shirt),
		"pants": _col(a.get("pants", null), Color(0.25, 0.28, 0.40)),
		"shoes": _col(a.get("shoe_color", null), Color(0.14, 0.11, 0.10)),
		"accent": _col(a.get("accent", null), Color(0.85, 0.85, 0.85)),
		"freckles": skin.darkened(0.38),
	}


## Prune + tint + morph. Returns the number of mesh nodes kept.
static func apply(rig: Node, ap: Dictionary, stage: String, fallback_shirt: Color = Color(0.3, 0.5, 0.8)) -> int:
	var keep: Dictionary = wanted(ap, stage)
	var a: Dictionary = Genetics.normalize(ap) if not ap.is_empty() else Genetics.neutral_appearance()
	var t: Dictionary = tints(ap, fallback_shirt)
	var kept := 0
	for n in rig.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var nm := String(mi.name)
		if _is_variant(nm) and not keep.has(nm):
			mi.get_parent().remove_child(mi)
			mi.queue_free()
			continue
		kept += 1
		_tint(mi, t)
		if nm.begins_with("top_") or nm.begins_with("bottom_"):
			_morph(mi, a)
	return kept


static func _is_variant(nm: String) -> bool:
	var i := nm.rfind("_")
	return i > 0 and (nm.substr(0, i) in GROUPS)


static func _tint(mi: MeshInstance3D, t: Dictionary) -> void:
	if mi.mesh == null:
		return
	for s in mi.mesh.get_surface_count():
		var m: Material = mi.mesh.surface_get_material(s)
		if m == null or not (m is BaseMaterial3D):
			continue
		var key := str(m.resource_name)
		if t.has(key):
			var d := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
			d.albedo_color = t[key]
			mi.set_surface_override_material(s, d)


static func _morph(mi: MeshInstance3D, a: Dictionary) -> void:
	var w := {"slim": 0.0, "broad": 0.0, "soft": 0.0, "angular": 0.0}
	match int(a["body_type"]):
		0:
			w["slim"] = 1.0
		2:
			w["broad"] = 1.0
	match int(a["frame"]):
		1:
			w["soft"] = 1.0
		2:
			w["angular"] = 1.0
	for k in w:
		var idx: int = mi.find_blend_shape_by_name(k)
		if idx >= 0:
			mi.set_blend_shape_value(idx, float(w[k]))


static func _col(hex: Variant, default: Color) -> Color:
	var s := str(hex)
	if s.begins_with("#") and (s.length() == 7 or s.length() == 9):
		return Color.html(s)
	return default
