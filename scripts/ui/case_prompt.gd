class_name CasePrompt
extends UIDialog
## The clear prompt of the crime and justice track: a title, a few plain sentences and one button per choice (robbery reaction, a dangerous grudge,
## bail, a lawyer, a plea deal, testimony, an arrest or verdict notice). The HUD registers `ask` as JusticePlayer.ask_fn. Several prompts queue up and
## are shown one after another; Esc / Close picks the default choice. No jargon, no ids.

var _queue: Array = []        # [{pid, title, text, options, cb, default}]
var _current: Dictionary = {}

## Task 63: a scene happening right now (the cashier at the door, a hand in the till) is not a decision that can wait for the morning:
## it is asked at once, at any hour, ahead of anything queued.
const LIVE := ["At the door", "At the till", "At the car", "Staff only", "Robbery!", "At your door", "Your guest", "Out here"]

static func is_live(title: String) -> bool:
	return title in LIVE or title.begins_with("Caught in")

func _ready() -> void:
	dialog_width = 440.0
	super._ready()

## JusticePlayer.ask_fn signature.
func ask(pid: int, title: String, text: String, options: Array, on_choice: Callable, default_id: String) -> void:
	var e: Dictionary = {"pid": pid, "title": title, "text": text, "options": options, "cb": on_choice, "default": default_id}
	if is_live(title):
		_queue.push_front(e)
	else:
		_queue.append(e)
	if not visible:
		_next()

## Playtest: a neighbour's favour came at midnight while the character slept and held the clock. A question waits until they are awake and it is
## daytime (07:00-22:00); it is still asked, just in the morning.
func _asleep_or_night(pid: int) -> bool:
	var f = SysUtil.folk(pid)
	var h: float = SysUtil.hour_f()
	var sleeping: bool = f != null and f.current != null and str(f.current.def_id).contains("sleep")
	return sleeping or h >= 22.0 or h < 7.0

func _process(_d: float) -> void:
	if not visible and _current.is_empty() and not _queue.is_empty():
		_next()

func _next() -> void:
	if _queue.is_empty() or (not is_live(str(_queue[0]["title"])) and _asleep_or_night(int(_queue[0]["pid"]))):
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
	if not visible:          # the answer may have asked a follow-up question, already on screen: don't hide it again
		_next()

## Task 65: a scene happening right now is asked from the top of the screen, so the people it is about stay in view in the middle.
func _place_centre() -> void:
	super._place_centre()
	if not _current.is_empty() and is_live(str(_current.get("title", ""))):
		position.y = 84.0

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
