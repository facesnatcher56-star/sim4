class_name PhoneOwn
extends RefCounted
## Task 51: the phone is a thing the pawn OWNS (one-character play only; every other person, and every classic game, always has a working phone).
## A phone can be stolen, broken, lost, pawned, or cut off when its weekly bill is not paid; without a working phone the calls, texts, invitations and the Jobs
## app are out of reach. Numbers: data/solo.json "phone". Saved in the PhoneState block ("own").
##   PhoneOwn.block(fid)    "" when the phone works, else why not (the text shown to the player)
##   PhoneOwn.give / lose / sell / buy      PhoneOwn.on_chronicle(p) (cause lines from the world: robbery steals, a bad fall breaks)   PhoneOwn.on_day(day)

static var own: Dictionary = {}          # folk id -> {kind, status: ok|broken|stolen|lost|none, billed: day last billed}

static func reset() -> void:
	own = {}

static func cfg() -> Dictionary:
	return SoloCfg.sect("phone")

static func tracked(fid: int) -> bool:
	return SoloHome.active and Pawn.is_pawn_id(fid)

static func status(fid: int) -> String:
	if not own.has(fid) and tracked(fid):
		give(fid, str(cfg().get("start_kind", "old")))          # the start (and an heir) carries an old phone
	return str((own.get(fid, {}) as Dictionary).get("status", "none"))

static func kind_def(kind: String) -> Dictionary:
	return (cfg().get("kinds", {}) as Dictionary).get(kind, {})

static func has_phone(fid: int) -> bool:
	return status(fid) in ["ok", "broken"]

## "" = a working phone.
static func block(fid: int) -> String:
	if not tracked(fid):
		return ""
	match status(fid):
		"ok":
			return "The line is cut off until the phone bill is paid." if cut_off(fid) else ""
		"broken":
			return "Your phone is broken."
		"stolen":
			return "Your phone was stolen."
		"lost":
			return "You lost your phone."
	return "You have no phone."

static func cut_off(fid: int) -> bool:
	var f = SysUtil.folk(fid)
	if f == null:
		return false
	for b in Economy.outstanding(int(f.household_id)):
		if str(b.get("reason", "")) == "phone" and bool(b["late"]):
			return true
	return false

static func give(fid: int, kind: String) -> void:
	own[fid] = {"kind": kind, "status": "ok", "billed": SysUtil.day()}

static func lose(fid: int, how: String, cause: String) -> void:
	if status(fid) != "ok" and status(fid) != "broken":
		return
	if how == "broken":
		(own[fid] as Dictionary)["status"] = "broken"
	else:
		(own[fid] as Dictionary)["status"] = how
	SysUtil.notify("%s" % cause, "bad")
	ChronicleHook.note("phone_" + how, cause, [fid], "", 2, true)

## Pawn the phone (a broken one fetches a little less). Returns coins.
static func sell(fid: int) -> int:
	if not has_phone(fid):
		return 0
	var d: Dictionary = kind_def(str(own[fid]["kind"]))
	var coins: int = int(d.get("sell", 5))
	if status(fid) == "broken":
		coins = coins / 2
	var f = SysUtil.folk(fid)
	Economy.deposit(int(f.household_id), coins, "pawned phone")
	own[fid] = {"kind": "", "status": "none", "billed": 0}
	ChronicleHook.note("phone_sold", "You pawned your phone for %d coins." % coins, [fid], "", 2, true)
	return coins

static func why_not_buy(fid: int, kind: String) -> String:
	var d: Dictionary = kind_def(kind)
	var f = SysUtil.folk(fid)
	if d.is_empty() or f == null:
		return "That is not for sale."
	if status(fid) == "ok":
		return "You already have a phone."
	if not _at_shop(f):
		return "Buy it at the Electronics Shop."
	if not ShopStock.is_open("electronics"):
		return "The shop is closed."
	if not Economy.can_afford(int(f.household_id), int(d.get("price", 0))):
		return "Not enough coins."
	return ""

static func _at_shop(f) -> bool:
	return at_lot(f, str(ShopStock.shop("electronics").get("lot", "office")))

## No map (tests / stub worlds) or the folk is at that lot.
static func at_lot(f, lot_id: String) -> bool:
	var w = WorldIface.world()
	if w == null or not ("regions" in w) or not w.regions.has_regions():
		return true
	return Neighborhood.lot_of(f) == lot_id

static func buy(fid: int, kind: String) -> Dictionary:
	var why: String = why_not_buy(fid, kind)
	if why != "":
		return {"ok": false, "reason": why}
	var f = SysUtil.folk(fid)
	var d: Dictionary = kind_def(kind)
	if not Economy.spend(int(f.household_id), int(d.get("price", 0)), "shop: %s" % str(d.get("label", "phone"))):
		return {"ok": false, "reason": "Not enough coins."}
	give(fid, kind)
	SysUtil.notify("You bought a %s." % str(d.get("label", "phone")), "good")
	return {"ok": true, "reason": ""}

## The world's own notes (ChronicleHook): a robbery takes the phone, a fall or a fight breaks it. Each has a chance, and the text says why it happened.
static func on_chronicle(p: Dictionary) -> void:
	if not SoloHome.active:
		return
	var pawn: int = Pawn.of()
	if pawn < 0 or status(pawn) != "ok" or not (p.get("subjects", []) as Array).has(pawn):
		return
	var k: String = str(p.get("kind", "")).to_lower()
	if k.begins_with("phone_"):
		return
	for w in cfg().get("steal_words", []):
		if k.contains(str(w)):
			if SysUtil.chance(float(cfg().get("stolen_chance", 0.4))):
				lose(pawn, "stolen", "Your phone was taken as well.")
			return
	for w in cfg().get("break_words", []):
		if k.contains(str(w)):
			if SysUtil.chance(float(cfg().get("broken_chance", 0.25))):
				lose(pawn, "broken", "Your phone cracked in the trouble. It does not work.")
			return

static func on_day(day: int) -> void:
	if not SoloHome.active:
		return
	var pawn: int = Pawn.of()
	var f = SysUtil.folk(pawn)
	if f == null or not own.has(pawn):
		return
	var st: String = status(pawn)
	if st == "ok" and SysUtil.chance(float(cfg().get("lost_per_day", 0.004))):
		lose(pawn, "lost", "You cannot find your phone anywhere. It is gone.")
		return
	if st != "ok" and st != "broken":
		return
	var b: Dictionary = cfg().get("bill", {})
	if day - int(own[pawn].get("billed", day)) >= int(b.get("every_days", 7)):
		own[pawn]["billed"] = day
		var amount: int = int(SoloCfg.by_diff("phone", "bill_amount"))
		var hid: int = int(f.household_id)
		Economy.bills.append({"id": Economy._seq, "hid": hid, "amount": amount, "base": amount, "issued": day, "due": day + int(b.get("due_after_days", 3)),
			"paid": false, "late": false, "fee": 0, "reason": "phone"})
		Economy._seq += 1
		SysUtil.notify("Phone bill: %d coins." % amount, "bill")

static func to_dict() -> Dictionary:
	return {"own": own.duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	reset()
	for k in (d.get("own", {}) as Dictionary):
		var e: Dictionary = (d["own"][k] as Dictionary).duplicate()
		e["billed"] = int(e.get("billed", 0))
		own[int(k)] = e
