class_name DressingTex
extends RefCounted
## Procedural textures for DistrictDressing decals and flat quads (task 41; view only, own RandomNumberGenerator, no game rng).
## tex(name) -> ImageTexture, cached. Names: crack, pothole, stain, graffiti_a, graffiti_b, peel, worn_mark, grime, chainlink, litter.

static var _cache: Dictionary = {}


static func tex(name: String) -> ImageTexture:
	if _cache.has(name):
		return _cache[name]
	if GraffitiTex.is_tag(name):           # task 41a: tags with outline, fill, highlight and shadow
		return GraffitiTex.tex(name)
	var rng := RandomNumberGenerator.new()
	rng.seed = name.hash()
	var side := 128 if name in ["stain", "grime", "worn_mark", "dead_grass", "dirt_patch", "oil"] else 256
	var img := Image.create(384 if name.begins_with("graffiti") else side, 144 if name.begins_with("graffiti") else side, false, Image.FORMAT_RGBA8)
	match name:
		"crack": _crack(img, rng)
		"pothole": _pothole(img, rng)
		"stain": _blotch(img, rng, Color(0.16, 0.11, 0.07), 0.9)
		"grime": _blotch(img, rng, Color(0.05, 0.05, 0.04), 0.75)
		"peel": _peel(img, rng)
		"worn_mark": _blotch(img, rng, Color(0.18, 0.19, 0.21), 0.95)
		"dead_grass": _blotch(img, rng, Color(0.4, 0.31, 0.17), 0.92)
		"dirt_patch": _blotch(img, rng, Color(0.27, 0.2, 0.13), 0.9)
		"oil": _blotch(img, rng, Color(0.03, 0.03, 0.035), 0.8)
		"graffiti_a": _graffiti(img, rng, [Color(0.85, 0.15, 0.2), Color(0.95, 0.95, 0.9), Color(0.05, 0.05, 0.06)])
		"graffiti_b": _graffiti(img, rng, [Color(0.15, 0.55, 0.85), Color(0.95, 0.8, 0.1), Color(0.05, 0.05, 0.06)])
		"chainlink": _chainlink(img)
		_: _blotch(img, rng, Color(0.1, 0.1, 0.1), 0.5)
	var t := ImageTexture.create_from_image(img)
	_cache[name] = t
	return t


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		var o := img.get_pixel(x, y)
		img.set_pixel(x, y, c if c.a >= o.a else o)


static func _disc(img: Image, cx: float, cy: float, r: float, c: Color, soft: float = 0.0) -> void:
	for y in range(int(cy - r - 1), int(cy + r + 2)):
		for x in range(int(cx - r - 1), int(cx + r + 2)):
			var d := Vector2(x - cx, y - cy).length()
			if d <= r:
				var a := c.a * (1.0 if soft <= 0.0 else clampf((r - d) / (r * soft), 0.0, 1.0))
				_px(img, x, y, Color(c.r, c.g, c.b, a))


static func _line(img: Image, a: Vector2, b: Vector2, w: float, c: Color) -> void:
	var n := int(a.distance_to(b)) + 1
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(maxi(n, 1)))
		_disc(img, p.x, p.y, w * 0.5, c)


static func _crack(img: Image, rng: RandomNumberGenerator) -> void:
	var c := Color(0.04, 0.04, 0.04, 0.95)
	var starts := [Vector2(20, 128), Vector2(128, 20)]
	for s in starts:
		var p: Vector2 = s
		var ang := rng.randf() * TAU
		if s.x == 20:
			ang = rng.randf_range(-0.4, 0.4)
		else:
			ang = PI * 0.5 + rng.randf_range(-0.4, 0.4)
		for i in 38:
			var q := p + Vector2(cos(ang), sin(ang)) * 6.0
			_line(img, p, q, 2.4 if i < 20 else 1.6, c)
			if rng.randf() < 0.18:
				var ba := ang + rng.randf_range(-1.1, 1.1)
				var bp := q
				for k in 8:
					var bq := bp + Vector2(cos(ba), sin(ba)) * 5.0
					_line(img, bp, bq, 1.4, c)
					bp = bq
					ba += rng.randf_range(-0.4, 0.4)
			p = q
			ang += rng.randf_range(-0.35, 0.35)


static func _pothole(img: Image, rng: RandomNumberGenerator) -> void:
	_disc(img, 128, 128, 104, Color(0.1, 0.1, 0.1, 0.35), 0.6)
	for i in 14:
		var a := float(i) / 14.0 * TAU
		var rr := 64.0 + rng.randf_range(-8.0, 10.0)
		_disc(img, 128 + cos(a) * rr * 0.55, 128 + sin(a) * rr * 0.45, rr * 0.5, Color(0.03, 0.03, 0.035, 0.97))
	_disc(img, 128, 128, 40, Color(0.015, 0.015, 0.02, 1.0))


static func _blotch(img: Image, rng: RandomNumberGenerator, col: Color, alpha: float) -> void:
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.frequency = 0.022
	n.fractal_octaves = 4
	var sz := img.get_width()                          # 128 px blotches (a quarter of the pixels; decals scale them up softly): task 41a first-use hitch
	var k := 256.0 / float(sz)
	for y in sz:
		for x in sz:
			var v := (n.get_noise_2d(x * k, y * k) + 1.0) * 0.5
			var edge := clampf(1.0 - Vector2(x - sz * 0.5, y - sz * 0.5).length() / (sz * 0.5), 0.0, 1.0)
			var a := clampf((v - 0.5) * 4.0, 0.0, 1.0) * alpha * clampf(edge * 2.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))


static func _peel(img: Image, rng: RandomNumberGenerator) -> void:
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.frequency = 0.03
	n.fractal_octaves = 3
	for y in 256:
		for x in 256:
			var v := (n.get_noise_2d(x, y) + 1.0) * 0.5
			if v > 0.6:
				var edge := clampf((v - 0.6) * 12.0, 0.0, 1.0)
				var rim := v < 0.64
				img.set_pixel(x, y, Color(0.78, 0.76, 0.7, 0.95) if rim else Color(0.34, 0.3, 0.26, edge * 0.92))


static func _graffiti(img: Image, rng: RandomNumberGenerator, cols: Array) -> void:
	var w := float(img.get_width())
	var h := float(img.get_height())
	for layer in 3:
		var c: Color = cols[layer % cols.size()]
		var th := 24.0 - layer * 7.0
		var p := Vector2(24 + layer * 5, h * 0.55 - layer * 8 + rng.randf_range(-6, 6))
		for seg in 6:
			var q := p + Vector2(rng.randf_range(w * 0.05, w * 0.1), rng.randf_range(-h * 0.35, h * 0.35))
			q.y = clampf(q.y, 22.0, h - 22.0)
			_line(img, p, q, th, c)
			if layer == 0 and rng.randf() < 0.5:
				_line(img, q, q + Vector2(rng.randf_range(-3, 3), rng.randf_range(14, 36)), 3.0, c)     # a drip
			p = q
	for i in 6:
		_disc(img, rng.randf_range(24, w - 24), rng.randf_range(24, h - 24), rng.randf_range(2, 5), Color(cols[0].r, cols[0].g, cols[0].b, 0.9))


static func _chainlink(img: Image) -> void:
	var c := Color(0.62, 0.64, 0.66, 0.9)
	for k in range(-256, 512, 32):
		_line(img, Vector2(k, 0), Vector2(k + 256, 256), 2.0, c)
		_line(img, Vector2(k, 256), Vector2(k + 256, 0), 2.0, c)
