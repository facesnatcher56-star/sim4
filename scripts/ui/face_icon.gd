class_name FaceIcon
extends Control
## Tiny procedural face: coloured head + a distinct expression for each of the 21 moods (shape, not only colour).
var color := Color("#9aa7b4"):
	set(v):
		color = v
		queue_redraw()
var mood := "neutral":
	set(v):
		mood = v
		queue_redraw()

## mood -> [mouth, brows, extra]
##   mouth: smile | grin | smirk | flat | frown | wavy | open | small_frown
##   brows: none | angry | worried | flat
##   extra: none | blush | sparkle | sweat | wink | closed_eyes | half_lids | x_eyes
const LOOKS := {
	"happy": ["smile", "none", "none"], "content": ["smile", "none", "closed_eyes"], "proud": ["smile", "flat", "none"],
	"confident": ["smirk", "flat", "none"], "energized": ["grin", "none", "none"], "playful": ["grin", "none", "wink"],
	"flirty": ["smile", "none", "blush"], "inspired": ["smile", "none", "sparkle"], "nostalgic": ["smile", "none", "closed_eyes"],
	"sad": ["frown", "worried", "none"], "lonely": ["small_frown", "worried", "none"], "guilty": ["small_frown", "worried", "blush"],
	"embarrassed": ["wavy", "worried", "blush"], "angry": ["frown", "angry", "none"], "jealous": ["smirk", "angry", "none"],
	"tense": ["flat", "angry", "none"], "anxious": ["wavy", "worried", "sweat"], "uncomfortable": ["wavy", "none", "none"],
	"bored": ["flat", "none", "half_lids"], "dazed": ["open", "none", "x_eyes"], "focused": ["flat", "flat", "none"],
	"neutral": ["flat", "none", "none"],
}

func _init() -> void:
	custom_minimum_size = Vector2(40, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 2.0
	var look: Array = LOOKS.get(mood, LOOKS["neutral"])
	draw_circle(c, r, color)
	var dark := Color(0, 0, 0, 0.78)
	var w := maxf(1.5, r * 0.09)
	var el := c + Vector2(-r * 0.33, -r * 0.15)
	var er := c + Vector2(r * 0.33, -r * 0.15)
	_eyes(str(look[2]), el, er, r, dark, w)
	_brows(str(look[1]), c, r, dark, w)
	_mouth(str(look[0]), c, r, dark, w)
	_extra(str(look[2]), c, el, er, r, w)

func _eyes(extra: String, el: Vector2, er: Vector2, r: float, dark: Color, w: float) -> void:
	match extra:
		"closed_eyes":
			for p in [el, er]:
				draw_arc(p + Vector2(0, r * 0.05), r * 0.12, PI + 0.3, TAU - 0.3, 8, dark, w)
		"half_lids":
			for p in [el, er]:
				draw_circle(p, r * 0.1, dark)
				draw_line(p + Vector2(-r * 0.16, -r * 0.06), p + Vector2(r * 0.16, -r * 0.06), dark, w)
		"x_eyes":
			for p in [el, er]:
				var d := r * 0.11
				draw_line(p + Vector2(-d, -d), p + Vector2(d, d), dark, w)
				draw_line(p + Vector2(-d, d), p + Vector2(d, -d), dark, w)
		"wink":
			draw_circle(el, r * 0.1, dark)
			draw_line(er + Vector2(-r * 0.12, 0), er + Vector2(r * 0.12, 0), dark, w)
		_:
			draw_circle(el, r * 0.1, dark)
			draw_circle(er, r * 0.1, dark)

func _brows(kind: String, c: Vector2, r: float, dark: Color, w: float) -> void:
	match kind:
		"angry":
			draw_line(c + Vector2(-r * 0.5, -r * 0.5), c + Vector2(-r * 0.15, -r * 0.33), dark, w)
			draw_line(c + Vector2(r * 0.5, -r * 0.5), c + Vector2(r * 0.15, -r * 0.33), dark, w)
		"worried":
			draw_line(c + Vector2(-r * 0.5, -r * 0.33), c + Vector2(-r * 0.15, -r * 0.5), dark, w)
			draw_line(c + Vector2(r * 0.5, -r * 0.33), c + Vector2(r * 0.15, -r * 0.5), dark, w)
		"flat":
			draw_line(c + Vector2(-r * 0.5, -r * 0.45), c + Vector2(-r * 0.15, -r * 0.45), dark, w)
			draw_line(c + Vector2(r * 0.5, -r * 0.45), c + Vector2(r * 0.15, -r * 0.45), dark, w)

func _mouth(kind: String, c: Vector2, r: float, dark: Color, w: float) -> void:
	var my := c.y + r * 0.35
	match kind:
		"smile":
			draw_arc(Vector2(c.x, my - r * 0.25), r * 0.4, 0.3, PI - 0.3, 12, dark, w)
		"grin":
			var pts := PackedVector2Array()
			for i in 13:
				var a := 0.2 + (PI - 0.4) * float(i) / 12.0
				pts.append(Vector2(c.x, my - r * 0.25) + Vector2(cos(a), sin(a)) * r * 0.45)
			draw_colored_polygon(pts, Color(0.15, 0.05, 0.05, 0.85))
		"smirk":
			draw_arc(Vector2(c.x + r * 0.1, my - r * 0.2), r * 0.35, 0.3, PI - 0.9, 10, dark, w)
		"frown":
			draw_arc(Vector2(c.x, my + r * 0.3), r * 0.35, PI + 0.4, TAU - 0.4, 12, dark, w)
		"small_frown":
			draw_arc(Vector2(c.x, my + r * 0.2), r * 0.22, PI + 0.4, TAU - 0.4, 10, dark, w)
		"wavy":
			var prev := Vector2(c.x - r * 0.32, my)
			for i in range(1, 9):
				var x := c.x - r * 0.32 + r * 0.64 * float(i) / 8.0
				var p := Vector2(x, my + sin(float(i) * 1.6) * r * 0.06)
				draw_line(prev, p, dark, w)
				prev = p
		"open":
			draw_circle(Vector2(c.x, my + r * 0.05), r * 0.14, Color(0.15, 0.05, 0.05, 0.85))
		_:
			draw_line(Vector2(c.x - r * 0.3, my), Vector2(c.x + r * 0.3, my), dark, w)

func _extra(extra: String, c: Vector2, el: Vector2, er: Vector2, r: float, _w: float) -> void:
	match extra:
		"blush":
			var pink := Color(1.0, 0.45, 0.55, 0.55)
			draw_circle(el + Vector2(-r * 0.1, r * 0.3), r * 0.12, pink)
			draw_circle(er + Vector2(r * 0.1, r * 0.3), r * 0.12, pink)
		"sparkle":
			var s := c + Vector2(r * 0.55, -r * 0.7)
			var gold := Color("#fff3a0")
			draw_line(s + Vector2(0, -r * 0.22), s + Vector2(0, r * 0.22), gold, 2.0)
			draw_line(s + Vector2(-r * 0.22, 0), s + Vector2(r * 0.22, 0), gold, 2.0)
		"sweat":
			draw_circle(c + Vector2(r * 0.62, -r * 0.35), r * 0.1, Color("#bfe6ff"))
