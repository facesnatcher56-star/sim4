class_name VehicleSignals
extends RefCounted
## Street furniture of the vehicle layer (display only): at every junction what VehicleControl says it is, and the bus shelters at the marked stops with the next bus.
##   signal      poles on the corners the data picks (2 to 4 of them, so junctions differ), light heads showing green / amber / red (a blinking amber when the zone has no power),
##               a mast arm over the road at the big crossing, pedestrian lamps where there is a zebra crossing (green walk only while the cars are on red)
##   stop        a red octagon on a pole at the right-hand kerb of each approach of the side street
##   giveway     a red-rimmed triangle on a pole at the same place
##   roundabout  a small raised island (grey kerb, green top) in the middle of the box
##   bollards    a few short posts on the corners the data lists
## Everything is built once for the whole map (no pole pops in when the camera pans); the heads are updated every frame from the control.

var view: VehicleView
var _heads: Dictionary = {}          # "i,j" -> [{head: MeshInstance3D, axis}]
var _lamps: Dictionary = {}          # "i,j" -> [MeshInstance3D] pedestrian lamps
var _shelters: Dictionary = {}       # lot id -> {node, label, text}
var _root: Node3D = null
var _mats: Dictionary = {}
var _built: bool = false

const COLORS := {"green": Color(0.25, 0.95, 0.35), "red": Color(1.0, 0.18, 0.12), "amber": Color(1.0, 0.7, 0.1), "pole": Color(0.25, 0.27, 0.3), "white": Color(0.92, 0.92, 0.9),
	"sign_red": Color(0.8, 0.1, 0.1), "kerb": Color(0.62, 0.62, 0.6), "island": Color(0.3, 0.55, 0.28), "bollard": Color(0.95, 0.85, 0.2), "off": Color(0.12, 0.12, 0.13)}
const CORNERS := [[1.0, 1.0, 1], [-1.0, -1.0, 1], [1.0, -1.0, 0], [-1.0, 1.0, 0]]


func _init(v: VehicleView) -> void:
	view = v


func clear() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_heads.clear()
	_lamps.clear()
	_shelters.clear()
	_built = false


func _ensure_root() -> void:
	if _root == null or not is_instance_valid(_root):
		_root = Node3D.new()
		_root.name = "Street"
		view.add_child(_root)
		_heads.clear()
		_lamps.clear()
		_shelters.clear()
		_built = false


func _mat(kind: String) -> StandardMaterial3D:
	if not _mats.has(kind):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if kind in ["green", "red", "amber", "off"] else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		m.albedo_color = COLORS[kind]
		_mats[kind] = m
	return _mats[kind]


func _box(parent: Node3D, size: Vector3, pos: Vector3, kind: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = _mat(kind)
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, kind: String, seg: int = 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = seg
	mi.mesh = cm
	mi.position = pos
	mi.material_override = _mat(kind)
	parent.add_child(mi)
	return mi


func sync() -> void:
	_ensure_root()
	if not _built:
		_built = true
		for id in VehicleRoads.junction_ids():
			_build_junction(id.x, id.y)
	_sync_shelters()


func _build_junction(i: int, j: int) -> void:
	var ctl: VehicleControl = view.sim.control
	var d: Dictionary = ctl.info(i, j)
	var key := "%d,%d" % [i, j]
	var c: Vector2 = VehicleRoads.junction_center(i, j)
	match str(d["type"]):
		"signal":
			_build_signal(key, c, d)
		"stop", "giveway":
			_build_signs(c, d)
		"roundabout":
			_cyl(_root, 0.78, 0.16, Vector3(c.x, 0.08, c.y), "kerb", 20)
			_cyl(_root, 0.58, 0.18, Vector3(c.x, 0.09, c.y), "island", 20)
	if (ctl.t.get("bollards", []) as Array).has(key):
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				for k in 3:
					_cyl(_root, 0.07, 0.55, Vector3(c.x + sx * 2.55, 0.28, c.y + sz * (1.9 + 0.35 * float(k))), "bollard", 8)


func _build_signal(key: String, c: Vector2, d: Dictionary) -> void:
	var list: Array = []
	var lamps: Array = []
	var big: bool = str(d["class"]) == "major"
	for idx in d["poles"]:
		var cr: Array = CORNERS[int(idx)]
		var n := Node3D.new()
		n.position = Vector3(c.x + float(cr[0]) * 2.7, 0.0, c.y + float(cr[1]) * 2.7)
		var h: float = 3.0 if big else 2.4
		_box(n, Vector3(0.12, h, 0.12), Vector3(0, h * 0.5, 0), "pole")
		var head := _box(n, Vector3(0.34, 0.34, 0.34), Vector3(0, h + 0.1, 0), "red")
		list.append({"head": head, "axis": int(cr[2])})
		if big:
			# a mast arm over the road with a second head hanging above the lane
			var toward := Vector3(-float(cr[0]), 0.0, 0.0) if int(cr[2]) == 0 else Vector3(0.0, 0.0, -float(cr[1]))
			_box(n, Vector3(2.6, 0.1, 0.1) if int(cr[2]) == 0 else Vector3(0.1, 0.1, 2.6), toward * 1.3 + Vector3(0, h - 0.1, 0), "pole")
			var head2 := _box(n, Vector3(0.3, 0.3, 0.3), toward * 2.4 + Vector3(0, h - 0.3, 0), "red")
			list.append({"head": head2, "axis": int(cr[2])})
		if not (d["zebra"] as Array).is_empty() and (int(idx) % 2 == 0):
			lamps.append(_box(n, Vector3(0.2, 0.28, 0.1), Vector3(0, 1.3, 0.08), "red"))
		_root.add_child(n)
	_heads[key] = list
	_lamps[key] = lamps


## Signs at the right-hand kerb of each approach of the street that gives way.
func _build_signs(c: Vector2, d: Dictionary) -> void:
	var minor: int = int(d["minor"])
	if minor < 0:
		return
	var is_stop: bool = str(d["type"]) == "stop"
	for dir in 4:
		if VehicleRoads.axis_of(dir) != minor:
			continue
		var dv := Vector2(VehicleRoads.DIRS[dir])
		var half: float = float(VehicleRoads.road_w()) * 0.5
		var p: Vector2 = c - dv * (half + 1.2) + VehicleRoads.right_of(dv) * (half - 0.4)
		var n := Node3D.new()
		n.position = Vector3(p.x, 0.0, p.y)
		_box(n, Vector3(0.07, 2.0, 0.07), Vector3(0, 1.0, 0), "pole")
		var face := Node3D.new()
		face.position = Vector3(0, 2.05, 0)
		face.rotation.y = atan2(-dv.x, -dv.y)
		n.add_child(face)
		if is_stop:
			var oct := _cyl(face, 0.34, 0.05, Vector3.ZERO, "sign_red", 8)
			oct.rotation_degrees = Vector3(90, 0, 0)
			_box(face, Vector3(0.36, 0.07, 0.06), Vector3(0, 0, -0.04), "white")
		else:
			var tri := _cyl(face, 0.4, 0.05, Vector3.ZERO, "sign_red", 3)
			tri.rotation_degrees = Vector3(90, 180, 0)
			var tin := _cyl(face, 0.24, 0.06, Vector3(0, 0, -0.01), "white", 3)
			tin.rotation_degrees = Vector3(90, 180, 0)
		_root.add_child(n)


func update() -> void:
	var cam: Camera3D = _root.get_viewport().get_camera_3d() if _root != null and _root.is_inside_tree() else null
	var far: bool = cam != null and cam.projection == Camera3D.PROJECTION_ORTHOGONAL and cam.size > 34.0
	for rec in _shelters.values():
		(rec["label"] as Label3D).visible = not far          # too far out to read: hidden, the shelter itself still shows
	if not _built:
		return
	var ctl: VehicleControl = view.sim.control
	var vt: float = view.sim.vt
	var hour: float = view.sim.hour
	var blink: bool = fposmod(vt, 1.0) < 0.5
	for key in _heads:
		var p: PackedStringArray = (key as String).split(",")
		var i: int = int(p[0])
		var j: int = int(p[1])
		var dark: bool = view.sim.dark_fn.is_valid() and bool(view.sim.dark_fn.call(i, j))
		for h in _heads[key]:
			var kind: String = "red"
			if dark:
				kind = "amber" if blink else "off"
			else:
				match ctl.head(i, j, int(h["axis"]), vt, hour):
					"green":
						kind = "green"
					"amber":
						kind = "amber"
					"flash":
						kind = "amber" if blink else "off"
					"stop":
						kind = "red" if blink else "off"
			(h["head"] as MeshInstance3D).material_override = _mat(kind)
		var walk: bool = ctl.ped_phase(i, j, vt, hour) and not dark
		for lamp in _lamps.get(key, []):
			(lamp as MeshInstance3D).material_override = _mat("green" if walk else "red")


func _sync_shelters() -> void:
	var stop_lots: Dictionary = {}
	for r in TransportBus.routes():
		for l in r["stops"]:
			stop_lots[str(l)] = true
	var model: PackedScene = load("res://assets/models/outdoor/bus_stop.glb") if ResourceLoader.exists("res://assets/models/outdoor/bus_stop.glb") else null
	for lot_id in stop_lots:
		var f: Dictionary = VehicleRoads.frontage(str(lot_id))
		if f.is_empty():
			continue
		var pos := Vector2(float(f["gate"]) + float((view.cfg.get("bus_stop", {}) as Dictionary).get("x_from_gate", 6.0)), float(f["hy"]) - 1.3)
		if not _shelters.has(lot_id) and model != null:
			var n: Node3D = model.instantiate()
			n.position = Vector3(pos.x, 0.0, pos.y)
			n.rotation.y = PI
			_root.add_child(n)
			var lb := Label3D.new()
			lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lb.fixed_size = true          # playtest: it filled the street zoomed in and was a speck zoomed out; now the same size on screen at any zoom
			lb.pixel_size = 0.0016
			lb.font_size = 28
			lb.outline_size = 28          # a dark plate behind the text (docs/UI_STYLE.md: world labels get a backing)
			lb.outline_modulate = Color(0.1, 0.13, 0.18, 0.92)
			lb.modulate = Color(1.0, 0.92, 0.55)
			lb.position = Vector3(0, 3.0, 0)
			n.add_child(lb)
			_shelters[lot_id] = {"node": n, "label": lb, "text": ""}
		if _shelters.has(lot_id):
			var txt: String = TransportBus.next_text(str(lot_id))
			var rec: Dictionary = _shelters[lot_id]
			if txt != str(rec["text"]):
				rec["text"] = txt
				(rec["label"] as Label3D).text = "%s\n%s" % [Neighborhood.label_of(str(lot_id)), txt]
