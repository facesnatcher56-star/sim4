class_name QueueBar
extends HBoxContainer
## Shows current + queued interactions of the selected folk. Click a chip to cancel it.
var folk = null
var folk_id := -1
var chips: Array = []

func _ready() -> void:
	UIU.connect_ev("queue_changed", _on_queue_changed)
	UIU.connect_ev("interaction_started", func(f, _i, _t): _on_queue_changed(f))
	UIU.connect_ev("interaction_finished", func(f, _i, _s): _on_queue_changed(f))

func set_folk(f) -> void:
	folk = f
	folk_id = int(UIU.prop(f, "id", -1)) if f != null else -1
	rebuild()

func _on_queue_changed(fid: int) -> void:
	if fid == folk_id:
		rebuild()

func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	chips.clear()
	if folk == null:
		return
	var cur = UIU.prop(folk, "current", null)
	if cur != null:
		_add_chip(cur, -1)
	var q = UIU.prop(folk, "queue", [])
	for i in q.size():
		_add_chip(q[i], i)
	if cur == null and q.size() == 0:
		add_child(UIU.make_label("Idle. Click an object or a person to give an order.", 13, UITheme.MUTED))

func _add_chip(it, idx: int) -> void:
	var def_id := str(UIU.prop(it, "def_id", ""))
	var b := Button.new()
	b.text = ("> " if idx < 0 else "") + UIU.interaction_label(def_id)
	b.tooltip_text = "Click to cancel this task" if idx >= 0 else "Doing this now. Click to stop."
	if idx < 0:
		b.add_theme_stylebox_override("normal", UITheme.box(UITheme.ACCENT.darkened(0.4), 6, UITheme.ACCENT, 1))
	b.pressed.connect(func(): cancel(idx))
	add_child(b)
	chips.append(b)

func cancel(idx: int) -> void:
	if folk == null:
		return
	if idx < 0:
		var cur = UIU.prop(folk, "current", null)
		if folk.has_method("cancel_current"):
			folk.call("cancel_current")
		elif cur != null and cur.has_method("finish"):
			cur.call("finish", false)
	else:
		var q = UIU.prop(folk, "queue", [])
		if idx < q.size():
			q.remove_at(idx)
	Events.queue_changed.emit(folk_id)
