class_name ThoughtLayer
extends Control
## Balloons above heads, positioned via LotView.screen_pos. Two kinds (playtest: a player could not tell who said what):
##   speech (Events.speech): a line said out loud, with the speaker's first name and a tail pointing at them; a reply waits until the line it answers
##                           is up, so a conversation reads in order. Anyone the player can see.
##   thought (Events.thought): someone thinking to themselves: a quieter grey balloon with their name and two small "thinking" dots instead of a tail.
##                           A thought from someone in a conversation is said out loud instead (speech, to the person they are talking with).
## A balloon whose person is off screen is hidden, never pushed to the edge; zoomed far out (camera size > FAR_ZOOM) none show.
var lot_view = null
var rings = null             # ProgressLayer: its rings are obstacles the balloons are pushed above
var balloons: Array = []     # {node, folk_id, born (msec), speech}
const MAX_BALLOONS := 6
const REPLY_GAP := 1.1        # seconds a reply waits after the line it answers
const FAR_ZOOM := 30.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UIU.connect_ev("thought", show_thought)
	UIU.connect_ev("speech", show_speech)

func show_thought(folk_id: int, text: String) -> void:
	if text.strip_edges() == "" or not GameSettings.get_bool("thought_bubbles"):
		return
	# rate, variety and no-repeats are decided upstream (ThoughtVoice gate in SimEnv.emit), so every thought that arrives is shown
	var to: int = _talking_to(folk_id)
	if to >= 0 and not ThoughtVoice.about_them(text):          # a line about the other person stays a thought
		show_speech(folk_id, text, to)          # someone in a conversation says it out loud, to the person they are talking with
	else:
		_add(folk_id, text, false, 0.0)          # thinking to themselves: the quieter "thinks" balloon

## Can the player see this person (not behind a building, not inside an unlit interior, not away)? A balloon over a blank wall says nothing.
func _seen(fid: int) -> bool:
	var fv = lot_view.get("_folk_views").get(fid, null) if lot_view != null and lot_view.get("_folk_views") != null else null
	return fv != null and is_instance_valid(fv) and (fv as Node3D).is_visible_in_tree() and not (fv as Node).has_meta("occluded")

## Who this person is talking with right now: the target of a social interaction, else someone in their conversation circle. -1 when nobody.
func _talking_to(fid: int) -> int:
	var f = SysUtil.folk(fid)
	if f == null:
		return -1
	if f.current != null and int(f.current.target_id) >= 0 and str(f.current.def.get("target", "")) == "folk":
		return int(f.current.target_id)
	for m in (Conversation.circle_of(fid).get("members", []) as Array):
		if int(m) != fid:
			return int(m)
	return -1

func show_speech(folk_id: int, text: String, to_id: int = -1) -> void:
	if text.strip_edges() == "" or not GameSettings.get_bool("thought_bubbles"):
		return
	var delay := 0.0
	var now: float = Time.get_ticks_msec()
	for b in balloons:
		if bool(b["speech"]) and int(b["folk_id"]) == to_id and now - float(b["born"]) < REPLY_GAP * 1000.0:
			delay = REPLY_GAP - (now - float(b["born"])) / 1000.0          # the answer comes after the line it answers
	_add(folk_id, text, true, delay)

func _add(folk_id: int, text: String, speech: bool, delay: float) -> void:
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
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	if speech:
		p.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.sem("bubble"), 0.97), 12, UITheme.sem("bubble_edge"), 2, 8))
		var who := UIU.make_label(SysUtil.folk_name(folk_id).get_slice(" ", 0), UITheme.SMALL, Color(UITheme.sem("bubble_text"), 0.75))          # dark on the light bubble: readable
		v.add_child(who)
		v.add_child(UIU.make_label(text, UITheme.BODY - 1, UITheme.sem("bubble_text")))
		var tail := Polygon2D.new()          # the tail points down at the speaker
		tail.color = Color(UITheme.sem("bubble"), 0.97)
		tail.polygon = PackedVector2Array([Vector2(-7, 0), Vector2(7, 0), Vector2(0, 9)])
		tail.name = "Tail"
		p.add_child(tail)
	else:
		p.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.PANEL, 0.93), 12, Color(1, 1, 1, 0.18), 1, 8))          # task 59: one balloon shape and size; solid enough to read at night
		v.add_child(UIU.make_label(SysUtil.folk_name(folk_id).get_slice(" ", 0) + " thinks", UITheme.SMALL, UITheme.MUTED))
		v.add_child(UIU.make_label(text, UITheme.BODY - 1, UITheme.TEXT.darkened(0.08)))
		var dots := Node2D.new()          # two small circles under it: thinking, not saying
		dots.name = "Tail"
		for k in 2:
			var d := Polygon2D.new()
			var r: float = 4.0 - float(k) * 1.5
			var pts := PackedVector2Array()
			for a in 10:
				pts.append(Vector2(cos(a * TAU / 10.0), sin(a * TAU / 10.0)) * r + Vector2(-3.0 * k, 4.0 + 8.0 * k))
			d.polygon = pts
			d.color = Color(UITheme.PANEL, 0.93)
			dots.add_child(d)
		p.add_child(dots)
	p.modulate.a = 0.0
	p.visible = false
	add_child(p)
	balloons.append({"node": p, "folk_id": folk_id, "born": Time.get_ticks_msec() + int(delay * 1000.0), "speech": speech})
	var tw := p.create_tween()
	var fade := 0.0 if GameSettings.reduce_motion() else 1.0
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(p, "modulate:a", 1.0, 0.25 * fade)
	tw.tween_interval(3.2 if speech else 2.6)
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
		var vpr: Rect2 = get_viewport_rect().grow(-20.0)
		var cam: Camera3D = get_viewport().get_camera_3d()
		var far: bool = cam != null and cam.projection == Camera3D.PROJECTION_ORTHOGONAL and cam.size > FAR_ZOOM
		if pos is Vector2 and pos.x >= 0.0 and vpr.has_point(pos) and not far and _seen(int(b["folk_id"])):          # off screen: hidden, never pushed to the edge
			n.visible = true
			items.append({"id": b["folk_id"], "pos": pos + Vector2(-n.size.x / 2.0, -n.size.y - 8), "size": n.size, "node": n})
		else:
			n.visible = false
	var placed := layout_rects(items, rings.rects() if rings != null else [])
	var vp: Vector2 = get_viewport_rect().size
	for i in items.size():
		var sz: Vector2 = items[i]["size"]
		var n2: Control = items[i]["node"]
		var at := Vector2(clampf(placed[i].x, 4.0, maxf(vp.x - sz.x - 4.0, 4.0)), maxf(placed[i].y, 64.0))          # a speaker near the edge: the balloon stays readable
		n2.position = at
		var tail = n2.get_node_or_null("Tail")
		if tail != null:          # the tail sits under the balloon, above the head it belongs to
			var head: Vector2 = items[i]["pos"] + Vector2(sz.x / 2.0, sz.y + 8.0)
			tail.position = Vector2(clampf(head.x - at.x, 10.0, sz.x - 10.0), sz.y - 1.0)

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
