class_name LookOverlay
extends CanvasLayer
## Screen-space vignette and film grain of the current look (task 41; view only). One full-screen ColorRect with a tiny shader, drawn above the
## 3D world and below the HUD (layer 2 < UILayer 5). Reference look: hidden (zero cost). Added by LotView._ready via ensure_on().

const SHADER := """
shader_type canvas_item;
uniform float vignette = 0.0;
uniform float grain = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 d = UV - vec2(0.5);
	float v = smoothstep(0.35, 0.95, length(d * vec2(1.0, 0.8)) * 1.35);
	float g = (hash(floor(FRAGCOORD.xy)) - 0.5) * grain;
	COLOR = vec4(0.0, 0.0, 0.02, clamp(v * vignette, 0.0, 0.9));
	COLOR.rgb += vec3(g);
	COLOR.a = clamp(COLOR.a + abs(g) * 2.0, 0.0, 0.95);
}
"""

var _rect: ColorRect
var _mat: ShaderMaterial


static func ensure_on(parent: Node) -> LookOverlay:
	var ex = parent.get_node_or_null("LookOverlay")
	if ex != null:
		return ex
	var lo := LookOverlay.new()
	lo.name = "LookOverlay"
	parent.add_child(lo)
	return lo


func _ready() -> void:
	layer = 2
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	add_child(_rect)
	Looks.bus.changed.connect(func(_i): _sync())
	_sync()


func _sync() -> void:
	var v := Looks.ef("vignette", 0.0)
	var g := Looks.ef("grain", 0.0)
	_rect.visible = v > 0.0 or g > 0.0
	_mat.set_shader_parameter("vignette", v)
	_mat.set_shader_parameter("grain", g)
