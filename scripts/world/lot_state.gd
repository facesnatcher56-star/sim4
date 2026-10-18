extends Node3D
## Shared state for the LotView layer chain: lot_state > camera > models > walls > picking > build > lot_view.
## Display only: all state lives in the World autoload. Everything is generated from World data and
## kept in sync via World/Events signals. Missing models fall back to coloured boxes.
##
## Controls: WASD / middle-drag pan, wheel zoom, Q/E rotate (4 steps), Z cycle wall mode,
##           R rotate build ghost, Esc / right-click cancel tool, Ctrl+Z undo build.

signal tile_hovered(tile: Vector2i)
signal tile_clicked(tile: Vector2i, button: int)
signal context_requested(kind: String, id: int, tile: Vector2i)   # right-click on something
signal tool_changed(tool: String, arg: String)
signal camera_rotated(step: int)
signal hover_changed(kind: String, id: int)

enum WallMode { UP, CUTAWAY, DOWN }

const WALL_H := 2.6
const WALL_T := 0.16
const CUT_RATIO := 0.16
const CAM_DIST := 60.0
const PITCH := deg_to_rad(35.0)
const ZOOM_MIN := 4.0
const ZOOM_MAX := 34.0           # single lot
const ZOOM_MAX_BIG := 110.0      # big map: the whole 160x120 neighbourhood fits on screen at 16:9
const FOLLOW_RATE := 5.0         # camera glide towards the followed folk (1/s)


var wall_mode: int = WallMode.CUTAWAY
var show_labels: bool = false
var show_names: bool = false:
	set(v):
		show_names = v
		for fv in _folk_views.values():
			fv.show_name = v

var tool: String = "select"          # select | place | wall | floor | sell
var tool_arg: String = ""
var build_rot: int = 0
var selected_kind: String = "none"
var selected_id: int = -1
var hover_kind: String = "none"
var hover_id: int = -1
var hover_tile: Vector2i = Vector2i(-1, -1)

var _pivot: Node3D
var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _floor_root: Node3D
var _wall_root: Node3D
var _obj_root: Node3D
var _folk_root: Node3D
var _fx_root: Node3D
var _floor_mi: MeshInstance3D
var _ground_mi: MeshInstance3D

var _yaw_step: int = 0
var _yaw: float = PI * 0.25
var _yaw_target: float = PI * 0.25
var _zoom: float = 14.0
var _zoom_target: float = 14.0
var _target: Vector3 = Vector3(16, 0, 12)
var _dragging_mmb: bool = false
var _follow_id: int = -1             # folk the camera glides after (big map only; any manual pan lets go)

var _obj_nodes: Dictionary = {}      # object id -> Node3D
var _folk_views: Dictionary = {}     # folk id -> FolkView
var _walls: Array = []               # {node, e, kind, pos, axis, h}
var _doors: Array = []               # {leaf, pos, open}
var _hl_box: MeshInstance3D
var _hl_ring: MeshInstance3D
var _sel_box: MeshInstance3D
var _sel_ring: MeshInstance3D
var _sel_arrow: MeshInstance3D
var _grid_mi: MeshInstance3D
var _hover_label: Label3D
var _xray_t: float = 0.0
var _tile_hl: MeshInstance3D
var _ghost: Node3D = null
var _ghost_ok: bool = false
var _ghost_tinted: bool = false
var _ghost_origin: Vector2i = Vector2i.ZERO
var _ghost_rot: int = 0
var _drag_start: Vector3 = Vector3.ZERO
var _dragging_tool: bool = false
var _preview_root: Node3D
var _walls_dirty: bool = false
var _floors_dirty: bool = false
var _cut_dirty: bool = true
var _last_cam_sig: String = ""
var _model_cache: Dictionary = {}
var level_view = null                # LevelView: multi-floor buildings (null until ensure_on)
var _plane_y: float = 0.0            # height of the plane mouse picking hits: the viewed floor
var _ground_hidden: Rect2i = Rect2i() # basement view: the ground inside this rectangle is not drawn


## Level the build tools work on: the viewed floor of the active building, else the ground.
func build_level() -> int:
	return int(level_view.viewed) if level_view != null and level_view.building >= 0 else 0


func _glow_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = false
	return m


func _mat(c: Color, rough: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
