class_name VehicleNodes
extends RefCounted
## The 3D bodies of the vehicle layer: loads the glb of a vehicle (assets/models/outdoor), keeps one node per live vehicle, places it from the sim
## (position, heading), spins the wheels, flashes hazard lamps and the roof bars of emergency vehicles. Display only.
##   nodes.sync(parent, vehicles, vt)      nodes.count()      nodes.node_of(id)

const DIR := "res://assets/models/outdoor/"

var _scenes: Dictionary = {}
var _nodes: Dictionary = {}               # vehicle id -> {root, wheels, haz, red, blue, amber, r}
var _tint_mats: Dictionary = {}
var rigs: VehicleLightRigs = VehicleLightRigs.new()      # real lights for the nearest few (task 42)
var cam_ground: Vector2 = Vector2.ZERO                   # where the camera looks, on the ground: the vehicles nearest to it get the real lights
var _rig_t: float = 0.0


func _scene(glb: String) -> PackedScene:
	if not _scenes.has(glb):
		var p: String = DIR + glb + ".glb"
		_scenes[glb] = load(p) if ResourceLoader.exists(p) else null
	return _scenes[glb]


func count() -> int:
	return _nodes.size()


func node_of(id: int) -> Node3D:
	return _nodes[id]["root"] if _nodes.has(id) else null


func clear() -> void:
	for id in _nodes:
		if is_instance_valid(_nodes[id]["root"]):
			(_nodes[id]["root"] as Node).queue_free()
	_nodes.clear()
	rigs.clear()


func _make(v: Dictionary) -> Dictionary:
	var ps: PackedScene = _scene(str(v["glb"]))
	var root := Node3D.new()
	root.name = "V%d" % int(v["id"])
	var rec: Dictionary = {"root": root, "wheels": [], "haz": [], "red": null, "blue": null, "amber": null, "r": 0.35, "lamps": null, "half_len": float(v["len"]) * 0.5, "pv": 0.0}
	if ps != null:
		var inst: Node = ps.instantiate()
		root.add_child(inst)
		_collect(inst, rec)
		if str(v["kind"]) == "bike" and str(v.get("color", "")) != "":
			_tint(inst, Color(str(v["color"])))
	rec["lamps"] = VehicleLights.attach(root, v)
	return rec


func _collect(n: Node, rec: Dictionary) -> void:
	var nm: String = str(n.name)
	if nm.begins_with("wheel_"):
		(rec["wheels"] as Array).append(n)
	elif nm.begins_with("haz_"):
		(rec["haz"] as Array).append(n)
		(n as Node3D).visible = false
	elif nm == "bar_red":
		rec["red"] = n
		(n as Node3D).visible = false
	elif nm == "bar_blue":
		rec["blue"] = n
		(n as Node3D).visible = false
	elif nm == "bar_amber":
		rec["amber"] = n
		(n as Node3D).visible = false
	for c in n.get_children():
		_collect(c, rec)


## Rider shirt on a bike: the 'body' surface takes the folk's colour.
func _tint(n: Node, col: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m: Material = mi.get_active_material(i)
			if m is StandardMaterial3D and str(m.resource_name) == "body":
				var d: StandardMaterial3D = (m as StandardMaterial3D).duplicate()
				d.albedo_color = col
				mi.set_surface_override_material(i, d)
	for c in n.get_children():
		_tint(c, col)


func sync(parent: Node3D, vehicles: Array, vt: float, flash: float) -> void:
	var seen: Dictionary = {}
	var lctx: Dictionary = VehicleLights.context()
	var blink: bool = fposmod(vt, VehicleLights.BLINK_S) < VehicleLights.BLINK_S * 0.5
	for v in vehicles:
		var id: int = int(v["id"])
		seen[id] = true
		if not _nodes.has(id):
			_nodes[id] = _make(v)
			parent.add_child((_nodes[id]["root"] as Node3D))
		var rec: Dictionary = _nodes[id]
		var root: Node3D = rec["root"]
		var p: Vector2 = v["pos"]
		var h: Vector2 = v["dir"]
		root.position = Vector3(p.x, 0.02, p.y)
		root.rotation.y = atan2(-h.x, -h.y)
		var spin: float = -float(v["s"]) / 0.4
		for w in rec["wheels"]:
			(w as Node3D).rotation.x = spin
		var lights: Dictionary = v["lights"]
		var on: bool = fposmod(vt, flash * 2.0) < flash
		for hz in rec["haz"]:
			(hz as Node3D).visible = bool(lights.get("hazard", false)) and on
		var siren: bool = bool(lights.get("siren", false))
		if rec["red"] != null:
			(rec["red"] as Node3D).visible = siren and on
		if rec["blue"] != null:
			(rec["blue"] as Node3D).visible = siren and not on
		if rec["amber"] != null:
			(rec["amber"] as Node3D).visible = bool(lights.get("amber", false)) and on
		root.visible = not bool(v.get("hidden", false))
		var lst: Dictionary = VehicleLights.state(v, lctx, float(rec["pv"]))
		rec["pv"] = float(v["v"])
		rec["head"] = bool(lst["head"])
		rec["siren"] = bool(lst["siren"])
		VehicleLights.apply(rec, lst, lctx, blink, on)
	for id2 in _nodes.keys():
		if not seen.has(id2):
			if is_instance_valid(_nodes[id2]["root"]):
				(_nodes[id2]["root"] as Node).queue_free()
			_nodes.erase(id2)
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - int(_rig_t) >= 400:
		_rig_t = float(now_ms)
		rigs.assign(_nodes, cam_ground, lctx)
	rigs.tick(fposmod(vt, flash * 2.0) < flash)
