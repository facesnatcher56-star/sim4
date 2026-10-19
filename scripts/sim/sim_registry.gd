class_name SimRegistry
extends RefCounted
## THE table of Clock-driven simulation work (task 17.2). Adding / merging a system's clock hook is ONE ROW in the matching list below.
## Row = [name, owner system, cadence (1 / 60 / 1440 or 5 / 15), order, priority, arg, Callable, active gate (or null), note]
##   order    position inside its layer (minute, then hour, then day): the old signal order is 200+ steps of 10; keep steps of 10 so a row can be
##            squeezed in between; ties run in registration order.
##   priority CRITICAL = never deferred; NORMAL = never deferred; LOW = postponed to a later tick when a frame is over its budget (only work whose
##            lateness by a frame does not change outcomes).
##   arg      "" = fn(), "total" = fn(minute total), "hour" = fn(hour), "day" = fn(day).
##   gate     optional Callable -> bool; false = nothing to do, the job costs one call (idle systems cost zero work).
##   note     tier behaviour / active set / caps (SimScheduler.describe() prints them into docs/PERFORMANCE.md).
## Rules (docs/PERFORMANCE.md): nothing per person per minute unless the person is ACTIVE; bucket per-entity periodic work with add_bucketed.

const C := SimScheduler.CRITICAL
const N := SimScheduler.NORMAL
const L := SimScheduler.LOW

## Groups: each installer owns one group so it can remove / disable its rows (teardown, tests that swap the Clock).
static func systems_group(sm: Object) -> String:
	return "systems#%d" % sm.get_instance_id()

static func director_group(dir: Object) -> String:
	return "director#%d" % dir.get_instance_id()

const GROUP_SOCIAL := "social"
const GROUP_SCENARIO := "scenario"
const GROUP_APP := "app"

# ------------------------------------------------------------------ SystemsManager rows
static func systems_rows(sm: Object) -> Array:
	var ens := Callable(sm, "ensure_registered")
	var autosave_on := Callable(sm, "autosave_active")
	return [
		# --- minute layer (was SystemsManager._minute_steps)
		["Tiers", "Tiers", 1, 90, C, "total", Tiers.refresh, null, "assigns ACTIVE / NEAR per person (hysteresis, cap); loops the world's folk only, cached by position"],
		["NeighborhoodService.before", "NeighborhoodService", 1, 210, N, "", NeighborhoodService.before_minute, null, "ACTIVE: lots with folk; far lots summarised"],
		["CareerShifts", "CareerShifts", 1, 220, N, "", CareerShifts.on_minute, null, "ACTIVE: people with a shift today (timed wake-up candidate)"],
		["Away", "Away", 1, 230, N, "", Away.on_minute, null, "people currently away only"],
		["StoryVisits", "StoryVisits", 1, 240, N, "", StoryVisits.on_minute, null, "visits in progress only"],
		["BabyCare", "BabyCare", 1, 250, N, "", BabyCare.on_minute, null, "babies / toddlers only"],
		["AccidentMarks", "AccidentMarks", 1, 260, N, "", AccidentMarks.on_minute, null, "ACTIVE folk x hazards; per-minute odds"],
		["Incidents", "Incidents", 1, 270, N, "", Incidents.on_minute, null, "open incidents / health records only"],
		["CrimeFlow", "CrimeFlow", 1, 280, N, "", CrimeFlow.on_minute, null, "police / open cases only"],
		["Fire", "Fire", 1, 290, N, "", Fire.on_minute, null, "burning cells only"],
		["DisasterClock", "DisasterClock", 1, 300, N, "", DisasterClock.on_minute, null, "running disasters only"],
		["Vacation", "Vacation", 1, 310, N, "", Vacation.on_minute, Callable(Vacation, "busy"), "trips on absolute due minutes; idle = one emptiness test"],
		["NeighborhoodService.after", "NeighborhoodService", 1, 320, N, "", NeighborhoodService.after_minute, null, "crowd gating by distance (Crowd.update)"],
		["WeatherFolk", "WeatherFolk", 1, 330, N, "", WeatherFolk.on_minute, null, "ACTIVE folk outdoors; per-minute exposure"],
		["LevelSystems", "LevelSystems", 1, 340, N, "", LevelSystems.on_minute, null, "multi-floor buildings with folk"],
		# --- hour layer (was SystemsManager._on_hour)
		["hour/ensure_registered", "SystemsManager", 60, 200, N, "", ens, null, ""],
		["hour/WeatherWorld.on_hour", "WeatherWorld", 60, 210, L, "hour", WeatherWorld.on_hour, null, "weather steps; world-level"],
		["hour/Holidays.on_hour", "Holidays", 60, 220, L, "", Holidays.on_hour, null, ""],
		["hour/Goals.on_hour", "Goals", 60, 230, L, "", Goals.on_hour, null, "residents only"],
		["hour/Story.on_hour", "Story", 60, 240, L, "hour", Story.on_hour, null, "STATISTICAL townies: hourly dice"],
		["hour/Family.on_hour", "Family", 60, 250, L, "", Family.on_hour, null, ""],
		["hour/AccidentMarks.on_hour", "AccidentMarks", 60, 260, N, "hour", AccidentMarks.on_hour, null, "before Incidents.on_hour"],
		["hour/Incidents.on_hour", "Incidents", 60, 270, N, "", Incidents.on_hour, null, "FULL near / STATISTICAL far dice per def"],
		["hour/AccidentMarks.after_hour", "AccidentMarks", 60, 280, N, "", AccidentMarks.after_hour, null, "right after Incidents.on_hour"],
		["hour/CrimeFlow.on_hour", "CrimeFlow", 60, 290, N, "", CrimeFlow.on_hour, null, ""],
		["hour/DisasterClock.on_hour", "DisasterClock", 60, 300, N, "hour", DisasterClock.on_hour, null, ""],
		["hour/Vacation.on_hour", "Vacation", 60, 310, N, "", Vacation.on_hour, Callable(Vacation, "busy"), "active trips only"],
		# --- day layer (was SystemsManager._on_day)
		["day/ensure_registered", "SystemsManager", 1440, 200, N, "", ens, null, ""],
		["day/Holidays.on_day", "Holidays", 1440, 210, N, "day", Holidays.on_day, null, ""],
		["day/Aging.on_day", "Aging", 1440, 220, N, "day", Aging.on_day, null, "residents + townies: O(people) cheap comparisons"],
		["day/Family.on_day", "Family", 1440, 230, N, "day", Family.on_day, null, ""],
		["day/Careers.on_day", "Careers", 1440, 240, N, "day", Careers.on_day, null, ""],
		["day/WeatherWorld.on_day", "WeatherWorld", 1440, 250, N, "day", WeatherWorld.on_day, null, ""],
		["day/Economy.on_day", "Economy", 1440, 260, N, "day", Economy.on_day, null, "bills per household"],
		["day/RelationshipService.on_day", "RelationshipService", 1440, 270, N, "day", RelationshipService.on_day, null, "decay of known pairs (bounded)"],
		["day/Story.on_day", "Story", 1440, 280, N, "day", Story.on_day, null, "townie daily dice (STATISTICAL tier)"],
		["day/Fire.on_day", "Fire", 1440, 290, N, "day", Fire.on_day, null, ""],
		["day/Incidents.on_day", "Incidents", 1440, 300, N, "", Incidents.on_day, null, "daily dice, FULL near / STATISTICAL far"],
		["day/CrimeFlow.on_day", "CrimeFlow", 1440, 310, N, "day", CrimeFlow.on_day, null, "all-townie pass (slice candidate, 17.3)"],
		["day/DisasterClock.on_day", "DisasterClock", 1440, 320, N, "day", DisasterClock.on_day, null, ""],
		["day/MarketTick.on_day", "MarketTick", 1440, 330, N, "day", MarketTick.on_day, null, "markets, shops, bank, rents"],
		["day/StoryPacing.on_day", "StoryPacing", 1440, 340, N, "day", StoryPacing.on_day, null, ""],
		["day/Vacation.on_day", "Vacation", 1440, 350, N, "", Vacation.on_day, Callable(Vacation, "busy"), "active trips only"],
		["day/systems_day event", "SystemsManager", 1440, 360, N, "day", Callable(sm, "emit_systems_day"), null, ""],
		["day/autosave", "SaveLoad", 1440, 370, N, "", SaveLoad.autosave, autosave_on, "one autosave per day (when Main is not doing it)"],
	]

# ------------------------------------------------------------------ the other Clock listeners
static func director_rows(dir: Object) -> Array:
	return [["SimDirector", "SimDirector", 1, 100, C, "total", Callable(dir, "_on_minute"), null,
		"ACTIVE: household folk every minute; strangers every minute for interactions, needs every STRANGER_PERIOD"]]

static func social_rows() -> Array:
	return [
		["SocialDynamics.on_minute", "SocialDynamics", 1, 400, L, "total", SocialDynamics.on_minute, null, "folk present in the same lot; contagion is the hotspot (17.3)"],
		["hour/SocialDynamics.on_hour", "SocialDynamics", 60, 400, L, "hour", SocialDynamics.on_hour, null, ""],
	]

static func scenario_rows() -> Array:
	return [["hour/ScenarioGoals.poll", "ScenarioGoals", 60, 500, N, "hour", ScenarioGoals._on_hour, Callable(Scenario, "active"), "only while a scenario is active"]]

static func app_rows(main: Object) -> Array:
	return [["day/Main.autosave", "Main", 1440, 900, N, "day", Callable(main, "_autosave_check"), null, "player autosave interval"]]

# ------------------------------------------------------------------ installers
static func install(sched: SimScheduler, group: String, rows: Array) -> void:
	for r in rows:
		var gate: Callable = r[7] if r[7] != null else Callable()
		sched.add(str(r[0]), str(r[1]), group, int(r[2]), int(r[3]), int(r[4]), r[6], str(r[5]), gate, str(r[8]))

static func install_systems(sched: SimScheduler, sm: Object) -> void:
	install(sched, systems_group(sm), systems_rows(sm))
	TownSim.install(sched, systems_group(sm))
	CrimeFlow.install_sliced(sched, systems_group(sm))

static func install_director(sched: SimScheduler, dir: Object) -> void:
	install(sched, director_group(dir), director_rows(dir))

static func install_social(sched: SimScheduler) -> void:
	install(sched, GROUP_SOCIAL, social_rows())

static func install_scenario(sched: SimScheduler) -> void:
	install(sched, GROUP_SCENARIO, scenario_rows())

static func install_app(sched: SimScheduler, main: Object) -> void:
	install(sched, GROUP_APP, app_rows(main))
