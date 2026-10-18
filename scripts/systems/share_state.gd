class_name ShareState
extends RefCounted
## Saved state of the sharing feature (systems.share): gifts waiting in the mailbox, letters and keepsakes already received,
## and the family histories of imported households. A gift is delivered once: it leaves `inbox`, and its fingerprint is also
## kept in a small user:// file so loading the same slot (or importing the same town file) twice never pays out twice.

static var inbox: Array = []         # waiting: {from, kind, coins|object|text}
static var received: Array = []      # delivered: {from, kind, coins|object|text, day}
static var families: Dictionary = {} # key -> {title, history:[lines], legacy:{...}, day}
static var town_title: String = ""   # title of the imported town file (part of a gift's fingerprint)
static var seen_path: String = "user://share_seen.json"
static var _next_family: int = 1

static func reset() -> void:
	inbox.clear()
	received.clear()
	families.clear()
	town_title = ""
	_next_family = 1

static func to_dict() -> Dictionary:
	return {"inbox": inbox.duplicate(true), "received": received.duplicate(true), "families": families.duplicate(true), "town_title": town_title, "next_family": _next_family}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	var gi: Dictionary = ShareValidate.gifts(d.get("inbox", []))
	inbox = gi["data"] if bool(gi["ok"]) else []
	var rraw: Variant = d.get("received", [])
	if rraw is Array:
		for r in (rraw as Array).slice(0, 50):
			var bare: Variant = (r as Dictionary).duplicate() if r is Dictionary else r
			if bare is Dictionary:
				(bare as Dictionary).erase("day")
			var rv: Dictionary = ShareValidate.gifts([bare])
			if bool(rv["ok"]) and not (rv["data"] as Array).is_empty():
				var item: Dictionary = (rv["data"] as Array)[0]
				item["day"] = ShareClean.clampi_((r as Dictionary).get("day", 0), 0, 1000000)
				received.append(item)
	for k in (d.get("families", {}) as Dictionary):
		var fam: Variant = d["families"][k]
		if fam is Dictionary:
			var hist := ShareValidate.lines(fam.get("history", []), int(ShareClean.cap("max_history", 40)))
			families[ShareClean.key(str(k))] = {"title": ShareClean.text(fam.get("title", ""), int(ShareClean.cap("max_title", 48))),
				"history": hist["data"] if bool(hist["ok"]) else [], "legacy": fam.get("legacy", {}) if fam.get("legacy", {}) is Dictionary else {},
				"day": ShareClean.clampi_(fam.get("day", 0), 0, 1000000)}
	town_title = ShareClean.text(d.get("town_title", ""), int(ShareClean.cap("max_title", 48)))
	_next_family = ShareClean.clampi_(d.get("next_family", 1), 1, 100000, 1)

static func new_family_key() -> String:
	var k := "f%d" % _next_family
	_next_family += 1
	return k

# ------------------------------------------------------------------ delivery
static func _fingerprint(item: Dictionary) -> String:
	return str(("%s|%s|%s|%s|%s|%s" % [town_title, item.get("from", ""), item.get("kind", ""), item.get("coins", 0), item.get("object", ""), item.get("text", "")]).hash())

static func _seen() -> Array:
	var fa := FileAccess.open(seen_path, FileAccess.READ)
	if fa == null:
		return []
	var v = JSON.parse_string(fa.get_as_text())
	return v if v is Array else []

static func _remember(fp: String) -> void:
	var s: Array = _seen()
	s.append(fp)
	while s.size() > 400:
		s.pop_front()
	var fa := FileAccess.open(seen_path, FileAccess.WRITE)
	if fa != null:
		fa.store_string(JSON.stringify(s))

## Hand out everything waiting in the inbox. Returns the number of items delivered (0 when nobody lives here yet).
static func deliver_pending() -> int:
	if inbox.is_empty():
		return 0
	var res: Array = SysUtil.residents()
	if res.is_empty():
		return 0
	var hid: int = int((res[0] as Folk).household_id)
	var seen: Array = _seen()
	var n := 0
	var waiting: Array = inbox.duplicate(true)
	inbox.clear()
	for item in waiting:
		var fp := _fingerprint(item)
		if seen.has(fp):
			continue
		seen.append(fp)
		_remember(fp)
		var who := str(item["from"])
		match str(item["kind"]):
			"coins":
				Economy.deposit(hid, int(item["coins"]), "gift")
				SysUtil.notify("A gift of %d coins from %s was waiting at your mailbox." % [int(item["coins"]), who], "story")
			"letter":
				SysUtil.notify("A letter from %s was waiting at your mailbox." % who, "story")
			"object":
				var placed := ShareMail.place_object(str(item["object"]))
				SysUtil.notify("A gift from %s was waiting at your mailbox: %s." % [who, ShareMail.object_label(str(item["object"]))] if placed else "A keepsake from %s was waiting at your mailbox: %s." % [who, ShareMail.object_label(str(item["object"]))], "story")
		var rec: Dictionary = item.duplicate(true)
		rec["day"] = SysUtil.day()
		received.append(rec)
		n += 1
	while received.size() > 50:
		received.pop_front()
	return n
