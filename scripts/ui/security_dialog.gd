class_name SecurityDialog
extends UIDialog
## Security of the household (task 21): what protects the home (read from the objects bought in build mode), alarm monitoring and a hired guard,
## the camera footage log, the insurance discount, and cover for the businesses the household owns. Opened from the case board. Plain words only;
## every purchase goes through the command layer (action `crimelife`).

func _ready() -> void:
	dialog_width = 520.0
	super._ready()

static func open_from(from: Node, fid: int) -> void:
	var host: Node = from.get_parent() if from.get_parent() != null else from
	for c in host.get_children():
		if c is SecurityDialog:
			(c as SecurityDialog).show_for(fid)
			return
	var d := SecurityDialog.new()
	host.add_child(d)
	d.show_for(fid)

func _cmd(args: Dictionary) -> void:
	var r: Dictionary = Commands.run({"player_id": Players.local_id, "folk_id": folk_id, "action": "crimelife", "args": args})
	if str(r.get("msg", "")) != "":
		SysUtil.notify(str(r["msg"]), "info" if bool(r.get("ok", false)) else "warn")
	refresh()

func build() -> void:
	title_label.text = "Security"
	var f = folk_obj()
	var hid: int = int(f.household_id) if f != null else 1
	var p: Dictionary = CrimeSecurity.home_profile(hid)
	heading("Your home")
	line(CrimeSecurity.describe(p), 14)
	bar(float(CrimeSecurity.score(p)), 100.0, "How hard your home is to break into and how likely a break-in is to be noticed.")
	line("Locks, window locks, an alarm, cameras, motion sensors, a safe, lights and a guard-dog kennel are bought in build mode (Security).", 11, UITheme.MUTED)
	var cut: int = int(round((1.0 - CrimeSecurityAlarm.insurance_mult(hid)) * 100.0))
	line("Alarms, cameras and good locks take %d%% off your home insurance." % cut if cut > 0 else "Alarms, cameras and good locks would earn a discount on your home insurance.", 12, UITheme.MUTED)
	_services(hid, p)
	var lines: Array = CrimeSecurityFootage.lines("home:%d" % hid)
	if int(p["cameras"]) > 0 or not lines.is_empty():
		heading("Camera log")
		if lines.is_empty():
			line("Quiet so far.", 12, UITheme.MUTED)
		for l in lines.slice(maxi(lines.size() - 5, 0)):
			line(str(l), 12)
		line("Stand at a camera and choose Review the Camera Footage to check the recordings.", 11, UITheme.MUTED)
	_businesses(hid)

func _services(hid: int, p: Dictionary) -> void:
	heading("Services")
	var up: Dictionary = CrimeSecurityUpgrade.defs()
	var mon := Button.new()
	if bool(p["monitored"]):
		mon.text = "Stop alarm monitoring (%d coins a week)" % int(CrimeSecurity.cfg().get("monitoring_weekly", 18))
		mon.pressed.connect(func(): _cmd({"action": "home_service", "key": "monitored", "value": 0}))
	else:
		mon.text = "Alarm monitoring: police called for you, and faster (%d coins to set up)" % int((up["monitored"]["price"] as Array)[1])
		mon.disabled = not bool(p["alarm"])
		mon.tooltip_text = "Needs a burglar alarm first." if not bool(p["alarm"]) else ""
		mon.pressed.connect(func(): _cmd({"action": "home_service", "key": "monitored", "value": 1}))
	body.add_child(mon)
	var g: int = int(p["guards"])
	var gb := Button.new()
	var nxt: int = CrimeSecurityUpgrade.next_price("guard", g)
	if nxt < 0:
		gb.text = "Your guards are the best there is"
		gb.disabled = true
	else:
		gb.text = "Hire a guard for the house (%d coins, then %d a week)" % [nxt, int((up["guard"]["weekly"] as Array)[g + 1])]
		gb.pressed.connect(func(): _cmd({"action": "home_service", "key": "guard", "value": g + 1}))
	body.add_child(gb)
	if g > 0:
		var fb := Button.new()
		fb.text = "Let the guard go"
		fb.pressed.connect(func(): _cmd({"action": "home_service", "key": "guard", "value": 0}))
		body.add_child(fb)

func _businesses(hid: int) -> void:
	var mine: Array = []
	for id in BusinessState.list:
		var b: Dictionary = BusinessState.list[id]
		if str(b["owner_kind"]) == "player" and int(b["owner"]) == hid:
			mine.append(b)
	if mine.is_empty():
		return
	heading("Your businesses")
	for b in mine:
		var prof: Dictionary = CrimeSecurity.business_profile(str(b["type"]), int(b["id"]))
		line("%s: %s" % [str(b["name"]), CrimeSecurity.describe(prof)], 13)
		var row := HFlowContainer.new()
		body.add_child(row)
		for key in ["lock", "alarm", "monitored", "camera", "motion", "light", "safe", "guard", "detective"]:
			var lvl: int = CrimeSecurityUpgrade.level_of_biz(int(b["id"]), key)
			var price: int = CrimeSecurityUpgrade.next_price(key, lvl)
			if price < 0:
				continue
			var bt := Button.new()
			bt.text = "%s (%d)" % [str(CrimeSecurityUpgrade.defs()[key].get("label", key)), price]
			bt.pressed.connect(func(): _cmd({"action": "biz_upgrade", "biz": int(b["id"]), "key": key}))
			row.add_child(bt)
