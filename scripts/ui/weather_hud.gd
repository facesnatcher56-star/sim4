class_name WeatherHud
extends HBoxContainer
## Top-bar widget: weather icon + temperature + condition, season icon + date. Tooltip = 2-day forecast and the next holiday.
## Hud adds one instance to its top bar. Icons are drawn in code (no assets). Updates on Clock minutes and weather_changed.

const ICON_SIZE := Vector2(30, 30)

var wx_icon: WxIcon
var temp_label: Label
var cond_label: Label
var season_icon: WxIcon
var date_label: Label
var _last_key: String = ""

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(VSeparator.new())
	wx_icon = WxIcon.new()
	wx_icon.custom_minimum_size = ICON_SIZE
	add_child(wx_icon)
	temp_label = UIU.make_label("--", 18, UITheme.ACCENT)
	temp_label.custom_minimum_size = Vector2(56, 0)
	add_child(temp_label)
	cond_label = UIU.make_label("", 14)
	cond_label.custom_minimum_size = Vector2(92, 0)
	add_child(cond_label)
	add_child(VSeparator.new())
	season_icon = WxIcon.new()
	season_icon.custom_minimum_size = ICON_SIZE
	add_child(season_icon)
	date_label = UIU.make_label("", 15)
	add_child(date_label)
	for c in get_children():
		if c is Control and not (c is VSeparator):
			(c as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	var clk = SimEnv.clock()
	if clk != null:
		clk.minute_passed.connect(func(_m): refresh())
	var ev = SimEnv.events()
	if ev != null:
		ev.game_event.connect(func(n, _p): if n == "weather_changed" or n == "season_changed": refresh(true))
	refresh(true)

func _make_custom_tooltip(for_text: String) -> Object:
	var pc := PanelContainer.new()
	var l := Label.new()
	l.text = for_text
	pc.add_child(l)
	return pc

func refresh(force: bool = false) -> void:
	if wx_icon == null:
		return
	var wid: String = Weather.current()
	var temp: String = Weather.temp_string()
	var date: String = Seasons.short_date()
	var key: String = "%s|%s|%s|%s" % [wid, temp, date, str(Weather.is_dark())]
	if key == _last_key and not force:
		return
	_last_key = key
	wx_icon.kind = Weather.icon(wid)
	wx_icon.night = Weather.is_dark()
	wx_icon.queue_redraw()
	temp_label.text = temp
	cond_label.text = Weather.label(wid)
	season_icon.kind = "season_" + Seasons.current()
	season_icon.tint = Seasons.icon_color()
	season_icon.queue_redraw()
	date_label.text = "%s, Y%d" % [date, Seasons.year()]
	tooltip_text = tooltip()

func tooltip() -> String:
	var lines: Array = ["%s - %s, feels like %d°C" % [Weather.label(), Weather.temp_string(), int(round(Weather.feels_like()))],
		"%s (day %d of %d), year %d" % [Seasons.current_label(), Seasons.day_of_season(), Seasons.length(), Seasons.year()], "", "Forecast:"]
	for d in Weather.forecast(2):
		lines.append("  %s: %s  %d / %d°C" % [Seasons.weekday_name(int(d["day"])), str(d["label"]), int(round(float(d["hi"]))), int(round(float(d["lo"])))])
	var h: Dictionary = Holidays.today()
	if not h.is_empty():
		lines.append("")
		lines.append("Today: " + str(h.get("label", "")))
	else:
		var nx: Dictionary = Holidays.next_after(int(SimEnv.clock().day()))
		if not nx.is_empty():
			lines.append("")
			lines.append("Next holiday: %s (%s)" % [str(nx.get("label", "")), Seasons.short_date(int(nx["day"]))])
	return "\n".join(lines)

## A tiny icon painter. kind: sun cloud rain storm fog snow heat cold wind | season_spring season_summer season_autumn season_winter
class WxIcon:
	extends Control
	var kind: String = "sun"
	var night: bool = false
	var tint: Color = Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.5
		match kind:
			"sun":
				if night:
					_moon(c, r)
				else:
					_sun(c, r * 0.5, Color("#f6c945"))
			"heat":
				_sun(c, r * 0.5, Color("#f08a2c"))
				for i in 3:
					draw_line(Vector2(c.x - r * 0.8 + i * r * 0.8, c.y + r * 0.95), Vector2(c.x - r * 0.8 + i * r * 0.8, c.y + r * 0.75), Color("#f08a2c"), 1.6)
			"cloud":
				_cloud(c + Vector2(0, -r * 0.05), r, Color("#cfd6de"))
			"rain":
				_cloud(c + Vector2(0, -r * 0.25), r * 0.95, Color("#aab4c0"))
				for i in 3:
					var x: float = c.x - r * 0.45 + i * r * 0.45
					draw_line(Vector2(x, c.y + r * 0.35), Vector2(x - 3, c.y + r * 0.85), Color("#5fa8f0"), 2.0)
			"storm":
				_cloud(c + Vector2(0, -r * 0.25), r * 0.95, Color("#7d8794"))
				var bolt := PackedVector2Array([c + Vector2(r * 0.1, r * 0.1), c + Vector2(-r * 0.25, r * 0.55), c + Vector2(0, r * 0.55), c + Vector2(-r * 0.15, r * 0.95), c + Vector2(r * 0.35, r * 0.4), c + Vector2(r * 0.08, r * 0.4)])
				draw_colored_polygon(bolt, Color("#ffd23f"))
			"fog":
				for i in 4:
					var y: float = c.y - r * 0.55 + i * r * 0.38
					draw_line(Vector2(c.x - r * (0.8 - 0.15 * (i % 2)), y), Vector2(c.x + r * (0.8 - 0.15 * ((i + 1) % 2)), y), Color("#b9c1c9"), 2.4)
			"snow":
				_cloud(c + Vector2(0, -r * 0.25), r * 0.95, Color("#c3ccd6"))
				for i in 3:
					draw_circle(Vector2(c.x - r * 0.45 + i * r * 0.45, c.y + r * 0.65), 2.2, Color.WHITE)
			"cold", "season_winter":
				_flake(c, r * 0.85, Color("#9cd2ff") if kind == "cold" else tint)
			"wind":
				for i in 3:
					var y2: float = c.y - r * 0.5 + i * r * 0.5
					draw_arc(Vector2(c.x - r * 0.1 + (i % 2) * r * 0.2, y2), r * 0.32, PI, TAU + PI * 0.7, 14, Color("#bcd4ea"), 2.0)
			"season_spring":
				draw_line(c + Vector2(0, r * 0.8), c + Vector2(0, -r * 0.1), Color("#4f9e4a"), 2.4)
				draw_colored_polygon(_leaf_poly(c + Vector2(0, -r * 0.05), r * 0.8, -0.5), tint)
				draw_colored_polygon(_leaf_poly(c + Vector2(0, r * 0.3), r * 0.7, 0.5 + PI), tint)
			"season_summer":
				_sun(c, r * 0.5, tint)
			"season_autumn":
				draw_colored_polygon(_leaf_poly(c, r * 1.1, -0.9), tint)
				draw_line(c + Vector2(-r * 0.5, r * 0.5), c + Vector2(r * 0.4, -r * 0.4), Color("#7a3d12"), 1.6)
			_:
				draw_circle(c, r * 0.4, Color.GRAY)

	func _sun(c: Vector2, rad: float, col: Color) -> void:
		draw_circle(c, rad, col)
		for i in 8:
			var a: float = TAU * float(i) / 8.0
			draw_line(c + Vector2(cos(a), sin(a)) * (rad + 2.5), c + Vector2(cos(a), sin(a)) * (rad + 6.0), col, 2.0)

	func _moon(c: Vector2, r: float) -> void:
		draw_circle(c, r * 0.62, Color("#e6e9f2"))
		draw_circle(c + Vector2(r * 0.3, -r * 0.2), r * 0.55, Color(0.13, 0.16, 0.22, 1.0))

	func _cloud(c: Vector2, r: float, col: Color) -> void:
		draw_circle(c + Vector2(-r * 0.38, r * 0.1), r * 0.34, col)
		draw_circle(c + Vector2(0.0, -r * 0.1), r * 0.44, col)
		draw_circle(c + Vector2(r * 0.4, r * 0.12), r * 0.32, col)
		draw_rect(Rect2(c + Vector2(-r * 0.38, r * 0.1), Vector2(r * 0.78, r * 0.34)), col)

	func _flake(c: Vector2, r: float, col: Color) -> void:
		for i in 3:
			var a: float = PI * float(i) / 3.0
			var d := Vector2(cos(a), sin(a)) * r
			draw_line(c - d, c + d, col, 2.0)
		draw_circle(c, 2.0, col)

	func _leaf_poly(c: Vector2, r: float, rot: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 13:
			var t: float = float(i) / 12.0
			pts.append(Vector2(sin(PI * t) * r * 0.42, (t - 0.5) * r))
		for i2 in 13:
			var t2: float = 1.0 - float(i2) / 12.0
			pts.append(Vector2(-sin(PI * t2) * r * 0.42, (t2 - 0.5) * r))
		var out := PackedVector2Array()
		for pt in pts:
			out.append(c + pt.rotated(rot))
		return out
