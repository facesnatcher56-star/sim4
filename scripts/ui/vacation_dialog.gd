class_name VacationDialog
extends UIDialog
## Holidays (task 22): plan and book a trip (destination, length, who goes, invited friends, cabin class and package for cruises, house-sitter,
## the price in plain lines and what it means for work and school), see the trip in progress (where, how long, ship alerts, go ashore / back on board,
## come home early) and the souvenirs and photos of earlier trips. Opened by the "Plan a Holiday" interaction (game event vacation_open_booking).
## Every button goes through Commands.run (action "vacation" -> Vacation.command): the multiplayer-ready command door.

var dest: String = "beach"
var days: int = 3
var cabin_class: String = "inside"
var package_id: String = "standard"
var sitter: bool = false
var who: Dictionary = {}          # folk id -> bool
var guests: Dictionary = {}       # townie id -> bool
var _price_box: VBoxContainer

func _ready() -> void:
	dialog_width = 520.0
	super._ready()

func hid() -> int:
	var f = folk_obj()
	return int(f.household_id) if f != null else Economy.primary_household()

func show_for(fid: int) -> void:
	who.clear()
	guests.clear()
	for f in VacationCost.household_folk(hid()):
		who[int(f.id)] = true
	super.show_for(fid)

func build() -> void:
	title_label.text = "Holidays"
	var t: Dictionary = Vacation.trip_of_household(hid())
	if t.is_empty():
		_booking()
	else:
		_trip(t)
	_collection()

# ------------------------------------------------------------------ booking
func _booking() -> void:
	heading("Where to?")
	var row := HFlowContainer.new()
	body.add_child(row)
	for d in Vacation.destinations():
		var b := Button.new()
		b.text = str(d["label"])
		b.toggle_mode = true
		b.button_pressed = str(d["id"]) == dest
		b.tooltip_text = str(d["blurb"])
		var did: String = str(d["id"])
		b.pressed.connect(func():
			dest = did
			var r: Array = VacationCost.day_range(dest)
			days = clampi(days, int(r[0]), int(r[1]))
			refresh())
		row.add_child(b)
	line(str(_dest_blurb()), 12, UITheme.MUTED)
	heading("How long?")
	var rng_d: Array = VacationCost.day_range(dest)
	var sp := SpinBox.new()
	sp.min_value = int(rng_d[0])
	sp.max_value = int(rng_d[1])
	sp.value = days
	sp.suffix = " days"
	sp.value_changed.connect(func(v):
		days = int(v)
		_update_price())
	body.add_child(sp)
	heading("Who goes?")
	for f in VacationCost.household_folk(hid()):
		var cb := CheckBox.new()
		var br: String = VacationCost.busy_reason(f)
		cb.text = str(f.name) + ("  (%s)" % br if br != "" else "")
		cb.button_pressed = bool(who.get(int(f.id), false)) and br == ""
		cb.disabled = br != ""
		var fid: int = int(f.id)
		cb.toggled.connect(func(on):
			who[fid] = on
			_update_price())
		body.add_child(cb)
	var friends: Array = _friends()
	if not friends.is_empty():
		heading("Invite a friend (they come along at your cost)")
		for pr in friends:
			var gb := CheckBox.new()
			gb.text = str(pr["name"])
			gb.button_pressed = bool(guests.get(int(pr["id"]), false))
			var gid: int = int(pr["id"])
			gb.toggled.connect(func(on):
				guests[gid] = on
				_update_price())
			body.add_child(gb)
	if dest == "cruise":
		heading("Cabin")
		var ob := OptionButton.new()
		var cls: Dictionary = VacationCost.cruise_cfg().get("classes", {})
		var keys: Array = ["inside", "ocean", "suite"]
		for k in keys:
			ob.add_item("%s (%d coins a night)" % [str(cls[k]["label"]), int(cls[k]["per_day"])])
		ob.select(maxi(keys.find(cabin_class), 0))
		ob.item_selected.connect(func(i):
			cabin_class = str(keys[i])
			_update_price())
		body.add_child(ob)
		var pk := OptionButton.new()
		var pkgs: Dictionary = VacationCost.cruise_cfg().get("packages", {})
		var pkeys: Array = ["standard", "honeymoon", "anniversary"]
		for k2 in pkeys:
			pk.add_item(str(pkgs[k2]["label"]))
		pk.select(maxi(pkeys.find(package_id), 0))
		pk.item_selected.connect(func(i):
			package_id = str(pkeys[i])
			_update_price())
		body.add_child(pk)
	var sb := CheckBox.new()
	sb.text = "Pay a house-sitter (keeps the plants and the post, lowers burglary risk)"
	sb.button_pressed = sitter
	sb.toggled.connect(func(on):
		sitter = on
		_update_price())
	body.add_child(sb)
	heading("Price")
	_price_box = VBoxContainer.new()
	body.add_child(_price_box)
	_update_price()

func _dest_blurb() -> String:
	for d in Vacation.destinations():
		if str(d["id"]) == dest:
			return str(d["blurb"])
	return ""

func _friends() -> Array:
	var out: Array = []
	var f = folk_obj()
	if f == null:
		return out
	for o in RelationshipService.all_known(int(f.id)):
		var oid: int = int(o)
		if Story.townies.has(oid) and bool(Story.townies[oid].get("alive", false)) and RelationshipService.value(int(f.id), oid, "friendship") >= 10.0 \
				and Story.stage_of(Story.townies[oid]) in ["teen", "adult", "elder"]:
			out.append({"id": oid, "name": str(Story.townies[oid]["name"])})
		if out.size() >= 6:
			break
	return out

func opts() -> Dictionary:
	var w: Array = []
	for k in who:
		if bool(who[k]):
			w.append(int(k))
	var g: Array = []
	for k2 in guests:
		if bool(guests[k2]):
			g.append(int(k2))
	return {"length_days": days, "who": w, "guests": g, "cabin_class": cabin_class, "package": package_id, "sitter": sitter, "household_id": hid()}

func _update_price() -> void:
	if _price_box == null or not is_instance_valid(_price_box):
		return
	for c in _price_box.get_children():
		_price_box.remove_child(c)
		c.queue_free()
	var q: Dictionary = Vacation.quote(hid(), dest, opts())
	for l in q.get("lines", []):
		_price_box.add_child(_row("%s" % str(l["label"]), "%d" % int(l["amount"])))
	if bool(q.get("ok", false)) or not (q.get("lines", []) as Array).is_empty():
		_price_box.add_child(_row("Total", "%d coins" % int(q.get("total", 0)), true))
	for lv in q.get("leave", []):
		var txt: String = "%s: " % str(lv["name"])
		if int(lv["work_days"]) > 0:
			txt += "%d work days off (%d paid leave, %d unpaid: performance suffers). " % [int(lv["work_days"]), int(lv["paid"]), int(lv["unpaid"])]
		if int(lv["school_days"]) > 0:
			txt += "%d school days missed (grade drops)." % int(lv["school_days"])
		_price_box.add_child(_note(txt))
	if not bool(q.get("ok", false)):
		_price_box.add_child(_note(str(q.get("reason", "")), Color("#e8913d")))
	var go := Button.new()
	go.text = "Book it and go"
	go.disabled = not bool(q.get("ok", false))
	go.pressed.connect(func():
		var res: Dictionary = Commands.run({"player_id": Players.LOCAL, "folk_id": folk_id, "action": "vacation", "args": {"action": "book", "args": _book_args()}})
		if bool(res.get("ok", false)):
			hide_dialog())
	_price_box.add_child(go)

func _book_args() -> Dictionary:
	var a: Dictionary = opts()
	a["dest"] = dest
	return a

func _row(a: String, b: String, strong: bool = false) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := UIU.make_label(a, 14 if not strong else 16)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(UIU.make_label(b, 14 if not strong else 16, Color("#f2c94c") if strong else UITheme.TEXT))
	return h

func _note(text: String, color: Color = UITheme.MUTED) -> Label:
	var l := UIU.make_label(text, 12, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(dialog_width - 60.0, 0)
	return l

# ------------------------------------------------------------------ a trip in progress
func _trip(t: Dictionary) -> void:
	heading("%s" % str(t["label"]))
	var st: String = str(t["state"])
	var now: int = SysUtil.now()
	var names: Array = VacationTrip.members(t).map(func(x): return str(x.name))
	line("%s" % ", ".join(names), 15)
	match st:
		"booked":
			line("Booked. Leaving in %s." % _mins(int(t["depart_min"]) - now), 14)
			_btn("Cancel the trip (80% back)", func(): Commands.run({"folk_id": folk_id, "action": "vacation", "args": {"action": "cancel", "args": {"trip": int(t["id"])}}}))
		"outbound":
			line("On the way. Arriving in %s." % _mins(int(t["arrive_min"]) - now), 14)
		"inbound":
			line("On the way home. Back in %s." % _mins(int(t["return_min"]) - now), 14)
		_:
			_there(t, now)
	line("Spending money left: %d coins. Photos: %d. Souvenirs: %d." % [int(t["wallet"]), int(t["photos"]), (t["souvenirs"] as Array).size()], 13, UITheme.MUTED)
	var log: Array = t.get("log", [])
	if not log.is_empty():
		heading("Lately")
		for e in log.slice(maxi(log.size() - 6, 0)):
			line("Day %d: %s" % [int(e["day"]), str(e["text"])], 12, UITheme.MUTED)

func _there(t: Dictionary, now: int) -> void:
	if str(t["dest"]) != "cruise":
		line("%s. Weather: %s. Heading home in %s." % [str(t["label"]), str(t.get("weather", "")), _mins(int(t["end_min"]) - now)], 14)
		_btn("Come home early", func(): Commands.run({"folk_id": folk_id, "action": "vacation", "args": {"action": "come_home", "args": {"trip": int(t["id"])}}}))
		return
	var c: Dictionary = t["cruise"]
	line("%s, %s. Sea: %s. Home at the quay in %s." % [str(c["name"]), str(c["phase"]), str(c["sea"]), _mins(CruiseRoute.first_min(c["timeline"], "home_dock") - now)], 14)
	if bool(c.get("restricted", false)):
		line("The captain has restricted movement on the ship.", 13, Color("#e8913d"))
	heading("Route")
	for r in c["route"]:
		var what: String = {"embark": "Sail from home", "sea": "At sea", "home": "Home"}.get(str(r["kind"]), "Port: %s" % str(r["label"]))
		line("Day %d: %s" % [int(r["day"]), what], 12, UITheme.MUTED)
	if int(c["port_zone"]) >= 0 and str(c["phase"]) == "docked":
		var here: bool = not CruiseShore.ashore_members(t).is_empty()
		_btn("Go ashore", func(): Commands.run({"folk_id": folk_id, "action": "vacation", "args": {"action": "go_ashore", "args": {}}}))
		_btn("Back to the ship", func(): Commands.run({"folk_id": folk_id, "action": "vacation", "args": {"action": "board", "args": {}}}))
		if here:
			line("Be back on the ship by 16:30 or it sails without you, and the flight home is expensive.", 12, Color("#e8913d"))

func _btn(text: String, fn: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		fn.call()
		refresh())
	body.add_child(b)

func _mins(m: int) -> String:
	m = maxi(m, 0)
	return "%dd %dh" % [m / 1440, (m % 1440) / 60] if m >= 1440 else ("%dh %dm" % [m / 60, m % 60] if m >= 60 else "%d min" % m)

# ------------------------------------------------------------------ keepsakes
func _collection() -> void:
	var sv: Array = Vacation.souvenirs_of(hid())
	var ph: Array = Vacation.photos_of(hid())
	if sv.is_empty() and ph.is_empty():
		return
	heading("Keepsakes")
	line("%d photos, %d souvenirs." % [ph.size(), sv.size()], 13)
	for s in sv.slice(maxi(sv.size() - 4, 0)):
		line("  A %s" % str(s["label"]), 12, UITheme.MUTED)
	for p in ph.slice(maxi(ph.size() - 4, 0)):
		line("  Photo, day %d: %s" % [int(p["day"]), str(p["text"])], 12, UITheme.MUTED)
