class_name UITheme
extends RefCounted
## One cohesive generated Theme (dark slate + teal accent).

## Colours come from the current look (data/looks.json "ui"; reference = the values below). They are static vars so a look switch re-colours
## everything built afterwards; build() re-reads them, main.gd re-themes the HUD / menus on Looks.bus.changed.
static var BG := Color("#1b2430")
static var PANEL := Color("#232f3e")
static var PANEL_HI := Color("#2d3c4f")
static var ACCENT := Color("#3fb8af")
static var TEXT := Color("#e8eef4")
static var MUTED := Color("#93a3b5")

## Semantic colours (good / warn / bad / coin ...): custom-drawn and per-label UI asks for these instead of hard-coding a colour, so the look decides
## how loud they are (the grounded look uses muted sage / ochre / brick with contrast >= 4.5:1 on the panels). The literals below ARE today's
## (reference) values; data/looks.json "ui.sem" overrides them per look. tests/ui_tone_test.gd keeps literals out of the other UI files.
const SEM_DEFAULT := {"good": "#4cc78a", "good_text": "#7ed6a5", "info": "#3fb8af", "warn": "#e8913d", "bad": "#e5534b", "coin": "#f2c94c", "coin_hi": "#ffe38a",
	"coin_bg": "#4a3d12", "romance": "#ee86a6", "trust": "#35a7b0", "group": "#8f6bf0", "low_text": "#ff8a80", "error": "#e07a5f", "caution": "#d9a441",
	"friendly": "#4cc78a", "funny": "#f2c94c", "deep": "#35a7b0", "mean": "#e5534b", "bubble": "#ffffff", "bubble_text": "#1d2630", "bubble_edge": "#333340",
	"ring_back": "#0f141f", "map_bg": "#17202a", "card_bg": "#1c2430"}
static var _sem: Dictionary = {}
static var _tone_sat := 1.0
static var _tone_val := 1.0

static func sem(key: String) -> Color:
	if _sem.is_empty():
		sync_look()
	return _sem.get(key, Color.MAGENTA)

## Mutes a colour by the look's UI tone (mood / need colours): identity for the reference look.
static func tone(c: Color) -> Color:
	if _sem.is_empty():
		sync_look()
	if _tone_sat == 1.0 and _tone_val == 1.0:
		return c
	return Color.from_hsv(c.h, clampf(c.s * _tone_sat, 0.0, 1.0), clampf(c.v * _tone_val, 0.0, 1.0), c.a)

## WCAG contrast ratio of two colours (1 .. 21).
static func contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

static func _lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)

## Re-read the colours of the current look.
static func sync_look() -> void:
	_sem.clear()
	var look_sem: Dictionary = Looks.ui_dict("sem")
	for k in SEM_DEFAULT:
		_sem[k] = Color(str(look_sem.get(k, SEM_DEFAULT[k])))
	var tn: Dictionary = Looks.ui_dict("tone")
	_tone_sat = float(tn.get("sat", 1.0))
	_tone_val = float(tn.get("val", 1.0))
	BG = Looks.ui_col("bg", Color("#1b2430"))
	PANEL = Looks.ui_col("panel", Color("#232f3e"))
	PANEL_HI = Looks.ui_col("panel_hi", Color("#2d3c4f"))
	ACCENT = Looks.ui_col("accent", Color("#3fb8af"))
	TEXT = Looks.ui_col("text", Color("#e8eef4"))
	MUTED = Looks.ui_col("muted", Color("#93a3b5"))

static func box(bg: Color, radius: int = 8, border: Color = Color(0, 0, 0, 0), bw: int = 0, pad: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(maxi(1, radius + Looks.ui_radius(10) - 10))      # sober looks have squarer corners
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s

static func build() -> Theme:
	sync_look()
	var t := Theme.new()
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(Color(PANEL, 0.94), 10, Color(1, 1, 1, 0.07), 1, 10))
	t.set_stylebox("panel", "Panel", box(Color(PANEL, 0.94), 10, Color(1, 1, 1, 0.07), 1, 10))
	for c in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", c, box(PANEL_HI, 6))
		t.set_stylebox("hover", c, box(PANEL_HI.lightened(0.15), 6, ACCENT, 1))
		t.set_stylebox("pressed", c, box(ACCENT.darkened(0.35), 6, ACCENT, 1))
		t.set_stylebox("disabled", c, box(PANEL.darkened(0.1), 6))
		t.set_stylebox("focus", c, box(Color(0, 0, 0, 0), 6, ACCENT, 1))
		t.set_color("font_color", c, TEXT)
		t.set_color("font_disabled_color", c, Color(MUTED, 0.5))
		t.set_color("font_hover_color", c, Color.WHITE)
	t.set_stylebox("normal", "LineEdit", box(BG, 6, Color(1, 1, 1, 0.12), 1))
	t.set_stylebox("focus", "LineEdit", box(BG, 6, ACCENT, 1))
	t.set_stylebox("background", "ProgressBar", box(BG, 4, Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, 4, Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("panel", "TooltipPanel", box(Color("#10161d"), 6, ACCENT, 1))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("panel", "TabContainer", box(Color(0, 0, 0, 0.12), 6))
	t.set_stylebox("tab_selected", "TabContainer", box(PANEL_HI, 6))
	t.set_stylebox("tab_unselected", "TabContainer", box(PANEL, 6))
	t.set_stylebox("tab_hovered", "TabContainer", box(PANEL_HI.darkened(0.1), 6))
	t.set_color("font_selected_color", "TabContainer", TEXT)
	t.set_color("font_unselected_color", "TabContainer", MUTED)
	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("separation", "HBoxContainer", 6)
	if GameSettings.high_contrast():
		_high_contrast(t)
	return t

## Accessibility: opaque panels, strong borders, pure-white text.
static func _high_contrast(t: Theme) -> void:
	var edge := Color(1, 1, 1, 0.9)
	for c in ["PanelContainer", "Panel"]:
		t.set_stylebox("panel", c, box(Color(BG, 1.0), 10, edge, 2, 10))
	for c in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", c, box(Color("#0f1620"), 6, edge, 2))
		t.set_stylebox("hover", c, box(Color("#26364a"), 6, Color.WHITE, 2))
		t.set_stylebox("pressed", c, box(ACCENT.darkened(0.3), 6, Color.WHITE, 2))
		t.set_color("font_color", c, Color.WHITE)
	t.set_color("font_color", "Label", Color.WHITE)
	t.set_stylebox("normal", "LineEdit", box(Color.BLACK, 6, edge, 2))
