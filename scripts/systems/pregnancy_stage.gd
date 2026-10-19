class_name PregnancyStage
extends RefCounted
## Finding out and living through the months (task 18 part 3): early symptoms -> pregnancy test (market / pharmacy) or a doctor's visit ->
## "she knows"; the optional ultrasound (reveals the sex and twins); prenatal care visits; late-pregnancy limits and bed rest.
## Until she knows, she only feels off (buff feeling_off); once she knows she gets the "Expecting" buff and the trimester buffs (Family).
## Every action is a Command-layer interaction (data/content_pregnancy.json: take_pregnancy_test, prenatal_checkup, ultrasound, bed_rest)
## that fires a game event; this file reacts to the events. Costs come out of the household's coins.

static func cost(key: String) -> int:
	return int(Pregnancy.cfg("stage").get(key, 0))

## She (and the player) now know. how: test | doctor | showing | ultrasound.
static func reveal(id: int, how: String) -> void:
	var r: Dictionary = Pregnancy.rec(id)
	if r.is_empty() or bool(r.get("known", false)):
		return
	r["known"] = true
	var f = SysUtil.folk(id)
	if f == null:
		return
	f.remove_buff("feeling_off")
	f.add_buff("pregnant")
	Family.update_pregnancies()
	var txt: String = "%s is expecting a baby!" % f.name
	if how == "test":
		txt = "The test is positive. %s is expecting a baby!" % f.name
	elif how == "doctor":
		txt = "The doctor confirms it: %s is expecting a baby!" % f.name
	SysUtil.notify(txt, "birthday")
	SysUtil.game_event("pregnancy_known", {"folk_id": id, "how": how, "target_id": int(r.get("father", -1))})

## Pay from the household. False (and a plain note) when they cannot afford it.
static func _pay(f, amount: int) -> bool:
	if amount <= 0:
		return true
	if WorldIface.get_coins(int(f.household_id)) < amount:
		SysUtil.notify("%s cannot afford that right now." % f.name, "warn")
		return false
	WorldIface.add_coins(int(f.household_id), -amount)
	return true

## "Take a pregnancy test": the answer is right once she is far enough along; before that the test says "not yet".
static func take_test(id: int) -> Dictionary:
	var f = SysUtil.folk(id)
	if f == null or Sexes.of(id) != Sexes.FEMALE:
		return {"ok": false, "reason": "not_possible"}
	if not _pay(f, cost("test_cost")):
		return {"ok": false, "reason": "no_money"}
	var r: Dictionary = Pregnancy.rec(id)
	if r.is_empty():
		SysUtil.notify("%s took a pregnancy test. It is negative." % f.name, "info")
		return {"ok": true, "result": "negative"}
	if Pregnancy.progress(id) < float(Pregnancy.cfg("stage").get("test_accuracy_from", 0.12)):
		SysUtil.notify("%s took a pregnancy test. It is negative, but it may be too early to tell." % f.name, "info")
		return {"ok": true, "result": "negative"}
	reveal(id, "test")
	return {"ok": true, "result": "positive"}

## A doctor's visit: confirms an unknown pregnancy; for a known one it is prenatal care (less risk, up to `max_visits`).
static func checkup(id: int) -> Dictionary:
	var f = SysUtil.folk(id)
	if f == null:
		return {"ok": false, "reason": "missing"}
	if not _pay(f, cost("checkup_cost")):
		return {"ok": false, "reason": "no_money"}
	var r: Dictionary = Pregnancy.rec(id)
	if r.is_empty():
		SysUtil.notify("The doctor finds %s healthy." % f.name, "info")
		return {"ok": true, "result": "healthy"}
	if not bool(r.get("known", false)):
		reveal(id, "doctor")
	r["visits"] = mini(int(r.get("visits", 0)) + 1, int(Pregnancy.cfg("care").get("max_visits", 3)))
	f.add_to_stat("fun", 4.0)
	SysUtil.notify(Sexes.fill("%s's check-up went well. The doctor says {they} and the baby are doing fine." % f.name, id), "good")
	SysUtil.game_event("prenatal_visit", {"folk_id": id, "visits": r["visits"]})
	return {"ok": true, "result": "visit"}

## The ultrasound: reveals the sex(es) and twins. Needs the pregnancy to be known and far enough along.
static func ultrasound(id: int) -> Dictionary:
	var f = SysUtil.folk(id)
	var r: Dictionary = Pregnancy.rec(id)
	if f == null or r.is_empty() or not bool(r.get("known", false)):
		return {"ok": false, "reason": "not_possible"}
	if Pregnancy.progress(id) < float(Pregnancy.cfg("stage").get("ultrasound_from", 0.3)):
		SysUtil.notify("It is too early to see much on the ultrasound. Try again a little later.", "info")
		return {"ok": false, "reason": "too_early"}
	if not _pay(f, cost("ultrasound_cost")):
		return {"ok": false, "reason": "no_money"}
	r["sex_known"] = true
	r["visits"] = mini(int(r.get("visits", 0)) + 1, int(Pregnancy.cfg("care").get("max_visits", 3)))
	SysUtil.notify("%s" % describe_scan(id), "birthday")
	SysUtil.game_event("ultrasound", {"folk_id": id, "kids": int(r["kids"])})
	return {"ok": true, "result": "scan", "text": describe_scan(id)}

## "A girl!" / "Twins: a boy and a girl." - only once the scan has been done.
static func describe_scan(id: int) -> String:
	var r: Dictionary = Pregnancy.rec(id)
	var sx: Array = r.get("kid_sexes", [])
	var words: Array = sx.map(func(s): return "girl" if s == Sexes.FEMALE else "boy")
	if words.size() == 1:
		return "The scan shows a %s!" % words[0]
	var count: String = "Twins" if words.size() == 2 else "Triplets"
	return "%s! The scan shows %s." % [count, ", ".join(words)]

## Rest in bed (optional, by choice or the doctor's advice): lowers risk while it lasts. Toggle.
static func set_bed_rest(id: int, on: bool) -> void:
	var r: Dictionary = Pregnancy.rec(id)
	if r.is_empty():
		return
	r["bed_rest"] = on
	var f = SysUtil.folk(id)
	if f != null:
		if on:
			f.add_buff("bed_rest")
		else:
			f.remove_buff("bed_rest")

# ------------------------------------------------------------------ limits (hooked from HealthInjury.blocks_activity)
## "" or the reason a pregnant folk cannot do something with these tags (late pregnancy: exercise, heavy work).
static func blocks_activity(f, tags: Array) -> String:
	if f == null or not Pregnancy.is_late(int(f.id)):
		return ""
	var blocked: Array = Pregnancy.cfg("stage").get("late_blocked_tags", [])
	for t in tags:
		if blocked.has(str(t)):
			return "too far along for that"
	return ""

## Game events that start the actions (interaction on_finish fire_event).
static func on_game_event(ev: String, payload: Dictionary) -> void:
	var id: int = int(payload.get("folk_id", -1))
	match ev:
		"take_pregnancy_test":
			take_test(id)
		"prenatal_checkup":
			checkup(id)
		"ultrasound_scan":
			ultrasound(id)
		"bed_rest_start":
			set_bed_rest(id, true)
		"bed_rest_end":
			set_bed_rest(id, false)
		"fertility_treatment":
			Fertility.treat(id)
