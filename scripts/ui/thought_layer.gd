class_name ThoughtLayer
extends Control
## Thought balloons above folk heads (Events.thought), positioned via LotView.screen_pos_of.
var lot_view = null
var balloons: Array = []     # {node, folk_id}
const MAX_BALLOONS := 5

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UIU.connect_ev("thought", show_thought)

func show_thought(folk_id: int, text: String) -> void:
	if text.strip_edges() == "" or not GameSettings.get_bool("thought_bubbles"):
		return
	# rate, variety and no-repeats are decided upstream (ThoughtVoice gate in SimEnv.emit), so every thought that arrives is shown
	for b in balloons:
		if b["folk_id"] == folk_id and is_instance_valid(b["node"]):
			b["node"].queue_free()
	balloons = balloons.filter(func(b): return b["folk_id"] != folk_id)
	while balloons.size() >= MAX_BALLOONS:
		var old = balloons.pop_front()
		if is_instance_valid(old["node"]):
			old["node"].queue_free()
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UITheme.box(Color(1, 1, 1, 0.95), 14, Color(0.2, 0.2, 0.25), 2, 10))
	var l := UIU.make_label(text, 14, Color("#1d2630"))
	p.add_child(l)
	p.modulate.a = 0.0
	p.visible = false
	add_child(p)
	balloons.append({"node": p, "folk_id": folk_id})
	var tw := p.create_tween()
	var fade := 0.0 if GameSettings.reduce_motion() else 1.0
	tw.tween_property(p, "modulate:a", 1.0, 0.25 * fade)
	tw.tween_interval(2.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.6 * fade)
	tw.tween_callback(p.queue_free)

func _process(_d: float) -> void:
	balloons = balloons.filter(func(b): return is_instance_valid(b["node"]))
	if lot_view == null or not lot_view.has_method("screen_pos"):
		return
	for b in balloons:
		var pos = lot_view.call("screen_pos", "folk", b["folk_id"])
		var n: Control = b["node"]
		if pos is Vector2 and pos.x >= 0.0:
			n.visible = true
			n.position = pos + Vector2(-n.size.x / 2.0, -n.size.y - 8)
		else:
			n.visible = false
