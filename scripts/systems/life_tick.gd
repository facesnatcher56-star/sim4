class_name LifeTick
extends RefCounted
## The one door of the life areas (task 14: education, health, food and nightlife, culture and leisure ...) into SystemsManager / SaveLoad, like
## MarketTick for the economy: reset, new game, the daily order, interaction and game-event routing, save / restore. Everything here is optional for
## the player and keeps running without them (townies study, places change staff, the job board turns over).
## Daily order: staff -> passes -> education (school, townies, job board) -> the other areas (each adds one line). See docs/LIFE.md for tiers and caps.

static func reset() -> void:
	LifeDefs.reset()
	Places.reset()
	PlaceStaff.reset()
	PlaceUse.reset()
	PlaceMember.reset()
	EduState.reset()
	HealthLife.reset()
	FoodServices.reset()
	LifeFame.reset()
	LeagueState.reset()
	ClubState.reset()
	TownNews.reset()
	PhoneState.reset()
	SocialFeed.reset()
	EventState.reset()

## A new game: the staff of every place is hired and this year's school events that are already past do not fire.
static func new_game() -> void:
	PlaceStaff.fill_all(false)
	EduSchool.init_year(SysUtil.day())
	LeagueState.ensure()
	ClubState.ensure()

static func on_day(day: int) -> void:
	PlaceStaff.on_day(day)
	PlaceMember.on_day(day)
	EduSchool.on_day(day)
	EduTownies.on_day(day)
	EduJobs.refresh(day)
	HealthLifeDay.on_day(day)
	PlaceNews.on_day(day)
	LifeFame.on_day(day)
	LeagueState.on_day(day)
	ClubState.on_day(day)
	PhoneDay.on_day(day)
	SocialFeed.on_day(day)

static func on_interaction_finished(folk_id: int, iid: String, success: bool) -> void:
	PlaceUse.on_interaction_finished(folk_id, iid, success)
	if success:
		HealthLife.on_interaction(folk_id, iid)
	if success and iid == "do_homework":
		EduSchool.on_homework_done(folk_id)

static func on_game_event(ev: String, payload: Dictionary) -> void:
	match ev:
		"returned_from_school":
			EduSchool.on_returned_from_school(int(payload.get("folk_id", -1)), bool(payload.get("skipped", false)))
		"returned_from_work":
			HealthLifeDay.on_work(int(payload.get("folk_id", -1)), bool(payload.get("skipped", false)))
		"chronicle":
			TownNews.on_chronicle(payload)
		"place_used":
			LifeOuting.on_place_used(int(payload.get("folk_id", -1)), str(payload.get("place", "")), str(payload.get("service", "")))
		"aged_up":
			EduSchool.on_aged_up(int(payload.get("folk_id", -1)), str(payload.get("from", "")), str(payload.get("to", "")))

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"staff": PlaceStaff.to_dict(), "use": PlaceUse.to_dict(), "member": PlaceMember.to_dict(), "edu": EduState.to_dict(), "health": HealthLife.to_dict(),
		"culture": {"fame": LifeFame.to_dict(), "league": LeagueState.to_dict(), "clubs": ClubState.to_dict()},
		"media": {"news": TownNews.to_dict(), "phone": PhoneState.to_dict(), "feed": SocialFeed.to_dict()}, "events": EventState.to_dict()}

## A save without the block (made before task 14) starts the life areas fresh.
static func from_dict(d: Dictionary, has_block: bool) -> void:
	reset()
	if not has_block:
		new_game()
		return
	PlaceStaff.from_dict(d.get("staff", {}))
	PlaceUse.from_dict(d.get("use", {}))
	PlaceMember.from_dict(d.get("member", {}))
	EduState.from_dict(d.get("edu", {}))
	HealthLife.from_dict(d.get("health", {}))
	var cu: Dictionary = d.get("culture", {})
	LifeFame.from_dict(cu.get("fame", {}))
	LeagueState.from_dict(cu.get("league", {}))
	ClubState.from_dict(cu.get("clubs", {}))
	var md: Dictionary = d.get("media", {})
	TownNews.from_dict(md.get("news", {}))
	PhoneState.from_dict(md.get("phone", {}))
	SocialFeed.from_dict(md.get("feed", {}))
	EventState.from_dict(d.get("events", {}))
