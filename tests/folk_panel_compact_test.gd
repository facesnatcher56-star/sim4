extends RefCounted
## Task 32d item 6: the folk panel is compact by default (face, mood, need pips) and expands on demand; the tips dock under the checklist.

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var before: bool = UIPrefs.get_flag("folk_panel_expanded", false)
	UIPrefs.set_flag("folk_panel_expanded", false)
	var root: Window = Engine.get_main_loop().root
	var p := FolkPanel.new()
	root.add_child(p)
	_check(not p.expanded, "compact by default")
	_check(not p.tabs.visible and not p.goal_row.visible and p.mini_box.visible, "compact: tabs and goal row hidden, need pips shown")
	_check(p.custom_minimum_size.x <= 340.0, "compact is narrow (%s)" % str(p.custom_minimum_size))
	p.set_expanded(true)
	_check(p.tabs.visible and p.goal_row.visible and not p.mini_box.visible, "expanded: everything shown")
	p.set_expanded(false)
	_check(not p.tabs.visible, "collapses again")
	p.queue_free()
	# the tips panel stacks under the checklist, inside the left column
	var tr := Control.new()
	tr.offset_top = 62.0
	tr.size = Vector2(270, 140)
	root.add_child(tr)
	var tips := FirstRunTips.new()
	tips.tracker = tr
	root.add_child(tips)
	tips.visible = true
	tips._process(0.0)
	_check(tips.offset_top >= 62.0 + 140.0, "tips sit below the checklist (%f)" % tips.offset_top)
	_check(tips.offset_left < 20.0 and tips.offset_right <= 300.0, "tips dock in the left column, off the home")
	tips.queue_free()
	tr.queue_free()
	UIPrefs.set_flag("folk_panel_expanded", before)
	return fails
