class_name FaceIcon
extends Control
## Tiny procedural face: colored head + mood mouth. Used for portraits and mood icon.
var color := Color("#9aa7b4"):
	set(v):
		color = v
		queue_redraw()
var mood := "neutral":
	set(v):
		mood = v
		queue_redraw()

func _init() -> void:
	custom_minimum_size = Vector2(40, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 2.0
	draw_circle(c, r, color)
	var dark := Color(0, 0, 0, 0.75)
	draw_circle(c + Vector2(-r * 0.33, -r * 0.15), r * 0.1, dark)
	draw_circle(c + Vector2(r * 0.33, -r * 0.15), r * 0.1, dark)
	var my := c.y + r * 0.35
	match mood:
		"happy", "energized", "flirty":
			draw_arc(Vector2(c.x, my - r * 0.25), r * 0.4, 0.3, PI - 0.3, 12, dark, 2.0)
		"sad", "uncomfortable":
			draw_arc(Vector2(c.x, my + r * 0.3), r * 0.35, PI + 0.4, TAU - 0.4, 12, dark, 2.0)
		"angry", "tense":
			draw_line(c + Vector2(-r * 0.4, -r * 0.4), c + Vector2(-r * 0.15, -r * 0.28), dark, 2.0)
			draw_line(c + Vector2(r * 0.4, -r * 0.4), c + Vector2(r * 0.15, -r * 0.28), dark, 2.0)
			draw_line(Vector2(c.x - r * 0.3, my), Vector2(c.x + r * 0.3, my), dark, 2.0)
		_:
			draw_line(Vector2(c.x - r * 0.3, my), Vector2(c.x + r * 0.3, my), dark, 2.0)
