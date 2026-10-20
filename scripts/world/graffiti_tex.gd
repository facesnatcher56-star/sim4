class_name GraffitiTex
extends RefCounted
## Task 41a (view only): procedural graffiti tags for Forward+ decals: real letters drawn with a fat round brush in an outline colour, a fill colour, a highlight and
## a drop shadow, with drips, an underline swoosh and a few stars, so a tag has bulk and colour (the look-test squiggles did not). `names()` lists the variants;
## `tex(name)` -> ImageTexture (cached, 512 x 192, transparent background). Own RandomNumberGenerator seeded by the name: the game rng is never touched.

const W := 512
const H := 192
const VARIANTS := {
	"tag_rat": {"word": "RAT", "fill": "#d8452e", "line": "#14110f", "light": "#ff9a78", "shadow": "#f2d24a", "tilt": -7.0, "style": "bubble"},
	"tag_koz": {"word": "KOZ", "fill": "#3f8fd2", "line": "#0e1218", "light": "#a9dcff", "shadow": "#ffffff", "tilt": 4.0, "style": "block"},
	"tag_six": {"word": "SIX", "fill": "#e2c53a", "line": "#1a1410", "light": "#fff3a0", "shadow": "#c2402a", "tilt": -3.0, "style": "bubble"},
	"tag_nek": {"word": "NEK", "fill": "#4fb27a", "line": "#0c1511", "light": "#bdf2d1", "shadow": "#1a1a1a", "tilt": 6.0, "style": "block"},
	"tag_doa": {"word": "DOA", "fill": "#c957a8", "line": "#170f15", "light": "#ffc4ec", "shadow": "#5a2a8a", "tilt": -5.0, "style": "bubble"},
	"tag_vex": {"word": "VEX", "fill": "#f08a2a", "line": "#18100a", "light": "#ffd29a", "shadow": "#2a5aa8", "tilt": 3.0, "style": "block"},
}
const GLYPHS := {
	"A": [[[0, 1], [0.5, 0], [1, 1]], [[0.2, 0.66], [0.8, 0.66]]],
	"B": [[[0, 0], [0.7, 0], [0.95, 0.2], [0.7, 0.46], [0, 0.5]], [[0, 0.5], [0.78, 0.5], [1, 0.75], [0.75, 1], [0, 1]], [[0, 0], [0, 1]]],
	"D": [[[0, 0], [0, 1]], [[0, 0], [0.65, 0.05], [1, 0.5], [0.65, 0.95], [0, 1]]],
	"E": [[[1, 0], [0, 0], [0, 1], [1, 1]], [[0, 0.5], [0.8, 0.5]]],
	"I": [[[0.5, 0], [0.5, 1]], [[0.2, 0], [0.8, 0]], [[0.2, 1], [0.8, 1]]],
	"K": [[[0, 0], [0, 1]], [[1, 0], [0, 0.55], [1, 1]]],
	"M": [[[0, 1], [0, 0], [0.5, 0.6], [1, 0], [1, 1]]],
	"N": [[[0, 1], [0, 0], [1, 1], [1, 0]]],
	"O": [[[0.5, 0], [0.9, 0.15], [1, 0.5], [0.9, 0.85], [0.5, 1], [0.1, 0.85], [0, 0.5], [0.1, 0.15], [0.5, 0]]],
	"R": [[[0, 1], [0, 0], [0.75, 0], [1, 0.25], [0.75, 0.5], [0, 0.5]], [[0.45, 0.5], [1, 1]]],
	"S": [[[1, 0.15], [0.6, 0], [0.1, 0.1], [0.05, 0.35], [0.5, 0.5], [0.95, 0.65], [0.9, 0.9], [0.4, 1], [0, 0.85]]],
	"T": [[[0, 0], [1, 0]], [[0.5, 0], [0.5, 1]]],
	"V": [[[0, 0], [0.5, 1], [1, 0]]],
	"X": [[[0, 0], [1, 1]], [[1, 0], [0, 1]]],
	"Z": [[[0, 0], [1, 0], [0, 1], [1, 1]]],
}
static var _cache: Dictionary = {}
static var _brushes: Dictionary = {}


static func names() -> Array:
	return VARIANTS.keys()


static func is_tag(name: String) -> bool:
	return VARIANTS.has(name)


static func tex(name: String) -> ImageTexture:
	if _cache.has(name):
		return _cache[name]
	var v: Dictionary = VARIANTS.get(name, VARIANTS["tag_rat"])
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = name.hash()
	var word: String = v["word"]
	var tilt := deg_to_rad(float(v["tilt"]))
	var bulk := 26.0 if str(v["style"]) == "bubble" else 20.0
	var lw := (W - 90.0) / float(word.length())
	var strokes: Array = []                                   # [[Vector2...]] in texture pixels, tilted
	for i in word.length():
		var g: Array = GLYPHS.get(word[i], [])
		var x0 := 45.0 + i * lw
		for poly in g:
			var pts: Array = []
			for p in poly:
				var q := Vector2(x0 + float(p[0]) * (lw - bulk * 1.3) + bulk * 0.6, 40.0 + float(p[1]) * (H - 100.0))
				q.y += (q.x - W * 0.5) * tan(tilt) * 0.55
				pts.append(q)
			strokes.append(pts)
	var shadow := Color(str(v["shadow"]))
	var line := Color(str(v["line"]))
	var fill := Color(str(v["fill"]))
	var light := Color(str(v["light"]))
	_draw(img, strokes, Vector2(7, 7), bulk + 10.0, shadow)       # drop shadow (offset)
	_draw(img, strokes, Vector2.ZERO, bulk + 10.0, line)          # outline
	_draw(img, strokes, Vector2.ZERO, bulk - 2.0, fill)           # fill
	_draw(img, strokes, Vector2(-4, -5), maxf(bulk * 0.22, 3.0), light)    # highlight
	var base_y := H - 30.0                                        # underline swoosh with an outline
	var sw: Array = [[Vector2(50, base_y + 2), Vector2(180, base_y - 6), Vector2(330, base_y + 4), Vector2(W - 60, base_y - 8)]]
	_draw(img, sw, Vector2.ZERO, 12.0, line)
	_draw(img, sw, Vector2.ZERO, 6.0, light)
	for i in 5:                                                   # drips from the lowest edge of the letters
		var dx := 70.0 + rng.randf() * (W - 140.0)
		var dl := 14.0 + rng.randf() * 36.0
		_draw(img, [[Vector2(dx, H - 62.0), Vector2(dx + rng.randf_range(-2, 2), H - 62.0 + dl)]], Vector2.ZERO, 5.0, fill)
	for i in 4:                                                   # stars / sparkles
		var c := Vector2(rng.randf_range(20, W - 20), rng.randf_range(14, 40))
		_draw(img, [[c - Vector2(8, 0), c + Vector2(8, 0)], [c - Vector2(0, 8), c + Vector2(0, 8)]], Vector2.ZERO, 4.0, light)
	var t := ImageTexture.create_from_image(img)
	_cache[name] = t
	return t


static func _brush(r: float, c: Color) -> Image:
	var key := "%d|%s" % [int(r * 2.0), c.to_html()]
	if _brushes.has(key):
		return _brushes[key]
	var d := int(ceil(r * 2.0)) + 2
	var b := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var ctr := float(d) * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5 - ctr, y + 0.5 - ctr).length()
			if dist <= r:
				b.set_pixel(x, y, Color(c.r, c.g, c.b, clampf((r - dist) * 1.5, 0.0, 1.0)))
	_brushes[key] = b
	return b


## Round brush along every polyline (stamped every r / 2 px with a native blend_rect).
static func _draw(img: Image, strokes: Array, off: Vector2, width: float, c: Color) -> void:
	var r := width * 0.5
	var b := _brush(r, c)
	var sz := b.get_size()
	var rect := Rect2i(Vector2i.ZERO, sz)
	for pts in strokes:
		for i in range(1, (pts as Array).size()):
			var a: Vector2 = (pts[i - 1] as Vector2) + off
			var e: Vector2 = (pts[i] as Vector2) + off
			var n := maxi(int(a.distance_to(e) / maxf(r * 0.5, 1.0)), 1)
			for k in n + 1:
				var p := a.lerp(e, float(k) / float(n))
				img.blend_rect(b, rect, Vector2i(int(p.x - sz.x * 0.5), int(p.y - sz.y * 0.5)))
