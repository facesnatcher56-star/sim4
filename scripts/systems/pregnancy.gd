class_name Pregnancy
extends RefCounted
## A pregnancy of a folk on the lot (task 18 part 3). The record lives in `Aging.pregnancies[mother_id]` (saved with the "aging" block, which
## also carries `Pregnancy.extra` under "preg"):
##   father, due_day, started, started_min   (the original keys)
##   planned (bool), known (she knows), told [ids], secret (bool), kids (1..3), kid_sexes [..], sex_known (ultrasound), risk (points),
##   visits (prenatal care), bed_rest, rested, ate_well, symptoms (buff shown), tracker keys of the other Pregnancy* files.
## Only females carry. Everything else (conception dice, telling people, care, risks, leave, loss, labour) is in the Conception / Pregnancy*
## classes; this file is the state, the clock hooks and the save.
## Tier behaviour: ACTIVE and NEAR residents only (the active set is `Aging.pregnancies`, a handful of records); townies use PregnancyTownie
## (daily dice on the townie record, STATISTICAL). Cadence: hourly (symptoms, telling) and daily (births, risks) from Family.on_hour / Aging.on_day.
## Caps: one record per mother; `extra` holds one small dict per person who was ever asked about fertility (pruned when they die).

static var rng: RandomNumberGenerator = _make_rng()
static var extra: Dictionary = {}          # person id -> fertility state (Fertility.state)

static func _make_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 0x7ab1e
	return r

static func seed_rng(s: int) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = s

static func reset() -> void:
	extra.clear()
	rng = _make_rng()
	PregnancyLoss.reset()

static func cfg(section: String = "") -> Dictionary:
	var t: Dictionary = SysUtil.table("pregnancy")
	return t if section == "" else t.get(section, {})

static func rec(id: int) -> Dictionary:
	return Aging.pregnancies.get(id, {})

static func is_pregnant(id: int) -> bool:
	return Aging.pregnancies.has(id)

## Does she know? (Records from before this system count as known.)
static func known(id: int) -> bool:
	return bool(rec(id).get("known", true))

static func length_days() -> int:
	return maxi(int(Aging.cfg().get("pregnancy", {}).get("days", 3)), 1)

# ------------------------------------------------------------------ start
## Begin a pregnancy of `mother_id` (must be female). Returns the record. `opts`: planned, kids (forced), father.
static func start(mother_id: int, father_id: int, planned: bool, opts: Dictionary = {}) -> Dictionary:
	var kids: int = int(opts.get("kids", 0))
	if kids <= 0:
		kids = roll_kids(mother_id)
	var sexes: Array = []
	for _i in kids:
		sexes.append(Sexes.roll())
	var day: int = SysUtil.day()
	var r: Dictionary = {"father": father_id, "due_day": day + length_days(), "started": day, "started_min": SysUtil.now(), "planned": planned, "known": false,
		"told": [], "secret": false, "kids": kids, "kid_sexes": sexes, "sex_known": false, "risk": 0.0, "visits": 0, "bed_rest": false,
		"symptoms": false, "events": []}
	Aging.pregnancies[mother_id] = r
	var m = SysUtil.folk(mother_id)
	if m != null:
		m.refresh_mood()
	SysUtil.game_event("pregnant", {"folk_id": mother_id, "target_id": father_id, "planned": planned, "kids": kids})
	return r

## 1 / 2 / 3 babies: twins and triplets by data; the fertility clinic's treatment raises the odds.
static func roll_kids(mother_id: int) -> int:
	var c: Dictionary = cfg("conception")
	var mult: float = float(Fertility.cfg().get("clinic", {}).get("twins_mult", 6.0)) if Fertility.treated(mother_id) else 1.0
	var x: float = rng.randf()
	if x < float(c.get("triplets", 0.001)) * mult:
		return 3
	if x < (float(c.get("triplets", 0.001)) + float(c.get("twins", 0.02))) * mult:
		return 2
	return 1

# ------------------------------------------------------------------ progress
static func progress(id: int) -> float:
	return Family.pregnancy_progress(id)

static func trimester(id: int) -> int:
	return Family.trimester_of(id)

## The third trimester, or later than `late_from`: a visible bump, limited activities.
static func is_late(id: int) -> bool:
	return is_pregnant(id) and known(id) and progress(id) >= float(cfg("stage").get("late_from", 0.66))

# ------------------------------------------------------------------ clock hooks
## Hourly: symptoms, finding out by herself, telling the partner.
static func on_hour() -> void:
	for mid in Aging.pregnancies.keys():
		var r: Dictionary = Aging.pregnancies[mid]
		var m = SysUtil.folk(int(mid))
		if m == null:
			continue
		var p: float = progress(int(mid))
		var st: Dictionary = cfg("stage")
		if not bool(r.get("symptoms", false)) and p >= float(st.get("symptoms_at", 0.18)):
			r["symptoms"] = true
			if not known(int(mid)):
				m.add_buff("feeling_off")
				if CrimePerson.is_player(int(mid)):
					SysUtil.notify(Sexes.fill("%s has felt queasy and tired lately. A pregnancy test could tell why." % m.name, int(mid)), "info")
		if not known(int(mid)) and p >= float(st.get("auto_known_at", 0.5)):
			PregnancyStage.reveal(int(mid), "showing")
		PregnancyTell.on_hour(int(mid), r)
		if bool(r.get("symptoms", false)) and not known(int(mid)) and not CrimePerson.is_player(int(mid)) and rng.randf() < 0.25:
			PregnancyStage.take_test(int(mid))             # townspeople and housemates the player does not steer find out by themselves

## Daily: births at the due date, risks, noticing, loss dice.
static func on_day() -> void:
	PregnancyLoss.daily_pending()
	for mid in Aging.pregnancies.keys():
		if not Aging.pregnancies.has(mid):
			continue
		var r: Dictionary = Aging.pregnancies[mid]
		PregnancyRisk.on_day(int(mid), r)
		_ai_care(int(mid), r)
		PregnancyTell.on_day(int(mid), r)
		PregnancyChoice.on_day(int(mid), r)
		PregnancyLoss.on_day(int(mid), r)
		if Aging.pregnancies.has(mid) and SysUtil.day() >= int(r["due_day"]):
			PregnancyBirth.deliver(int(mid), int(r["father"]))
			Aging.pregnancies.erase(mid)

## Folk the player does not steer go to a prenatal check-up now and then.
static func _ai_care(id: int, r: Dictionary) -> void:
	if CrimePerson.is_player(id) or not bool(r.get("known", false)) or int(r.get("visits", 0)) >= int(cfg("care").get("max_visits", 3)):
		return
	if rng.randf() < 0.5:
		PregnancyStage.checkup(id)

static func on_game_event(ev: String, payload: Dictionary) -> void:
	PregnancyRisk.on_game_event(ev, payload)
	PregnancyLoss.on_game_event(ev, payload)

## A person is gone (died, moved out): their pregnancy and fertility state go with them.
static func forget(id: int) -> void:
	Aging.pregnancies.erase(id)
	extra.erase(id)

# ------------------------------------------------------------------ save
## JSON turns ints into floats: put the record's number fields back.
static func normalize_loaded(r: Dictionary) -> void:
	for k in ["kids", "visits", "tell_at_min"]:
		if r.has(k):
			r[k] = int(r[k])
	if r.has("told"):
		r["told"] = SysUtil.to_ints(r["told"])
	for e in r.get("events", []):
		e["day"] = int(e["day"])

static func to_dict() -> Dictionary:
	return {"extra": SysUtil.str_keys(extra).duplicate(true), "loss": PregnancyLoss.to_dict()}

static func from_dict(d: Dictionary) -> void:
	extra = SysUtil.int_keys((d.get("extra", {}) as Dictionary).duplicate(true))
	PregnancyLoss.from_dict(d.get("loss", {}))
	for k in extra:
		extra[k]["boost_until"] = int(extra[k].get("boost_until", 0))
		for key in ["tries", "rest_until", "leave_until"]:
			if extra[k].has(key):
				extra[k][key] = int(extra[k][key])
