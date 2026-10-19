class_name PregnancyLabour
extends RefCounted
## Labour (task 18 part 5). A few game hours before the due time: "Contractions!" (a warning toast). The place is chosen then: the HOSPITAL
## (when the town has a maternity ward; a short trip, safer) or a HOME birth. The player's folk are asked (prompt, default as drawn); the rest
## decide by the hospital birth chance in data/hospital.json. Labour lasts 3 to 6 game hours (data), the birth follows. The partner is present
## when they are around (a strong shared memory) or absent (a regret). Tier behaviour: only mothers in labour (a handful), driven by the
## hourly pregnancy hook; no polling of anyone else. The record keeps `labour = {start, end, place, ward}` and is saved with the pregnancy.

static func cfg() -> Dictionary:
	return Pregnancy.cfg("labour")

static func due_min(r: Dictionary) -> int:
	return (int(r["due_day"]) - 1) * 1440

static func in_labour(id: int) -> bool:
	return Pregnancy.rec(id).has("labour")

## Hourly: start labour near the due time, finish it when its hours are over.
static func on_hour(id: int, r: Dictionary) -> void:
	var now: int = SysUtil.now()
	if r.has("labour"):
		if now >= int((r["labour"] as Dictionary)["end"]):
			finish(id)
		return
	if now >= due_min(r) - int(cfg().get("lead_hours", 6)) * 60:
		start(id)

static func start(id: int) -> void:
	var r: Dictionary = Pregnancy.rec(id)
	var m = SysUtil.folk(id)
	if r.is_empty() or m == null or r.has("labour"):
		return
	var c: Dictionary = cfg()
	var mins: int = Pregnancy.rng.randi_range(int(c.get("minutes_min", 180)), int(c.get("minutes_max", 360)))
	var has_ward: bool = HospitalWard.lot_id() != "" and Workplace.map_ready() and SysUtil.is_resident(m)
	var place: String = "hospital" if has_ward and Pregnancy.rng.randf() < float(Hospital.cfg().get("birth", {}).get("chance", 0.7)) else "home"
	r["labour"] = {"start": SysUtil.now(), "end": SysUtil.now() + mins + (int(c.get("travel_minutes", 30)) if place == "hospital" else 0), "place": place, "ward": has_ward}
	m.add_buff("in_labour")
	m.cancel_current("labour")
	m.clear_queue()
	SysUtil.notify("Contractions! %s's baby is on the way." % m.name, "warn")
	if CrimePerson.is_player(id) and has_ward:
		JusticePlayer.ask(id, "Contractions!", "%s's labour has started. Go to the hospital, or have the baby at home?" % m.name,
			[{"id": "hospital", "label": "Go to the hospital"}, {"id": "home", "label": "Stay at home"}], func(choice): set_place(id, str(choice)), place)
	SysUtil.game_event("labour_started", {"folk_id": id, "place": place})

static func set_place(id: int, place: String) -> void:
	var r: Dictionary = Pregnancy.rec(id)
	if r.is_empty() or not r.has("labour") or not (place in ["home", "hospital"]):
		return
	var lb: Dictionary = r["labour"]
	if place == "hospital" and not bool(lb.get("ward", false)):
		return
	lb["place"] = place

## The birth. Without an hourly clock (a day tick, tests) the labour is simply over.
static func finish(id: int) -> void:
	var r: Dictionary = Pregnancy.rec(id)
	if r.is_empty():
		return
	if not r.has("labour"):
		start(id)
	PregnancyBirth.deliver(id, int(r.get("father", -1)))
	Aging.pregnancies.erase(id)
	var m = SysUtil.folk(id)
	if m != null:
		m.remove_buff("in_labour")

## Was the partner there? Present = a resident who is not away; it becomes a shared memory, absence a regret.
static func partner_at_birth(mother_id: int, father_id: int) -> void:
	var fa = SysUtil.folk(father_id) if father_id >= 0 else null
	if fa == null:
		return
	var c: Dictionary = cfg()
	if not SysUtil.is_away(fa) and str(fa.age_stage) in ["adult", "elder"]:
		fa.add_buff("birth_bond")
		var m = SysUtil.folk(mother_id)
		if m != null:
			m.add_buff("birth_bond")
		Emotions.imprint(fa, "folk:%d" % mother_id, float(c.get("present_bonus", 0.8)), "birth", "happy", "the birth of our baby")
		RelationshipService.add_both(mother_id, father_id, "romance", 4.0)
		RelationshipService.add_both(mother_id, father_id, "friendship", 4.0)
		SysUtil.game_event("birth_witnessed", {"folk_id": father_id, "target_id": mother_id, "present": true})
	else:
		fa.add_buff("missed_birth")
		Emotions.imprint(fa, "folk:%d" % mother_id, float(c.get("absent_penalty", -0.5)), "birth", "guilty", "missing the birth")
		RelationshipService.add_both(mother_id, father_id, "friendship", -3.0)
		SysUtil.game_event("birth_witnessed", {"folk_id": father_id, "target_id": mother_id, "present": false})
