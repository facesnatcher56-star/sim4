class_name SoloShelter
extends RefCounted
## The bottom of the ladder (R12.1): sleeping rough, the night shelter and day labour. All three are interactions in data/content_solo.json that call
## back here through {"solo_hook": ...}. The shelter gives a bed, a shower and a locker for a few nights a week and NO food. Numbers: data/solo.json.

static func cfg() -> Dictionary:
	return SoloCfg.sect("shelter")

static func lot_id() -> String:
	return str(cfg().get("lot", "shelter"))

static func nights_allowed() -> int:
	return int(SoloCfg.by_diff("start", "shelter_nights"))

## Week number of a day (weeks start on day 1, 8, 15 ...).
static func week_of(day: int) -> int:
	return (day - 1) / 7

static func on_day(day: int) -> void:
	if not SoloHome.active:
		return
	if week_of(day) != SoloHome.shelter_week:
		SoloHome.shelter_week = week_of(day)
		SoloHome.shelter_nights = 0

static func nights_left() -> int:
	return maxi(nights_allowed() - SoloHome.shelter_nights, 0)

# ------------------------------------------------------------------ rough sleeping
## The night is over: the cold ground, maybe a robbery or the police.
static func rough_night(f) -> void:
	if f == null:
		return
	SoloHome.rough_nights += 1
	var rs: Dictionary = SoloCfg.sect("rough_sleep")
	var mult: float = SoloDistricts.violence_mult(Neighborhood.lot_of(f), "robbery") if SoloHome.active else 1.0
	var hid: int = int(f.household_id)
	var coins: int = Economy.balance(hid)
	var r: RandomNumberGenerator = SysUtil.rng
	if coins >= int(rs.get("rob_min_coins", 20)) and r.randf() < float(rs.get("robbery_chance", 0.03)) * mult:
		var lost: int = int(float(coins) * float(rs.get("rob_share", 0.5)))
		if lost > 0:
			Economy.record(hid, -lost, "robbed while sleeping rough")
			SysUtil.notify("%s was robbed in the night: %d coins gone. Carrying little is the only protection out here." % [f.name, lost], "bad")
			SysUtil.game_event("robbed_rough", {"folk_id": int(f.id), "amount": lost})
	elif r.randf() < float(rs.get("moved_on_chance", 0.2)) / maxf(mult, 1.0) * (0.3 if mult > 1.0 else 1.0):
		SysUtil.notify("The police moved %s on in the night: no fine, but no proper sleep." % f.name, "warn")
		f.add_buff("slept_badly")

# ------------------------------------------------------------------ the shelter
static func shelter_night(f) -> void:
	SoloHome.shelter_nights += 1
	SysUtil.notify("A night in the shelter (%d left this week). It gives you a bed, not a meal." % nights_left(), "info")

# ------------------------------------------------------------------ day labour
static func day_labour_done(f) -> void:
	if f == null:
		return
	SysUtil.game_event("day_labour", {"folk_id": int(f.id)})
