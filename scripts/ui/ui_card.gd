class_name UICard
extends RefCounted
## Cards take the colour of the window they sit in (set by UIDialog.refresh).
static var accent: Color = Color("#3fb8af")
## Building blocks of the panel style in docs/UI_STYLE.md: scan first, read second. A CARD has a title (and a badge), a row of labelled CHIPS for the key
## numbers, a row of requirement chips (check / cross) and ONE primary action with its reason underneath; flavour goes into the tooltip.
##   var inner := UICard.card(body, width, "Bedsit at Elm Court", "YOU LIVE HERE", "A room in somebody else's house ...")
##   UICard.chips(inner, [["Rent", "25/wk"], ["Bills", "10/wk"], ["Deposit", "35"]])
##   UICard.reqs(inner, [["Income 500/wk (you 0)", false], ["No arrears", true]])
##   UICard.action(inner, "Move here", func(): ..., enabled, "why it is off")

const OK := Color("#4cc78a")
const NO := Color("#e5534b")
const WARN := Color("#f2c94c")

## A rounded panel inside `parent`; returns the VBox to fill.
static func card(parent: Control, width: float, title: String, badge: String = "", tip: String = "") -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.box(UITheme.PANEL_HI, 8, Color(1, 1, 1, 0.05), 1, 8))
	pc.custom_minimum_size = Vector2(width, 0)
	pc.tooltip_text = tip
	parent.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	pc.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UIU.make_label(title, 15, UITheme.TEXT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART          # a long title wraps instead of widening the window
	t.custom_minimum_size = Vector2(60, 0)
	head.add_child(t)
	if badge != "":
		head.add_child(badge_label(badge))
	return v

static func badge_label(text: String, color: Color = Color("#3fb8af")) -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.box(color.darkened(0.45), 6, color, 1, 4))
	pc.add_child(UIU.make_label(text, 11, color.lightened(0.5)))
	return pc

## A row of small labelled numbers: [["Rent", "25/wk"], ...]. An entry may carry a third element, a colour, for gain / loss only.
static func chips(box: Control, items: Array) -> HFlowContainer:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("separation", 6)
	box.add_child(h)
	for it in items:
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UITheme.box(UITheme.PANEL, 6, Color(0, 0, 0, 0), 0, 4))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		pc.add_child(hb)
		hb.add_child(UIU.make_label(str(it[0]), 11, UITheme.MUTED))
		hb.add_child(UIU.make_label(str(it[1]), 13, it[2] if it.size() > 2 else UITheme.TEXT))
		h.add_child(pc)
	return h

## Requirement chips: [["Income 500/wk (you 0)", false], ...] drawn with a tick or a cross.
static func reqs(box: Control, items: Array) -> HFlowContainer:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("separation", 6)
	box.add_child(h)
	for it in items:
		var ok: bool = bool(it[1])
		var l := UIU.make_label(("✓ " if ok else "✗ ") + str(it[0]), 12, OK if ok else NO)
		h.add_child(l)
	return h

## One primary button, right aligned; when it is off the reason shows underneath (and in the tooltip).
static func action(box: Control, text: String, fn: Callable, enabled: bool = true, reason: String = "") -> Button:
	var h := HBoxContainer.new()
	box.add_child(h)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(120, 28)
	if enabled:
		b.add_theme_stylebox_override("normal", UITheme.box(accent.darkened(0.45), 6, accent, 1, 6))
		b.add_theme_stylebox_override("hover", UITheme.box(accent.darkened(0.25), 6, accent, 1, 6))
	b.tooltip_text = reason
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.pressed.connect(fn)
	h.add_child(b)
	if not enabled and reason != "":
		var r := UIU.make_label(reason, 12, WARN)
		r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(r)
	return b

static func note(box: Control, text: String) -> Label:
	var l := UIU.make_label(text, 12, UITheme.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	return l
