class_name WearShader
extends RefCounted
## Task 41a (view only): one grime / peel / soot shader for walls, window frames, door frames and leaves under a look that asks for it (looks.json wear.shader_classes).
## World-space, so a wall that cuts down keeps its dirty base course and its top gets soot and moss at any height. Per mesh `instance uniform wear` (0..1) sets how
## worn it is (lot wear / poverty, strong outside, lighter indoors; WearRules.wall_wear); `base_wear` is the look's own baseline for every wall.
##   base course splash (dark, up to ~1.2 m), rain streaks from the top, peeling paint patches that show the bare plaster, speckle, dark moss / soot on top faces.
## Cost: a handful of noise lookups per pixel on wall meshes only; materials are shared per (colour, look), no extra draw calls.

const CODE := """shader_type spatial;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float rough = 0.9;
uniform float base_wear = 0.1;
uniform vec3 grime_col : source_color = vec3(0.1, 0.085, 0.07);
uniform vec3 under_col : source_color = vec3(0.6, 0.55, 0.47);
uniform vec3 top_col : source_color = vec3(0.14, 0.15, 0.1);
instance uniform float wear : hint_range(0.0, 1.0) = 0.0;
varying vec3 wp;
varying vec3 wn;
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float w = clamp(wear + base_wear, 0.0, 1.0);
	vec3 c = albedo.rgb;
	float u = wp.x + wp.z;
	float n1 = vn(vec2(u * 2.5, wp.y * 2.0));
	float n2 = vn(vec2(u * 9.0, wp.y * 5.0));
	float band = clamp(1.0 - wp.y / (0.3 + 0.9 * w), 0.0, 1.0);
	band = band * band * (0.55 + 0.8 * n1);
	c = mix(c, grime_col, clamp(band * w * 1.7, 0.0, 0.88));
	float streak = smoothstep(0.62, 0.92, vn(vec2(u * 11.0, 3.0))) * smoothstep(0.0, 2.2, wp.y) * (0.5 + 0.5 * vn(vec2(u * 3.0, wp.y * 0.8)));
	c *= 1.0 - streak * w * 0.5;
	float pm = n1 * 0.65 + n2 * 0.35;
	float peel = smoothstep(1.02 - w * 0.3, 1.06 - w * 0.3, pm) * step(0.45, w);
	c = mix(c, under_col, peel * 0.8);
	c *= 1.0 - w * 0.22 * n2;
	if (wn.y > 0.7) {
		c = mix(c, top_col, clamp(w * 1.1 + 0.1, 0.0, 0.9) * (0.75 + 0.25 * n2));
	}
	ALBEDO = c;
	ROUGHNESS = rough;
}
"""

static var _shader: Shader = null
static var _mats: Dictionary = {}


static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CODE
	return _shader


## Shared material for a base colour (look id separates the cache so a look switch does not reuse stale colours).
static func material(c: Color, rough: float, base_wear: float, look_id: String) -> ShaderMaterial:
	var key := "%s|%s|%.2f|%.2f" % [c.to_html(), look_id, rough, base_wear]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = shader()
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("base_wear", base_wear)
	_mats[key] = m
	return m


## Sets the per-mesh wear (0..1) on every mesh under `n`.
static func set_wear(n: Node, w: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).set_instance_shader_parameter("wear", clampf(w, 0.0, 1.0))
	for c in n.get_children():
		set_wear(c, w)
