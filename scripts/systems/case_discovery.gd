class_name CaseDiscovery
extends RefCounted
## How crimes get found (09b). Nothing goes unnoticed forever.
##   witnessed crime       -> reported straight away (CaseDiscovery.report)
##   hidden killing        -> MISSING score grows every hour from who would miss the victim (family, a job, friends); over the threshold
##                            someone reports them missing; independently a body can be found (passers-by, a smell, a search party)
##   theft / burglary      -> the owner notices when they are home and awake (items quickly, coins when they next look at their wallet)
## Delay by connection (default data): family within a game day, a worker in a day or two, a jobless loner about a week.

static func cfg() -> Dictionary:
	return JusticeState.sect("discovery")

# ------------------------------------------------------------------ hourly
static func on_hour() -> void:
	for c in CaseStore.in_state(["hidden", "open"]):
		if str(c["state"]) == "hidden":
			c["hours_hidden"] = int(c["hours_hidden"]) + 1
			match str(c["kind"]):
				"murder", "serial", "manslaughter":
					_missing_tick(c)
				"burglary", "theft", "robbery", "assault", "fraud":
					_theft_tick(c)
				"arson":
					report(c, -1, "seen")

## Missing-person score per hour for the victim (also used by the tests to explain the delay).
static func missing_rate(victim: int) -> float:
	var k: Dictionary = cfg().get("missing", {})
	var rate: float = float(k.get("base_per_hour", 0.07))
	var relatives: int = 0
	for o in CrimePerson.close_ones(victim):
		if CrimePerson.alive(int(o)):
			relatives += 1
	rate += float(relatives) * float(k.get("relative_per_hour", 0.8))
	if CrimePerson.has_job(victim) and SysUtil.weekday() < 5 and SysUtil.hour_f() >= 8.0 and SysUtil.hour_f() < 18.0:
		rate += float(k.get("job_per_hour", 1.0))
	if Careers.school.has(victim) and SysUtil.weekday() < 5 and SysUtil.hour_f() >= 8.0 and SysUtil.hour_f() < 15.0:
		rate += float(k.get("school_per_hour", 1.5))
	rate += float(CrimePerson.friends(victim).size()) * float(k.get("friend_per_hour", 0.05))
	return rate

static func _missing_tick(c: Dictionary) -> void:
	var k: Dictionary = cfg().get("missing", {})
	var v: int = int(c["victim"])
	c["missing"] = float(c["missing"]) + missing_rate(v) * float(c.get("missing_mult", 1.0))
	if float(c["missing"]) >= float(k.get("threshold", 12.0)):
		report(c, _reporter_for(v), "missing")
		return
	var scene: String = str(c["scene"])
	var p: float = float(cfg().get("body_found_per_hour", {}).get("street" if scene == "street" else ("home" if scene.begins_with("home:") else "town"), 0.003))
	if int(c["hours_hidden"]) > 48:
		p *= 2.5                                      # the smell
	p *= 1.0 - 0.7 * float(c.get("concealed", 0.0))
	if JusticeState.chance(p):
		report(c, -1, "body")

static func _reporter_for(victim: int) -> int:
	for o in CrimePerson.close_ones(victim):
		if CrimePerson.alive(int(o)):
			return int(o)
	var fr: Array = CrimePerson.friends(victim)
	for o2 in fr:
		if CrimePerson.alive(int(o2)):
			return int(o2)
	return -1

static func _theft_tick(c: Dictionary) -> void:
	var k: Dictionary = cfg().get("theft", {})
	var hid: int = int(c["vhid"])
	var h: float = SysUtil.hour_f()
	var p: float = 0.0
	if hid > 0:
		if CrimePlace.awake_at_home(hid).is_empty():
			return
		p = float(k.get("items_per_hour", 0.5)) if not (c["loot"] as Array).is_empty() else float(k.get("coins_per_hour", 0.12))
	else:
		if h < 7.0 or h > 22.0:
			return
		p = float(k.get("townie_per_hour", 0.15))
	if JusticeState.chance(p):
		report(c, int(c["victim"]), "noticed")

# ------------------------------------------------------------------ report
## A crime becomes known to the police. `how`: seen | noticed | missing | body | victim | called.
static func report(c: Dictionary, reporter: int, how: String) -> void:
	if str(c["state"]) != "hidden":
		return
	c["state"] = "open"
	c["disc_day"] = SysUtil.day()
	c["reporter"] = reporter
	c["reported_min"] = SysUtil.now()
	c["how"] = how
	var v: int = int(c["victim"])
	var kind: String = str(c["kind"])
	var text: String = ""
	var deadly: bool = kind in ["murder", "serial", "manslaughter"]
	if deadly:
		if how == "missing":
			c["found"] = false
			text = "%s has been reported missing. The police are looking for them." % CrimePerson.name_of(v)
			CaseStore.note(c, text, "missing", 3)
			CaseStore.toast(c, text, "warn")
			CrimeSerial.on_missing_report(c)
			return
		_found(c, "body" if how == "body" else how)
		return
	match kind:
		"burglary", "theft":
			text = "A break-in was discovered at %s. Some belongings are missing." % CaseStore.house_label(str(c["scene"])) if kind == "burglary" \
				else "Something was stolen at %s." % CaseStore.house_label(str(c["scene"]))
		"robbery":
			text = "%s was robbed." % CrimePerson.name_of(v)
		"assault":
			text = "%s was attacked." % CrimePerson.name_of(v)
		"arson":
			text = "%s was set on fire on purpose." % CaseStore.house_label(str(c["scene"]))
		"fraud":
			text = "%s was cheated out of money." % CrimePerson.name_of(v)
		"embezzlement":
			text = "Money went missing at a workplace."
		"blackmail":
			text = "%s is being blackmailed." % CrimePerson.name_of(v)
		_:
			text = "%s was reported." % CaseStore.kind_label(kind).capitalize()
	CaseStore.note(c, text, kind, 3 if kind != "robbery" else 2)
	if int(c["vhid"]) > 0 or CrimePerson.is_player(v):
		CaseStore.toast(c, text + " The police have been told.", "bad", true)
	Police.open_case(c)

## The body is found: the death becomes known (grief, grave) and the murder investigation begins in earnest.
static func _found(c: Dictionary, how: String) -> void:
	c["found"] = true
	var v: int = int(c["victim"])
	CrimePerson.reveal_death(v)
	var nm: String = CrimePerson.name_of(v)
	var text: String = "%s was found dead. The police say it was no accident." % nm if how != "missing" else "%s was found. The police are treating it as a killing." % nm
	if bool(c.get("folk_victim", false)):
		text = "The police are investigating the death of %s." % nm
	CaseStore.note(c, text, "murder", 5)
	CaseStore.toast(c, text, "death")
	JusticeState.uneasy_until = maxi(JusticeState.uneasy_until, SysUtil.day() + int(JusticeState.sect("police").get("uneasy_days_murder", 10)))
	Police.open_case(c)

## Daily: a reported-missing victim may be found by the search (police work + volunteers).
static func on_day() -> void:
	for c in CaseStore.in_state(["open"]):
		if bool(c.get("ship_hold", false)):
			continue                       # task 22: the ship searches for its own missing
		if c.has("found") and not bool(c["found"]):
			var p: float = float(cfg().get("search_found_per_day", 0.3)) * (0.5 + Police.strength())
			if JusticeState.chance(p) or SysUtil.day() - int(c["disc_day"]) > int(cfg().get("search_give_up_days", 8)):
				_found(c, "search")
