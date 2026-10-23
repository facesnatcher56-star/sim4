class_name OrderMarker
extends Node3D
## Task 58b (view only): where the player's own character is going. A small ring on the spot they will stand (the clicked tile, or the use spot of
## an object, or beside a person) and a thin line along the walk's own route from the drawn character to it. Same size on screen at any zoom;
## shown from the click (paused too), shortens as they walk, fades when they arrive or the order is replaced or cancelled. Never for NPCs.

const COLOR := Color("#f2c46a")          # the warm accent of the pie menu, quiet on the grounded palette
const RING_PX := 0.022                   # ring radius as a share of the view height (the camera's ortho size)
const LINE_PX := 0.0035                  # line width, same
const LIFT := 0.04                       # above the floor so it never z-fights
const FADE_S := 0.35

var lot: Node3D = null
var _ring: MeshInstance3D
var _line: MeshInstance3D
var _mesh := ImmediateMesh.new()
var _mat: StandardMaterial3D
var _alpha := 0.0
var _dest := Vector3.ZERO


static func ensure_on(lv: Node3D) -> OrderMarker:
	var om := OrderMarker.new()
	om.name = "OrderMarker"
	om.lot = lv
	lv.add_child(om)
	return om


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = COLOR
	var torus := TorusMesh.new()
	torus.inner_radius = 0.78
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = _mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_line = MeshInstance3D.new()
	_line.mesh = _mesh
	_line.material_override = _mat
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)
	visible = false


func _process(delta: float) -> void:
	var f = World.get_folk(Pawn.of())
	var pts: Array = _route_left(f)
	if not pts.is_empty():
		_dest = pts[pts.size() - 1]
		_alpha = 1.0
	else:
		_alpha = maxf(_alpha - delta / FADE_S, 0.0)
	visible = _alpha > 0.0
	if not visible:
		return
	_mat.albedo_color = Color(COLOR, 0.85 * _alpha)
	var cam: Camera3D = get_viewport().get_camera_3d()
	var view_h: float = cam.size if cam != null and cam.projection == Camera3D.PROJECTION_ORTHOGONAL else 20.0
	var r: float = view_h * RING_PX
	_ring.position = _dest + Vector3(0, LIFT, 0)
	_ring.scale = Vector3(r, r * 0.15, r)
	_draw_line(pts, view_h * LINE_PX)


## The route still to walk, as points: the drawn character, the tiles the view was handed and not yet passed, then the rest of the route.
## [] when the pawn is not walking to something (no order, arrived, cancelled, a ride, away).
func _route_left(f) -> Array:
	if f == null or f.current == null or str(f.current.state) != "walking" or f.has_meta("away"):
		return []
	var ir = f.current
	var path: Array = ir.path
	if path.is_empty() or not ir.path3.is_empty() or ir.params.has("ride_minutes"):
		return []
	var fv = lot.call("get_folk_view", int(f.id)) if lot != null else null
	if fv == null or not fv.visible:
		return []
	var out: Array = [fv.position]
	var fed: int
	if int(fv.get("_lead_id")) == ir.get_instance_id():
		for w in fv.get("_waypoints"):
			out.append(w)
		fed = int(fv.get("_lead_fed"))
	else:
		fed = maxi(path.find(f.tile) + 1, 0)
	for i in range(fed, path.size()):
		out.append(fv.call("_wp", path[i], int(f.level)))
	return out


## A flat ribbon along the points (two triangles per segment), lifted off the floor.
func _draw_line(pts: Array, w: float) -> void:
	_mesh.clear_surfaces()
	if pts.size() < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i] + Vector3(0, LIFT, 0)
		var b: Vector3 = pts[i + 1] + Vector3(0, LIFT, 0)
		var d := Vector3(b.x - a.x, 0, b.z - a.z)
		if d.length() < 0.001:
			continue
		var side := Vector3(-d.z, 0, d.x).normalized() * (w * 0.5)
		for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
			_mesh.surface_add_vertex(v)
	_mesh.surface_end()
