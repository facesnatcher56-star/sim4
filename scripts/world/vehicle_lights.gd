class_name VehicleLights
extends RefCounted
## The lamps of the vehicles (task 42, display only, nothing here touches sim state). Cause: a driver lights the road when it is dark, in rain, snow or fog, so the car can be seen and
## sees; brake lights show a slowing or waiting car; the indicator blinks on the side of a turn about to be made; the white reversing lights show while backing out; a parked car shows
## nothing. Emergency vehicles flash their blue and red over the road around them.
##
## ONE extra mesh per vehicle (a shared additive mesh per body size) holds every lamp, the beam on the road and the flash discs; a shader with per-instance parameters switches the parts
## (lamps: head, tail 0 / dim 0.5 / brake 1, indicator left, indicator right; lamps2: reversing, beam strength, flash red, flash blue), so a car costs one draw call and no material.
## Real lights (a SpotLight3D low beam, an OmniLight3D for the blue and red) are given to the nearest few only: VehicleLightRigs.
##   VehicleLights.context() -> {on, dark, t}       VehicleLights.state(v, ctx, prev_speed) -> {head, tail, brake, ind (-1 left, 0, 1 right), rev, siren}
##   VehicleLights.attach(root, v) -> MeshInstance3D or null       VehicleLights.apply(mi, st, ctx, phase)

const HEAD := 0
const TAIL := 1
const IND_L := 2
const IND_R := 3
const REV := 4
const BEAM := 5
const FLASH_R := 6
const FLASH_B := 7

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
instance uniform vec4 lamps = vec4(0.0);
instance uniform vec4 lamps2 = vec4(0.0);
void fragment() {
	int g = int(UV.x + 0.5);
	float a = 0.0;
	vec3 c = vec3(1.0);
	if (g == 0) { a = lamps.x; c = vec3(1.0, 0.94, 0.78) * 2.4; }
	else if (g == 1) { a = lamps.y > 0.0 ? 1.0 : 0.0; c = lamps.y > 0.75 ? vec3(1.0, 0.1, 0.07) * 2.6 : vec3(0.7, 0.03, 0.03) * 1.3; }
	else if (g == 2) { a = lamps.z; c = vec3(1.0, 0.55, 0.05) * 2.4; }
	else if (g == 3) { a = lamps.w; c = vec3(1.0, 0.55, 0.05) * 2.4; }
	else if (g == 4) { a = lamps2.x; c = vec3(1.0, 1.0, 1.0) * 2.2; }
	else if (g == 5) { a = lamps2.y * COLOR.a; c = vec3(1.0, 0.93, 0.76); }
	else if (g == 6) { a = lamps2.z * COLOR.a; c = vec3(1.0, 0.12, 0.08) * 1.6; }
	else if (g == 7) { a = lamps2.w * COLOR.a; c = vec3(0.1, 0.3, 1.0) * 1.8; }
	ALBEDO = c;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

const BEAM_LEN := 17.0            # low beam: it reaches about 17 m down the road
const BEAM_W0 := 1.5              # half width at the lamps
const BEAM_W1 := 3.6              # half width at the end
const FLASH_R_M := 6.0            # radius of the blue / red flash on the road
const BLINK_S := 0.7

static var _mat: ShaderMaterial = null
static var _meshes: Dictionary = {}
static var disabled: bool = false          # benchmarks only (tests/lights_bench.gd): every lamp off, as before task 42


static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.render_priority = 2
	return _mat


static func forget() -> void:
	_mat = null
	_meshes.clear()


# ------------------------------------------------------------------ what the lights do (pure)

## Headlights are wanted when it is dusk, dark, raining, snowing or foggy. `dark` 0..1 (how strong the beam shows), `on` the switch.
static func context() -> Dictionary:
	var dl: float = Weather.daylight() * Weather.light_factor()
	var fog: float = Weather.fog_amount()
	var wet: bool = Weather.is_precipitating() and Weather.precip_intensity() > 0.05
	var on: bool = (dl < 0.55 or fog > 0.2 or wet) and not disabled
	var dark: float = clampf(1.0 - dl * 1.15, 0.0, 1.0)
	if on:
		dark = maxf(dark, 0.4)
	return {"on": on, "dark": dark}


## Turn about to be made: +1 right, -1 left, 0 none (the way ahead of the vehicle on its path: a heading change of more than ~30 degrees within 16 m).
static func turn_ahead(v: Dictionary) -> int:
	var path: VehiclePath = v["path"]
	var s: float = float(v["s"])
	if s > path.length - 1.5:
		return 0
	var h0: Vector2 = path.dir_at(s + 1.0)
	var h1: Vector2 = path.dir_at(minf(s + 16.0, path.length))
	var ang: float = atan2(h0.x * h1.y - h0.y * h1.x, h0.dot(h1))          # x east, z south: positive = clockwise seen from above = a right turn
	if absf(ang) < 0.5:
		return 0
	return 1 if ang > 0.0 else -1


static func state(v: Dictionary, ctx: Dictionary, prev_speed: float) -> Dictionary:
	var out := {"head": false, "tail": false, "brake": false, "ind": 0, "rev": false, "siren": false}
	var st: String = str(v["state"])
	if st == "parked" or st == "dead":
		out["siren"] = bool((v["lights"] as Dictionary).get("siren", false))
		return out
	var sp: float = float(v["v"])
	var rev: bool = VehicleSim.reversing(v) or v.has("reverse_left")          # backing out of a drive / bay, or backing up to free a deadlock (VehicleJams)
	var slowing: bool = sp < prev_speed - 0.03
	out["head"] = bool(ctx["on"])
	out["rev"] = rev
	out["brake"] = (sp < 0.15 or slowing) and not rev
	out["tail"] = bool(ctx["on"]) or bool(out["brake"])
	out["ind"] = 0 if rev else turn_ahead(v)
	out["siren"] = bool((v["lights"] as Dictionary).get("siren", false))
	return out


# ------------------------------------------------------------------ the mesh

class _Acc:
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, g: int, alphas: Array = [1.0, 1.0, 1.0, 1.0]) -> void:
		var i := pos.size()
		for k in 4:
			uv.append(Vector2(float(g), 0.0))
		pos.append(a)
		pos.append(b)
		pos.append(c)
		pos.append(d)
		for k2 in 4:
			col.append(Color(1, 1, 1, float(alphas[k2])))
		idx.append_array(PackedInt32Array([i, i + 1, i + 2, i, i + 2, i + 3]))

	func grid(x0: Callable, z_of: Callable, rows: int, cols: int, g: int, y: float, alpha_fn: Callable) -> void:
		var base := pos.size()
		for r in rows + 1:
			var t: float = float(r) / float(rows)
			for c in cols + 1:
				var u: float = float(c) / float(cols) * 2.0 - 1.0
				pos.append(Vector3(float(x0.call(t, u)), y, float(z_of.call(t))))
				uv.append(Vector2(float(g), 0.0))
				col.append(Color(1, 1, 1, float(alpha_fn.call(t, u))))
		for r2 in rows:
			for c2 in cols:
				var a: int = base + r2 * (cols + 1) + c2
				idx.append_array(PackedInt32Array([a, a + 1, a + cols + 2, a, a + cols + 2, a + cols + 1]))

	func commit() -> ArrayMesh:
		var normals := PackedVector3Array()
		normals.resize(pos.size())
		normals.fill(Vector3.UP)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_COLOR] = col
		arrays[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return am


static func _lamp_y(glb: String) -> float:
	if glb.begins_with("bus") or glb.begins_with("fire") or glb.begins_with("ambulance"):
		return 0.85
	if glb.contains("van") or glb.begins_with("tow"):
		return 0.74
	return 0.64


static func mesh_for(wid: float, len: float, glb: String) -> ArrayMesh:
	var y: float = _lamp_y(glb)
	var key := "%.2f|%.2f|%.2f" % [wid, len, y]
	if _meshes.has(key):
		return _meshes[key]
	var a := _Acc.new()
	var hf: float = len * 0.5
	var hw: float = wid * 0.5
	for sx in [-1.0, 1.0]:
		var x: float = float(sx) * (hw - 0.3)
		a.quad(Vector3(x - 0.17, y - 0.07, -hf - 0.02), Vector3(x + 0.17, y - 0.07, -hf - 0.02), Vector3(x + 0.17, y + 0.07, -hf - 0.02), Vector3(x - 0.17, y + 0.07, -hf - 0.02), HEAD)
		a.quad(Vector3(x - 0.17, y - 0.07, hf + 0.02), Vector3(x + 0.17, y - 0.07, hf + 0.02), Vector3(x + 0.17, y + 0.07, hf + 0.02), Vector3(x - 0.17, y + 0.07, hf + 0.02), TAIL)
		var xi: float = float(sx) * (hw - 0.1)
		var g: int = IND_L if sx < 0.0 else IND_R
		a.quad(Vector3(xi - 0.07, y - 0.06, -hf - 0.025), Vector3(xi + 0.07, y - 0.06, -hf - 0.025), Vector3(xi + 0.07, y + 0.06, -hf - 0.025), Vector3(xi - 0.07, y + 0.06, -hf - 0.025), g)
		a.quad(Vector3(xi - 0.07, y - 0.06, hf + 0.025), Vector3(xi + 0.07, y - 0.06, hf + 0.025), Vector3(xi + 0.07, y + 0.06, hf + 0.025), Vector3(xi - 0.07, y + 0.06, hf + 0.025), g)
		var xr: float = float(sx) * (hw - 0.62)
		a.quad(Vector3(xr - 0.1, y - 0.1, hf + 0.03), Vector3(xr + 0.1, y - 0.1, hf + 0.03), Vector3(xr + 0.1, y + 0.02, hf + 0.03), Vector3(xr - 0.1, y + 0.02, hf + 0.03), REV)
	# the low beam on the road: a soft fan from the lamps to BEAM_LEN ahead, brightest near the car, fading to the sides and to the far end
	a.grid(func(t: float, u: float) -> float: return u * lerpf(BEAM_W0, BEAM_W1, t), func(t: float) -> float: return -hf - 0.3 - t * BEAM_LEN, 10, 6, BEAM, 0.03,
		func(t: float, u: float) -> float: return pow(1.0 - t, 1.5) * (1.0 - u * u) * 0.42)
	# the blue / red flash of an emergency vehicle: a soft disc round the body
	for g2 in [FLASH_R, FLASH_B]:
		var cx: float = -1.1 if g2 == FLASH_R else 1.1
		a.grid(func(t: float, u: float) -> float: return cx + u * FLASH_R_M * 0.5 * (1.0 - t * 0.0), func(t: float) -> float: return (t * 2.0 - 1.0) * FLASH_R_M * 0.5, 6, 6, g2, 0.032,
			func(t: float, u: float) -> float: return clampf(1.0 - (u * u + (t * 2.0 - 1.0) * (t * 2.0 - 1.0)), 0.0, 1.0) * 0.55)
	var m: ArrayMesh = a.commit()
	_meshes[key] = m
	return m


## The lamp mesh of a vehicle as a child of its root (null for bikes).
static func attach(root: Node3D, v: Dictionary) -> MeshInstance3D:
	if str(v["kind"]) == "bike":
		return null
	var mi := MeshInstance3D.new()
	mi.name = "Lamps"
	mi.mesh = mesh_for(float(v["wid"]), float(v["len"]), str(v["glb"]))
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = BEAM_LEN
	mi.set_instance_shader_parameter("lamps", Vector4(0.0, 0.0, 0.0, 0.0))
	mi.visible = false
	root.add_child(mi)
	return mi


## Switch the parts of a vehicle's lamp mesh (only when something changed: `rec` keeps the last signature).
static func apply(rec: Dictionary, st: Dictionary, ctx: Dictionary, blink_on: bool, flash_on: bool, beam_scale: float = 1.0) -> void:
	var mi: MeshInstance3D = rec.get("lamps", null)
	if mi == null or not is_instance_valid(mi):
		return
	var head: float = 1.0 if bool(st["head"]) else 0.0
	var tail: float = 1.0 if bool(st["brake"]) else (0.5 if bool(st["tail"]) else 0.0)
	var ind: int = int(st["ind"])
	var il: float = 1.0 if (ind < 0 and blink_on) else 0.0
	var ir: float = 1.0 if (ind > 0 and blink_on) else 0.0
	var rev: float = 1.0 if bool(st["rev"]) else 0.0
	var beam: float = float(ctx["dark"]) * 0.9 * beam_scale if bool(st["head"]) else 0.0
	var siren: bool = bool(st["siren"])
	var fr: float = 1.0 if (siren and flash_on) else 0.0
	var fb: float = 1.0 if (siren and not flash_on) else 0.0
	var sig: String = "%.1f|%.1f|%.1f|%.1f|%.1f|%.2f|%.1f|%.1f" % [head, tail, il, ir, rev, beam, fr, fb]
	if sig == str(rec.get("lamp_sig", "")):
		return
	rec["lamp_sig"] = sig
	mi.set_instance_shader_parameter("lamps", Vector4(head, tail, il, ir))
	mi.set_instance_shader_parameter("lamps2", Vector4(rev, beam, fr, fb))
	mi.visible = head > 0.0 or tail > 0.0 or il > 0.0 or ir > 0.0 or rev > 0.0 or fr > 0.0 or fb > 0.0
