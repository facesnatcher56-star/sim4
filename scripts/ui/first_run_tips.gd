class_name FirstRunTips
extends PanelContainer
## Short, dismissible welcome tips shown once (flag stored in user://ui_prefs.cfg).
const TIPS := [
	"Click one of your Folk (the faces at the bottom-left) to see their needs and mood. Click a thing in the world to choose what they do with it.",
	"Chosen tasks queue up along the bottom-left. Click a queued task to cancel it. Right-click the ground to send a Folk somewhere.",
	"Space pauses the game. Keys 1, 2 and 3 set the speed. Folk look after themselves, but they cope better when you steer them.",
	"Press B to Build / Buy and redecorate. Press M to open the map and visit other places. Press F1 or ? for all controls.",
	"Watch the Needs bars and the mood face. The Goals and Work buttons show what each Folk is dreaming of and earning.",
]
var index := 0
var tips: Array = TIPS      # the active list (a scenario can bring its own)
var label: Label
var next_btn: Button
var count_label: Label

func _ready() -> void:
	visible = false
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -230
	offset_right = 230
	offset_top = -170
	offset_bottom = -14
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	var v := VBoxContainer.new()
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UIU.make_label("Welcome tips", 15, UITheme.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	count_label = UIU.make_label("", 12, UITheme.MUTED)
	head.add_child(count_label)
	label = UIU.make_label("", 14)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(420, 60)
	v.add_child(label)
	var row := HBoxContainer.new()
	v.add_child(row)
	var skip := Button.new()
	skip.text = "Skip tips"
	skip.pressed.connect(dismiss)
	row.add_child(skip)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	next_btn = Button.new()
	next_btn.pressed.connect(_next)
	row.add_child(next_btn)

static func already_seen() -> bool:
	return UIPrefs.get_flag("tips_seen", false)

## Shows the tips unless the player has dismissed them before (force = ignore the flag). `list` = scenario-specific tips.
func start(force: bool = false, list: Array = []) -> void:
	if already_seen() and not force:
		return
	tips = list if not list.is_empty() else TIPS
	index = 0
	_show()
	visible = true

func _show() -> void:
	label.text = str(tips[index])
	count_label.text = "%d / %d" % [index + 1, tips.size()]
	next_btn.text = "Next" if index < tips.size() - 1 else "Got it"

func _next() -> void:
	if index >= tips.size() - 1:
		dismiss()
		return
	index += 1
	_show()

func dismiss() -> void:
	visible = false
	UIPrefs.set_flag("tips_seen", true)
