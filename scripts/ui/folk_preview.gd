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
	_tint(_rig, {"skin": _col("skin", "#d9a47f"), "hair": _col("hair_color", "#3d281c"), "eyes": _col("eye_color", "#5b3a22"),
		"shirt": _col("shirt", "#4f9ec4"), "pants": _col("pants", "#3a4660")})
	var style: int = clampi(int(_ap.get("hair_style", 0)), 0, 5)
	for i in 6:
		var hn := _rig.find_child("hair_%d" % i, true, false)
		if hn is Node3D:
			(hn as Node3D).visible = (i == style)
	var anim := _find_anim(_rig)
	if anim != null:
		FolkView.prepare_player(anim)
		if anim.has_animation("Idle"):
			anim.play("Idle")
	var h: float = 1.85 * vs * height
	_cam.position = Vector3(0, h * 0.52, h * 2.35 + 0.6)
	_cam.look_at_from_position(_cam.position, Vector3(0, h * 0.48, 0), Vector3.UP)

func _col(key: String, fallback: String) -> Color:
	return Color.html(str(_ap.get(key, fallback)))

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null

func _tint(n: Node, tints: Dictionary) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(s)
			if m is BaseMaterial3D and tints.has(str(m.resource_name)):
				var d := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
				d.albedo_color = tints[str(m.resource_name)]
				mi.set_surface_override_material(s, d)
	for c in n.get_children():
		_tint(c, tints)
