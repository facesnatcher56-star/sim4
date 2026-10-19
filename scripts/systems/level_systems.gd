class_name LevelSystems
extends RefCounted
## One per-minute step for everything that only matters in buildings with floors (SystemsManager runs it): falls on the stairs and stuck lifts
## (LevelAccidents). Fire, disasters, crime and weather hook into their own files (FireLevels, LevelDisasters, CrimePlace, Weather).
## Returns at once on worlds without portals, so a flat map costs nothing.

static func on_minute() -> void:
	LevelAccidents.on_minute()


static func reset() -> void:
	LevelAccidents.reset()
	ApartmentUnits.reset()
