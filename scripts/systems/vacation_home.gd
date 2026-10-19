class_name VacationHome
extends RefCounted
## The home lot while the household is away (task 22). The lot is SUMMARISED: nothing runs there but a few daily numbers.
##   * bills still come and auto-pay (Economy does that; the return report lists what was paid),
##   * plants lose water every day and wilt unless a house-sitter was paid,
##   * mail and newspapers pile up (the mailbox fills; a sitter collects them),
##   * an EMPTY house is a better target for burglars: `burglary_mult` multiplies the burglary incident's yearly rate (hook in
##     IncidentRisk.effective_rate through the incident's "burglary_odds" tag); a burglar alarm and a sitter lower it again.
## Tier: STATISTICAL daily, cadence 1 day per trip, active set = the households on a trip, caps: none needed (a handful of numbers per trip).

static func cfg() -> Dictionary:
	return (Vacation.cfg().get("home", {}) as Dictionary)

static func plants_of(hid: int) -> Array:
	var out: Array = []
	for o in Economy.objects_of(hid):
		if str(o.def_id) == "plant":
			out.append(o)
	return out

static func has_alarm(hid: int) -> bool:
	for o in Economy.objects_of(hid):
		if str(o.def_id) == "burglar_alarm":
			return true
	return false

static func begin(t: Dictionary) -> void:
	t["home"] = {"since_min": SysUtil.now(), "since_day": SysUtil.day(), "days_empty": 0, "mail": 0, "papers": 0, "plants": plants_of(int(t["hid"])).size(), "wilted": 0}

static func on_day(t: Dictionary) -> void:
	var hid: int = int(t["hid"])
	if not Vacation.household_empty(hid):
		return
	var h: Dictionary = t["home"]
	if h.is_empty():
		begin(t)
		h = t["home"]
	h["days_empty"] = int(h["days_empty"]) + 1
	var k: Dictionary = cfg()
	if bool(t["sitter"]):
		for o in plants_of(hid):
			WorldIface.state_set(o, "water", maxf(float(WorldIface.state_get(o, "water", 0.0)), 6.0))
		return                                      # the sitter also takes the post in
	h["mail"] = int(h["mail"]) + 1
	h["papers"] = int(h["papers"]) + int(k.get("newspaper_per_day", 1))
	for o2 in plants_of(hid):
		WorldIface.state_add(o2, "water", -float(k.get("plant_loss_per_day", 1.6)))

## The party is home: count what happened to the house, tell the player.
static func finish(t: Dictionary) -> void:
	var hid: int = int(t["hid"])
	var h: Dictionary = t.get("home", {})
	if h.is_empty():
		return
	var k: Dictionary = cfg()
	var wilted: int = 0
	for o in plants_of(hid):
		if float(WorldIface.state_get(o, "water", 10.0)) < float(k.get("plant_wilt_below", 2.0)):
			wilted += 1
	h["wilted"] = wilted
	var paid: int = 0
	for e in Economy.ledger_for(hid):
		if str(e.get("reason", "")) == "bills" and int(e.get("day", 0)) >= int(h.get("since_day", 0)):
			paid += absi(int(e.get("amount", 0)))
	h["bills_paid"] = paid
	if not bool(t["sitter"]) and int(h["mail"]) > 0:
		for o2 in SysUtil.all_world_objects():
			if str(o2.def_id) == "mailbox" and Economy.owner.get(int(o2.id), hid) == hid and NeighborhoodLots.lot_at(o2.tile) == Neighborhood.HOME:
				WorldIface.state_set(o2, "mail", minf(float(WorldIface.state_get(o2, "mail", 0.0)) + float(h["mail"]), float(k.get("mail_cap", 5))))
	if int(h["days_empty"]) > 0:
		var bits: Array = []
		if bool(t["sitter"]):
			bits.append("the sitter kept the plants and the post in order")
		else:
			bits.append("%s of mail and %s on the mat" % [SysUtil.count_text(int(h["mail"]), "day"), SysUtil.count_text(int(h["papers"]), "paper")])
			if int(h["plants"]) > 0:
				bits.append("%d of %d plants wilted" % [wilted, int(h["plants"])])
		if paid > 0:
			bits.append("bills were paid (%d coins)" % paid)
		SysUtil.notify("Back home: " + ", ".join(bits) + ".", "info")

# ------------------------------------------------------------------ burglary odds (hook: IncidentRisk.effective_rate)
## Called with every incident definition and subject; only incidents tagged "burglary_odds" are touched.
static func rate_mult(def: Dictionary, subj) -> float:
	var tags: Variant = def.get("tags", null)
	if tags == null or not (tags as Array).has("burglary_odds"):
		return 1.0
	return burglary_mult(subj)

## x3 for an empty house; a house-sitter x0.6, a burglar alarm x0.5 on top. 1.0 for a house with somebody home.
static func burglary_mult(subj) -> float:
	if subj == null or subj.kind != "lot" or not str(subj.lot_key).begins_with("home:"):
		return 1.0
	var hid: int = int(subj.household_id)
	if not Vacation.household_empty(hid):
		return 1.0
	var k: Dictionary = cfg()
	var m: float = float(k.get("burglary_away_mult", 3.0))
	var t: Dictionary = Vacation.trip_of_household(hid)
	if not t.is_empty() and bool(t.get("sitter", false)):
		m *= float(k.get("sitter_mult", 0.6))
	if has_alarm(hid):
		m *= float(k.get("alarm_mult", 0.5))
	return m
