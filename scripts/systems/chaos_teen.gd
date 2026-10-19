class_name ChaosTeen
extends RefCounted
## Runaway teen (task 07b). Teens only. Every day a teen who is miserable (a bad mood or empty fun and social needs) adds a day to
## ChaosState.unhappy; a good day takes two off. After about five bad days in a row the `runaway_teen` incident can roll: the teen leaves a note
## (a warning a few hours ahead; cheering them up cancels it) and stays away for two to four days, then comes home on their own.
## Housemates who are grown up are worried sick meanwhile. Nothing happens on screen but the note and the empty chair. Numbers: config.chaos.teen.

static func cfg() -> Dictionary:
	return ChaosState.cfg("teen")

static func on_day() -> void:
	if ChaosState.unhappy.is_empty() and not _any_teen():
		return
	var c: Dictionary = cfg()
	for f in SysUtil.residents():
		if str(f.age_stage) != "teen":
			continue
		var id: int = int(f.id)
		if ChaosState.gone.has(id):
			continue
		if miserable(f, c):
			ChaosState.unhappy[id] = int(ChaosState.unhappy.get(id, 0)) + 1
		else:
			var left: int = int(ChaosState.unhappy.get(id, 0)) - int(c.get("good_day_takes", 2))
			if left > 0:
				ChaosState.unhappy[id] = left
			else:
				ChaosState.unhappy.erase(id)
	for id2 in ChaosState.unhappy.keys():                      # teens who grew up, left or died
		var t = SysUtil.folk(int(id2))
		if t == null or str(t.age_stage) != "teen":
			ChaosState.unhappy.erase(id2)

static func _any_teen() -> bool:
	for f in SysUtil.residents():
		if str(f.age_stage) == "teen":
			return true
	return false

static func miserable(f, c: Dictionary) -> bool:
	if (c.get("moods", ["sad", "angry", "tense", "uncomfortable"]) as Array).has(str(f.mood_name)) and int(f.mood_intensity) >= int(c.get("mood_intensity", 2)):
		return true
	var low: float = float(c.get("low_need", -45))
	return f.get_stat_value("fun") < low and f.get_stat_value("social") < low

# ------------------------------------------------------------------ the incident
static func run_away(f) -> Dictionary:
	if f == null or str(f.age_stage) != "teen" or ChaosState.gone.has(int(f.id)):
		return {"text": ""}
	var c: Dictionary = cfg()
	var days: int = Incidents.rng.randi_range(int(c.get("days_min", 2)), int(c.get("days_max", 4)))
	if not Away.send(f, float(days * 1440), "runaway", {"label": "Gone for a while"}):
		return {"text": ""}
	var id: int = int(f.id)
	ChaosState.gone[id] = {"since": SysUtil.now(), "back": SysUtil.now() + days * 1440}
	ChaosState.unhappy.erase(id)
	for o in SysUtil.residents():
		if int(o.household_id) == int(f.household_id) and int(o.id) != id and str(o.age_stage) in ["adult", "elder"]:
			o.add_buff("worried_sick")
	ChaosState.count("runaway")
	return {"text": "%s left a note and walked out: they could not stand it at home any more. They will probably be back in a few days." % f.name, "kind": "bad"}

static func on_returned(f, reason: String) -> void:
	if f == null or reason != "runaway":
		return
	ChaosState.gone.erase(int(f.id))
	ChaosState.unhappy.erase(int(f.id))
	f.add_buff("relieved")
	for o in SysUtil.residents():
		if int(o.household_id) == int(f.household_id):
			o.remove_buff("worried_sick")
	ChaosState.count("runaway_home")
	SysUtil.notify("%s came home. Maybe it is time for a proper talk." % f.name, "good")
