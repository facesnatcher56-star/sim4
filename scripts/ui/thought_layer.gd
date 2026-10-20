class_name ThoughtLayer
extends Control
## Thought balloons above folk heads (Events.thought), positioned via LotView.screen_pos_of.
var lot_view = null
var rings = null             # ProgressLayer: its rings are obstacles the balloons are pushed above
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
	p.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.sem("bubble"), 0.95), 14, UITheme.sem("bubble_edge"), 2, 10))
	var l := UIU.make_label(text, 14, UITheme.sem("bubble_text"))
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
	var items: Array = []
	for b in balloons:
		var pos = lot_view.call("screen_pos", "folk", b["folk_id"])
		var n: Control = b["node"]
		if pos is Vector2 and pos.x >= 0.0:
			n.visible = true
			items.append({"id": b["folk_id"], "pos": pos + Vector2(-n.size.x / 2.0, -n.size.y - 8), "size": n.size, "node": n})
		else:
			n.visible = false
	var placed := layout_rects(items, rings.rects() if rings != null else [])
	for i in items.size():
		items[i]["node"].position = placed[i]

## View-only de-overlap: items {id, pos (top-left), size}. Returns top-left positions in the same order.
## Balloons are processed by folk id (stable), each pushed up until it clears the ones already placed.
## `fixed` = rects already taken (progress rings): balloons never overlap them either.
static func layout_rects(items: Array, fixed: Array = []) -> Array:
	var order: Array = range(items.size())
	order.sort_custom(func(a, b): return int(items[a]["id"]) < int(items[b]["id"]))
	var out: Array = []
	out.resize(items.size())
	var placed: Array = fixed.duplicate()
	for i in order:
		var sz: Vector2 = items[i]["size"]
		var p: Vector2 = items[i]["pos"]
		var moved := true
		var guard := 0
		while moved and guard < 12:
			moved = false
			guard += 1
			for r in placed:
				if Rect2(p, sz).grow(2.0).intersects(r):
					p.y = r.position.y - sz.y - 4.0
					moved = true
		out[i] = p
		placed.append(Rect2(p, sz))
	return out
