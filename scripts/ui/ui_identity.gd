class_name UIIdentity
extends RefCounted
## Every window its own look (data/ui_identity.json): an accent colour, a glyph badge in the title, a header style (coloured top edge / left edge / frame /
## centred title), a corner radius and a tint of the panel. UIDialog._ready calls dress(); the HUD top bar buttons get a coloured underline (accent_button).

static var _themes: Dictionary = {}

static func table() -> Dictionary:
	return SysUtil.table("ui_identity")

static func of(dlg) -> Dictionary:
	var d: Dictionary = (table().get("default", {}) as Dictionary).duplicate()
	var name: String = str(dlg.get_script().get_global_name()) if dlg.get_script() != null else ""
	d.merge((table().get("dialogs", {}) as Dictionary).get(name, {}), true)
	return d

## A small Theme that overrides only the buttons with the accent (hover border, pressed fill); the rest falls through to the game theme.
static func theme_for(accent: Color) -> Theme:
	var key: String = accent.to_html(false)
	if _themes.has(key):
		return _themes[key]
	var t := Theme.new()
	for c in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("hover", c, UITheme.box(UITheme.PANEL_HI.lightened(0.12), 6, accent, 1))
		t.set_stylebox("pressed", c, UITheme.box(accent.darkened(0.4), 6, accent, 1))
		t.set_stylebox("focus", c, UITheme.box(Color(0, 0, 0, 0), 6, accent, 1))
	_themes[key] = t
	return t

static func panel_box(id: Dictionary) -> StyleBoxFlat:
	var accent := Color(str(id["accent"]))
	var bg: Color = UITheme.PANEL.lerp(accent, float(id["tint"]))
	var sb := UITheme.box(Color(bg, 0.96), int(id["radius"]), Color(accent, 0.55), 1, 12)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
	match str(id["header"]):
		"band":
			sb.border_color = accent
			sb.border_width_top = 6
		"ribbon":
			sb.border_color = accent
			sb.border_width_left = 7
			sb.content_margin_left = 14
		"frame":
			sb.border_color = accent
			sb.set_border_width_all(2)
		_:
			sb.border_color = Color(accent, 0.4)
	return sb

## Called at the end of UIDialog._ready (the title label and the dialog's panel exist).
static func dress(dlg) -> void:
	var id: Dictionary = of(dlg)
	var accent := Color(str(id["accent"]))
	dlg.accent_color = accent
	dlg.add_theme_stylebox_override("panel", panel_box(id))
	dlg.theme = theme_for(accent)
	var head: Node = dlg.title_label.get_parent()
	var badge := Label.new()
	badge.text = str(id["glyph"])
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.custom_minimum_size = Vector2(24, 24)
	badge.add_theme_font_size_override("font_size", 16)
	badge.add_theme_color_override("font_color", Color("#10161d"))
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", UITheme.box(accent, 14, Color(0, 0, 0, 0), 0, 2))
	holder.add_child(badge)
	head.add_child(holder)
	head.move_child(holder, 0)
	dlg.title_label.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.35))
	if str(id["header"]) == "plain":
		dlg.title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dlg.title_label.add_theme_font_size_override("font_size", 24)
	elif str(id["header"]) == "frame":
		dlg.title_label.add_theme_font_size_override("font_size", 19)
	else:
		dlg.title_label.add_theme_font_size_override("font_size", 21)

## A coloured underline for a top-bar button.
static func accent_button(b: Button, accent: Color) -> void:
	for st in ["normal", "hover", "pressed"]:
		var base: Color = UITheme.PANEL_HI if st != "pressed" else accent.darkened(0.45)
		var sb := UITheme.box(base.lightened(0.1) if st == "hover" else base, 6, accent, 0)
		sb.border_width_bottom = 3
		sb.border_color = accent
		b.add_theme_stylebox_override(st, sb)

## Dress a small HUD panel (checklist, tips, banners) in an accent and a header style without the dialog machinery.
static func skin(panel: PanelContainer, accent_hex: String, header: String, radius: int) -> void:
	panel.add_theme_stylebox_override("panel", panel_box({"accent": accent_hex, "header": header, "radius": radius, "tint": 0.06}))
	panel.theme = theme_for(Color(accent_hex))
