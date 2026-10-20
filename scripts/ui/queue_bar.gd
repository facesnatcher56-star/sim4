class_name QueueBar
extends HBoxContainer
## Shows current + queued interactions of the selected folk. Click a chip to cancel it.
var folk = null
var folk_id := -1
var chips: Array = []
var bars: Array = []         # task 33.4: [Button chip, ProgressBar] of the current action, filled from Interaction.progress()
var _tick := 0.0

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
	bars.clear()
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
	b.text = chip_text(def_id, idx < 0, ProgressRing.chip_fraction(it) if idx < 0 else -1.0)
	b.tooltip_text = "Click to cancel this task" if idx >= 0 else "Doing this now. Click to stop."
	if idx < 0:
		b.add_theme_stylebox_override("normal", UITheme.box(UITheme.ACCENT.darkened(0.4), 6, UITheme.ACCENT, 1))
	b.pressed.connect(func(): cancel(idx))
	if idx < 0:
		var pb := ProgressBar.new()          # thin bar along the bottom of the chip: how far along the running action is
		pb.show_percentage = false
		pb.min_value = 0.0
		pb.max_value = 1.0
		pb.value = maxf(ProgressRing.chip_fraction(it), 0.0)
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pb.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		pb.offset_top = -5
		pb.offset_left = 3
		pb.offset_right = -3
		pb.offset_bottom = -2
		pb.add_theme_stylebox_override("background", UITheme.box(Color(0, 0, 0, 0.35), 2, Color(0, 0, 0, 0), 0))
		pb.add_theme_stylebox_override("fill", UITheme.box(UITheme.ACCENT, 2, Color(0, 0, 0, 0), 0))
		b.add_child(pb)
		bars.append([b, pb])
	add_child(b)
	chips.append(b)

## Chip text: "> Water the Plant 40%" for the running action (the percent only once it is really running), "Water the Plant" for queued ones.
static func chip_text(def_id: String, running: bool, frac: float) -> String:
	var t := ("> " if running else "") + UIU.interaction_label(def_id)
	if running and frac >= 0.0:
		t += "  " + ProgressRing.percent_text(frac)
	return t

func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0 or bars.is_empty() or folk == null:
		return
	_tick = 0.3
	var cur = UIU.prop(folk, "current", null)
	for pair in bars:
		var frac := ProgressRing.chip_fraction(cur)
		(pair[1] as ProgressBar).value = maxf(frac, 0.0)
		(pair[0] as Button).text = chip_text(str(UIU.prop(cur, "def_id", "")), true, frac) if cur != null else (pair[0] as Button).text

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
