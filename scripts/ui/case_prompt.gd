class_name CasePrompt
extends UIDialog
## The clear prompt of the crime and justice track: a title, a few plain sentences and one button per choice (robbery reaction, a dangerous grudge,
## bail, a lawyer, a plea deal, testimony, an arrest or verdict notice). The HUD registers `ask` as JusticePlayer.ask_fn. Several prompts queue up and
## are shown one after another; Esc / Close picks the default choice. No jargon, no ids.

var _queue: Array = []        # [{pid, title, text, options, cb, default}]
var _current: Dictionary = {}

func _ready() -> void:
	dialog_width = 440.0
	super._ready()

## JusticePlayer.ask_fn signature.
func ask(pid: int, title: String, text: String, options: Array, on_choice: Callable, default_id: String) -> void:
	_queue.append({"pid": pid, "title": title, "text": text, "options": options, "cb": on_choice, "default": default_id})
	if not visible:
		_next()

func _next() -> void:
	if _queue.is_empty():
		_current = {}
		visible = false
		return
	_current = _queue.pop_front()
	folk_id = int(_current["pid"])
	refresh()
	visible = true
	if is_inside_tree():
		call_deferred("_center")

func build() -> void:
	if _current.is_empty():
		return
	title_label.text = str(_current["title"])
	line(str(_current["text"]), 14)
	for o in _current["options"]:
		var b := Button.new()
		b.text = str(o["label"])
		b.custom_minimum_size = Vector2(0, 30)
		b.pressed.connect(_pick.bind(str(o["id"])))
		body.add_child(b)

func _pick(choice: String) -> void:
	var cb: Callable = _current.get("cb", Callable())
	_current = {}
	visible = false
	if cb.is_valid():
		cb.call(choice)
	_next()

## Esc / Close = the default answer, so nothing waits forever.
func hide_dialog() -> void:
	if visible and not _current.is_empty():
		_pick(str(_current["default"]))
	else:
		visible = false

func _unhandled_input(ev: InputEvent) -> void:
	if visible and ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		hide_dialog()
