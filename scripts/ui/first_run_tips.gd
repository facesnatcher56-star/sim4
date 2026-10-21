class_name FirstRunTips
extends PanelContainer
## Short, dismissible welcome tips shown once (flag stored in user://ui_prefs.cfg). Docked in the top-left column UNDER the 'Getting Started'
## checklist (never over the home in the middle of the screen). When the home started bare it then turns into a 'Next step' note that follows
## what the household has bought (StartHome.next_basic: bed, toilet, fridge, shower, stove, seats) until the basics are covered.
const WIDTH := 270.0
const TIPS := [
	"Click one of your Folk (the faces at the bottom-left) to see their needs and mood. Click a thing in the world to choose what they do with it.",
	"Chosen tasks queue up along the bottom-left. Click a queued task to cancel it. Right-click the ground to send a Folk somewhere.",
	"Space pauses the game. Keys 1, 2 and 3 set the speed. Folk look after themselves, but they cope better when you steer them.",
	"Press B to Build / Buy and redecorate. Press M to open the map and visit other places. Press F1 or ? for all controls.",
	"Watch the Needs bars and the mood face. The Goals and Work buttons show what each Folk is dreaming of and earning.",
]
var index := 0
var tips: Array = TIPS      # the active list (a scenario can bring its own)
var title_label: Label
var label: Label
var next_btn: Button
var skip_btn: Button
var count_label: Label
var basics_mode := false     # after the tips: follow the household's shopping list (bare-home start)
var next_step_shown := false # the panel currently shows the 'Next step' note
var tracker: Control         # the checklist this panel stacks under (set by the HUD)

func _ready() -> void:
	UIIdentity.skin(self, "#5bb8ff", "band", 14)          # the tips: blue band
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = 12
	offset_right = 12 + WIDTH
	offset_top = 62
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	title_label = UIU.make_label("Welcome tips", 15, UITheme.ACCENT)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	count_label = UIU.make_label("", 12, UITheme.MUTED)
	head.add_child(count_label)
	next_btn = Button.new()
	next_btn.flat = true
	next_btn.pressed.connect(_next)
	head.add_child(next_btn)
	skip_btn = Button.new()
	skip_btn.flat = true
	skip_btn.text = "Skip"
	skip_btn.tooltip_text = "Skip the welcome tips (Help brings them back)"
	skip_btn.pressed.connect(dismiss)
	head.add_child(skip_btn)
	label = UIU.make_label("", 12)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(WIDTH - 24, 0)
	v.add_child(label)
	UIU.connect_ev("game_event", _on_event)

static func already_seen() -> bool:
	return UIPrefs.get_flag("tips_seen", false)

## Keep the panel in the left column, below the checklist (which grows and shrinks).
var _folded: bool = false          # we folded the checklist to make room (one overlay at a time, 45 rule 5); unfolded when the tips close
var _was_up: bool = false
var _day0: int = -1

func _process(_d: float) -> void:
	if visible != _was_up:          # fold the checklist once when the tips open (the player can open it again), unfold it when they close
		_was_up = visible
		if tracker != null and visible and not tracker.collapsed:
			_folded = true
			tracker.collapsed = true
			tracker.refresh()
		elif tracker != null and not visible and _folded:
			_folded = false
			tracker.collapsed = false
			tracker.refresh()
	if not visible:
		return
	if _day0 < 0:
		_day0 = SysUtil.day()
	elif SysUtil.day() > _day0:          # playtest: the card was still covering the screen on day 2; it folds away after the first day
		visible = false
		return
	var top := 62.0
	if tracker != null and tracker.visible:
		top = tracker.offset_top + tracker.size.y + 8.0
	offset_top = top
	offset_bottom = top + get_combined_minimum_size().y          # shrink back when the text gets shorter or the panel moves up

## Shows the tips unless the player has dismissed them before (force = ignore the flag). `list` = scenario-specific tips.
## `basics` = the home started bare: keep a 'Next step' note after the tips (always shown for a bare start, even to a returning player).
func start(force: bool = false, list: Array = [], basics: bool = false) -> void:
	basics_mode = basics
	next_step_shown = false
	if (already_seen() and not force and not basics):
		return
	tips = list if not list.is_empty() else TIPS
	index = 0
	_day0 = -1
	_show()
	visible = true

func _show() -> void:
	next_step_shown = false
	title_label.text = "Welcome tips"
	skip_btn.visible = true
	label.text = str(tips[index])
	count_label.text = "%d / %d" % [index + 1, tips.size()]
	next_btn.text = "Next" if index < tips.size() - 1 else "Got it"

func _next() -> void:
	if next_step_shown:
		basics_mode = false
		visible = false
		return
	if index >= tips.size() - 1:
		dismiss()
		return
	index += 1
	_show()

func dismiss() -> void:
	UIPrefs.set_flag("tips_seen", true)
	if basics_mode and _show_next_step():
		return
	visible = false

## The shopping-list note: what to buy next, from the household's own belongings.
func _show_next_step() -> bool:
	var nb: Dictionary = StartHome.next_basic(Economy.primary_household())
	if nb.is_empty():
		return false
	next_step_shown = true
	visible = true
	title_label.text = "Next step"
	count_label.text = ""
	label.text = str(nb["text"])
	skip_btn.visible = false
	next_btn.text = "Hide"
	return true

func _on_event(ev_name: String, _p: Dictionary) -> void:
	if not next_step_shown or ev_name != "object_bought":
		return
	var nb: Dictionary = StartHome.next_basic(Economy.primary_household())
	if nb.is_empty():
		label.text = str(StartHome.cfg().get("done_text", "That is the basics covered."))
		next_step_shown = false
		basics_mode = false
		title_label.text = "All set"
		next_btn.text = "Got it"
		skip_btn.visible = false
		tips = [label.text]
		index = 0
	else:
		label.text = str(nb["text"])
