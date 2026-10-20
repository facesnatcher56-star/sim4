class_name ProgressIcons
extends RefCounted
## Task 33.4: tiny vector icons drawn inside the progress ring (no font or texture needed). `draw(ci, shape, c, r, col)` paints into radius `r` around `c`.


static func draw(ci: CanvasItem, shape: String, c: Vector2, r: float, col: Color) -> void:
	match shape:
		"drop":
			ci.draw_circle(c + Vector2(0, r * 0.25), r * 0.5, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.75), c + Vector2(r * 0.46, r * 0.05), c + Vector2(-r * 0.46, r * 0.05)]), col)
		"flame":
			ci.draw_circle(c + Vector2(0, r * 0.2), r * 0.45, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.8), c + Vector2(r * 0.4, r * 0.1), c + Vector2(-r * 0.4, r * 0.1)]), col)
			ci.draw_circle(c + Vector2(0, r * 0.3), r * 0.2, Color(1, 0.95, 0.7))
		"leaf":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.6, r * 0.5), c + Vector2(-r * 0.4, -r * 0.3), c + Vector2(r * 0.4, -r * 0.7), c + Vector2(r * 0.6, -r * 0.2), c + Vector2(r * 0.1, r * 0.45)]), col)
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI * 0.5 + i * PI / 5.0
				var rr := r * (0.8 if i % 2 == 0 else 0.35)
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			ci.draw_colored_polygon(pts, col)
		"bolt":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.15, -r * 0.8), c + Vector2(-r * 0.5, r * 0.1), c + Vector2(-r * 0.05, r * 0.1), c + Vector2(-r * 0.2, r * 0.8), c + Vector2(r * 0.5, -r * 0.2), c + Vector2(r * 0.05, -r * 0.2)]), col)
		"moon":
			ci.draw_circle(c, r * 0.6, col)
			ci.draw_circle(c + Vector2(r * 0.3, -r * 0.2), r * 0.5, Color(0.1, 0.12, 0.17, 1.0))
		"book":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.65, -r * 0.5), Vector2(r * 0.6, r * 1.0)), col)
			ci.draw_rect(Rect2(c + Vector2(r * 0.05, -r * 0.5), Vector2(r * 0.6, r * 1.0)), col.darkened(0.2))
		"note":
			ci.draw_circle(c + Vector2(-r * 0.2, r * 0.45), r * 0.3, col)
			ci.draw_line(c + Vector2(r * 0.05, r * 0.4), c + Vector2(r * 0.05, -r * 0.65), col, maxf(r * 0.16, 1.5))
			ci.draw_line(c + Vector2(r * 0.05, -r * 0.65), c + Vector2(r * 0.5, -r * 0.4), col, maxf(r * 0.16, 1.5))
		"heart":
			ci.draw_circle(c + Vector2(-r * 0.27, -r * 0.2), r * 0.32, col)
			ci.draw_circle(c + Vector2(r * 0.27, -r * 0.2), r * 0.32, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.57, -r * 0.05), c + Vector2(r * 0.57, -r * 0.05), c + Vector2(0, r * 0.65)]), col)
		"plate":
			ci.draw_arc(c, r * 0.55, 0.0, TAU, 20, col, maxf(r * 0.16, 1.5))
			ci.draw_circle(c, r * 0.25, col)
		_:
			for i in 3:
				ci.draw_circle(c + Vector2((i - 1) * r * 0.5, 0), r * 0.16, col)
