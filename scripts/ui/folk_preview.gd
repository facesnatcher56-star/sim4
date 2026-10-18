class_name FolkPreview
extends SubViewportContainer
## Small live 3D preview of a Folk for the household creator: the real folk model of the age group, tinted with the
## Genetics appearance dictionary (skin, hair style + colour, eyes, shirt, pants, height, build). Slowly turns.

const SIZE := Vector2i(230, 320)

var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _rig: Node = null
var _stage := "adult"
var _ap: Dictionary = {}

func _init() -> void:
	custom_minimum_size = Vector2(SIZE)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

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
		_pivot.rotation.y = fmod(_pivot.rotation.y + delta * 0.5, TAU)

## Show a Folk of this age group with this appearance (Genetics appearance contract).
func show_folk(stage: String, appearance: Dictionary) -> void:
	_stage = stage
	_ap = appearance
	if _pivot != null:
		_rebuild()

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
