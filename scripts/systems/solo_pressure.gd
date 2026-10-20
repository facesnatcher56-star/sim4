class_name SoloPressure
extends RefCounted
## The pressure cycle (R14.5): a pawn who is broke, jobless or behind on a bill and lives in a rough district gets a CREW OFFER, never a command.
## First offer within `first_offer_days` of the trouble starting (Easy 5, Normal 3, Hard 2), then one every `repeat_days` while it lasts: a lookout
## (2 h, 40 coins), a run (1 h, 55) or a corner shift (4 h, 90) against legal work that pays 10 to 20 an hour but starts slowly or far away.
## Accepting costs HEAT (police attention), DUES (3 a day once in), a RECORD if caught (blocks hiring until it is expunged after clean living) and
## the crew's rivals. Refusing keeps you clean and poorer; the third refusal brings a scare, never a death. Leaving costs a payoff.
## Every offer waits for the player's answer (JusticePlayer.ask: Esc = no). Numbers: data/solo.json "pressure".

static var member: bool = false           # in a crew
static var crew_name: String = ""
static var heat: float = 0.0              # police attention, falls by `heat_decay_per_day`
static var standing: float = 0.0          # grows with every job
static var refusals: int = 0
static var trouble_since: int = -1        # first day of the present trouble (-1 none)
static var last_offer: int = -99
static var clean_days: int = 0            # days without a crew job (the record is expunged after expunge days of clean living)
static var waiting: bool = false          # an offer is on the screen

static func reset() -> void:
	member = false
	crew_name = ""
	heat = 0.0
	standing = 0.0
	refusals = 0
	trouble_since = -1
	last_offer = -99
	clean_days = 0
	waiting = false

static func cfg() -> Dictionary:
	return SoloCfg.sect("pressure")

static func to_dict() -> Dictionary:
	return {"member": member, "crew": crew_name, "heat": heat, "standing": standing, "refusals": refusals, "since": trouble_since, "last": last_offer, "clean": clean_days}

static func from_dict(d: Dictionary) -> void:
	reset()
	member = bool(d.get("member", false))
	crew_name = str(d.get("crew", ""))
	heat = float(d.get("heat", 0.0))
	standing = float(d.get("standing", 0.0))
	refusals = int(d.get("refusals", 0))
	trouble_since = int(d.get("since", -1))
	last_offer = int(d.get("last", -99))
	clean_days = int(d.get("clean", 0))

# ------------------------------------------------------------------ the trouble
static func in_trouble(f) -> bool:
	var hid: int = int(f.household_id)
	if Economy.balance(hid) < int(cfg().get("broke_coins", 150)):
		return true
	if not Careers.jobs.has(int(f.id)):
		return true
	for b in Economy.outstanding(hid):
		if bool(b["late"]):
			return true
	return false

## The rough district the pawn is in now (where they stand, else where they live; the shelter is in the Kiln Quarter too).
static func district_of_pawn(f) -> String:
	var d: String = SoloDistricts.district_at_tile(f.tile)
	if d == "":
		d = SoloDistricts.district_of(Neighborhood.HOME) if not SoloHome.homeless else SoloDistricts.district_of(SoloShelter.lot_id())
	return d

# ------------------------------------------------------------------ daily
static func on_day(day: int) -> void:
	if not SoloHome.active:
		return
	var f = SysUtil.folk(Pawn.of())
	if f == null or str(f.age_stage) not in ["teen", "adult", "elder"]:
		return
	heat = maxf(heat - float(cfg().get("heat_decay_per_day", 1.0)), 0.0)
	record_tick(f)
	if member:
		_member_day(f, day)
		if not waiting and day - last_offer >= 2:
			_offer(f, district_of_pawn(f), day)          # a member is asked for work every other day; a "no" costs standing
		return
	var d: String = district_of_pawn(f)
	var rough: bool = SoloDistricts.roughness_of(d) >= float(cfg().get("min_roughness", 0.6)) and SoloDistricts.setting_factor() > 0.0
	if rough and in_trouble(f):
		if trouble_since < 0:
			trouble_since = day
		var first: int = int(SoloCfg.by_diff("pressure", "first_offer_days"))
		var due_first: bool = last_offer < trouble_since and day - trouble_since >= first
		var due_again: bool = last_offer >= trouble_since and day - last_offer >= int(cfg().get("repeat_days", 4))
		if (due_first or due_again) and not waiting:
			_offer(f, d, day)
	else:
		trouble_since = -1

static func _member_day(f, day: int) -> void:
	var dues: int = int(cfg().get("dues_per_day", 3))
	if not Economy.spend(int(f.household_id), dues, "crew dues"):
		standing -= 0.5
	clean_days = 0
	var d: String = district_of_pawn(f)
	if SoloDistricts.roughness_of(d) < 0.5 and SysUtil.chance(0.2):
		SysUtil.notify("The block has quietened down and the crew has little work for you now.", "info")

## The record is expunged after `record_expunge_days` of clean living.
static func record_tick(f) -> void:
	if member:
		return
	clean_days += 1
	var need: int = int(cfg().get("record_expunge_days", 56))
	if clean_days >= need and JusticeState.records.has(int(f.id)):
		var left: Array = []
		for r in JusticeState.records[int(f.id)]:
			if str(r.get("charge", "")) != "crew work":
				left.append(r)
		if left.size() != (JusticeState.records[int(f.id)] as Array).size():
			JusticeState.records[int(f.id)] = left
			SysUtil.notify("Your record for crew work has been expunged: you kept clean.", "good")

# ------------------------------------------------------------------ offers
static func _offer(f, did: String, day: int) -> void:
	var offers: Array = cfg().get("offers", [])
	if offers.is_empty():
		return
	var o: Dictionary = offers[mini(refusals if not member else int(standing) % offers.size(), offers.size() - 1)]
	last_offer = day
	waiting = true
	var crew: String = _crew_name(did)
	var legal: String = "Legal work pays 10 to 20 an hour but it starts slowly or far away."
	var txt: String = "A man from %s catches you on the block. \"%s: %d minutes, %d coins, tonight.\" He does not ask twice a day, but he asks again. %s" % [crew, str(o["label"]), int(o["minutes"]), int(o["pay"]), legal]
	JusticePlayer.ask(int(f.id), "An offer on the block", txt, [{"id": "yes", "label": "Take it (%d coins)" % int(o["pay"])}, {"id": "no", "label": "Not interested"}],
		_answer.bind(int(f.id), str(o["id"]), crew), "no")
	if not JusticePlayer.ask_fn.is_valid():
		waiting = false          # no screen (headless): the offer waits for nobody, counts as a refusal

static func _crew_name(did: String) -> String:
	var gs: Array = CrimeUnderGang.ids()
	if not gs.is_empty():
		return str(CrimeUnderGang.get_gang(int(gs[0])).get("name", "the Crew"))
	var names: Array = (SoloCfg.sect("districts").get(did, {}) as Dictionary).get("crews", ["the Harbour Crew", "the Ashen Hands"])
	return str(names[0])

static func _answer(choice, pid: int, offer_id: String, crew: String) -> void:
	waiting = false
	var f = SysUtil.folk(pid)
	if f == null:
		return
	if str(choice) != "yes" and member:
		standing -= 2.0
		if standing < -5.0:
			member = false
			crew_name = ""
			SysUtil.notify("%s has cut you loose: you stopped being any use." % crew, "info")
		else:
			SysUtil.notify("%s did not like that. Your standing with the crew drops." % crew, "warn")
		return
	if str(choice) != "yes":
		refusals += 1
		if refusals >= 3 and refusals % 3 == 0:
			f.add_buff("eviction_scare")          # the scare: standing in the block drops, a night of looking over the shoulder
			SysUtil.notify("They did not like the answer. Someone leans on you in a doorway and says the block remembers.", "warn")
		return
	var o: Dictionary = {}
	for x in cfg().get("offers", []):
		if str(x["id"]) == offer_id:
			o = x
	if o.is_empty():
		return
	var joined: bool = not member
	member = true
	crew_name = crew
	refusals = 0
	_do_job(f, o)
	if joined:
		SysUtil.notify("You are in with %s. Dues are %d coins a day." % [crew, int(cfg().get("dues_per_day", 3))], "warn")

## Run one job at once (pay, heat, a chance of the police) and send the pawn out for its length.
static func _do_job(f, o: Dictionary) -> void:
	var hid: int = int(f.household_id)
	Economy.deposit(hid, int(o["pay"]), "crew work")
	heat += float(o.get("heat", 8))
	standing += 1.0
	clean_days = 0
	var d: String = district_of_pawn(f)
	var low_cover: bool = SoloDistricts.roughness_of(d) >= float(cfg().get("min_roughness", 0.6))
	var arrest_p: float = float(o.get("arrest", 0.03)) * (1.0 if low_cover else 8.0 / 3.0) * (1.0 + heat / 40.0)
	var minutes: float = float(o.get("minutes", 60))
	if SysUtil.chance(arrest_p):
		_arrested(f)
		JusticePlayer.hold(f, 360.0, "custody", "Held by the police")
		return
	if o.has("trouble") and SysUtil.chance(float(o["trouble"])):
		SysUtil.notify("Rivals spotted you on the run. You got away, but it was close.", "warn")
		f.add_buff("eviction_scare")
	Away.send(f, minutes, "errand", {"label": "Out on a job"})

static func _arrested(f) -> void:
	var fine: int = 60
	Economy.record(int(f.household_id), -mini(fine, Economy.balance(int(f.household_id))), "fine: crew work")
	var recs: Array = JusticeState.records.get(int(f.id), [])
	recs.append({"day": SysUtil.day(), "charge": "crew work", "case": -1, "result": "fined"})
	JusticeState.records[int(f.id)] = recs
	SysUtil.notify("%s was picked up by the police and held for a night. A fine and a record: it will block job offers until it is expunged." % f.name, "bad")
	SysUtil.game_event("pawn_arrested", {"folk_id": int(f.id)})

## Leave the crew: pay the payoff, or take the chance of a beating.
static func leave(f) -> Dictionary:
	if not member:
		return {"ok": false, "reason": "You are not in a crew."}
	var payoff: int = int(cfg().get("leave_payoff", 150))
	if Economy.spend(int(f.household_id), payoff, "paid off the crew"):
		member = false
		crew_name = ""
		SysUtil.notify("You paid the crew off and walked away.", "good")
		return {"ok": true, "reason": ""}
	member = false
	crew_name = ""
	if SysUtil.chance(float(CrimeUnderGang.cfg().get("leave_traitor", 0.3))):
		Health.injure(f, 1, "a beating from the crew")
		return {"ok": true, "reason": "You could not pay. They beat you and let you go."}
	return {"ok": true, "reason": "You could not pay. They let you go this once."}
