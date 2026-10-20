class_name DistrictDressing
extends Node3D
## Optional "rough dressing" layer (task 41 look test; view only, nothing here touches sim state or rng). data/district_dressing.json holds named
## groups of items placed relative to a lot's top-left tile; `DistrictDressing.apply(lot_view, lot_id, ["group", ...])` builds them under
## a child node of the LotView. Used by tests/art41_shot.gd only today; it is meant to become a district's identity table later.
## Item kinds ("k"): glb (model, pos [x,z], y, yaw, roll, scale, tint), lamp (street lamp + light, mode on / flicker / broken), decal (Forward+ Decal:
## tex, pos [x,y,z], size, face ax|az|ay), box, litter, weeds, chainlink, boards (window objects of the lot: board / bars index lists),
## gutter, house (decor shell glb scaled to a footprint), bulb (bare bulb + light), sign (lit text), light (point light).
## Budget: decals and lights are few (tens); everything is static meshes, the flicker is one per-frame energy write per flickering lamp.

const PATH := "res://data/district_dressing.json"

var _lights: Array = []          # {node, base, mode, phase}
var _origin := Vector2.ZERO
var _t := 0.0
var _mats: Dictionary = {}


static func data() -> Dictionary:
	var fa := FileAccess.open(PATH, FileAccess.READ)
	if fa == null:
		return {}
	var j := JSON.new()
	return j.data if j.parse(fa.get_as_text()) == OK and j.data is Dictionary else {}


static func apply(lv: Node3D, lot_id: String, groups: Array) -> DistrictDressing:
	var old = lv.get_node_or_null("DistrictDressing")
	if old != null:
		old.free()
	var dd := DistrictDressing.new()
	dd.name = "DistrictDressing"
	lv.add_child(dd)
	var reg: Dictionary = {}
	for r in World.regions.regions.values():
		if str(r.get("lot", "")) == lot_id:
			reg = r
	var o: Vector2i = (reg["rect"] as Rect2i).position
	dd._origin = Vector2(o)
	var d := data().get("groups", {}) as Dictionary
	for g in groups:
		for item in (d.get(g, []) as Array):
			dd._item(item)
	return dd


func _process(delta: float) -> void:
	_t += delta
	for l in _lights:
		var n := l["node"] as OmniLight3D
		if str(l["mode"]) == "flicker":
			var ph: float = float(l["phase"])
			var f := 0.55 + 0.45 * sin(_t * 17.0 + ph) * sin(_t * 5.3 + ph * 2.0)
			if fmod(_t * 0.7 + ph, 4.0) > 3.55:
				f *= 0.1                       # a dead moment
			n.light_energy = float(l["base"]) * clampf(f, 0.0, 1.0)


func _w(x: float, z: float) -> Vector2:
	return _origin + Vector2(x, z)


func _vec2(a, d := Vector2.ZERO) -> Vector2:
	return Vector2(float(a[0]), float(a[1])) if a is Array and (a as Array).size() >= 2 else d


func _col(s, d := Color.WHITE) -> Color:
	return Color(str(s)) if s != null else d


func _mat(c: Color, rough := 0.9, emit := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [c.to_html(true), rough, emit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m


func _item(it: Dictionary) -> void:
	match str(it.get("k", "")):
		"glb": _glb(it)
		"lamp": _lamp(it)
		"decal": _decal(it)
		"box": _box(it)
		"litter": _litter(it)
		"weeds": _weeds(it)
		"chainlink": _chainlink(it)
		"boards": _boards(it)
		"gutter": _gutter(it)
		"house": _house(it)
		"bulb": _bulb(it)
		"sign": _sign(it)
		"light": _omni(it, Vector3(float(it["pos"][0]), float(it.get("y", 3.0)), float(it["pos"][1])))


# ------------------------------------------------------------------ pieces

func _glb(it: Dictionary) -> Node3D:
	var ps = load("res://assets/models/%s.glb" % str(it["model"]))
	if ps == null:
		return null
	var n: Node3D = (ps as PackedScene).instantiate()
	var p := _w(float(it["pos"][0]), float(it["pos"][1]))
	n.position = Vector3(p.x, float(it.get("y", 0.0)), p.y)
	n.rotation = Vector3(deg_to_rad(float(it.get("pitch", 0.0))), deg_to_rad(float(it.get("yaw", 0.0))), deg_to_rad(float(it.get("roll", 0.0))))
	n.scale = Vector3.ONE * float(it.get("scale", 1.0))
	if it.has("tint"):
		_tint(n, _col(it["tint"]), float(it.get("tint_mix", 0.6)))
	add_child(n)
	return n


## Dirty / burnt / rusty look for a model: every surface colour pulled toward `c` (own material copies).
func _tint(n: Node, c: Color, mix: float) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as BaseMaterial3D
			m.albedo_color = src.albedo_color.lerp(src.albedo_color * c, mix)
			mi.set_surface_override_material(s, m)
	for ch in n.get_children():
		_tint(ch, c, mix)


func _omni(it: Dictionary, pos: Vector3) -> OmniLight3D:
	var l := OmniLight3D.new()
	var p := _w(pos.x, pos.z)
	l.position = Vector3(p.x, pos.y, p.y)
	l.light_color = _col(it.get("color", "#ffc06a"))
	l.light_energy = float(it.get("energy", 3.0))
	l.omni_range = float(it.get("range", 9.0))
	l.omni_attenuation = float(it.get("atten", 1.3))
	l.shadow_enabled = bool(it.get("shadow", false))
	add_child(l)
	_lights.append({"node": l, "base": l.light_energy, "mode": str(it.get("mode", "on")), "phase": float(_lights.size()) * 1.7})
	return l


func _lamp(it: Dictionary) -> void:
	var mode := str(it.get("mode", "on"))
	var p: Array = it["pos"]
	var pole := _glb({"model": "outdoor/street_lamp", "pos": p, "yaw": it.get("yaw", 0.0), "roll": 9.0 if mode == "broken" else 0.0,
		"tint": "#8a7a68", "tint_mix": 0.5})
	var h := float(it.get("height", 4.4))
	var off := _vec2(it.get("arm", [0, 0]))
	if mode == "broken":
		return
	var l := _omni({"color": it.get("color", "#ff9c3d"), "energy": it.get("energy", 4.5), "range": it.get("range", 11.0), "mode": mode}, Vector3(float(p[0]) + off.x, h, float(p[1]) + off.y))
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	bulb.mesh = sm
	bulb.material_override = _mat(_col(it.get("color", "#ff9c3d")), 0.3, 3.0)
	bulb.position = l.position
	add_child(bulb)
	if pole == null:
		_box({"pos": p, "size": [0.15, h, 0.15], "color": "#3a3a3c"})


func _decal(it: Dictionary) -> void:
	var d := Decal.new()
	d.texture_albedo = DressingTex.tex(str(it["tex"]))
	var sz: Array = it.get("size", [2, 1, 2])
	d.size = Vector3(float(sz[0]), float(sz[1]), float(sz[2]))
	var p := _w(float(it["pos"][0]), float(it["pos"][2]))
	d.position = Vector3(p.x, float(it["pos"][1]), p.y)
	var face := str(it.get("face", "ay"))
	match face:
		"ax": d.rotation = Vector3(0, 0, PI * 0.5)      # projects along x (a wall facing east / west)
		"az": d.rotation = Vector3(PI * 0.5, 0, 0)      # projects along z (a wall facing north / south)
	d.rotation.y += deg_to_rad(float(it.get("spin", 0.0)))
	d.modulate = _col(it.get("color", "#ffffff"))
	d.upper_fade = 0.05
	d.lower_fade = 0.05
	d.normal_fade = 0.1 if face == "ay" else 0.0
	add_child(d)


func _box(it: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var s: Array = it.get("size", [1, 1, 1])
	bm.size = Vector3(float(s[0]), float(s[1]), float(s[2]))
	mi.mesh = bm
	mi.material_override = _mat(_col(it.get("color", "#777777")), float(it.get("rough", 0.9)), float(it.get("emit", 0.0)))
	var p := _w(float(it["pos"][0]), float(it["pos"][1]))
	mi.position = Vector3(p.x, float(it.get("y", float(s[1]) * 0.5)), p.y)
	mi.rotation = Vector3(deg_to_rad(float(it.get("pitch", 0.0))), deg_to_rad(float(it.get("yaw", 0.0))), deg_to_rad(float(it.get("roll", 0.0))))
	add_child(mi)
	return mi


func _litter(it: Dictionary) -> void:
	var a: Array = it["area"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(it.get("seed", 3))
	var cols := ["#c9c4b8", "#8a6d3b", "#b0302a", "#d8d2a0", "#4f6c8a", "#e8e8e8"]
	for i in int(it.get("count", 20)):
		var sz := rng.randf_range(0.1, 0.28)
		_box({"pos": [rng.randf_range(float(a[0]), float(a[2])), rng.randf_range(float(a[1]), float(a[3]))], "size": [sz, 0.02 + rng.randf() * 0.05, sz * rng.randf_range(0.5, 1.2)],
			"color": cols[rng.randi() % cols.size()], "yaw": rng.randf() * 180.0, "y": 0.02})


func _weeds(it: Dictionary) -> void:
	var a: Array = it["area"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(it.get("seed", 5))
	var cols := ["#6b7340", "#7b7a3c", "#5d6a38", "#8a7a45"]
	for i in int(it.get("tufts", 0)):            # overgrown yard: big dry grass tufts of the outdoor kit
		var tp := _w(rng.randf_range(float(a[0]), float(a[2])), rng.randf_range(float(a[1]), float(a[3])))
		var tuft := _glb({"model": "outdoor/grass_tuft", "pos": [tp.x - _origin.x, tp.y - _origin.y], "yaw": rng.randf() * 360.0, "scale": rng.randf_range(1.8, 3.2),
			"tint": ["#9a9450", "#7d8a48", "#a08a50"][rng.randi() % 3], "tint_mix": 0.7})
	for i in int(it.get("count", 30)):
		var h := rng.randf_range(0.25, 0.55)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = rng.randf_range(0.05, 0.11)
		cm.height = h
		cm.radial_segments = 5
		mi.mesh = cm
		mi.material_override = _mat(Color(cols[rng.randi() % cols.size()]), 1.0)
		var p := _w(rng.randf_range(float(a[0]), float(a[2])), rng.randf_range(float(a[1]), float(a[3])))
		mi.position = Vector3(p.x, h * 0.5, p.y)
		mi.rotation = Vector3(rng.randf_range(-0.25, 0.25), rng.randf() * TAU, rng.randf_range(-0.25, 0.25))
		add_child(mi)


func _chainlink(it: Dictionary) -> void:
	var a := _vec2(it["from"])
	var b := _vec2(it["to"])
	var h := float(it.get("h", 1.8))
	var length := a.distance_to(b)
	var wa := _w(a.x, a.y)
	var wb := _w(b.x, b.y)
	var mid := (wa + wb) * 0.5
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(length, h)
	quad.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_texture = DressingTex.tex("chainlink")
	m.uv1_scale = Vector3(length * 1.6, h * 1.6, 1.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.3
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.5
	m.metallic = 0.4
	quad.material_override = m
	quad.position = Vector3(mid.x, h * 0.5, mid.y)
	quad.rotation.y = -atan2(wb.y - wa.y, wb.x - wa.x)
	add_child(quad)
	var posts := int(length / 3.0) + 1
	for i in posts + 1:
		var q := a.lerp(b, float(i) / float(posts))
		_box({"pos": [q.x, q.y], "size": [0.09, h + 0.15, 0.09], "color": "#5b5f63", "rough": 0.5, "roll": float(it.get("lean", 0.0)) if i % 3 == 1 else 0.0})
	var rail := _box({"pos": [(a.x + b.x) * 0.5, (a.y + b.y) * 0.5], "size": [length, 0.06, 0.06], "y": h + 0.05, "color": "#5b5f63", "rough": 0.5})
	rail.rotation.y = quad.rotation.y


func _window_edge(o) -> Vector3i:
	for e in World.mounts:
		if int(World.mounts[e]) == int(o.id):
			return e
	return Vector3i(o.tile.x, o.tile.y, 0)


## Boards or bars over some of the lot's windows (index lists into the windows sorted by position).
func _boards(it: Dictionary) -> void:
	var wins: Array = []
	for o in World.all_objects():
		if str(o.def_id) == "window" and o.level == 0 and Rect2(_origin, Vector2(32, 24)).has_point(Vector2(o.tile)):
			wins.append(o)
	wins.sort_custom(func(a, b): return a.tile.x + a.tile.y * 64 < b.tile.x + b.tile.y * 64)
	var board: Array = (it.get("board", []) as Array).map(func(v): return int(v))      # JSON numbers are floats
	var bars: Array = (it.get("bars", []) as Array).map(func(v): return int(v))
	for i in wins.size():
		var mode := "board" if i in board else ("bars" if i in bars else "")
		if mode == "":
			continue
		var e := _window_edge(wins[i])
		var horizontal := e.z == 0
		var c := Vector2(e.x + 0.5, e.y) if horizontal else Vector2(e.x, e.y + 0.5)
		c -= _origin
		for side in [-1.0, 1.0]:
			if mode == "board":
				for k in 4:
					var sz := [0.94, 0.17, 0.035] if horizontal else [0.035, 0.17, 0.94]
					var pos := [c.x, c.y + 0.12 * side] if horizontal else [c.x + 0.12 * side, c.y]
					_box({"pos": pos, "size": sz, "y": 1.0 + k * 0.22 + 0.03 * ((k * 7 + i) % 3), "color": ["#5a4630", "#6b5438", "#4a3a28"][(k + i) % 3], "yaw": float(((k * 5 + i) % 5) - 2) * 1.2 + (0.0 if horizontal else 90.0)})
			elif side > 0.0:
				for k in 5:
					var bx := (k - 2) * 0.2
					var pos2 := [c.x + bx, c.y + 0.12] if horizontal else [c.x + 0.12, c.y + bx]
					_box({"pos": pos2, "size": [0.05, 1.1, 0.05], "y": 1.4, "color": "#2b2b2e", "rough": 0.4})
				for yy in [0.95, 1.85]:
					var pos3 := [c.x, c.y + 0.12] if horizontal else [c.x + 0.12, c.y]
					_box({"pos": pos3, "size": [0.96, 0.03, 0.03] if horizontal else [0.03, 0.03, 0.96], "y": yy, "color": "#2b2b2e", "rough": 0.4})


## A gutter along a wall edge with its far end broken off and hanging.
func _gutter(it: Dictionary) -> void:
	var a := _vec2(it["from"])
	var b := _vec2(it["to"])
	var y := float(it.get("y", 3.0))
	var d := b - a
	var length := d.length()
	var along_x := absf(d.x) > absf(d.y)
	var m1 := a + d * 0.31
	var half := _box({"pos": [m1.x, m1.y], "size": [length * 0.62, 0.1, 0.12] if along_x else [0.12, 0.1, length * 0.62], "y": y, "color": "#4b4f52", "rough": 0.5})
	var m2 := a + d * 0.85
	var hang := _box({"pos": [m2.x, m2.y], "size": [length * 0.28, 0.1, 0.12] if along_x else [0.12, 0.1, length * 0.28], "y": y - 0.45, "color": "#4b4f52", "rough": 0.5,
		"roll": -28.0 if along_x else 0.0, "pitch": 28.0 if not along_x else 0.0})
	half.name = "gutter"
	hang.name = "gutter_hanging"


func _house(it: Dictionary) -> void:
	var ps = load("res://assets/models/outdoor/%s.glb" % str(it["model"]))
	if ps == null:
		return
	var model: Node3D = (ps as PackedScene).instantiate()
	var fp: Array = it["footprint"]
	var m := str(it["model"])
	var natural := Vector2(10, 7) if m.begins_with("house_small") else (Vector2(14, 11) if m.begins_with("house_medium") else Vector2(22, 14))
	model.scale = Vector3(float(fp[0]) / natural.x, 1.0, float(fp[1]) / natural.y)
	var root := Node3D.new()
	var p := _w(float(it["pos"][0]), float(it["pos"][1]))
	root.position = Vector3(p.x, 0, p.y)
	root.rotation.y = deg_to_rad(float(it.get("yaw", 180.0)))
	root.add_child(model)
	add_child(root)
	Looks.tint_tree(model, str(it.get("id", "decor_house")))


func _bulb(it: Dictionary) -> void:
	var p: Array = it["pos"]
	var y := float(it.get("y", 2.6))
	_omni({"color": it.get("color", "#ffd08a"), "energy": it.get("energy", 2.2), "range": it.get("range", 6.5), "mode": it.get("mode", "on")}, Vector3(float(p[0]), y, float(p[1])))
	var cord := _box({"pos": p, "size": [0.015, 2.9 - y, 0.015], "y": y + (2.9 - y) * 0.5, "color": "#1d1d1d"})
	cord.name = "cord"
	var bm := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	bm.mesh = sm
	bm.material_override = _mat(_col(it.get("color", "#ffd08a")), 0.3, 4.0)
	var w := _w(float(p[0]), float(p[1]))
	bm.position = Vector3(w.x, y, w.y)
	add_child(bm)


func _sign(it: Dictionary) -> void:
	var l := Label3D.new()
	l.text = str(it.get("text", "OPEN"))
	l.font_size = int(it.get("size", 96))
	l.pixel_size = 0.01
	l.modulate = _col(it.get("color", "#5dff8a"))
	l.shaded = false
	l.double_sided = true
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.8)
	var p := _w(float(it["pos"][0]), float(it["pos"][1]))
	l.position = Vector3(p.x, float(it.get("y", 3.0)), p.y)
	l.rotation.y = deg_to_rad(float(it.get("yaw", 0.0)))
	add_child(l)
	_omni({"color": it.get("color", "#5dff8a"), "energy": 1.4, "range": 5.0}, Vector3(float(it["pos"][0]), float(it.get("y", 3.0)) - 0.3, float(it["pos"][1]) + 0.8))
