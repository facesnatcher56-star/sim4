class_name LifeHubPlaces
extends RefCounted
## The "Places" tab of LifeHub: pick a kind of place, then a place; see its hours, staff and what it offers; go there; use a service.
## A service button is greyed out with the reason in its tooltip (closed, too young, too poor, "go there first").

const KINDS := [["", "All"], ["education", "Learning"], ["health", "Clinics and Gym"], ["food", "Food"], ["night", "Nightlife"], ["culture", "Culture"], ["leisure", "Leisure"], ["community", "Community"], ["family", "Events"], ["media", "Media"], ["pets", "Vet and Shelter"], ["hobby", "Hobbies"]]

static var show_all: bool = false             # only the nearest few open places are listed until asked
static var closed_open: bool = false          # the "Closed right now" list is collapsed until asked for

static func _walk(dlg: LifeHub, f, pid: String) -> int:
	var lot: String = Places.lot_of(pid)
	if not Places.on_map(lot):
		return 9999
	var m: int = Neighborhood.walk_minutes(dlg.folk_id, PlayerLots.home_of(f) if lot == Places.HOME else lot)
	return 9999 if m < 0 else m

static func _place_button(dlg: LifeHub, f, pid: String, is_open: bool) -> Button:
	var b := Button.new()
	var mins: int = _walk(dlg, f, pid) if is_open else 9999
	b.text = Places.label(pid) + ("" if not is_open or mins >= 9999 or Places.is_there(f, pid) else "  %d min" % mins)
	b.toggle_mode = true
	b.button_pressed = (dlg.place_id == pid)
	b.tooltip_text = Places.status_text(pid)
	b.modulate = Color(1, 1, 1, 1.0 if is_open else 0.6)
	b.pressed.connect(func():
		dlg.place_id = pid
		dlg.refresh())
	return b

static func build(dlg: LifeHub) -> void:
	var f = dlg.folk_obj()
	var kinds_here: Array = []
	for pid in Places.all():
		if Places.usable_by(str(pid), f) and not kinds_here.has(Places.kind_of(pid)):
			kinds_here.append(Places.kind_of(pid))
	var row := HFlowContainer.new()
	dlg.body.add_child(row)
	for k in KINDS:
		if str(k[0]) != "" and not kinds_here.has(k[0]):
			continue
		var b := Button.new()
		b.text = str(k[1])
		b.toggle_mode = true
		b.button_pressed = (dlg.kind == k[0])
		b.pressed.connect(func():
			dlg.kind = str(k[0])
			dlg.place_id = ""
			dlg.refresh())
		row.add_child(b)
	var ids: Array = Places.ids_of_kind(dlg.kind).filter(func(p): return Places.usable_by(str(p), f))          # a TV, a radio or a pet at home only when the home has one
	var open_ids: Array = ids.filter(func(p): return Places.is_open(str(p)))
	var closed_ids: Array = ids.filter(func(p): return not Places.is_open(str(p)))
	open_ids.sort_custom(func(a, b): return _walk(dlg, f, str(a)) < _walk(dlg, f, str(b)))          # nearest first
	if dlg.place_id == "" or not ids.has(dlg.place_id):
		dlg.place_id = "" if open_ids.is_empty() else str(open_ids[0])
	if open_ids.is_empty():
		dlg.line("Nothing of this kind is open right now.", 14, UITheme.MUTED)
	var prow := HFlowContainer.new()
	dlg.body.add_child(prow)
	var cap: int = 8
	for i in open_ids.size():
		if not show_all and i >= cap and str(open_ids[i]) != dlg.place_id:
			continue
		prow.add_child(_place_button(dlg, f, str(open_ids[i]), true))
	if open_ids.size() > cap:
		var more := Button.new()
		more.flat = true
		more.text = "Show fewer" if show_all else "More places (%d)" % (open_ids.size() - cap)
		more.pressed.connect(func():
			show_all = not show_all
			dlg.refresh())
		dlg.body.add_child(more)
	if not closed_ids.is_empty():
		var tog := Button.new()
		tog.flat = true
		tog.text = "%s Closed right now (%d)" % ["▾" if closed_open else "▸", closed_ids.size()]
		tog.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tog.pressed.connect(func():
			closed_open = not closed_open
			dlg.refresh())
		dlg.body.add_child(tog)
		if closed_open:
			var crow := HFlowContainer.new()
			dlg.body.add_child(crow)
			for pid2 in closed_ids:
				crow.add_child(_place_button(dlg, f, str(pid2), false))
	if dlg.place_id == "":
		return
	_place(dlg, f, dlg.place_id)

static func _place(dlg: LifeHub, f, pid: String) -> void:
	var d: Dictionary = Places.def(pid)
	dlg.heading(Places.label(pid))
	dlg.line("%s. At %s." % [Places.status_text(pid), Places.lot_label(pid)], 14)
	if str(d.get("blurb", "")) != "":
		dlg.line(str(d["blurb"]), 13, UITheme.MUTED)
	var staff: Array = PlaceStaff.roster(pid)
	if not staff.is_empty():
		dlg.line("Staff: " + ", ".join(staff.map(func(e): return "%s (%s)" % [e["name"], str(e["role"]).to_lower()])), 13, UITheme.MUTED)
	if not Places.is_there(f, pid):
		var lot: String = Places.lot_of(pid)
		var mins: int = Neighborhood.walk_minutes(dlg.folk_id, PlayerLots.home_of(f) if lot == Places.HOME else lot)
		dlg.row_with("You are not there. It is a walk of about %s." % SysUtil.count_text(mins, "minute"),
			[dlg.button("Go there", "Walk to " + Places.lot_label(pid), func(): dlg.act("go", {"place": pid}), Places.on_map(lot))])
	var svcs: Dictionary = Places.services(pid)
	if svcs.is_empty():
		dlg.line("Nothing to buy here. Just a busy place.", 13, UITheme.MUTED)
	for sid in svcs:
		var s: Dictionary = svcs[sid]
		var why: String = PlaceUse.why_not(dlg.folk_id, pid, str(sid))
		var price: int = PlaceUse.price(pid, str(sid), dlg.folk_id)
		var txt: String = "%s%s%s%s" % [Places.service_label(pid, str(sid)), " (today's special)" if FoodMenu.is_special(pid, str(sid)) else "", "" if price <= 0 else ", %d coins" % price, "" if int(s.get("minutes", 0)) <= 0 else ", about %s" % _span(int(s["minutes"]))]
		dlg.row_with(txt, [dlg.button("Use", why if why != "" else "Go ahead", func(): dlg.act("use", {"place": pid, "service": sid}), why == "")], why != "")

static func _span(minutes: int) -> String:
	if minutes < 60:
		return "%d min" % minutes
	var h: float = float(minutes) / 60.0
	return "%s hour%s" % [str(snappedf(h, 0.5)).trim_suffix(".0"), "" if h <= 1.0 else "s"]
