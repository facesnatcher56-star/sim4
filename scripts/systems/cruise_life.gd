class_name CruiseLife
extends RefCounted
## Life on board (task 22): the programme (welcome buffet, captain's dinner, formal night, talent show, deck party, theme nights, shows, farewell
## dinner; data/cruise_ship.json "program"), the sea state of the day, seasickness, and shipboard romance and drama with passengers.
## The captain can cancel the fun (`restricted`: a killer aboard). Everything is events and notifications (non-graphic).
## Tier: FULL; cadence: programme items at their exact minute (timeline), seasick 1/day (10:00), romance 1/evening (21:00), sea state 1/sea day.
## Active set: the party aboard (a handful of folk) and the passengers (<= 8).

static func cfg() -> Dictionary:
	return CruiseRoute.cfg()

static func program_item(id: String) -> Dictionary:
	for it in cfg().get("program", []):
		if str(it["id"]) == id:
			return it
	return {}

static func tag_of(id: String) -> String:
	if id.contains("dinner") or id.contains("buffet"):
		return "dinner"
	if id.contains("show"):
		return "show"
	if id == "sail_away" or id == "safety_drill":
		return "port"
	return "party"

# ------------------------------------------------------------------ programme
static func program(t: Dictionary, e: Dictionary) -> void:
	var c: Dictionary = t["cruise"]
	var item: Dictionary = program_item(str(e["id"]))
	if item.is_empty():
		return
	var aboard: Array = Cruise.members_aboard(t)
	if aboard.is_empty():
		return
	if bool(c.get("restricted", false)) and tag_of(str(e["id"])) in ["show", "party"]:
		if int(c.get("cancelled_notes", 0)) < 3:
			c["cancelled_notes"] = int(c.get("cancelled_notes", 0)) + 1
			VacationLog.note(t, "incident", "The captain cancelled tonight's entertainment: everyone is asked to stay in the lounges and cabins.", [], 2, true)
		return
	var names: Array = aboard.map(func(x): return str(x.name))
	var text: String = str(item.get("text", "")).replace("{names}", ", ".join(names)).replace("{ship}", str(c["name"])).replace("{theme}", str(e.get("theme", "")))
	for f in aboard:
		VacationLife.apply_effects(t, f, item.get("effects", []))
	if text != "" and int(item.get("log", 1)) > 0:
		VacationLog.note(t, tag_of(str(e["id"])), text, aboard.map(func(x): return int(x.id)), int(item.get("log", 1)), true)
	if str(e["id"]) in ["captains_dinner", "sail_away"] and text != "":
		SysUtil.notify(text, "travel")
	if str(e["id"]) == "captains_dinner":
		for f2 in aboard:
			VacationLife.take_photo(t, f2, "the captain's dinner")

# ------------------------------------------------------------------ the sea
static func sea_day(t: Dictionary, _day: int) -> void:
	var c: Dictionary = t["cruise"]
	var r := Vacation.rng_for(t)
	var weights: Dictionary = (cfg().get("sea", {}) as Dictionary).get("weights", {"calm": 1})
	var keys: Array = weights.keys()
	keys.sort()
	var total: float = 0.0
	for k in keys:
		total += float(weights[k])
	var roll: float = r.randf() * total
	var pick: String = str(keys[keys.size() - 1])
	for k2 in keys:
		roll -= float(weights[k2])
		if roll <= 0.0:
			pick = str(k2)
			break
	if SysUtil.now() < int(c["storm_until"]):
		pick = "rough"
	c["sea"] = pick
	if pick == "rough":
		VacationLog.note(t, "sea", "A rough day at sea.", [], 1, false)

static func on_hour(t: Dictionary) -> void:
	var c: Dictionary = t["cruise"]
	var h: int = int(SysUtil.hour_f())
	if h == 10 and str(c["phase"]) == "sailing":
		_seasick(t)
	if h == 21 and str(c["phase"]) == "sailing":
		_evening(t)

static func _seasick(t: Dictionary) -> void:
	var c: Dictionary = t["cruise"]
	var r := Vacation.rng_for(t)
	var sea: Dictionary = cfg().get("sea", {})
	var state: String = str(c["sea"])
	var p: float = float((sea.get("seasick", {}) as Dictionary).get(state, 0.0))
	if SysUtil.now() < int(c["storm_until"]):
		p = float(sea.get("storm_seasick", 0.55))
	if p <= 0.0:
		return
	for f in Cruise.members_aboard(t):
		var pm: float = p
		for tr in (sea.get("seasick_traits_mult", {}) as Dictionary):
			if f.has_trait(str(tr)):
				pm *= float(sea["seasick_traits_mult"][tr])
		if r.randf() < pm and not f.has_buff("seasick"):
			f.add_buff("seasick")
			VacationLog.note(t, "seasick", "%s felt seasick as the ship rolled." % f.name, [int(f.id)], 1, false)

# ------------------------------------------------------------------ romance and drama
static func _evening(t: Dictionary) -> void:
	var c: Dictionary = t["cruise"]
	var r := Vacation.rng_for(t)
	var rc: Dictionary = cfg().get("romance", {})
	if bool(c.get("restricted", false)):
		return
	var cands: Array = CruiseCrew.passengers(t)
	for f in Cruise.members_aboard(t):
		if str(f.age_stage) not in ["adult", "elder", "teen"] or cands.is_empty():
			continue
		if r.randf() > float(rc.get("chance_per_evening", 0.14)) * (1.4 if f.has_trait("romantic") or f.has_trait("flirty") else 1.0):
			continue
		var adults: Array = cands.filter(func(x): return str(x.age_stage) in ["adult", "elder"] and not CrimePerson.is_kin_or_partner(int(f.id), int(x.id)))
		if adults.is_empty():
			continue
		var npc = adults[r.randi_range(0, adults.size() - 1)]
		RelationshipService.add_both(int(f.id), int(npc.id), "friendship", 14.0)
		RelationshipService.add_both(int(f.id), int(npc.id), "romance", 12.0)
		f.add_buff("holiday_fling")
		VacationLog.note(t, "romance", "%s and %s spent the evening dancing on deck: a shipboard romance." % [f.name, npc.name], [int(f.id), int(npc.id)], 2, true)
		if r.randf() < float(rc.get("drama_chance", 0.05)) * 4.0 and cands.size() > 1:
			var rival = cands[r.randi_range(0, cands.size() - 1)]
			if rival != npc:
				RelationshipService.add_both(int(npc.id), int(rival.id), "friendship", -8.0)
				VacationLog.note(t, "romance", "%s was seen scowling at %s over %s. There will be drama at breakfast." % [rival.name, f.name, npc.name], [int(rival.id), int(f.id)], 2, true)
	# passengers pair off among themselves sometimes
	if cands.size() >= 2 and r.randf() < float(rc.get("drama_chance", 0.05)):
		var a = cands[r.randi_range(0, cands.size() - 1)]
		var b = cands[r.randi_range(0, cands.size() - 1)]
		if a != b:
			VacationLog.note(t, "romance", "%s and %s had a loud disagreement over a deck chair." % [a.name, b.name], [int(a.id), int(b.id)], 1, false)
