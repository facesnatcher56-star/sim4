class_name ConfirmDialog
extends UIDialog
## Small yes/no question. ask() shows it; `on_yes` runs when the player confirms, `on_no` on No / Esc / timeout.
var message := ""
var yes_text := "Yes"
var no_text := "Cancel"
var on_yes: Callable = Callable()
var on_no: Callable = Callable()
var timeout := 0.0          # seconds; 0 = wait forever. When it runs out the answer is No.
var _left := 0.0
var _count: Label = null

func _ready() -> void:
	dialog_width = 380.0
	super._ready()

func ask(title: String, text: String, yes: String, yes_cb: Callable, no: String = "Cancel", no_cb: Callable = Callable(), seconds: float = 0.0) -> void:
	title_label.text = title
	message = text
	yes_text = yes
	no_text = no
	on_yes = yes_cb
	on_no = no_cb
	timeout = seconds
	_left = seconds
	show_for(-1)

func build() -> void:
	line(message, 14)
	_count = null
	if timeout > 0.0:
		_count = line("", 13, UITheme.MUTED)
		_update_count()
	var row := HBoxContainer.new()
	body.add_child(row)
	var y := Button.new()
	y.text = yes_text
	y.pressed.connect(_answer.bind(true))
	row.add_child(y)
	var n := Button.new()
	n.text = no_text
	n.pressed.connect(_answer.bind(false))
	row.add_child(n)

func _update_count() -> void:
	if _count != null:
		_count.text = "Going back in %d s..." % int(ceil(_left))

func _process(d: float) -> void:
	if visible and timeout > 0.0:
		_left -= d
		_update_count()
		if _left <= 0.0:
			_answer(false)

func _answer(yes: bool) -> void:
	var cb := on_yes if yes else on_no
	timeout = 0.0
	on_yes = Callable()
	on_no = Callable()
	visible = false
	if cb.is_valid():
		cb.call()

## Esc / the Close button count as No.
func hide_dialog() -> void:
	if visible:
		_answer(false)

func _unhandled_input(ev: InputEvent) -> void:
	if visible and ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_answer(false)
