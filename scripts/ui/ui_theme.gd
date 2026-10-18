class_name UITheme
extends RefCounted
## One cohesive generated Theme (dark slate + teal accent).

const BG := Color("#1b2430")
const PANEL := Color("#232f3e")
const PANEL_HI := Color("#2d3c4f")
const ACCENT := Color("#3fb8af")
const TEXT := Color("#e8eef4")
const MUTED := Color("#93a3b5")

static func box(bg: Color, radius: int = 8, border: Color = Color(0, 0, 0, 0), bw: int = 0, pad: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s

static func build() -> Theme:
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
	return t
