class_name ScenarioTracker
extends PanelContainer
## Compact 'Getting Started' checklist under the top bar (top-left) for scenarios that have goals. Collapsible.
## When the last goal is done it turns into a 'What next?' card that points to aspirations (Goals).
signal goals_requested

const WIDTH := 270.0

var collapsed := false
var celebrating := false         # the checklist was finished in this session: show the 'what next' card
var dismissed := false
var box: VBoxContainer

func _ready() -> void:
	UIIdentity.skin(self, "#5fcf80", "ribbon", 12)          # the checklist: green ribbon
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_left = 0.0
	offset_left = 12
	offset_top = 62
	offset_right = 12 + WIDTH
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	UIU.connect_ev("game_event", _on_event)
	refresh()

func _on_event(ev_name: String, _p: Dictionary) -> void:
	match ev_name:
		"scenario_goal_done", "scenario_progress":
			refresh()
		"scenario_finished":
			celebrating = true
			dismissed = false
			refresh()

## Call after a game starts or loads.
func reset_for_game() -> void:
	collapsed = false
	celebrating = false
	dismissed = false
	refresh()

func refresh() -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	visible = Scenario.active() and Scenario.has_goals() and not dismissed and (not Scenario.finished or celebrating)
	if not visible:
		return
	var goals: Array = Scenario.goals()
	var head := HBoxContainer.new()
	box.add_child(head)
	var t := UIU.make_label("What next?" if Scenario.finished else "Getting Started", 15, UITheme.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	if not Scenario.finished:
		head.add_child(UIU.make_label("%d / %d" % [Scenario.done_count(), goals.size()], 13, UITheme.MUTED))
	var tog := Button.new()
	tog.text = "+" if collapsed else "-"
	tog.flat = true
	tog.tooltip_text = "Show or hide this checklist"
	tog.pressed.connect(func():
		collapsed = not collapsed
		refresh())
	head.add_child(tog)
	if collapsed:
		return
	if Scenario.finished:
		_next_card(goals)
		return
	var shown_hint := false
	for g in goals:
		var done: bool = Scenario.is_done(str(g["id"]))
		var row := HBoxContainer.new()
		box.add_child(row)
		var mark := CheckMark.new()
		mark.on = done
		row.add_child(mark)
		var gt: Dictionary = Scenario.goal_text(g)
		var label: String = str(gt["label"])
		var need: int = int((g.get("check", {}) as Dictionary).get("count", 1))
		if need > 1 and not done:
			label += " (%d/%d)" % [int(Scenario.progress.get(str(g["id"]), 0)), need]
		var l := UIU.make_label(label, 14, UITheme.MUTED if done else UITheme.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(WIDTH - 60, 0)
		row.add_child(l)
		if not done and not shown_hint:
			shown_hint = true
			var hint := UIU.make_label(str(gt["hint"]), 12, UITheme.MUTED)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.custom_minimum_size = Vector2(WIDTH - 40, 0)
			var hr := HBoxContainer.new()
			var ind := Control.new()
			ind.custom_minimum_size = Vector2(26, 0)
			hr.add_child(ind)
			hr.add_child(hint)
			box.add_child(hr)

func _next_card(goals: Array) -> void:
	for g in goals:
		var row := HBoxContainer.new()
		box.add_child(row)
		var mark := CheckMark.new()
		mark.on = true
		row.add_child(mark)
		row.add_child(UIU.make_label(str(g["label"]), 13, UITheme.MUTED))
	var msg := UIU.make_label("All done, well played! Every Folk has a life aspiration: a long-term dream with milestones and rewards. Pick one in Goals, or just keep living.", 13)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(WIDTH - 20, 0)
	box.add_child(msg)
	var hb := HBoxContainer.new()
	box.add_child(hb)
	var open := Button.new()
	open.text = "Open Goals"
	open.pressed.connect(func(): goals_requested.emit())
	hb.add_child(open)
	var done := Button.new()
	done.text = "Got it"
	done.pressed.connect(func():
		dismissed = true
		refresh())
	hb.add_child(done)


## Little check box drawn by hand (no font dependency).
class CheckMark extends Control:
	var on := false

	func _init() -> void:
		custom_minimum_size = Vector2(20, 20)

	func _draw() -> void:
		var r := Rect2(Vector2(2, 3), Vector2(15, 15))
		draw_rect(r, Color(UITheme.ACCENT, 0.9) if on else Color(0, 0, 0, 0.25))
		draw_rect(r, Color(1, 1, 1, 0.55), false, 1.5)
		if on:
			draw_polyline(PackedVector2Array([Vector2(5, 11), Vector2(8.5, 14.5), Vector2(15, 6)]), Color.WHITE, 2.4)
