class_name FolkPreview
extends SubViewportContainer
## Small live 3D preview of a Folk for the household creator: the real folk model of the age group, tinted with the
## Genetics appearance dictionary (skin, hair style + colour, eyes, shirt, pants, height, build). It FACES THE CAMERA, sways a little left and right (a slow turn that
## never shows the back) and can be dragged round with the mouse; the body shows the sex's shoulder / hip width and height (body_type, frame, height, build).

const SIZE := Vector2i(230, 320)

var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _rig: Node = null
var _stage := "adult"
var _ap: Dictionary = {}

const FACING := PI                    # the model's front is -Z and the camera stands on +Z: turn it round
const SWAY := 0.5
const HOLD_AFTER_DRAG := 2.5

var yaw_offset: float = 0.0           # set by dragging
var _t: float = 0.0
var _hold_until: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(SIZE)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_HSIZE
	tooltip_text = "Drag to turn"


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		yaw_offset = fmod(yaw_offset + (ev as InputEventMouseMotion).relative.x * 0.015, TAU)
		_hold_until = _t + HOLD_AFTER_DRAG
		_apply_yaw()


func _apply_yaw() -> void:
	if _pivot != null:
		var sway: float = sin(_t * 0.6) * SWAY if _t >= _hold_until and absf(wrapf(yaw_offset, -PI, PI)) < 0.01 else 0.0
		_pivot.rotation.y = FACING + yaw_offset + sway


## The yaw the model is turned to now (radians; PI = looking straight at the camera).
func yaw() -> float:
	return _pivot.rotation.y if _pivot != null else FACING

func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.95)
	env.ambient_light_energy = 0.65
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_energy = 1.1
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 28
	_vp.add_child(_cam)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_rebuild()

func _process(delta: float) -> void:
	if _pivot != null and is_visible_in_tree():
		_t += delta
		if _t >= _hold_until and absf(wrapf(yaw_offset, -PI, PI)) >= 0.01:
			yaw_offset = lerp_angle(yaw_offset, 0.0, clampf(delta * 1.2, 0.0, 1.0))      # after a drag it slowly comes back to face you
		_apply_yaw()

## Show a Folk of this age group with this appearance (Genetics appearance contract).
func show_folk(stage: String, appearance: Dictionary) -> void:
	_stage = stage
	_ap = appearance
	yaw_offset = 0.0
	if _pivot != null:
		_rebuild()
		_apply_yaw()

func _rebuild() -> void:
	if _rig != null:
		_rig.queue_free()
		_rig = null
	var path: String = FolkView.variant_path(_stage)
	if path == "":
		return
	var ps = load(path)
	if not (ps is PackedScene):
		return
	_rig = ps.instantiate()
	_pivot.add_child(_rig)
	var vs: float = float(FolkView.anim_map().get("variant_scale", {}).get(_stage, 1.0))
	var height: float = clampf(float(_ap.get("height", 1.0)), 0.8, 1.2)
	var build: float = clampf(float(_ap.get("build", 1.0)), 0.8, 1.2)
	_rig.scale = Vector3(build * height, height, build * height) * vs
	FolkRigStyle.apply(_rig, _ap, _stage)
	var anim := _find_anim(_rig)
	if anim != null:
		FolkView.prepare_player(anim)
		if anim.has_animation("Idle"):
			anim.play("Idle")
	var h: float = 1.85 * vs * height
	_cam.position = Vector3(0, h * 0.52, h * 2.35 + 0.6)
	_cam.look_at_from_position(_cam.position, Vector3(0, h * 0.48, 0), Vector3.UP)

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null
