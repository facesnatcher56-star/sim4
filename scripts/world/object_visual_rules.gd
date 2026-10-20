class_name ObjectVisualRules
extends RefCounted
## Task 33.3 (view only, pure functions): which VISUAL an object has for its current state. All data in data/object_visuals.json:
##   objects.<def_id>.layers = [layer | "@template", ...]; a layer = {id, states: [{id, when: [cond...], surfaces, hide, overlay, scale, tilt, parts, fx}]}
##   and the FIRST state of a layer whose `when` holds applies (a state with no `when` is the default). The looks of all layers are merged.
## Conditions (AND'd): {key, eq|lte|gte|lt|gt|ratio_lte|ratio_gte|ratio_lt|ratio_gt}, {in_use: bool}, {use_tag: [...]}, {use_not_tag: [...]}, {any: [cond...]}.
## `resolve` reads the object's `state` Dictionary only; it never touches the sim, the rng or the world, so the same state always gives the same look.

const PATH := "res://data/object_visuals.json"
static var _cfg: Dictionary = {}
static var _loaded := false


static func cfg() -> Dictionary:
	if _loaded:
		return _cfg
	_loaded = true
	_cfg = {}
	if FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_cfg = parsed
	return _cfg


static func reload() -> void:
	_loaded = false


static func objects() -> Dictionary:
	return cfg().get("objects", {})


static func has_rules(def_id: String) -> bool:
	return objects().has(def_id)


## Objects farther than this many tiles from the camera target keep their parts but drop particles and lights (LOD).
static func near_tiles() -> float:
	return float(cfg().get("near_tiles", 26.0))


static func fx_kind(kind: String) -> Dictionary:
	return (cfg().get("fx_kinds", {}) as Dictionary).get(kind, {})


static func _layers_of(def_id: String) -> Array:
	var c: Dictionary = objects().get(def_id, {})
	if c.has("extends"):
		c = objects().get(str(c["extends"]), {})
	var out: Array = []
	var tpl: Dictionary = cfg().get("templates", {})
	for l in (c.get("layers", []) as Array):
		if l is String:
			var key := str(l).trim_prefix("@")
			if tpl.has(key):
				out.append(tpl[key])
		elif l is Dictionary:
			out.append(l)
	return out


static func _part_scale(def_id: String) -> Vector3:
	var c: Dictionary = objects().get(def_id, {})
	var ps: Array = c.get("part_scale", [1, 1, 1])
	return Vector3(float(ps[0]), float(ps[1]), float(ps[2]))


# ------------------------------------------------------------------ conditions

static func _num(state: Dictionary, key: String) -> float:
	var v: Variant = state.get(key, 0.0)
	if v is bool:
		return 1.0 if v else 0.0
	return float(v)


static func _ratio(state: Dictionary, def_state: Dictionary, key: String) -> float:
	var sd: Dictionary = def_state.get(key, {})
	if not sd.has("max"):
		return 1.0 if bool(state.get(key, false)) else 0.0
	var mn := float(sd.get("min", 0.0))
	var mx := float(sd.get("max", 1.0))
	if mx <= mn:
		return 0.0
	return clampf((_num(state, key) - mn) / (mx - mn), 0.0, 1.0)


static func cond_holds(c: Dictionary, state: Dictionary, def_state: Dictionary, use_tags: Variant) -> bool:
	var in_use: bool = use_tags != null
	if c.has("any"):
		for sub in (c["any"] as Array):
			if cond_holds(sub, state, def_state, use_tags):
				return true
		return false
	if c.has("in_use"):
		return in_use == bool(c["in_use"])
	if c.has("use_tag"):
		if not in_use:
			return false
		for t in (c["use_tag"] as Array):
			if (use_tags as Array).has(str(t)):
				return true
		return false
	if c.has("use_not_tag"):
		if not in_use:
			return false
		for t in (c["use_not_tag"] as Array):
			if (use_tags as Array).has(str(t)):
				return false
		return true
	var key := str(c.get("key", ""))
	if key == "":
		return true
	var v := _num(state, key)
	if c.has("eq"):
		var want: Variant = c["eq"]
		if want is bool:
			return bool(state.get(key, false)) == want
		return is_equal_approx(v, float(want))
	if c.has("lte") and not v <= float(c["lte"]):
		return false
	if c.has("gte") and not v >= float(c["gte"]):
		return false
	if c.has("lt") and not v < float(c["lt"]):
		return false
	if c.has("gt") and not v > float(c["gt"]):
		return false
	if c.has("ratio_lte") or c.has("ratio_gte") or c.has("ratio_lt") or c.has("ratio_gt"):
		var r := _ratio(state, def_state, key)
		if c.has("ratio_lte") and not r <= float(c["ratio_lte"]):
			return false
		if c.has("ratio_gte") and not r >= float(c["ratio_gte"]):
			return false
		if c.has("ratio_lt") and not r < float(c["ratio_lt"]):
			return false
		if c.has("ratio_gt") and not r > float(c["ratio_gt"]):
			return false
	return true


static func state_holds(st: Dictionary, state: Dictionary, def_state: Dictionary, use_tags: Variant) -> bool:
	for c in (st.get("when", []) as Array):
		if not cond_holds(c, state, def_state, use_tags):
			return false
	return true


## The id of the state each layer is in: ["water:wilting", "broken:ok"...]. Handy for tests and debugging.
static func state_ids(def_id: String, state: Dictionary, def_state: Dictionary, use_tags: Variant = null) -> Array:
	var out: Array = []
	for layer in _layers_of(def_id):
		var st := _pick(layer, state, def_state, use_tags)
		if not st.is_empty():
			out.append("%s:%s" % [str(layer.get("id", "")), str(st.get("id", ""))])
	return out


static func _pick(layer: Dictionary, state: Dictionary, def_state: Dictionary, use_tags: Variant) -> Dictionary:
	for st in (layer.get("states", []) as Array):
		if state_holds(st, state, def_state, use_tags):
			return st
	return {}


# ------------------------------------------------------------------ resolve

static func _vec(a: Variant, d: Vector3 = Vector3.ZERO) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return d


static func _color(s: Variant, d: Color = Color.WHITE) -> Color:
	return Color(str(s)) if s != null and str(s) != "" else d


## The look of an object: {} when it simply keeps its model. Keys: ids, surfaces {name_or_prefix*: {color, emit, flicker}}, hide [names],
## overlay Color (tint over the whole model), scale Vector3, tilt (degrees about the front axis), parts [...], fx [...].
## `use_tags` is null when nobody is using the object, else the tags of what they are doing; `height` is the model height (fx "on_top").
static func resolve(def_id: String, state: Dictionary, def_state: Dictionary, use_tags: Variant = null, height: float = 1.0) -> Dictionary:
	if not has_rules(def_id):
		return {}
	var ps := _part_scale(def_id)
	var look := {"ids": [], "surfaces": {}, "hide": [], "overlay": null, "scale": Vector3.ONE, "tilt": 0.0, "parts": [], "fx": []}
	var any := false
	for layer in _layers_of(def_id):
		var st := _pick(layer, state, def_state, use_tags)
		if st.is_empty():
			continue
		any = true
		(look["ids"] as Array).append("%s:%s" % [str(layer.get("id", "")), str(st.get("id", ""))])
		for sname in (st.get("surfaces", {}) as Dictionary):
			var sv: Variant = st["surfaces"][sname]
			var sd: Dictionary = sv if sv is Dictionary else {"color": str(sv)}
			look["surfaces"][sname] = {"color": _color(sd.get("color", "#ffffff")), "emit": float(sd.get("emit", 0.0)), "flicker": float(sd.get("flicker", 0.0))}
		for h in (st.get("hide", []) as Array):
			(look["hide"] as Array).append(str(h))
		if st.has("overlay"):
			var oc := _color(st["overlay"])
			if look["overlay"] == null or oc.a > (look["overlay"] as Color).a:
				look["overlay"] = oc
		if st.has("scale"):
			look["scale"] = _vec(st["scale"], Vector3.ONE)
		look["tilt"] = float(st.get("tilt", look["tilt"]))
		for p in (st.get("parts", []) as Array):
			_add_part(look["parts"], p, state, def_state, ps)
		for fxd in (st.get("fx", []) as Array):
			var fp := _vec(fxd.get("pos", [0, 0, 0])) * ps
			if bool(fxd.get("on_top", false)):
				fp.y += height
			(look["fx"] as Array).append({"kind": str(fxd.get("kind", "")), "pos": fp})
	return look if any else {}


static func _add_part(out: Array, p: Dictionary, state: Dictionary, def_state: Dictionary, ps: Vector3) -> void:
	var size := _vec(p.get("size", [0.1, 0.1, 0.1]), Vector3.ONE * 0.1)
	var pos := _vec(p.get("pos", [0, 0, 0]))
	if p.has("grow"):
		var g: Dictionary = p["grow"]
		var r := maxf(_ratio(state, def_state, str(g.get("key", ""))), float(g.get("min", 0.0)))
		var axis := clampi(int(g.get("axis", 1)), 0, 2)
		var full: float = size[axis]
		size[axis] = full * r
		pos[axis] -= (full - size[axis]) * 0.5
	var part := {
		"shape": str(p.get("shape", "box")), "size": size, "rot": _vec(p.get("rot", [0, 0, 0])),
		"color": _color(p.get("color", "#cccccc")), "emit": float(p.get("emit", 0.0)), "flicker": float(p.get("flicker", 0.0)),
		"light": p.get("light", []),
	}
	if str(part["shape"]) == "box":
		part["size"] = size * Vector3(absf(ps.x), absf(ps.y), absf(ps.z))
	if p.has("grid"):
		var gd: Dictionary = p["grid"]
		var nx := int(gd.get("nx", 1))
		var nz := int(gd.get("nz", 1))
		for ix in nx:
			for iz in nz:
				var q: Dictionary = part.duplicate()
				q["pos"] = (pos + Vector3(float(gd.get("x0", 0.0)) + ix * float(gd.get("dx", 0.0)), 0.0, float(gd.get("z0", 0.0)) + iz * float(gd.get("dz", 0.0)))) * ps
				out.append(q)
		return
	part["pos"] = pos * ps
	out.append(part)
