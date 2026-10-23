class_name UIIdentity
extends RefCounted
## Task 59 (owner: one frame style): every window shares one frame, title size and close button; what is left of each window's identity
## (data/ui_identity.json) is its accent colour (a thin top line, the title badge, button hover) and the badge glyph. The old per-window header
## styles, radii and tints are no longer used. UIDialog._ready calls dress(); HUD panels call skin().

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
	var sb := UITheme.box(Color(UITheme.PANEL, 0.97), 10, Color(str(id["accent"])), 0, 12)
	sb.border_width_top = 3          # the accent is one thin line along the top; the rest of the frame is the same for every window
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
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
	dlg.title_label.add_theme_color_override("font_color", UITheme.TEXT)
	dlg.title_label.add_theme_font_size_override("font_size", UITheme.TITLE)

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
