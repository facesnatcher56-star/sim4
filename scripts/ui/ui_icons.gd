class_name UIIcons
extends RefCounted
## Task 59: small vector glyphs for the HUD (top-bar buttons, needs, click-menu groups), drawn with the CanvasItem API like ProgressIcons (no textures).
## `draw(ci, name, c, r, col)` paints into radius `r` around `c`; names ProgressIcons knows (drop, bolt, star, heart, plate, book, note, ...) fall through to it.

const NEED := {"hunger": "plate", "energy": "bolt", "bladder": "drop", "hygiene": "bubbles", "social": "talk", "fun": "star", "comfort": "seat"}
const NEED_LABEL := {"hunger": "Hunger", "energy": "Energy", "bladder": "Bladder", "hygiene": "Hygiene", "social": "Social", "fun": "Fun", "comfort": "Comfort"}
const GROUP := {"Friendly": "talk", "Funny": "star", "Romantic": "heart", "Deep": "book", "Group": "people", "Mean": "bolt", "Physical": "fist",
	"Social": "people", "Food": "plate", "Rest": "moon", "Hygiene": "bubbles", "Fun": "star", "Skills": "book", "Chores": "broom", "Vehicles": "car",
	"Town": "house", "Call for help": "phone", "Shop": "coin", "Ask": "talk"}


static func draw(ci: CanvasItem, name: String, c: Vector2, r: float, col: Color) -> void:
	var w := maxf(r * 0.16, 1.5)
	match name:
		"map":
			var pts := PackedVector2Array([c + Vector2(-r * 0.8, -r * 0.5), c + Vector2(-r * 0.27, -r * 0.75), c + Vector2(r * 0.27, -r * 0.5), c + Vector2(r * 0.8, -r * 0.75),
				c + Vector2(r * 0.8, r * 0.5), c + Vector2(r * 0.27, r * 0.75), c + Vector2(-r * 0.27, r * 0.5), c + Vector2(-r * 0.8, r * 0.75), c + Vector2(-r * 0.8, -r * 0.5)])
			ci.draw_polyline(pts, col, w)
			ci.draw_line(c + Vector2(-r * 0.27, -r * 0.75), c + Vector2(-r * 0.27, r * 0.5), col, w * 0.7)
			ci.draw_line(c + Vector2(r * 0.27, -r * 0.5), c + Vector2(r * 0.27, r * 0.75), col, w * 0.7)
		"coin":
			ci.draw_arc(c, r * 0.7, 0.0, TAU, 24, col, w)
			ci.draw_line(c + Vector2(0, -r * 0.4), c + Vector2(0, r * 0.4), col, w)
		"bank":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.85, -r * 0.3), c + Vector2(0, -r * 0.85), c + Vector2(r * 0.85, -r * 0.3)]), col)
			for i in 3:
				var x := (i - 1) * r * 0.55
				ci.draw_line(c + Vector2(x, -r * 0.2), c + Vector2(x, r * 0.55), col, w)
			ci.draw_line(c + Vector2(-r * 0.85, r * 0.7), c + Vector2(r * 0.85, r * 0.7), col, w * 1.2)
		"phone":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.42, -r * 0.8), Vector2(r * 0.84, r * 1.6)), col, false, w)
			ci.draw_circle(c + Vector2(0, r * 0.55), r * 0.1, col)
		"house":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.75, -r * 0.05), c + Vector2(0, -r * 0.75), c + Vector2(r * 0.75, -r * 0.05)]), col, w)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.55, -r * 0.1), Vector2(r * 1.1, r * 0.85)), col, false, w)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.15, r * 0.3), Vector2(r * 0.3, r * 0.45)), col)
		"hammer":
			ci.draw_line(c + Vector2(-r * 0.55, r * 0.75), c + Vector2(r * 0.3, -r * 0.1), col, w * 1.3)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.0, -r * 0.55), c + Vector2(r * 0.35, -r * 0.85), c + Vector2(r * 0.85, -r * 0.35), c + Vector2(r * 0.55, -r * 0.05)]), col)
		"menu":
			for i in 3:
				var y := (i - 1) * r * 0.5
				ci.draw_line(c + Vector2(-r * 0.7, y), c + Vector2(r * 0.7, y), col, w * 1.2)
		"bubbles":
			ci.draw_arc(c + Vector2(-r * 0.25, r * 0.2), r * 0.4, 0.0, TAU, 16, col, w)
			ci.draw_arc(c + Vector2(r * 0.35, -r * 0.35), r * 0.28, 0.0, TAU, 14, col, w)
			ci.draw_circle(c + Vector2(r * 0.45, r * 0.45), r * 0.12, col)
		"talk":
			ci.draw_arc(c + Vector2(0, -r * 0.1), r * 0.62, 0.0, TAU, 20, col, w)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.4, r * 0.35), c + Vector2(-r * 0.6, r * 0.85), c + Vector2(-r * 0.05, r * 0.5)]), col)
		"seat":
			ci.draw_line(c + Vector2(-r * 0.5, -r * 0.7), c + Vector2(-r * 0.5, r * 0.75), col, w)
			ci.draw_line(c + Vector2(-r * 0.5, r * 0.1), c + Vector2(r * 0.55, r * 0.1), col, w * 1.3)
			ci.draw_line(c + Vector2(r * 0.55, r * 0.1), c + Vector2(r * 0.55, r * 0.75), col, w)
		"people":
			for x in [-0.35, 0.35]:
				ci.draw_circle(c + Vector2(r * x, -r * 0.4), r * 0.22, col)
				ci.draw_arc(c + Vector2(r * x, r * 0.55), r * 0.38, PI, TAU, 10, col, w)
		"fist":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.5, -r * 0.45), Vector2(r * 1.0, r * 0.75)), col)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.3, r * 0.3), Vector2(r * 0.6, r * 0.45)), col.darkened(0.15))
		"broom":
			ci.draw_line(c + Vector2(r * 0.6, -r * 0.8), c + Vector2(-r * 0.1, r * 0.2), col, w)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.3, 0), c + Vector2(r * 0.15, r * 0.35), c + Vector2(-r * 0.25, r * 0.85), c + Vector2(-r * 0.8, r * 0.45)]), col)
		"car":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.8, -r * 0.1), Vector2(r * 1.6, r * 0.5)), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.45, -r * 0.1), c + Vector2(-r * 0.25, -r * 0.5), c + Vector2(r * 0.3, -r * 0.5), c + Vector2(r * 0.5, -r * 0.1)]), col)
			for x in [-0.45, 0.45]:
				ci.draw_circle(c + Vector2(r * x, r * 0.45), r * 0.2, col.darkened(0.3))
		_:
			ProgressIcons.draw(ci, name, c, r, col)


## A round badge with a glyph (toasts, window titles): the colour is the meaning (good / info / warn / bad), the glyph the kind.
class Badge extends Control:
	var glyph := ""
	var col := Color.WHITE

	func _init(p_glyph: String, p_col: Color, d: float = 22.0) -> void:
		glyph = p_glyph
		col = p_col
		custom_minimum_size = Vector2(d, d)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		draw_circle(size * 0.5, r, col)
		UIIcons.draw(self, glyph, size * 0.5, r * 0.62, UITheme.BG)


## A flat HUD button that shows a glyph instead of text; the name and key hint are the tooltip.
class IconButton extends Button:
	var glyph := ""
	var tint := Color.WHITE

	func _init(p_glyph: String = "", tip: String = "", p_tint: Color = Color.WHITE) -> void:
		glyph = p_glyph
		tooltip_text = tip
		tint = p_tint
		custom_minimum_size = Vector2(38, 32)
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		var col: Color = tint if not is_hovered() else tint.lightened(0.25)
		UIIcons.draw(self, glyph, size * 0.5, minf(size.x, size.y) * 0.34, col)
