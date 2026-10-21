class_name GoalsDialog
extends UIDialog
## Aspiration, milestone, active whims (with time left), satisfaction points and the perk shop for one Folk.
var picking := false

func _ready() -> void:
	dialog_width = 480.0
	super._ready()

static func time_left_text(minutes: int) -> String:
	if minutes <= 0:
		return "ending now"
	if minutes < 60:
		return "%d min left" % minutes
	return "%dh %02dm left" % [minutes / 60, minutes % 60]

func build() -> void:
	var f = folk_obj()
	title_label.text = "%s's Goals" % str(UIU.prop(f, "name", "Folk"))
	if f == null:
		line("Nobody selected.", 14, UITheme.MUTED)
		return
	Goals.ensure_profile(f)
	var info: Dictionary = Goals.active_for(folk_id)
	if info.is_empty():
		line("No goals yet.", 14, UITheme.MUTED)
		return
	_aspiration(info)
	_whims(info)
	_perks(info)

func _aspiration(info: Dictionary) -> void:
	heading("Aspiration (long-term dream)")
	line(str(info["aspiration_label"]), 18)
	line(str(info["description"]), 13, UITheme.MUTED)
	var ms: Dictionary = info["milestone"]
	if bool(info["completed"]):
		line("All %d milestones complete. Well done!" % int(info["milestones_total"]), 14, UITheme.ACCENT)
	else:
		line("Milestone %d of %d: %s" % [int(info["milestones_done"]) + 1, int(info["milestones_total"]), str(ms["label"])], 14)
		if int(ms["target"]) > 1:
			bar(float(ms["progress"]), float(ms["target"]), "%d / %d" % [int(ms["progress"]), int(ms["target"])])
		line("Reward: %d satisfaction points" % int(ms["points"]), 12, UITheme.MUTED)
	var pick := Button.new()
	pick.text = "Choose a different aspiration..." if not picking else "Never mind"
	pick.tooltip_text = "Switching restarts this aspiration's milestones. Satisfaction points are kept."
	pick.pressed.connect(func():
		picking = not picking
		refresh())
	body.add_child(pick)
	if picking:
		_picker(str(info["aspiration"]))

func _picker(current: String) -> void:
	var defs: Dictionary = Goals.cfg().get("aspirations", {})
	var grid := GridContainer.new()
	grid.columns = 2
	body.add_child(grid)
	for aid in Goals.aspiration_ids():
		var b := Button.new()
		b.text = str(defs[aid].get("label", aid))
		b.tooltip_text = str(defs[aid].get("description", ""))
		b.custom_minimum_size = Vector2(200, 28)
		b.disabled = (str(aid) == current)
		var id := str(aid)
		b.pressed.connect(func():
			Commands.run({"folk_id": folk_id, "action": "set_aspiration", "args": {"aspiration": id}})
			picking = false
			refresh())
		grid.add_child(b)

func _whims(info: Dictionary) -> void:
	heading("Whims (short-term wishes)")
	var whims: Array = info["whims"]
	if whims.is_empty():
		line("No whims right now. New ones pop up as the day goes on.", 13, UITheme.MUTED)
	for w in whims:
		line("%s   +%d" % [str(w["label"]), int(w["points"])], 14)
		line("    " + time_left_text(int(w["minutes_left"])), 11, UITheme.MUTED)
		if int(w["target"]) > 1:
			bar(float(w["progress"]), float(w["target"]), "%d / %d" % [int(w["progress"]), int(w["target"])])
	line("Fulfilling whims and milestones earns satisfaction points to spend below.", 11, UITheme.MUTED)

func _perks(info: Dictionary) -> void:
	heading("Perk shop: %d points to spend (%d earned in total)" % [int(info["points"]), int(info["lifetime_points"])])
	var owned: Array = info["perks"]
	var defs := Goals.perk_defs()
	var ids: Array = defs.keys()
	ids.sort_custom(func(a, b): return int(defs[a].get("cost", 0)) < int(defs[b].get("cost", 0)))
	var shown: int = 0
	var hidden: int = 0
	for pid in ids:
		var d: Dictionary = defs[pid]
		# only what you own, what you can buy now, and the next two you are saving for; the rest is not listed
		var can: bool = Goals.can_buy(folk_id, str(pid))
		if not owned.has(pid) and not can:
			if shown >= 2 + owned.size() + ids.filter(func(x): return not owned.has(x) and Goals.can_buy(folk_id, str(x))).size():
				hidden += 1
				continue
		shown += 1
		var row := HBoxContainer.new()
		body.add_child(row)
		var txt := UIU.make_label("%s: %s" % [str(d.get("label", pid)), str(d.get("description", ""))], 12)
		txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.custom_minimum_size = Vector2(250, 0)
		row.add_child(txt)
		var b := Button.new()
		if owned.has(pid):
			b.text = "Owned"
			b.disabled = true
		else:
			b.text = "%d pts" % int(d.get("cost", 0))
			b.disabled = not Goals.can_buy(folk_id, str(pid))
			if b.disabled:
				b.tooltip_text = "Not enough satisfaction points yet." if int(info["points"]) < int(d.get("cost", 0)) else "Can't unlock this right now."
				b.mouse_filter = Control.MOUSE_FILTER_STOP
			var id := str(pid)
			b.pressed.connect(func():
				Goals.buy_perk(folk_id, id)
				refresh())
		b.custom_minimum_size = Vector2(70, 0)
		row.add_child(b)
	if hidden > 0:
		line("%d more perks unlock as you earn points." % hidden, 11, UITheme.MUTED)
