class_name PhoneNav
extends Control
## One button of the phone's navigation bar (back triangle, home circle, recents square). Drawn; shrinks while pressed. Emits `tapped`.

signal tapped

var kind: String = "home"
var _down: bool = false
var _hover: bool = false

func _init(p_kind: String = "home") -> void:
	kind = p_kind
	custom_minimum_size = Vector2(70, 34)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	var c := size * 0.5
	var col := Color(1, 1, 1, 1.0 if _hover else 0.8)
	if _down:
		draw_circle(c, 17.0, Color(1, 1, 1, 0.18))
	match kind:
		"back":
			draw_colored_polygon(PackedVector2Array([c + Vector2(6, -8), c + Vector2(6, 8), c + Vector2(-7, 0)]), col)
		"home":
			draw_arc(c, 8.0, 0, TAU, 20, col, 2.5)
		_:
			draw_rect(Rect2(c + Vector2(-7, -7), Vector2(14, 14)), col, false, 2.5)
