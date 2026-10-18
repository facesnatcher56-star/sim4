class_name ToastFeed
extends VBoxContainer
## Stacking notification toasts (Events.notification).
const MAX_TOASTS := 6
const KIND_COLORS := {"info": Color("#3fb8af"), "good": Color("#4cc78a"), "warn": Color("#e8913d"), "bad": Color("#e5534b")}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	UIU.connect_ev("notification", push)

func push(text: String, kind: String = "info") -> void:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col: Color = KIND_COLORS.get(kind, KIND_COLORS["info"])
	p.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.PANEL, 0.96), 8, col, 2, 10))
	var l := UIU.make_label(text, 14)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(260, 0)
	p.add_child(l)
	p.modulate.a = 0.0
	add_child(p)
	while get_child_count() > MAX_TOASTS:
		get_child(0).queue_free()
		remove_child(get_child(0))
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(4.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)
