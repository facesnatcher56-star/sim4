class_name FireView
extends Node3D
## Flames, smoke, scorch marks and a smoky haze for a LotView. Display only: every quarter second it reads Fire.* and keeps one small
## particle emitter (flames + a smoke plume + a flickering light) per burning tile, a dark soot decal per scorched tile and a grey haze slab
## over every lot with smoke. Cheap on purpose: at most MAX_EMITTERS burning tiles are drawn, particles are CPU quads, lights are capped.
## Burnt remains are real objects (ash_pile), not drawn here. Added to the LotView by FireView.ensure_on(lot_view), same pattern as WeatherView.

const MAX_EMITTERS := 24
const MAX_LIGHTS := 8
const SYNC_EVERY := 0.25

var lot: Node3D = null
var _emitters: Dictionary = {}       # fire id -> Node3D
var _scorch: Dictionary = {}         # "x,y" -> MeshInstance3D
var _haze: Dictionary = {}           # lot id -> MeshInstance3D
var _t: float = 0.0
var _flame_mat: StandardMaterial3D = null
var _smoke_mat: StandardMaterial3D = null
var _soot_mat: StandardMaterial3D = null
var _haze_mat: StandardMaterial3D = null

static func ensure_on(lv: Node3D) -> FireView:
	var existing = lv.get_node_or_null("FireView")
	if existing != null:
		return existing
	var fv := FireView.new()
	fv.name = "FireView"
	lv.add_child(fv)
	fv.lot = lv
	return fv

func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = SYNC_EVERY
	sync_now()
	_flicker()

func emitter_count() -> int:
	return _emitters.size()

func scorch_count() -> int:
	return _scorch.size()

func haze_count() -> int:
	return _haze.size()

## One pass: create / update / free the visuals so they match Fire.fires, Fire.scorch and Fire.blazes.
func sync_now() -> void:
	var seen: Dictionary = {}
	var drawn: int = 0
	var fires: Array = Fire.active()
	for f in fires:
		if drawn >= MAX_EMITTERS:
			break
		drawn += 1
		var id: int = int(f["id"])
		seen[id] = true
		var node: Node3D = _emitters.get(id, null)
		if node == null:
			node = _make_emitter(f, drawn <= MAX_LIGHTS)
			_emitters[id] = node
			add_child(node)
		_set_stage(node, int(f["stage"]))
	for id2 in _emitters.keys():
		if not seen.has(id2):
			(_emitters[id2] as Node).queue_free()
			_emitters.erase(id2)
	_sync_scorch()
	_sync_haze()

# ------------------------------------------------------------------ materials
func _mats() -> void:
	if _flame_mat != null:
		return
	_flame_mat = _particle_mat(BaseMaterial3D.BLEND_MODE_ADD)
	_smoke_mat = _particle_mat(BaseMaterial3D.BLEND_MODE_MIX)
	_soot_mat = StandardMaterial3D.new()
	_soot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_soot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_soot_mat.albedo_texture = _soot_texture()
	_soot_mat.render_priority = -3
	_haze_mat = StandardMaterial3D.new()
	_haze_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_haze_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_haze_mat.albedo_color = Color(0.32, 0.30, 0.30, 0.0)
	_haze_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_haze_mat.no_depth_test = false

func _particle_mat(blend: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = blend
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = _soft_texture()
	return m

static func _soft_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 32
	t.height = 32
	return t

static func _soot_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.02, 0.02, 0.7))
	g.add_point(0.55, Color(0.02, 0.02, 0.02, 0.5))
	g.set_color(g.get_point_count() - 1, Color(0.02, 0.02, 0.02, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.05)
	t.width = 48
	t.height = 48
	return t

# ------------------------------------------------------------------ one burning tile
func _make_emitter(f: Dictionary, with_light: bool) -> Node3D:
	_mats()
	var root := Node3D.new()
	var o = WorldIface.get_object(int(f["obj"])) if int(f["obj"]) >= 0 else null
	var c := Vector2(f["tile"]) + Vector2(0.5, 0.5)
	var h: float = 0.5
	var ext := Vector3(0.28, 0.02, 0.28)
	if o != null:
		if o.has_method("center2d"):
			c = o.center2d()
		var fp: Array = FireRules.footprint(o)
		ext = Vector3(0.28 * maxf(float(fp.size()), 1.0) * 0.6 + 0.1, 0.02, 0.28)
		h = float(FireRules.obj_def(o).get("height", 0.8))
	root.position = Vector3(c.x, 0.05, c.y)
	root.set_meta("height", h)
	var flame := CPUParticles3D.new()
	flame.name = "Flame"
	flame.mesh = _quad(0.42, _flame_mat)
	flame.amount = 14
	flame.lifetime = 0.75
	flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flame.emission_box_extents = ext
	flame.direction = Vector3(0, 1, 0)
	flame.spread = 14.0
	flame.initial_velocity_min = 0.45
	flame.initial_velocity_max = 1.0
	flame.gravity = Vector3(0, 0.5, 0)
	flame.scale_amount_min = 0.7
	flame.scale_amount_max = 1.2
	flame.scale_amount_curve = _shrink_curve()
	flame.color_ramp = _ramp([Color(1.0, 0.95, 0.5, 0.95), Color(1.0, 0.5, 0.1, 0.8), Color(0.8, 0.12, 0.05, 0.0)])
	flame.position = Vector3(0, clampf(h * 0.85, 0.35, 1.3), 0)
	root.add_child(flame)
	var smoke := CPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.mesh = _quad(0.7, _smoke_mat)
	smoke.amount = 8
	smoke.lifetime = 2.6
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	smoke.emission_box_extents = Vector3(ext.x, 0.02, ext.z)
	smoke.direction = Vector3(0, 1, 0)
	smoke.spread = 22.0
	smoke.initial_velocity_min = 0.35
	smoke.initial_velocity_max = 0.7
	smoke.gravity = Vector3(0.05, 0.25, 0)
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 1.6
	smoke.color_ramp = _ramp([Color(0.25, 0.24, 0.24, 0.0), Color(0.3, 0.29, 0.29, 0.5), Color(0.5, 0.5, 0.5, 0.0)])
	smoke.position = Vector3(0, clampf(h + 0.2, 0.7, 1.8), 0)
	root.add_child(smoke)
	if with_light:
		var l := OmniLight3D.new()
		l.name = "Glow"
		l.light_color = Color(1.0, 0.55, 0.2)
		l.omni_range = 2.6
		l.light_energy = 1.2
		l.shadow_enabled = false
		l.position = Vector3(0, clampf(h + 0.3, 0.9, 1.8), 0)
		root.add_child(l)
	root.set_meta("stage", 0)
	return root

func _quad(size: float, mat: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	return q

func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, colors[0])
	g.set_color(1, colors[colors.size() - 1])
	if colors.size() == 3:
		g.add_point(0.45, colors[1])
	return g

func _shrink_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 0.6))
	c.add_point(Vector2(0.35, 1.0))
	c.add_point(Vector2(1, 0.1))
	return c

func _set_stage(node: Node3D, stage: int) -> void:
	if int(node.get_meta("stage", 0)) == stage:
		return
	node.set_meta("stage", stage)
	var flame: CPUParticles3D = node.get_node_or_null("Flame")
	var smoke: CPUParticles3D = node.get_node_or_null("Smoke")
	if flame != null:
		flame.amount = [10, 18, 28][clampi(stage - 1, 0, 2)]
		flame.initial_velocity_max = [0.8, 1.1, 1.5][clampi(stage - 1, 0, 2)]
		flame.scale_amount_max = [1.0, 1.4, 1.9][clampi(stage - 1, 0, 2)]
	if smoke != null:
		smoke.amount = [5, 9, 14][clampi(stage - 1, 0, 2)]
	var glow: OmniLight3D = node.get_node_or_null("Glow")
	if glow != null:
		glow.set_meta("base", [0.5, 0.9, 1.3][clampi(stage - 1, 0, 2)])

func _flicker() -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	for id in _emitters:
		var g: OmniLight3D = (_emitters[id] as Node).get_node_or_null("Glow")
		if g != null:
			g.light_energy = float(g.get_meta("base", 1.2)) * (0.85 + 0.15 * sin(t * 11.0 + float(id) * 1.7))

# ------------------------------------------------------------------ soot and haze
func _sync_scorch() -> void:
	_mats()
	for k in Fire.scorch:
		if not _scorch.has(k):
			var parts: PackedStringArray = str(k).split(",")
			var mi := MeshInstance3D.new()
			var q := QuadMesh.new()
			var lv: int = int(Fire.scorch[k]["lv"])
			q.size = Vector2.ONE * (1.1 + 0.25 * float(lv))
			q.material = _soot_mat
			mi.mesh = q
			mi.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
			mi.position = Vector3(float(parts[0]) + 0.5, 0.08, float(parts[1]) + 0.5)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_scorch[k] = mi
	for k2 in _scorch.keys():
		if not Fire.scorch.has(k2):
			(_scorch[k2] as Node).queue_free()
			_scorch.erase(k2)

func _sync_haze() -> void:
	_mats()
	for l in Fire.blazes:
		var s: float = Fire.smoke_of(str(l))
		var mi: MeshInstance3D = _haze.get(l, null)
		if s < 0.15:
			if mi != null:
				mi.visible = false
			continue
		if mi == null:
			mi = MeshInstance3D.new()
			mi.mesh = BoxMesh.new()
			mi.material_override = _haze_mat.duplicate()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_haze[l] = mi
		var rc: Rect2i = _area(str(l))
		(mi.mesh as BoxMesh).size = Vector3(rc.size.x, 0.1, rc.size.y)
		mi.position = Vector3(rc.position.x + rc.size.x * 0.5, 1.7, rc.position.y + rc.size.y * 0.5)
		(mi.material_override as StandardMaterial3D).albedo_color.a = clampf(s * 0.3, 0.0, 0.3)
		mi.visible = true
	for l2 in _haze.keys():
		if not Fire.blazes.has(l2):
			(_haze[l2] as Node).queue_free()
			_haze.erase(l2)

## The lot's rectangle, or (no regions) a box around its fires.
func _area(l: String) -> Rect2i:
	var rc: Rect2i = NeighborhoodLots.rect_of(l)
	if rc.size != Vector2i.ZERO:
		return rc
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for f in Fire.fires_in(l):
		lo = Vector2i(mini(lo.x, f["tile"].x), mini(lo.y, f["tile"].y))
		hi = Vector2i(maxi(hi.x, f["tile"].x), maxi(hi.y, f["tile"].y))
	if lo.x > hi.x:
		return Rect2i(0, 0, 1, 1)
	return Rect2i(lo - Vector2i(5, 5), hi - lo + Vector2i(11, 11))
