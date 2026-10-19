class_name LifeHubPhone
extends RefCounted
## The "Phone" tab of LifeHub: invitations that came in (answer yes or no), the contact list (call, text, ask out) and the social media app.
## Asking out picks an outing from data (Cinema, Lunch, Bowling ...); the buttons are greyed out with the reason in the tooltip.

static var asking: int = -1            # contact being asked out (-1 = none)

static func build(dlg: LifeHub) -> void:
	var f = dlg.folk_obj()
	var fid: int = dlg.folk_id
	if str(f.age_stage) in ["baby", "toddler", "child"]:
		dlg.line("%s is too young for a phone." % f.name, 14, UITheme.MUTED)
		return
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
				var b := dlg.button(str(o["label"]).capitalize(), w if w != "" else "Ask %s along" % c["name"], func():
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
