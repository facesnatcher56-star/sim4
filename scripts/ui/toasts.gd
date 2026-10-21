class_name ToastFeed
extends VBoxContainer
## Stacking notification toasts (Events.notification), top-centre under the bar. Click a toast to dismiss it.
## ToastPolicy removes repeats and folds whim messages into a digest; job offers become an Accept / Decline card.
const MAX_TOASTS := 4
const KIND_COLORS := {"info": Color("#3fb8af"), "good": Color("#4cc78a"), "warn": Color("#e8913d"), "bad": Color("#e5534b")}
## Systems use many kinds; they map onto four looks. Warn / bad also carry a "!" so colour is never the only cue.
const KIND_LOOK := {"birthday": "good", "goal": "good", "career": "good", "holiday": "info", "weather": "info", "relationship": "info",
	"story": "info", "visit": "info", "invite": "info", "travel": "info", "bill": "warn", "death": "bad", "job_offer": "good"}
## Each kind its own colour and badge glyph (the toast is a card with a coloured left edge and a round badge), so a bill, a story and a death do not look alike.
const KIND_STYLE := {"bill": ["#e0b341", "$"], "story": ["#9b6bd6", "~"], "travel": ["#5bb8ff", ">"], "relationship": ["#ff6b9d", "+"], "job_offer": ["#4f8cff", "W"],
	"birthday": ["#ffd166", "*"], "weather": ["#7fb3d5", "o"], "death": ["#8a8f98", "x"], "goal": ["#5fcf80", "v"], "career": ["#4f8cff", "W"], "holiday": ["#f59e0b", "*"],
	"visit": ["#3fb8af", "i"], "invite": ["#3fb8af", "@"], "warn": ["#e8913d", "!"], "bad": ["#e5534b", "!"], "good": ["#4cc78a", "v"], "info": ["#3fb8af", "i"]}

var policy := ToastPolicy.new()
var offer: OfferToast = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	UIU.connect_ev("notification", push)
	UIU.connect_ev("game_event", _on_game_event)

func _process(_d: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if policy.whim_due(now):
		_show(policy.take_whim_digest(), "good")

func _on_game_event(ev: String, payload: Dictionary) -> void:
	if ev == "job_offer":
		offer.show_offer(int(payload.get("folk_id", -1)))

## Drop every toast on screen (a new game starts with a clean slate).
func clear() -> void:
	for c in get_children():
		if c != offer:
			c.queue_free()

func push(text: String, kind: String = "info") -> void:
	if not GameSettings.notification_allowed(text, kind):
		return
	var r := policy.filter(text, kind, Time.get_ticks_msec() / 1000.0)
	match str(r["action"]):
		"show":
			_show(str(r["text"]), kind)

func _show(text: String, kind: String) -> void:
	var look: String = KIND_LOOK.get(kind, kind)
	var col: Color = KIND_COLORS.get(look, KIND_COLORS["info"])
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.tooltip_text = "Click to dismiss"
	var st: Array = KIND_STYLE.get(kind, KIND_STYLE.get(look, KIND_STYLE["info"]))
	col = Color(str(st[0]))
	var sb := UITheme.box(Color(UITheme.PANEL, 0.96), 10, Color(col, 0.35), 1, 10)
	sb.border_color = col
	sb.border_width_left = 6
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 6
	p.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", UITheme.box(col, 12, Color(0, 0, 0, 0), 0, 2))
	var gl := UIU.make_label(str(st[1]), 14, Color("#10161d"))
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gl.custom_minimum_size = Vector2(20, 0)
	gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(gl)
	row.add_child(badge)
	var l := UIU.make_label(text, 14)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	p.modulate.a = 0.0
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			p.queue_free())
	add_child(p)
	var shown := 0
	for c in get_children():
		if c != offer and not c.is_queued_for_deletion():
			shown += 1
	for c in get_children():
		if shown <= MAX_TOASTS:
			break
		if c != offer and not c.is_queued_for_deletion():
			c.queue_free()
			shown -= 1
	var fade := 0.0 if GameSettings.reduce_motion() else 1.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2 * fade)
	tw.tween_interval(ToastPolicy.duration_for(text))
	tw.tween_property(p, "modulate:a", 0.0, 0.5 * fade)
	tw.tween_callback(p.queue_free)
