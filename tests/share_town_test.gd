extends RefCounted
## Sharing, towns and gifts: a town file imports into a NEW slot (never over a used one), gifts and letters left in it are
## delivered exactly once and bounded, share state round-trips through saves.

const K = preload("res://tests/systems_kit.gd")
const S = preload("res://tests/share_kit.gd")
const SLOT := 95
var _bal0 := 0

func run() -> Array:
	var f: Array = []
	S.prepare()
	ShareImport.first_slot = SLOT
	ShareImport.last_slot = SLOT
	SaveLoad.delete_slot(SLOT)
	_town(f)
	_gifts(f)
	SaveLoad.delete_slot(SLOT)
	S.finish()
	K.teardown()
	return f

func _town(f: Array) -> void:
	S.world()
	var r := ShareExport.export_town("Vale town", "Vale")
	K.expect(f, bool(r["ok"]) and str(r["file"]).ends_with(".sim4town"), "town export writes a .sim4town file: %s" % r["error"])
	var rd := ShareFile.read("town", str(r["file"]))
	var v := ShareValidateTown.town(rd["data"])
	K.expect(f, bool(v["ok"]), "the town file validates: %s" % v["error"])
	K.expect(f, (v["data"]["chronicle"] as Array).size() >= 2, "the Chronicle travels with the town: %d lines" % (v["data"]["chronicle"] as Array).size())
	K.expect(f, (v["data"]["save"]["folk"] as Array).size() == 3, "all folk are in the file")
	var before := SaveLoad.snapshot("current")
	var im := ShareImport.town(v["data"])
	K.expect(f, bool(im["ok"]) and int(im["data"]["slot"]) == SLOT and SaveLoad.has_slot(SLOT), "import creates a NEW slot: %s" % im["error"])
	var again := ShareImport.town(v["data"])
	K.expect(f, not bool(again["ok"]), "no free slot left: a used slot is never overwritten")
	var forced := ShareImport.town(v["data"], SLOT)
	K.expect(f, not bool(forced["ok"]), "asking for a used slot is refused")
	var diffs: Array = []
	K.expect(f, K.deep_eq(before["folk"], SaveLoad.snapshot("current")["folk"], "folk", diffs), "the current game is untouched by an import")
	var saved := SaveLoad.read(SLOT)
	K.expect(f, str(saved["label"]).find("Vale town") >= 0 and not (saved["systems"]["share"] as Dictionary).is_empty(), "the slot carries its label and share block")
	K.teardown()

func _file_with_gifts(f: Array) -> String:
	S.world()
	var r := ShareExport.export_town("Gift town", "Vale")
	K.expect(f, bool(r["ok"]), "export for the gift test")
	var file := str(r["file"])
	_bal0 = Economy.balance(1)
	for g in [{"from": "Pat", "kind": "coins", "coins": 120}, {"from": "Pat", "kind": "letter", "text": "Come visit <b>soon</b>!"}, {"from": "Pat", "kind": "object", "object": "plant"}]:
		var lg := ShareExport.leave_gift(file, g)
		K.expect(f, bool(lg["ok"]), "a gift can be left in the file: %s" % lg["error"])
	var big := ShareExport.leave_gift(file, {"from": "Pat", "kind": "coins", "coins": 9999})
	K.expect(f, bool(big["ok"]), "an oversized gift is clamped, not refused")
	var bad := ShareExport.leave_gift(file, {"from": "Pat", "kind": "object", "object": "stove"})
	K.expect(f, not bool(bad["ok"]), "a gift outside the allowlist is refused")
	for i in 5:
		ShareExport.leave_gift(file, {"from": "Pat", "kind": "letter", "text": "more %d" % i})
	var full := ShareExport.leave_gift(file, {"from": "Pat", "kind": "letter", "text": "one too many"})
	K.expect(f, not bool(full["ok"]), "the inbox is bounded (at most %d items)" % int(ShareClean.cap("gift")["max_items"]))
	K.teardown()
	return file

func _gifts(f: Array) -> void:
	var file := _file_with_gifts(f)
	var rd := ShareFile.read("town", file)
	var v := ShareValidateTown.town(rd["data"])
	K.expect(f, bool(v["ok"]) and (v["data"]["inbox"] as Array).size() == 6, "six items wait in the inbox")
	SaveLoad.delete_slot(SLOT)
	var im := ShareImport.town(v["data"])
	K.expect(f, bool(im["ok"]), "import the gift town: %s" % im["error"])
	# play it
	var w := K.setup()
	K.make_folk(w, "Zed", [], 1)
	K.expect(f, SaveLoad.load_slot(SLOT), "the town loads: %s" % SaveLoad.last_error)
	var hid2: int = int((SysUtil.residents()[0] as Folk).household_id)
	K.expect(f, K.has_note("A letter from Pat was waiting at your mailbox"), "a notification announces the letter")
	K.expect(f, ShareState.inbox.is_empty() and ShareState.received.size() == 6, "everything was delivered and moved to received: %d" % ShareState.received.size())
	var coins_total := 0
	for g in ShareState.received:
		if str(g["kind"]) == "coins":
			coins_total += int(g["coins"])
	K.expect(f, coins_total == 120 + 500, "coins are bounded (120 + 500 capped)")
	K.expect(f, Economy.balance(hid2) == _bal0 + 620, "the household got the coins: %d -> %d" % [_bal0, Economy.balance(hid2)])
	var snap := Economy.balance(hid2)
	# loading the same slot again must not pay twice
	K.expect(f, SaveLoad.load_slot(SLOT), "load again")
	K.expect(f, ShareState.received.is_empty() and ShareState.inbox.is_empty(), "the same slot does not deliver a second time")
	K.expect(f, ShareState.deliver_pending() == 0, "nothing left to deliver")
	# delivered state survives a save/load of the player's own slot
	ShareState.received.append({"from": "Pat", "kind": "letter", "text": "kept", "day": 3})
	var d := ShareState.to_dict()
	ShareState.reset()
	ShareState.from_dict(JSON.parse_string(JSON.stringify(d)))
	K.expect(f, ShareState.received.size() == 1 and str(ShareState.received[0]["text"]) == "kept", "received letters survive a save")
	K.expect(f, Economy.balance(hid2) == _bal0 and snap == _bal0 + 620, "reloading the slot pays nothing again")
	K.teardown()
