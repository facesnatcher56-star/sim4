class_name NeedIcon
extends Control
## Task 59: the small glyph over a need's mini bar in the compact person panel (fork and plate, bolt, drop ...), full name on hover. A need that
## is low pulses in the warning colour, so it reads without the number and without colour alone.

const LOW := 0.2
var glyph := "plate"
var ratio := 1.0
var _t := 0.0


func _init(nid: String, label: String) -> void:
	glyph = str(UIIcons.NEED.get(nid, "plate"))
	tooltip_text = label
	custom_minimum_size = Vector2(36, 20)


func set_ratio(r: float) -> void:
	var was_low := ratio < LOW
	ratio = r
	if (r < LOW) != was_low:
		queue_redraw()


func _process(delta: float) -> void:
	if ratio >= LOW:
		if modulate.a != 1.0:
			modulate.a = 1.0
		return
	_t += delta
	modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 5.0))


func _draw() -> void:
	var col: Color = UITheme.sem("low_text") if ratio < LOW else UITheme.MUTED
	UIIcons.draw(self, glyph, size * 0.5, minf(size.x, size.y) * 0.5, col)
