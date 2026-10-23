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
		["Tiers", "Tiers", 1, 90, C, "total", Tiers.refresh, null, "all tiers: assigns ACTIVE / NEAR per person (hysteresis, ACTIVE cap); loops the world's folk once, classification cached until someone moves"],
		["NeighborhoodService.before", "NeighborhoodService", 1, 210, N, "", NeighborhoodService.before_minute, null, "ACTIVE: scheduled visits waiting for a resident at home (situations list only)"],
		["CareerShifts", "CareerShifts", 1, 220, N, "", CareerShifts.on_minute, null, "ACTIVE residents with a shift today; townie shifts are the TOWN schedule (CommuteTownies windows), not polled"],
		["WeaponShop", "WeaponShop", 1, 228, N, "", WeaponShop.on_minute, null, "task 57: the pawn walking onto a lot with a screening post (one comparison a minute)"],
		["JobApps", "JobApps", 1, 225, N, "", JobApps.on_minute, Callable(JobApps, "busy"), "task 61: the pawn's open job applications and interviews only (idle = zero)"],
		["SoloOpening", "SoloOpening", 1, 226, N, "", SoloOpening.on_minute, Callable(SoloOpening, "busy"), "task 61: a pending probation check-in only (idle = zero)"],
		["WorkNudge", "WorkNudge", 1, 227, N, "", WorkNudge.on_minute, null, "task 61: the pawn's next shift, one comparison a minute"],
		["Away", "Away", 1, 230, N, "", Away.on_minute, null, "people currently away only (residents; townies are STATISTICAL)"],
		["StoryVisits", "StoryVisits", 1, 240, N, "", StoryVisits.on_minute, null, "visits in progress only; held guests are dropped from scheduled visits"],
		["BabyCare", "BabyCare", 1, 250, N, "", BabyCare.on_minute, null, "ACTIVE babies / toddlers only"],
		["AccidentMarks", "AccidentMarks", 1, 260, N, "", AccidentMarks.on_minute, null, "ACTIVE every minute, NEAR / TOWN folk on their turn (odds scaled to the period); company from a per-minute grouping by lot; TOWN records get hourly markers"],
		["Incidents", "Incidents", 1, 270, N, "", Incidents.on_minute, null, "open incidents / health records only"],
		["CrimeFlow", "CrimeFlow", 1, 280, N, "", CrimeFlow.on_minute, null, "police / open cases only (ACTIVE)"],
		["Fire", "Fire", 1, 290, N, "", Fire.on_minute, null, "lots with burning cells only (idle = zero)"],
		["DisasterClock", "DisasterClock", 1, 300, N, "", DisasterClock.on_minute, null, "running disasters only"],
		["Vacation", "Vacation", 1, 310, N, "", Vacation.on_minute, Callable(Vacation, "busy"), "trips on absolute due minutes; idle = one emptiness test"],
		["PlaceAuto", "PlaceAuto", 1, 312, N, "", PlaceAuto.on_minute, Callable(PlaceAuto, "busy"), "outings of residents on autonomy: only while a plan is waiting or a trip is on (a handful of people); idle = one emptiness test"],
		["Utilities", "Utilities", 1, 315, N, "", Utilities.on_minute, Callable(Utilities, "busy"), "zone outages only (a few records); idle = one emptiness test"],
		["Transport", "Transport", 1, 316, N, "", Transport.on_minute, Callable(Transport, "busy"), "trips in progress only (the player's households); finished at their arrival minute"],
		["ShopActs", "ShopActs", 1, 317, N, "", ShopActs.on_minute, Callable(ShopActs, "busy"), "task 53: only while someone holds unpaid goods (the exit check)"],
		["RestrictedPlaces", "RestrictedPlaces", 1, 318, N, "", RestrictedPlaces.on_minute, null, "task 53: the pawn only, and only on a lot with a staff-only part (a few comparisons)"],
		["PersonActs", "PersonActs", 1, 319, N, "", PersonActs.on_minute, Callable(PersonActs, "busy"), "task 53: only while the pawn follows someone"],
		["hour/Habits.on_hour", "Habits", 60, 321, N, "hour", Habits.on_hour, null, "task 55: smokers only (a handful)"],
		["Fears", "Fears", 1, 320, N, "", Fears.on_minute, Callable(Fears, "busy"), "task 55: only people with a fear flaw, every 5 minutes"],
		["CityAmbulance", "CityServices", 1, 317, N, "", CityAmbulance.on_minute, Callable(CityAmbulance, "busy"), "ambulances on their way (residents on the real map); idle = one emptiness test"],
		["NeighborhoodService.after", "NeighborhoodService", 1, 320, N, "", NeighborhoodService.after_minute, null, "Crowd.update loops only the lots near an anchor (Tiers.lot_distances, cached); crowd checks per lot every 10 min; NEAR / TOWN crowd on their turn, they leave / arrive without walks; far lots dropped"],
		["WeatherFolk", "WeatherFolk", 1, 330, N, "", WeatherFolk.on_minute, null, "ACTIVE every minute, NEAR / TOWN folk on their turn with the exposure scaled to the period"],
		["LevelSystems", "LevelSystems", 1, 340, N, "", LevelSystems.on_minute, null, "multi-floor buildings with folk (ACTIVE / NEAR)"],
		# --- hour layer (was SystemsManager._on_hour)
		["hour/ensure_registered", "SystemsManager", 60, 200, N, "", ens, null, "residents only"],
		["hour/WeatherWorld.on_hour", "WeatherWorld", 60, 210, L, "hour", WeatherWorld.on_hour, null, "garden plots always; plants only near an anchor (far lots count owed rain hours, caught up daily); weather steps are world-level"],
		["hour/Holidays.on_hour", "Holidays", 60, 220, L, "", Holidays.on_hour, null, "world-level"],
		["hour/Goals.on_hour", "Goals", 60, 230, L, "", Goals.on_hour, null, "residents only (ACTIVE)"],
		["hour/Story.on_hour", "Story", 60, 240, L, "hour", Story.on_hour, null, "STATISTICAL townies: hourly dice"],
		["hour/Family.on_hour", "Family", 60, 250, L, "", Family.on_hour, null, "residents + townies in family records (small)"],
		["hour/AccidentMarks.on_hour", "AccidentMarks", 60, 260, N, "hour", AccidentMarks.on_hour_sched, null, "before the hourly dice: TOWN records get their markers; job markers are set around each slice when the dice are sliced"],
		["hour/Incidents.on_hour", "Incidents", 60, 270, N, "", Incidents.on_hour_sliced, null, "hospital + health upkeep, then starts a sliced pass of the hourly dice (Incidents.slice)"],
		["hour/AccidentMarks.after_hour", "AccidentMarks", 60, 280, N, "", AccidentMarks.after_hour_sched, null, "job markers removed again (unless sliced: done per slice)"],
		["hour/CrimeFlow.on_hour", "CrimeFlow", 60, 290, N, "", CrimeFlow.on_hour, null, "places of everyone (O(people), a few lookups each)"],
		["hour/Utilities.on_hour", "Utilities", 60, 295, N, "hour", Utilities.on_hour, null, "zones x causes (about 10 dice) + the player's homes while something is wrong; townie lots are one-line records"],
		["hour/DisasterClock.on_hour", "DisasterClock", 60, 300, N, "hour", DisasterClock.on_hour, null, "running disasters only"],
		["hour/Vacation.on_hour", "Vacation", 60, 310, N, "", Vacation.on_hour, Callable(Vacation, "busy"), "active trips only"],
		["hour/PlaceAuto.on_hour", "PlaceAuto", 60, 312, N, "hour", PlaceAuto.on_hour, null, "residents ACTIVE: who is ill, which pets need care (O(residents + pets), a few comparisons each)"],
		["hour/SoloOpening.on_hour", "SoloOpening", 60, 315, N, "hour", SoloOpening.on_hour, null, "task 61: the first week's moments (a few comparisons an hour)"],
		["hour/SoloPressure.on_hour", "SoloPressure", 60, 316, N, "hour", SoloPressure.on_hour, null, "task 61c: a crew offer the evening it is ready (one comparison an hour)"],
		["hour/SoloGrey.on_hour", "SoloGrey", 60, 316, N, "hour", SoloGrey.on_hour, null, "task 61c: an offer of grey money the day it is ready (one comparison an hour)"],
		["hour/SoloTeach.on_hour", "SoloTeach", 60, 317, N, "hour", SoloTeach.on_hour, null, "task 61: first-time lines (the pawn only)"],
		["hour/SoloCrews.on_hour", "SoloCrews", 60, 314, N, "hour", SoloCrews.on_hour, null, "one-character play: the planned drive-by of a rough district (one comparison an hour)"],
		["hour/CarActs.on_hour", "CarActs", 60, 316, N, "", CarActs.on_hour, null, "task 53: stolen cars found missing (a handful of pending reports)"],
		["hour/DynLife.on_hour", "DynLife", 60, 313, N, "hour", DynLife.on_hour, null, "residents ACTIVE / NEAR: stateless dice for small plans, household dinners / game nights / playtime, friends over (O(residents), a few comparisons each); far residents get a stat nudge"],
		# --- day layer (was SystemsManager._on_day)
		["day/ensure_registered", "SystemsManager", 1440, 200, N, "", ens, null, "residents only"],
		["day/Holidays.on_day", "Holidays", 1440, 210, N, "day", Holidays.on_day, null, "world-level"],
		["day/Aging.on_day", "Aging", 1440, 220, N, "day", Aging.on_day, null, "residents + townies: O(people) cheap comparisons"],
		["day/Succession.on_day", "Succession", 1440, 235, N, "day", Succession.on_day, null, "players whose household has nobody left (normally none)"],
		["day/Family.on_day", "Family", 1440, 230, N, "day", Family.on_day, null, "residents + townie family records (small)"],
		["day/Careers.on_day", "Careers", 1440, 240, L, "day", Careers.on_day, null, "residents' jobs; townie careers by daily comparison"],
		["day/WeatherWorld.on_day", "WeatherWorld", 1440, 250, L, "day", WeatherWorld.on_day_sched, null, "garden plots + the rain catch-up of far plants (sliced over the day)"],
		["day/Economy.on_day", "Economy", 1440, 260, L, "day", Economy.on_day, null, "bills per household"],
		["day/AutoFurnish.on_day", "AutoFurnish", 1440, 262, N, "day", AutoFurnish.on_day, null, "players' households only: buys the basics after 2 days with no player order and a bare home (a handful of comparisons, placement only when it fires)"],
		["day/RelationshipService.on_day", "RelationshipService", 1440, 270, L, "day", RelationshipService.on_day_sched, null, "known pairs, 1/24 per hour (DaySlices); ACTIVE and STATISTICAL pairs alike (data only)"],
		["day/Story.on_day", "Story", 1440, 280, L, "day", Story.on_day, null, "STATISTICAL townies: daily dice (TOWN townies too)"],
		["day/Fire.on_day", "Fire", 1440, 290, N, "day", Fire.on_day, null, "burning / burnt lots only"],
		["day/Incidents.on_day", "Incidents", 1440, 300, N, "", Incidents.on_day_sliced, null, "Health.on_day, then starts the sliced daily dice (96 slices)"],
		["day/CrimeFlow.on_day", "CrimeFlow", 1440, 310, L, "day", CrimeFlow.on_day, null, "global passes and case upkeep; per-person dice are the bucketed daily job, grudges are sliced (DaySlices)"],
		["day/Utilities.on_day", "Utilities", 1440, 315, N, "day", Utilities.on_day, null, "boil notices and the player's homes only"],
		["day/Transport.on_day", "Transport", 1440, 316, N, "day", Transport.on_day, null, "roads per zone, the player's cars on the street or in the car park"],
		["day/CityGov.on_day", "CityGov", 1440, 317, N, "day", CityGov.on_day, null, "world-level: the weekly budget, the election campaign and the monthly council (townies are only counted)"],
		["day/WorksEvents.on_day", "WorksEvents", 1440, 318, N, "day", WorksEvents.on_day, null, "world-level: strike and closure dice per industrial career (headcounts only; townies are counted, never visited)"],
		["day/DisasterClock.on_day", "DisasterClock", 1440, 320, N, "day", DisasterClock.on_day, null, "running disasters only"],
		["day/TownDrama.on_day", "TownDrama", 1440, 334, N, "day", TownDrama.on_day, null, "task 61d: the seeded town threads (a handful): has the player got involved with someone in one"],
		["day/SoloRent.on_day", "SoloRent", 1440, 335, N, "day", SoloRent.on_day, null, "one-character play: the pawn's eviction notice, the shelter week; a few comparisons"],
		["day/PlayerRequests.on_day", "PlayerRequests", 1440, 340, N, "day", PlayerRequests.on_day, null, "one-character play: a friend with no job and no money asks the pawn for a loan (a few comparisons)"],
		["day/Heritage.on_day", "Heritage", 1440, 339, N, "day", Heritage.on_day, null, "one-character play: the pawn's heritage festival day (one comparison a day)"],
		["day/SoloDistricts.on_day", "SoloDistricts", 1440, 336, N, "day", SoloDistricts.on_day, null, "one-character play: the roughness drift once a month (one comparison a day)"],
		["day/SoloPressure.on_day", "SoloPressure", 1440, 337, N, "day", SoloPressure.on_day, null, "one-character play: the pawn's crew offers and dues; a few comparisons"],
		["day/SoloCrews.on_day", "SoloCrews", 1440, 338, N, "day", SoloCrews.on_day, null, "one-character play: the drive-by dice of the rough districts (one roll per rough district)"],
		["day/MarketTick.on_day", "MarketTick", 1440, 330, L, "day", MarketTick.on_day, null, "markets, shops, bank, rents (world-level)"],
		["day/LifeTick.on_day", "LifeTick", 1440, 335, L, "day", LifeTick.on_day, null, "places (staff), school and college records of residents, townie studies, the job board: all daily, O(places + townies)"],
		["day/StoryPacing.on_day", "StoryPacing", 1440, 340, L, "day", StoryPacing.on_day, null, "world-level"],
		["day/Storyteller.on_day", "Storyteller", 1440, 345, N, "day", Storyteller.on_day, null, "households (FULL), townie lots (STATISTICAL) and zones: O(keys) daily, a few comparisons each; cards are rare"],
		["day/Vacation.on_day", "Vacation", 1440, 350, N, "", Vacation.on_day, Callable(Vacation, "busy"), "active trips only"],
		["day/systems_day event", "SystemsManager", 1440, 360, N, "day", Callable(sm, "emit_systems_day"), null, "event bus"],
		["day/autosave", "SaveLoad", 1440, 370, L, "", SaveLoad.autosave, autosave_on, "one autosave per day (when Main is not doing it)"],
	]

# ------------------------------------------------------------------ the other Clock listeners
static func director_rows(dir: Object) -> Array:
	return [["SimDirector", "SimDirector", 1, 100, C, "total", Callable(dir, "_on_minute"), null,
		"ACTIVE set every minute; NEAR every 5 min (10 when far), TOWN every 15, elapsed minutes applied; loops the tier sets, never the world"]]

static func social_rows() -> Array:
	return [
		["SocialDynamics.on_minute", "SocialDynamics", 1, 400, L, "total", SocialDynamics.on_minute, null, "mood sync for the due folk (ACTIVE every minute); contagion only inside the ACTIVE set; conversations in progress"],
		["hour/SocialDynamics.on_hour", "SocialDynamics", 60, 400, L, "hour", SocialDynamics.on_hour, null, "gathering markers and goals for the ACTIVE set"],
	]

static func scenario_rows() -> Array:
	return [["hour/ScenarioGoals.poll", "ScenarioGoals", 60, 500, N, "hour", ScenarioGoals._on_hour, Callable(Scenario, "active"), "only while a scenario is active"]]

static func app_rows(main: Object) -> Array:
	return [["day/Main.autosave", "Main", 1440, 900, L, "day", Callable(main, "_autosave_check"), null, "player autosave interval"]]

# ------------------------------------------------------------------ installers
static func install(sched: SimScheduler, group: String, rows: Array) -> void:
	for r in rows:
		var gate: Callable = r[7] if r[7] != null else Callable()
		sched.add(str(r[0]), str(r[1]), group, int(r[2]), int(r[3]), int(r[4]), r[6], str(r[5]), gate, str(r[8]))

static func install_systems(sched: SimScheduler, sm: Object) -> void:
	install(sched, systems_group(sm), systems_rows(sm))
	TownSim.install(sched, systems_group(sm))
	CrimeFlow.install_sliced(sched, systems_group(sm))
	IncidentSlices.install(sched, systems_group(sm))
	RainSlices.install(sched, systems_group(sm))
	DaySlices.install(sched, systems_group(sm))

static func install_director(sched: SimScheduler, dir: Object) -> void:
	install(sched, director_group(dir), director_rows(dir))

static func install_social(sched: SimScheduler) -> void:
	install(sched, GROUP_SOCIAL, social_rows())

static func install_scenario(sched: SimScheduler) -> void:
	install(sched, GROUP_SCENARIO, scenario_rows())

static func install_app(sched: SimScheduler, main: Object) -> void:
	install(sched, GROUP_APP, app_rows(main))
