class_name SoloRent
extends RefCounted
## The pawn's tenancy day by day: the start (a rented Starter Studio on a landlord's own small property), the eviction that follows the unpaid rent
## (notice -> the locks are changed after `notice_days` -> homeless) and the end of a notice when the arrears are paid. The rent itself is the ordinary
## HousingRent bill (reason "rent"); this class adds the end states. Numbers: data/solo.json "start".

# ------------------------------------------------------------------ the start
## A fresh solo game: the studio is rented. Call after the Players table, the townies and the home lot exist.
static func begin(hid: int) -> void:
	SoloHome.reset()
	SoloHome.active = true
	SoloHome.rung = "starter"
	SoloHome.since_day = SysUtil.day()
	Economy.auto_pay = true                         # the rent and the bills pay themselves when the coins are there (the setting can switch it off)
	HousingProps.ensure()
	var p: Dictionary = HousingProps.get_prop("map_home")
	if p.is_empty():
		return
	var fp: Dictionary = (SoloCfg.sect("start") as Dictionary).get("flat_property", {})
	p["base"] = int(fp.get("base", 6000))
	p["hood"] = float(fp.get("hood", 0.5))
	p["label"] = str(fp.get("label", "Starter Studio"))
	p["condition"] = 80.0
	_let(p, hid, SoloCfg.rent())
	var prepaid: bool = bool(SoloCfg.by_diff("start", "first_week_prepaid"))
	HousingRent.next_cycle = SysUtil.day() + (7 if prepaid else 3)      # Hard: the first rent is due on day 7, issued on day 4
	SoloHome.deposit = SoloCfg.rent()
	SoloMove.mark_fixtures(Neighborhood.HOME)

## Make `p` a let property with the pawn's household as tenant (a landlord townie owns it).
static func _let(p: Dictionary, hid: int, rent: int) -> void:
	var landlord: Dictionary = _landlord()
	if landlord.is_empty():
		p["owner_kind"] = "bank"
		p["owner"] = 0
	else:
		p["owner_kind"] = "townie"
		p["owner"] = int(landlord["id"])
		landlord["home_prop"] = landlord.get("home_prop", "")
	p["tenant_kind"] = "player"
	p["tenant"] = hid
	p["rent"] = rent
	p["to_let"] = false
	p["for_sale"] = false
	p["missed"] = 0
	p["arrears"] = 0
	p["notice"] = false
	p["last_rent_change"] = SysUtil.day()

static func _landlord() -> Dictionary:
	var best: Dictionary = {}
	for t in Story.alive_townies():
		if Story.stage_of(t) in ["adult", "elder"] and (best.is_empty() or int(t["coins"]) > int(best["coins"])):
			best = t
	return best

# ------------------------------------------------------------------ daily
static func on_day(day: int) -> void:
	if not SoloHome.active:
		return
	SoloShelter.on_day(day)
	if SoloHome.homeless:
		return
	var p: Dictionary = SoloHome.prop()
	if p.is_empty() or str(p["tenant_kind"]) != "player":
		return
	var hid: int = SoloHome.hid()
	var late: int = _unpaid_rent_bills(p)
	if bool(p.get("notice", false)):
		if SoloHome.notice_day < 0:
			SoloHome.notice_day = day
		if late == 0:
			p["notice"] = false
			SoloHome.notice_day = -1
			SysUtil.notify("The landlord has dropped the eviction notice: the rent is paid.", "good")
		elif day - SoloHome.notice_day >= int(SoloCfg.sect("start").get("notice_days", 3)):
			evict(hid, "unpaid rent")
			return
	elif late >= 1:
		var due: int = _first_late_due(p)
		if due >= 0 and day == due + 1:
			SysUtil.notify("The rent is overdue. Pay it, or the landlord starts eviction.", "warn")

static func _unpaid_rent_bills(p: Dictionary) -> int:
	var n: int = 0
	for b in Economy.bills:
		if str(b.get("reason", "")) == "rent" and not bool(b["paid"]) and bool(b["late"]):
			n += 1
	return n

static func _first_late_due(p: Dictionary) -> int:
	for b in Economy.bills:
		if str(b.get("reason", "")) == "rent" and not bool(b["paid"]) and bool(b["late"]):
			return int(b["due"])
	return -1

## Rents missed before the notice (data per difficulty).
static func evict_after() -> int:
	return maxi(int(SoloCfg.by_diff("start", "evict_after_missed")), 1)

# ------------------------------------------------------------------ the end of a tenancy
## The landlord changes the locks: everything left in the flat is lost, the pawn stands on the street with what they carry.
static func evict(hid: int, why: String) -> void:
	var p: Dictionary = SoloHome.prop()
	if not p.is_empty():
		p["tenant_kind"] = ""
		p["tenant"] = 0
		p["notice"] = false
		p["to_let"] = true
	SoloHome.notice_day = -1
	SoloHome.leaving_day = -1
	SoloHome.homeless = true
	SoloHome.rung = "street"
	SoloHome.deposit = 0
	SoloMove.lose_everything_here(hid)
	SoloMove.put_on_street(hid)
	SysUtil.notify("EVICTED: the landlord has changed the locks (%s). You have what you carry. Day labour at the Works and the night shelter are open to you." % why, "bad")
	ChronicleHook.note("eviction", "%s was evicted for %s." % [_pawn_name(), why], [], "home:%d" % hid, 3, true)
	SysUtil.game_event("evicted", {"household_id": hid, "why": why})

static func _pawn_name() -> String:
	var f = SysUtil.folk(Pawn.of())
	return "Someone" if f == null else str(f.name)
