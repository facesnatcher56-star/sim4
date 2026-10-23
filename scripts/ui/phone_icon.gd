class_name PhoneIcon
extends Control
## An app icon of the phone (task 51 polish): a rounded square in the app's colour with a simple drawn glyph, the label under it and an optional badge. Touch-like:
## it shrinks a little while pressed and lights up under the pointer. Emits `tapped`.

signal tapped

var glyph: String = "bubble"
var label: String = ""
var tint: Color = Color("#3ddc84")
var badge: String = ""
var show_label: bool = true
var _down: bool = false
var _hover: bool = false

func _init(p_glyph: String = "bubble", p_label: String = "", p_tint: Color = Color("#3ddc84"), p_badge: String = "") -> void:
	glyph = p_glyph
	label = p_label
	tint = p_tint
	badge = p_badge
	custom_minimum_size = Vector2(78, 92 if show_label else 68)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func():
		_hover = true
		queue_redraw())
	mouse_exited.connect(func():
		_hover = false
		_down = false
		queue_redraw())

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_down = true
		else:
			if _down and Rect2(Vector2.ZERO, size).has_point((ev as InputEventMouseButton).position):
				tapped.emit()
			_down = false
		queue_redraw()
		accept_event()

func _draw() -> void:
	var side: float = 64.0
	var c := Vector2(size.x * 0.5, 4.0 + side * 0.5)
	var sc: float = 0.9 if _down else (1.04 if _hover else 1.0)
	draw_set_transform(c, 0.0, Vector2(sc, sc))
	var r := Rect2(Vector2(-side * 0.5, -side * 0.5), Vector2(side, side))
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint.lightened(0.08) if _hover else tint
	sb.set_corner_radius_all(20)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	draw_style_box(sb, r)
	var shine := StyleBoxFlat.new()          # a soft highlight on the upper half
	shine.bg_color = Color(1, 1, 1, 0.12)
	shine.corner_radius_top_left = 20
	shine.corner_radius_top_right = 20
	draw_style_box(shine, Rect2(r.position, Vector2(side, side * 0.5)))
	_glyph(Vector2.ZERO)
	if badge != "":
		var b := Vector2(side * 0.5 - 4.0, -side * 0.5 + 4.0)
		draw_circle(b, 11.0, Color("#ff3b4a"))
		draw_string(ThemeDB.fallback_font, b + Vector2(-5, 5), badge, HORIZONTAL_ALIGNMENT_CENTER, 10, 13, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if show_label:
		draw_string(ThemeDB.fallback_font, Vector2(0, 4.0 + side + 18.0), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color("#f1f5fa"))

func _glyph(o: Vector2) -> void:
	var w := Color.WHITE
	match glyph:
		"bubble":
			draw_style_box(_fill(w, 9), Rect2(o + Vector2(-18, -16), Vector2(36, 26)))
			draw_colored_polygon(PackedVector2Array([o + Vector2(-8, 9), o + Vector2(-14, 20), o + Vector2(2, 9)]), w)
		"person":
			draw_circle(o + Vector2(0, -8), 8.0, w)
			draw_style_box(_fill(w, 12), Rect2(o + Vector2(-15, 4), Vector2(30, 16)))
		"case":
			draw_style_box(_fill(w, 5), Rect2(o + Vector2(-19, -8), Vector2(38, 26)))
			draw_arc(o + Vector2(0, -10), 8.0, PI, TAU, 12, w, 3.0)
			draw_rect(Rect2(o + Vector2(-19, 3), Vector2(38, 2)), tint.darkened(0.3))
		"coin":
			draw_circle(o, 19.0, w)
			draw_string(ThemeDB.fallback_font, o + Vector2(-8, 9), "$", HORIZONTAL_ALIGNMENT_CENTER, 16, 26, tint.darkened(0.25))
		"news":
			draw_style_box(_fill(w, 4), Rect2(o + Vector2(-17, -18), Vector2(34, 36)))
			for i in 3:
				draw_rect(Rect2(o + Vector2(-12, -12 + i * 10), Vector2(24 if i != 0 else 14, 4)), tint.darkened(0.25))
		"heart":
			draw_circle(o + Vector2(-8, -6), 9.0, w)
			draw_circle(o + Vector2(8, -6), 9.0, w)
			draw_colored_polygon(PackedVector2Array([o + Vector2(-16, -2), o + Vector2(16, -2), o + Vector2(0, 17)]), w)
		"pin":
			draw_circle(o + Vector2(0, -6), 12.0, w)
			draw_colored_polygon(PackedVector2Array([o + Vector2(-10, 1), o + Vector2(10, 1), o + Vector2(0, 19)]), w)
			draw_circle(o + Vector2(0, -6), 5.0, tint.darkened(0.25))
		"calendar":
			draw_style_box(_fill(w, 5), Rect2(o + Vector2(-17, -15), Vector2(34, 33)))
			draw_rect(Rect2(o + Vector2(-17, -15), Vector2(34, 9)), tint.darkened(0.3))
			draw_string(ThemeDB.fallback_font, o + Vector2(-12, 14), str(SysUtil.day() % 100), HORIZONTAL_ALIGNMENT_CENTER, 24, 18, tint.darkened(0.35))
		"cart":
			draw_style_box(_fill(w, 4), Rect2(o + Vector2(-16, -6), Vector2(32, 18)))
			draw_arc(o + Vector2(-8, 18), 3.0, 0, TAU, 8, w, 3.0)
			draw_arc(o + Vector2(8, 18), 3.0, 0, TAU, 8, w, 3.0)
		_:
			draw_circle(o, 14.0, w)

func _fill(c: Color, r: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(r)
	return s
