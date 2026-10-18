class_name SharePageMail
extends RefCounted
## Gifts & letters: what has arrived at the mailbox, and leaving a coin gift or a letter in a friend's town file.

static var _letter: LineEdit = null

static func build(h: ShareHub) -> void:
	h.heading("Received")
	if ShareState.received.is_empty():
		h.line("Nothing yet.", 13, UITheme.MUTED)
	for g in ShareState.received:
		match str(g["kind"]):
			"letter":
				h.line("Letter from %s (day %d): %s" % [g["from"], int(g["day"]), g["text"]], 13)
			"coins":
				h.line("%d coins from %s (day %d)" % [int(g["coins"]), g["from"], int(g["day"])], 13)
			"object":
				h.line("%s from %s (day %d)" % [ShareMail.object_label(str(g["object"])), g["from"], int(g["day"])], 13)
	h.heading("Leave something in a friend's town file")
	h.folder_line()
	var files: Array = ShareFile.list("town")
	if files.is_empty():
		h.line("No town files in the folder.", 13, UITheme.MUTED)
		return
	for f in files:
		h.pick_button(str(f), str(f))
	if h.choice == "":
		return
	var max_letter: int = int((ShareClean.cap("gift", {}) as Dictionary).get("max_letter", 500))
	_letter = LineEdit.new()
	_letter.placeholder_text = "A short letter (up to %d characters)" % max_letter
	_letter.max_length = max_letter
	h.body.add_child(_letter)
	var from := _sender()
	h.action_button("Leave the letter", func(): _leave(h, {"from": from, "kind": "letter", "text": _letter.text}))
	var cap: int = int((ShareClean.cap("gift", {}) as Dictionary).get("max_coins", 500))
	for amt in [50, 200, cap]:
		h.action_button("Leave %d coins" % amt, func(): _leave(h, {"from": from, "kind": "coins", "coins": amt}))

static func _sender() -> String:
	var res: Array = SysUtil.residents()
	return (ShareValidate.surname(str((res[0] as Folk).name)) + " family") if not res.is_empty() else "A friend"

static func _leave(h: ShareHub, gift: Dictionary) -> void:
	var res: Array = SysUtil.residents()
	if str(gift["kind"]) == "coins":
		if res.is_empty() or WorldIface.get_coins(int(res[0].household_id)) < int(gift["coins"]):
			h.say("You do not have that many coins.")
			return
	var r := ShareExport.leave_gift(h.choice, gift)
	if bool(r["ok"]) and str(gift["kind"]) == "coins":
		Economy.deposit(int(res[0].household_id), -int(gift["coins"]), "gift")
	h.say(("Left in %s. It will be waiting at their mailbox." % h.choice) if bool(r["ok"]) else ("Could not leave it: %s." % r["error"]))
