class_name Police
extends RefCounted
## The police: a rabbit hole (no map lot; the station is "somewhere in town", cells below it once the floors arrive). Holds the town's
## policing strength (officers, detectives, an active serial hunt), answers calls for crimes in progress, and opens cases.
##   Police.strength()                 0.3 .. 1.6 multiplier on investigation work and arrest chances
##   Police.respond(c, delay)          a call for a crime in progress: officers arrive after a delay and may catch the culprit
##   Police.open_case(c)               the crime is known: investigation starts (CaseInvestigation does the daily work)
##   Police.call_police(folk_id)            the "Call the police" action of a resident

static func cfg() -> Dictionary:
	return JusticeState.sect("police")

## Officers and detectives in town (townie careers and player jobs).
static func officers() -> int:
	return _count_career("police_officer")

static func detectives() -> int:
	return _count_career("detective")

static func _count_career(cid: String) -> int:
	var n: int = 0
	for pid in CrimePerson.everyone():
		if CrimePerson.career(pid) == cid and not CrimePerson.in_custody(pid):
			n += 1
	return n

static func strength() -> float:
	var c: Dictionary = cfg()
	var s: float = float(c.get("base_strength", 0.55)) + float(officers()) * float(c.get("per_officer", 0.12)) + float(detectives()) * float(c.get("per_detective", 0.2))
	if JusticeState.serial.get("hunt", false):
		s += float(c.get("serial_hunt_bonus", 0.4))
	return clampf(s, 0.3, float(c.get("max_strength", 1.6)))

## Patrols out at night make street crime harder.
static func patrol_factor() -> float:
	var c: Dictionary = cfg()
	return CityPolicy.crime_mult() / (1.0 + float(officers()) * float(c.get("patrol_per_officer", 0.15)) + (float(c.get("serial_patrol", 0.5)) if JusticeState.serial.get("hunt", false) else 0.0))      # task 12: a curfew helps

static func open_case(c: Dictionary) -> void:
	c["state"] = "open"
	if int(c.get("disc_day", -1)) < 0:
		c["disc_day"] = SysUtil.day()
	if str(c["kind"]) in ["murder", "serial", "manslaughter"]:
		Police.stir_town(c)
	SysUtil.game_event("case_opened", {"case": int(c["id"]), "kind": str(c["kind"])})

## Fear: the town is "Uneasy at night" until the case is solved (murder), a few days for a robbery.
static func stir_town(c: Dictionary) -> void:
	var days: int = int(cfg().get("uneasy_days_murder", 10))
	JusticeState.uneasy_until = maxi(JusticeState.uneasy_until, SysUtil.day() + days)
	for r in SysUtil.residents():
		r.add_buff("uneasy_at_night")

static func is_uneasy() -> bool:
	return JusticeState.uneasy_until >= SysUtil.day()

## A crime in progress was reported. Officers arrive after `delay` minutes (queued); the catch roll happens when they do.
static func respond(c: Dictionary, delay: int = -1) -> void:
	if delay < 0:
		delay = int(cfg().get("response_min", [12, 30])[0]) + JusticeState.rng.randi_range(0, int(cfg().get("response_min", [12, 30])[1]) - int(cfg().get("response_min", [12, 30])[0]))
		if CityServices.map_ready():                                    # task 12: a patrol car drives from the station
			var scene: String = str(c.get("scene", ""))
			var lot: String = PlayerLots.home_of_household(int(c.get("vhid", 0))) if scene.begins_with("home:") else Neighborhood.HOME
			delay = int(CityServices.dispatch("police", lot)["minutes"])
	JusticeState.queue({"kind": "police_arrive", "due_min": SysUtil.now() + delay, "case": int(c["id"])})
	CaseStore.note(c, "The police were called.")

static func on_minute() -> void:
	if JusticeState.pending.is_empty():
		return
	var keep: Array = []
	var now: int = SysUtil.now()
	var due: Array = []
	for p in JusticeState.pending:
		if int(p.get("due_min", 0)) <= now:
			due.append(p)
		else:
			keep.append(p)
	JusticeState.pending = keep
	for p2 in due:
		CrimeFlow.run_pending(p2)

## The officers arrive: they may catch a culprit who is still on the scene, and always start the case.
static func arrive(c: Dictionary) -> void:
	if not CaseStore.has_case(int(c["id"])):
		return
	var culprit: int = int(c["culprit"])
	if str(c["state"]) == "hidden":
		CaseDiscovery.report(c, int(c["victim"]), "called")
	var here: bool = bool(c.get("on_scene", false))
	if here and culprit >= 0 and JusticeState.chance(float(cfg().get("catch_on_scene", 0.5)) * strength()):
		c["on_scene"] = false
		CrimeBurglary.end_scene(c, true)
		c["recovered"] = true
		CaseStore.note(c, "The police caught the burglar and got the belongings back.", "arrest", 3)
		CaseStore.toast(c, "The police caught the burglar and recovered the stolen things!", "good", true)
		CrimeBurglary.restore_loot(c)
		JusticeProcess.arrest(c, culprit)
	else:
		CaseStore.note(c, "Police arrived but the culprit was gone.")
		CaseStore.toast(c, "The police arrived, but the culprit was already gone. They are taking statements.", "warn")

## The resident's "Call the police" action.
static func call_police(folk_id: int) -> void:
	for c in CaseStore.in_state(["hidden", "open"]):
		if bool(c.get("on_scene", false)) and int(c["vhid"]) == CrimePerson.hid(folk_id):
			c["called"] = true
			respond(c)
			return
	SysUtil.notify("There is nothing to report right now.", "info")
