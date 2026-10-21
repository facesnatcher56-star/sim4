class_name LifeHubPhone
extends RefCounted
## The "Phone" tab of LifeHub: invitations that came in (answer yes or no), the contact list (call, text, ask out) and the social media app.
## Asking out picks an outing from data (Cinema, Lunch, Bowling ...); the buttons are greyed out with the reason in the tooltip.

static var asking: int = -1            # contact being asked out (-1 = none)

static var app: String = ""             # "" = the phone's home screen, else the open app: messages | jobs | bank

static func build(dlg: LifeHub) -> void:
	var f = dlg.folk_obj()
	var fid: int = dlg.folk_id
	if str(f.age_stage) in ["baby", "toddler", "child"]:
		dlg.line("%s is too young for a phone." % f.name, 14, UITheme.MUTED)
		return
	var why: String = PhoneOwn.block(fid)
	if why != "":
		_no_phone(dlg, fid, why)
		return
	if app == "":
		_home(dlg, fid)
		return
	dlg.body.add_child(dlg.button("< Home", "Back to the phone's home screen", func():
		app = ""
		dlg.refresh()))
	match app:
		"jobs":
			LifeHubJobs.build(dlg)
		"bank":
			_bank(dlg, f)
		"news":
			LifeHubMedia.build(dlg)
		_:
			_messages(dlg, f, fid)

static func _app_tile(dlg: LifeHub, row: Container, label: String, badge: String, id: String) -> void:
	var b: Button = dlg.button(label + ("  (%s)" % badge if badge != "" else ""), "Open " + label, func():
		app = id
		dlg.refresh())
	b.custom_minimum_size = Vector2(92, 76)
	row.add_child(b)

static func _home(dlg: LifeHub, fid: int) -> void:
	dlg.heading("Phone")
	var fl := HFlowContainer.new()
	dlg.body.add_child(fl)
	var msgs: int = PhoneState.inbox_of(fid).size()
	_app_tile(dlg, fl, "Messages", "%d new" % msgs if msgs > 0 else "", "messages")
	_app_tile(dlg, fl, "Jobs", "offer" if not Careers.pending_offer(fid).is_empty() else "", "jobs")
	_app_tile(dlg, fl, "Bank", "", "bank")
	_app_tile(dlg, fl, "News", "", "news")
	var f = dlg.folk_obj()
	var d: Dictionary = PhoneOwn.kind_def(str(PhoneOwn.own.get(fid, {}).get("kind", "")))
	dlg.line("Your %s. Weekly line charge: %d coins." % [str(d.get("label", "phone")), int(SoloCfg.by_diff("phone", "bill_amount"))], 12, UITheme.MUTED)
	dlg.body.add_child(dlg.button("Pawn the phone (%d coins)" % int(d.get("sell", 0)), "You will have no phone until you buy another", func(): dlg.act("phone_sell")))

static func _bank(dlg: LifeHub, f) -> void:
	var hid: int = int(f.household_id)
	dlg.heading("Bank")
	dlg.line("Coins: %d" % Economy.balance(hid), 15, UITheme.TEXT)
	var due: Array = Economy.outstanding(hid)
	if due.is_empty():
		dlg.line("No bills waiting.", 13, UITheme.MUTED)
	for bl in due:
		var what: String = str(bl.get("reason", "")).capitalize() if str(bl.get("reason", "")) != "" else "Household bills"
		dlg.line("%s: %d coins, due day %d%s" % [what, int(bl["amount"]), int(bl["due"]), " (late)" if bool(bl["late"]) else ""], 13, UITheme.MUTED)

## No working phone: why, how to get one, and the other ways to find work (the job centre counter at city hall, the paper).
static func _no_phone(dlg: LifeHub, fid: int, why: String) -> void:
	dlg.heading("No phone")
	dlg.line(why, 14, UITheme.MUTED)
	if PhoneOwn.status(fid) == "broken":
		dlg.body.add_child(dlg.button("Pawn the broken phone", "A little cash for the parts", func(): dlg.act("phone_sell")))
	if PhoneOwn.status(fid) != "ok":
		var fl := HFlowContainer.new()
		dlg.body.add_child(fl)
		for k in (SoloCfg.sect("phone").get("kinds", {}) as Dictionary):
			var kd: Dictionary = PhoneOwn.kind_def(str(k))
			var w: String = PhoneOwn.why_not_buy(fid, str(k))
			fl.add_child(dlg.button("Buy a %s (%d)" % [str(kd["label"]), int(kd["price"])], w if w != "" else "Buy it here", func(): dlg.act("phone_buy", {"kind": k}), w == ""))
	CareerDialog.offer_card(dlg, fid)          # a pending offer (it came by letter) is answered here
	dlg.heading("Finding work without a phone")
	var hrs: Array = (SoloCfg.sect("phone").get("job_centre", {}) as Dictionary).get("hours", [9, 17])
	dlg.line("The job centre counter at city hall shows the same board (%02d:00-%02d:00). The paper has a few of this week's openings." % [int(hrs[0]), int(hrs[1])], 13, UITheme.MUTED)
	var h: String = PhoneJobs.how(fid)
	if h == "centre":
		LifeHubJobs.build(dlg)
		return
	var price: int = int((SoloCfg.sect("phone").get("paper", {}) as Dictionary).get("price", 2))
	if PhoneJobs.paper_careers(fid).is_empty():
		dlg.body.add_child(dlg.button("Buy the paper (%d)" % price, "Today's job ads", func(): dlg.act("paper")))
	else:
		dlg.line("Today's paper:", 13, UITheme.MUTED)
		LifeHubJobs.build(dlg, PhoneJobs.paper_careers(fid))

static func _messages(dlg: LifeHub, f, fid: int) -> void:
	var inbox: Array = PhoneState.inbox_of(fid)
	if not inbox.is_empty():
		dlg.heading("Messages")
		for m in inbox:
			dlg.row_with(str(m["text"]), [dlg.button("Yes", "Go along", func(): dlg.act("phone_respond", {"id": m["id"], "yes": true})),
				dlg.button("No thanks", "Say no politely", func(): dlg.act("phone_respond", {"id": m["id"], "yes": false}))])
	dlg.heading("Contacts")
	var cs: Array = PhoneCmd.contacts(fid)
	if cs.is_empty():
		dlg.line("Nobody in the contacts yet. Meet people around town.", 13, UITheme.MUTED)
	for c in cs:
		var why: String = str(c["reason"])
		var txt: String = "%s, %s (%d)" % [c["name"], str(c["label"]).to_lower(), int(c["friendship"])]
		dlg.row_with(txt + ("" if why == "" else ". " + why), [
			dlg.button("Call", why if why != "" else "Have a chat", func(): dlg.act("phone_call", {"other": c["id"]}), why == ""),
			dlg.button("Text", why if why != "" else "A quick message", func(): dlg.act("phone_text", {"other": c["id"]}), why == ""),
			dlg.button("Ask out", why if why != "" else "Invite them somewhere", func():
				asking = int(c["id"]) if asking != int(c["id"]) else -1
				dlg.refresh(), why == "")], why != "")
		if asking == int(c["id"]):
			var fl := HFlowContainer.new()
			dlg.body.add_child(fl)
			for o in LifeOuting.outings():
				var w: String = LifeOuting.why_not(fid, int(c["id"]), o)
				var b := dlg.button(UIU.sentence(str(o["label"])), w if w != "" else "Ask %s along" % c["name"], func():
					asking = -1
					dlg.act("phone_invite", {"other": c["id"], "outing": o["id"]}), w == "")
				fl.add_child(b)
	dlg.heading("Social media")
	var fl2 := HFlowContainer.new()
	dlg.body.add_child(fl2)
	for kind in SocialFeed.kinds():
		var why2: String = SocialFeed.why_not(fid, str(kind))
		fl2.add_child(dlg.button(str(SocialFeed.kinds()[kind]["label"]), why2 if why2 != "" else "Post it", func(): dlg.act("post", {"kind": kind}), why2 == ""))
	dlg.line("Fame: %s." % LifeFame.label(fid), 13, UITheme.MUTED)
	for p in SocialFeed.feed(6):
		dlg.line("Day %d: %s" % [int(p["day"]), str(p["text"])], 13, UITheme.MUTED)
