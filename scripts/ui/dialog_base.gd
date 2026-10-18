class_name UIDialog
extends PanelContainer
## Small centred, closable dialog used by the Goals / Career / Household / Help panels.
## Subclasses override build() (fill `body`) and are rebuilt every time they open, so content is never stale.
var body: VBoxContainer
var title_label: Label
var folk_id := -1
var dialog_width := 460.0

func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(dialog_width, 0)
	var root := VBoxContainer.new()
	add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	title_label = UIU.make_label("", 20)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	var close := Button.new()
	close.text = "Close"
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(hide_dialog)
	head.add_child(close)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, 120)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(sc)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	_scroll = sc
	visibility_changed.connect(_track_pause)
	tree_exiting.connect(func():
		_open.erase(get_instance_id())
		_resume_if_none())

var _scroll: ScrollContainer

# ---- pause time while a dialog is open (setting "Pause when a window is open"); the previous speed comes back when the last one closes
static var _open: Dictionary = {}
static var _resume_speed := 0

func _track_pause() -> void:
	track_open(get_instance_id(), visible)

## Any modal-ish panel can call this when it shows / hides (the save menu does).
static func track_open(id: int, vis: bool) -> void:
	for k in _open.keys():      # forget dialogs that were freed or hidden without telling us
		var o = instance_from_id(k)
		if k != id and (o == null or (o is Control and not o.is_visible_in_tree())):
			_open.erase(k)
	if vis and not _open.has(id):
		if _open.is_empty() and GameSettings.get_bool("pause_on_dialog") and UIU.get_speed() != 0:
			_resume_speed = UIU.get_speed()
			UIU.set_speed(0)
		_open[id] = true
	elif not vis and _open.has(id):
		_open.erase(id)
		_resume_if_none()

static func _resume_if_none() -> void:
	if _open.is_empty() and _resume_speed > 0:
		if UIU.get_speed() == 0:
			UIU.set_speed(_resume_speed)
		_resume_speed = 0

func show_for(fid: int) -> void:
	folk_id = fid
	refresh()
	visible = true
	if is_inside_tree():
		call_deferred("_center")

func _center() -> void:
	# size the scroll area to its content (up to what fits on screen), then centre
	var max_h := clampf(minf(get_viewport_rect().size.y - 150.0, 560.0), 120.0, 560.0)
	_scroll.custom_minimum_size = Vector2(0, clampf(body.get_combined_minimum_size().y + 6.0, 80.0, max_h))
	reset_size()
	var vp := get_viewport_rect().size
	position = ((vp - size) / 2.0).floor()
	position.y = maxf(position.y, 56.0)       # never under the top bar

func hide_dialog() -> void:
	visible = false

func toggle_for(fid: int) -> void:
	if visible and fid == folk_id:
		hide_dialog()
	else:
		show_for(fid)

func refresh() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	build()

## The Folk this dialog is about (real world first, then whatever world the sim is bound to).
func folk_obj():
	var f = UIU.get_folk(folk_id)
	return f if f != null else SysUtil.folk(folk_id)

## Override: fill `body`.
func build() -> void:
	pass

# ---- tiny helpers shared by subclasses
func line(text: String, size: int = 14, color: Color = UITheme.TEXT) -> Label:
	var l := UIU.make_label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(dialog_width - 50.0, 0)
	body.add_child(l)
	return l

func heading(text: String) -> Label:
	return line(text.to_upper(), 12, UITheme.ACCENT)

func bar(value: float, maxv: float, tip: String = "") -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0.0
	b.max_value = maxf(maxv, 0.001)
	b.value = value
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, 12)
	b.tooltip_text = tip
	body.add_child(b)
	return b
