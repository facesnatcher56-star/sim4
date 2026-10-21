class_name TownDialog
extends UIDialog
## The Town panel: everything the town does in one place, in plain words. The mayor and how the town feels, taxes and where the budget goes as sliders (the player can always
## SEE them; only a player who is the mayor can MOVE them, through the command layer: CityCmd set_tax / focus), the next election, the projects on the planners' plots,
## power / water / phone outages with the time left, and the bus times of the lot the folk is at. Opened by the top bar "Council" button or the mailbox "Read the Town Notice".

# The storyteller log (StorytellerLogPanel, task 29) sits at the bottom: what has been happening in town, in plain words.
var _slot: VBoxContainer = null


func _ready() -> void:
	dialog_width = 540.0
	super._ready()
	UIU.connect_ev("game_event", func(n, p): if n == "town_notice": show_for(int(p.get("folk_id", folk_id))))


func _is_mayor() -> bool:
	return bool(CityGov.mayor.get("player", false)) and int(CityGov.mayor.get("id", -1)) == folk_id


func build() -> void:
	title_label.text = "Town council"
	if CityGov.mayor.is_empty():
		line("The town has no mayor yet.", 13, UITheme.MUTED)
		return
	_mayor()
	_budget()
	_election()
	_projects()
	_outages()
	_buses()
	_slot = VBoxContainer.new()
	_slot.name = "StorytellerSlot"
	body.add_child(_slot)
	var log := StorytellerLogPanel.new()
	log.household_only = true
	_slot.add_child(log)


func _mayor() -> void:
	heading("Mayor")
	var plat: String = str(((CityGov.cfg().get("platforms", {}) as Dictionary).get(str(CityGov.mayor.get("platform", "")), {}) as Dictionary).get("label", ""))
	var pol: Array = []
	for pid in CityGov.policies:
		pol.append(str(((CityPolicy.cfg()[pid]) as Dictionary).get("label", pid)).to_lower())
	var inner: VBoxContainer = UICard.card(body, dialog_width - 50.0, str(CityGov.mayor["name"]), "MAYOR", CityMood.words())
	var chips: Array = []
	if plat != "":
		chips.append(["Platform", plat])
	chips.append(["Laws", ", ".join(pol) if not pol.is_empty() else "none"])
	UICard.chips(inner, chips)
	UICard.note(inner, CityMood.words())


func _budget() -> void:
	heading("Taxes and budget")
	var t: Dictionary = CityGov.cfg().get("tax", {})
	var mayor_now: bool = _is_mayor()
	line("Taxes: %d percent of the standard rate. The town takes in about %d coins a week. Savings: %d coins." % [int(round(CityGov.tax * 100.0)), int(round(CityGov.revenue(CityGov.tax))), int(round(CityGov.treasury))], 12)
	var tax_slider := HSlider.new()
	tax_slider.name = "TaxSlider"
	tax_slider.min_value = float(t.get("min", 0.6))
	tax_slider.max_value = float(t.get("max", 1.6))
	tax_slider.step = float(t.get("step", 0.1))
	tax_slider.value = CityGov.tax
	tax_slider.editable = mayor_now
	tax_slider.tooltip_text = "Only the mayor can change taxes." if not mayor_now else "Drag to change taxes"
	tax_slider.custom_minimum_size = Vector2(dialog_width - 60.0, 18.0)
	if mayor_now:
		tax_slider.value_changed.connect(func(v: float):
			Commands.run({"player_id": Players.LOCAL, "folk_id": folk_id, "action": "city", "args": {"action": "set_tax", "args": {"value": v}}})
			call_deferred("refresh"))
	body.add_child(tax_slider)
	var labels: Dictionary = CityGov.cfg().get("dept_labels", {})
	var lo: float = float(CityGov.cfg().get("alloc_min", 0.03))
	var hi: float = float(CityGov.cfg().get("alloc_max", 0.4))
	for d in CityGov.alloc:
		var row := HBoxContainer.new()
		body.add_child(row)
		var nm := UIU.make_label("%s: %d percent" % [_cap(str(labels.get(d, d))), int(round(float(CityGov.alloc[d]) * 100.0))], 12)
		nm.custom_minimum_size = Vector2(230, 0)
		row.add_child(nm)
		var sl := HSlider.new()
		sl.name = "Alloc_" + str(d)
		sl.min_value = lo
		sl.max_value = hi
		sl.step = 0.01
		sl.value = float(CityGov.alloc[d])
		sl.editable = mayor_now and d != "reserve"
		sl.custom_minimum_size = Vector2(220, 18)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.tooltip_text = "Only the mayor can change the budget." if not mayor_now else "Drag to give this part more or less"
		if mayor_now and d != "reserve":
			var dept: String = str(d)
			sl.value_changed.connect(func(v: float):
				Commands.run({"player_id": Players.LOCAL, "folk_id": folk_id, "action": "city", "args": {"action": "focus", "args": {"dept": dept, "amount": v - float(CityGov.alloc[dept])}}})
				call_deferred("refresh"))
		row.add_child(sl)
	if not mayor_now:
		line("You can see the budget here. Only the mayor can change it.", 11, UITheme.MUTED)


func _cap(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1)


func _election() -> void:
	heading("Next election")
	if CityElection.phase == "campaign":
		line("The campaign is under way. Election day is day %d (%d days away)." % [CityElection.vote_day, maxi(CityElection.vote_day - SysUtil.day(), 0)], 13)
	else:
		var d: int = int(CityGov.mayor.get("term_end", 0))
		line("The next election is on day %d (%d days away)." % [d, maxi(d - SysUtil.day(), 0)], 13)


func _projects() -> void:
	heading("Projects")
	if CityPlan.projects.is_empty():
		line("Nothing is being built. %d reserved plots are still empty." % _free_plots(), 12, UITheme.MUTED)
	for p in CityPlan.projects:
		line(CityPlan.describe(p), 12)
	var done: Array = []
	for plot_id in CityPlan.built_plots:
		done.append(str((CityPlan.kind_def(str(CityPlan.built_plots[plot_id]))).get("short", CityPlan.built_plots[plot_id])))
	if not done.is_empty():
		line("Finished: %s." % ", ".join(done), 12, UITheme.MUTED)


func _free_plots() -> int:
	var n: int = 0
	for id in CityPlan.plot_ids():
		if CityPlan.plot_state(str(id)) == "free":
			n += 1
	return n


func _outages() -> void:
	heading("Power, water and phones")
	var any: bool = false
	for o in Utilities.outages:
		any = true
		line("%s off in %s. Back in about %s." % [Utilities.label(str(o["util"])), CityState.zone_label(str(o["zone"])), Utilities._span(Utilities.minutes_left(o))], 12)
	if not any:
		line("Everything is working.", 12, UITheme.MUTED)
	var dark: int = 0
	for z in CityState.zone_ids():
		dark += int(CityPublic.broken.get(str(z), 0))
	if dark > 0:
		line("%d street lamps are out across town." % dark, 12, UITheme.MUTED)


func _buses() -> void:
	heading("Bus times")
	var f = folk_obj()
	var lot: String = NeighborhoodLots.lot_at(f.tile) if f != null else ""
	if lot == "":
		lot = Neighborhood.HOME
	var lines: Array = TransportBus.timetable_text(lot)
	if lines.is_empty():
		line("No bus stops at %s." % Neighborhood.label_of(lot), 12, UITheme.MUTED)
	else:
		line("%s: %s" % [Neighborhood.label_of(lot), TransportBus.next_text(lot)], 13)
		for l in lines:
			line(str(l), 12, UITheme.MUTED)
		for r in TransportBus.routes():
			var calls: Array = TransportBus.calls_today(str(r["id"]), lot)
			if calls.is_empty():
				continue
			var bits: Array = []
			for m in calls:
				bits.append(TransportBus.clock_text(int(m)))
			line("%s today: %s" % [str(r["name"]), " ".join(bits)], 11, UITheme.MUTED)
