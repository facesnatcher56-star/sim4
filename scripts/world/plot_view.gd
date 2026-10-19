class_name PlotView
extends Node3D
## The reserved plots of the east side of the map (data/map_layout.json `plots`) as the planners' projects (CityPlan, task 12.6) change them. View only, from CityPlan.plot_state:
##   free      nothing (the lawn of the plot)
##   scaffold  a scaffold frame (poles, boards) round the footprint of the coming building and a site sign
##   building  the scaffold, a rising concrete building (grows with the days that have passed) and a few workers' hard hats
##   built     the finished building: shells of the outdoor kit (flats = three townhouses, shops = two shop shells, community centre = a library shell)
## Added to the LotView by PlotView.ensure_on(lot_view); `sync_now()` rebuilds what changed (once a second, and at once on a new game / load).

const MODELS := {"residential": ["townhouse_a", "townhouse_b", "townhouse_c"], "commercial": ["market_a", "cafe_b"], "civic": ["library_b"]}
const SIZES := {"townhouse_a": Vector2(7, 10), "townhouse_b": Vector2(7, 10), "townhouse_c": Vector2(7, 10), "market_a": Vector2(22, 14), "cafe_b": Vector2(22, 14), "library_b": Vector2(22, 14)}
const SYNC_EVERY := 1.0

var lot: Node3D = null
var _shown: Dictionary = {}          # plot id -> signature of what is drawn
var _nodes: Dictionary = {}          # plot id -> Node3D
var _t: float = 0.0
var _mats: Dictionary = {}


static func ensure_on(lv: Node3D) -> PlotView:
	var existing = lv.get_node_or_null("PlotView")
	if existing != null:
		return existing
	var pv := PlotView.new()
	pv.name = "PlotView"
	pv.lot = lv
	lv.add_child(pv)
	return pv


func _ready() -> void:
	var w = WorldIface.world()
	if w != null and w.has_signal("world_reset"):
		w.world_reset.connect(func(): _shown.clear())


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = SYNC_EVERY
		sync_now()


func node_count(plot_id: String) -> int:
	return _nodes[plot_id].get_child_count() if _nodes.has(plot_id) else 0


func state_drawn(plot_id: String) -> String:
	return str(_shown.get(plot_id, "")).split("|")[0]


## Rebuild every plot whose state (or progress) changed.
func sync_now() -> void:
	for plot_id in CityPlan.plot_ids():
		var st: String = CityPlan.plot_state(str(plot_id))
		var sig: String = st
		var p: Dictionary = CityPlan.plot_project(str(plot_id))
		if st == "building":
			sig += "|%d" % int(floor(_progress(p) * 6.0))
		elif st == "built":
			sig += "|" + str(CityPlan.built_plots.get(str(plot_id), ""))
		elif st == "scaffold":
			sig += "|" + str(p.get("kind", ""))
		if str(_shown.get(plot_id, "")) == sig:
			continue
		_shown[plot_id] = sig
		if _nodes.has(plot_id):
			(_nodes[plot_id] as Node).queue_free()
			_nodes.erase(plot_id)
		if st == "free":
			continue
		var rc: Rect2i = MapBuilder.plot_rect(str(plot_id))
		var root := Node3D.new()
		root.name = str(plot_id)
		root.position = Vector3(float(rc.position.x) + float(rc.size.x) * 0.5, 0.0, float(rc.position.y) + float(rc.size.y) * 0.5)
		add_child(root)
		_nodes[plot_id] = root
		var kind: String = str(p.get("kind", CityPlan.built_plots.get(str(plot_id), "residential")))
		match st:
			"scaffold":
				_scaffold(root, kind, 3.0)
				_sign(root, rc)
			"building":
				var pr: float = _progress(p)
				_scaffold(root, kind, 3.0 + 6.0 * pr)
				_block(root, kind, 1.0 + 6.5 * pr)
				_sign(root, rc)
			"built":
				_finished(root, kind)


func _progress(p: Dictionary) -> float:
	if p.is_empty():
		return 0.0
	var a: float = float(p.get("scaffold_end", 0))
	var b: float = float(p.get("ready", 1))
	return clampf((float(SysUtil.day()) - a) / maxf(b - a, 1.0), 0.0, 1.0)


func _mat(name: String, col: Color) -> StandardMaterial3D:
	if not _mats.has(name):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.9
		_mats[name] = m
	return _mats[name]


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


## The footprint of the project in tiles (width, depth) by kind: flats are a row of three townhouses, shops two shells, a community centre one.
func _footprint(kind: String) -> Vector2:
	match kind:
		"residential":
			return Vector2(22, 10)
		"commercial":
			return Vector2(22, 14)
	return Vector2(18, 12)


func _scaffold(root: Node3D, kind: String, height: float) -> void:
	var fp: Vector2 = _footprint(kind) + Vector2(2, 2)
	var pole: StandardMaterial3D = _mat("pole", Color(0.55, 0.57, 0.6))
	var board: StandardMaterial3D = _mat("board", Color(0.72, 0.55, 0.33))
	var nx: int = int(fp.x / 4.0)
	var nz: int = int(fp.y / 4.0)
	for i in range(nx + 1):
		for k in [0, nz]:
			_box(root, Vector3(0.14, height, 0.14), Vector3(-fp.x * 0.5 + fp.x * float(i) / float(nx), height * 0.5, -fp.y * 0.5 + fp.y * float(k) / float(nz)), pole)
	for j in range(1, nz):
		for e in [0, nx]:
			_box(root, Vector3(0.14, height, 0.14), Vector3(-fp.x * 0.5 + fp.x * float(e) / float(nx), height * 0.5, -fp.y * 0.5 + fp.y * float(j) / float(nz)), pole)
	var y: float = 2.0
	while y < height:
		_box(root, Vector3(fp.x, 0.1, 0.5), Vector3(0, y, -fp.y * 0.5), board)
		_box(root, Vector3(fp.x, 0.1, 0.5), Vector3(0, y, fp.y * 0.5), board)
		_box(root, Vector3(0.5, 0.1, fp.y), Vector3(-fp.x * 0.5, y, 0), board)
		_box(root, Vector3(0.5, 0.1, fp.y), Vector3(fp.x * 0.5, y, 0), board)
		y += 2.4


func _block(root: Node3D, kind: String, height: float) -> void:
	var fp: Vector2 = _footprint(kind)
	_box(root, Vector3(fp.x, height, fp.y), Vector3(0, height * 0.5, 0), _mat("concrete", Color(0.72, 0.71, 0.68)))
	_box(root, Vector3(fp.x + 0.4, 0.2, fp.y + 0.4), Vector3(0, height + 0.1, 0), _mat("slab", Color(0.55, 0.55, 0.57)))


func _sign(root: Node3D, rc: Rect2i) -> void:
	var z: float = float(rc.size.y) * 0.5 - 1.5
	_box(root, Vector3(0.15, 2.0, 0.15), Vector3(-3.0, 1.0, z), _mat("pole", Color(0.55, 0.57, 0.6)))
	_box(root, Vector3(0.15, 2.0, 0.15), Vector3(3.0, 1.0, z), _mat("pole", Color(0.55, 0.57, 0.6)))
	_box(root, Vector3(6.4, 1.1, 0.12), Vector3(0, 2.2, z), _mat("sign", Color(0.95, 0.78, 0.15)))
	for i in 3:
		_box(root, Vector3(0.4, 0.3, 0.4), Vector3(-5.0 + float(i) * 1.1, 0.9, z + 1.6), _mat("hat", Color(0.95, 0.6, 0.1)))      # workers' hard hats on the site


func _finished(root: Node3D, kind: String) -> void:
	var names: Array = MODELS.get(kind, ["townhouse_a"])
	var total: float = 0.0
	for nm in names:
		total += (SIZES[nm] as Vector2).x + 1.0
	var x: float = -total * 0.5
	for nm2 in names:
		var path: String = "res://assets/models/outdoor/%s.glb" % str(nm2)
		var sz: Vector2 = SIZES[nm2]
		if ResourceLoader.exists(path):
			var inst: Node3D = (load(path) as PackedScene).instantiate()
			inst.position = Vector3(x + sz.x * 0.5, 0.0, 0.0)
			inst.rotation.y = PI                                    # the door side of the kit's shells is -Z; the street is south here
			root.add_child(inst)
		else:
			_box(root, Vector3(sz.x, 5.0, sz.y), Vector3(x + sz.x * 0.5, 2.5, 0.0), _mat("fallback", Color(0.8, 0.75, 0.7)))
		x += sz.x + 1.0
