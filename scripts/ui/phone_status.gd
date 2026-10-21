class_name PhoneStatus
extends Control
## The status bar of the phone: the time on the left; the signal bars (or "No service" when the line is cut off or the phone is dead) and the battery with its
## percentage on the right. Drawn, not made of widgets.

var time_text: String = "08:00"
var signal_bars: int = 4
var battery: int = 100
var service_text: String = ""

func _init() -> void:
	custom_minimum_size = Vector2(0, 28)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_state(t: String, bars: int, bat: int, no_service: String) -> void:
	time_text = t
	signal_bars = bars
	battery = bat
	service_text = no_service
	queue_redraw()

func _draw() -> void:
	var f := ThemeDB.fallback_font
	var white := Color(1, 1, 1, 0.95)
	draw_string(f, Vector2(14, 20), time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, white)
	var x: float = size.x - 14.0
	# battery
	var bw := 26.0
	var by := 8.0
	x -= bw
	draw_rect(Rect2(x, by, bw, 13), white, false, 1.5)
	draw_rect(Rect2(x + bw, by + 4, 3, 5), white)
	var fill: Color = Color("#ff5a5f") if battery < 15 else (Color("#ffd166") if battery < 30 else Color("#5be584"))
	draw_rect(Rect2(x + 2, by + 2, (bw - 4) * clampf(float(battery) / 100.0, 0.0, 1.0), 9), fill)
	var pct: String = "%d%%" % battery
	draw_string(f, Vector2(x - 34, 20), pct, HORIZONTAL_ALIGNMENT_RIGHT, 30, 12, white)
	x -= 46.0
	# signal
	if service_text != "":
		draw_string(f, Vector2(x - 70, 20), "No service", HORIZONTAL_ALIGNMENT_RIGHT, 78, 12, Color("#ff8a8a"))
	else:
		for i in 4:
			var h: float = 4.0 + i * 3.0
			draw_rect(Rect2(x - 22 + i * 6, 21 - h, 4, h), white if i < signal_bars else Color(1, 1, 1, 0.3))
