# Performance notes

"Optimization is king" (owner). The game must keep adding systems, a bigger town and many more people and still run smoothly. This file has
the **rules every system must follow** (next section), how to run the **scale benchmark**, its **baseline** and the ranked **hotspots**; the
round-1 / round-2 history of the single-household speed-ups follows after that.

## Rules every system must follow

**Budgets** (speed 3 = 12 game minutes per second = 0.2 game minutes per 60 fps frame, mid-range PC; the benchmark converts ms per game minute x 0.2):

| What | Budget |
|---|---|
| Simulation per frame, average | under 4 ms (= under 20 ms per game minute on average) |
| Simulation, worst frame | under 12 ms (a frame that runs a game minute pays for the whole minute, including the hourly / daily jobs of that minute: hour and day work must be sliced or scheduled, never one 500 ms lump) |
| One household `Autonomy.choose` | under 3 ms |
| All town-level work (everything that is not SimDirector ticking folk: SystemsManager steps, hourly / daily jobs, social, crowd) | under 1 ms per frame average (= 5 ms per game minute) |
| Tests | fast tier under 120 s, slow tier under 600 s; only the scale benchmark uses the big town |

**Target scale**: today = 1 household + about 15 active people on 160x136 tiles, 15 lots, 12 townies. Design for = 1 household + **200+ townies** on a
map of **4x the area** (about 320x272), **50 active at once**, many multi-floor buildings, **20+ incident systems** (44 incident defs exist today).
Nothing may be O(all townies) or O(all objects) per minute, and nothing O(n^2) in the people who are present.

**Every new system must declare** (in its header comment, and in the done message):
1. **Tier behaviour** - what it does for each person tier. ACTIVE (visible / near the household): full sim, every minute. NEAR (same area, off screen): full sim at a
   coarser cadence (5 to 15 minutes, with the elapsed minutes applied). TOWN (elsewhere): a cheap schedule-driven state (where / doing what by the hour, needs as curves).
   STATISTICAL (far, or no recent contact): daily dice from the same data and rates (Story / Away / `Incidents.resolve_statistical`). Promotion rebuilds a plausible full
   state from the cheap one with the same rates. (Implemented in task 17.3: `Tiers`, `TownSim`, see the next section.)
2. **Cadence** - timed ("wake folk 12 at 07:00", "bill due day 9": a wake-up at a minute, not a poll) or periodic with a declared period (5 / 15 / 60 minutes or daily),
   spread over minutes by id (`(minute + id) % period`) so nothing runs for everybody in the same minute. Idle systems cost zero.
3. **Active set** - the list it loops over, kept by the system itself (people in the lot, objects with that state, open cases). **Never loop all folk, all townies, all
   lots or all objects** in a per-minute or per-hour hook. A daily pass over all townies is allowed only when it is O(townies) with a few comparisons per person
   (no per-person dictionary building, no pair loops) and is measured in the benchmark.
4. **Caps** - every history, ledger, log, memory list, cache and node pool has a maximum (drop oldest), and a count the benchmark or a long-run test can assert. Views are built
   only for visible things, cached by appearance and reused.

**Rule: nothing new may run per person per minute unless that person is already ACTIVE** (a folk who is in the world and being simulated). Townies and strangers who are not
in the world cost nothing per minute. Anything that only reacts to an event uses the event bus (`SysUtil.game_event` / Events); clock work is a `SimRegistry` row (next section), never a `minute_passed` connection.

**Checklist before you say "done"** (copy it into the done message with the numbers):
- [ ] Header declares tier behaviour, cadence, active set, caps.
- [ ] No loop over `World.all_folk()`, `Story.townies`, `Neighborhood.lots()` or all objects in a per-minute or per-hour hook (grep for them).
- [ ] No pair loops (folk x folk) beyond the people in one conversation / one lot; no string or dictionary building per person per minute (debug text only when shown).
- [ ] Hot paths reuse cached lookups (`_memo` style) instead of rebuilding tables; packed arrays for big per-person state where profiling shows it matters.
- [ ] Added a count the benchmark can assert (work items per minute) or a cap the long-run test checks.
- [ ] Ran `powershell -File tools/run_scale.ps1` (big town, 3 game days) and compared with the last section of `docs/PERF_SCALE_RESULTS.md`: ms/game-min total and for your system,
      folk / path-query counts, nodes, memory. **A regression over 10% needs a written reason in the done message.**
- [ ] Fast tier still passes and stays near 120 s wall: `powershell -File tools/run_fast.ps1` (6 balanced shards side by side; `tests/perf_scale_small_test.gd` is the benchmark's fast-tier twin: counts only).
- [ ] Dice over many subjects draw FIRST against an upper bound (`IncidentRisk.max_rate`) and evaluate conditions only for a draw that can hit; "who would do this" pickers weigh a sample (`CrimePerson.sample_townies`), never the whole town; a daily lump goes through `DaySlices` or a LOW row.

## The scheduler (task 17.2): how clock work is registered

**No system connects to `Clock.minute_passed` / `hour_passed` / `day_passed`** (views like the HUD may: they are not the simulation). The only Clock listener is
`SimScheduler` (`scripts/sim/sim_scheduler.gd`, one per Clock via `SimScheduler.of(clock)`); every clock hook is a row in the table `scripts/sim/sim_registry.gd`.
A Clock minute runs the minute layer, then (on the hour) the hour layer, then (at midnight) the day layer, each in `order` (ties: registration order), which keeps the
old signal order. To add a system's hook: add ONE row to `systems_rows()` (name, owner, cadence, order in steps of 10, priority, arg, Callable, optional emptiness gate, note).

- **Timed**: `sched.at(minute, owner, callable, args)` fires once at an absolute game minute, ordered by (minute, seq). Not saved: re-register from your own saved state after a load.
- **Periodic**: cadence 1 / 5 / 15 minutes, hourly (60) or daily (1440). The `active` gate (a Callable returning false when idle) makes an idle system cost one call.
- **Bucketed**: `sched.add_bucketed(name, owner, group, cadence, order, prio, fn(id, elapsed))` + `job.track(id)` / `job.untrack(id)`: each tracked id is visited once per `cadence`
  minutes at minute `id % cadence`; 200 townies at cadence 60 run 3-4 per minute, nothing tracked = zero cost. Use it for any per-person periodic work of people who are not ACTIVE.
- **Priority**: CRITICAL (household-critical) and NORMAL are never deferred; LOW is postponed to a later tick when the frame's sim work passed `budget_usec` (main.gd sets 4 ms; tests and
  probes leave 0 = unlimited so runs stay deterministic). Postponed jobs run first on the next tick (forced after `MAX_DEFER_TICKS`) and are counted in `stats()["deferred_total"]`.
  Only mark a job LOW when running one frame late changes no outcome (hourly world-level jobs, social contagion).
- **Stats**: `sched.profile = true` times every job; `sched.stats()` = jobs, ticks, deferred, per-owner and per-job calls / usec / idle skips / max bucket batch (tests/perf_probe.gd and
  tests/perf_scale.gd read it). `sched.describe()` prints the registry below (`tools/sched_describe.gd` regenerates it).
- Determinism: `SimSeed.apply(seed)` seeds every random stream; `tests/state_hash_probe.gd` plays a real game N days and prints state hashes (identical before and after the scheduler refactor).

### Scheduler registry (generated by tools/sched_describe.gd; every row's last column is its tier behaviour)

| layer | order | job | system | cadence | priority | tier behaviour / active set / caps |
|---|---|---|---|---|---|---|
| minute | 90 | Tiers | Tiers | minute | CRITICAL | all tiers: assigns ACTIVE / NEAR per person (hysteresis, ACTIVE cap); loops the world's folk once, classification cached until someone moves |
| minute | 95 | TownSim.hourly | TownSim | hour (bucketed) | LOW | TOWN: schedule + needs curves once per hour, bucketed by id; STATISTICAL: skipped (daily dice only) |
| minute | 96 | TownSim.sync | TownSim | minute | NORMAL | keeps the bucketed job's tracked ids equal to the living townies (one size test per minute) |
| minute | 100 | SimDirector | SimDirector | minute | CRITICAL | ACTIVE set every minute; NEAR every 5 min (10 when far), TOWN every 15, elapsed minutes applied; loops the tier sets, never the world |
| minute | 210 | NeighborhoodService.before | NeighborhoodService | minute | NORMAL | ACTIVE: scheduled visits waiting for a resident at home (situations list only) |
| minute | 220 | CareerShifts | CareerShifts | minute | NORMAL | ACTIVE residents with a shift today; townie shifts are the TOWN schedule (CommuteTownies windows), not polled |
| minute | 230 | Away | Away | minute | NORMAL | people currently away only (residents; townies are STATISTICAL) |
| minute | 240 | StoryVisits | StoryVisits | minute | NORMAL | visits in progress only; held guests are dropped from scheduled visits |
| minute | 250 | BabyCare | BabyCare | minute | NORMAL | ACTIVE babies / toddlers only |
| minute | 260 | AccidentMarks | AccidentMarks | minute | NORMAL | ACTIVE every minute, NEAR / TOWN folk on their turn (odds scaled to the period); company from a per-minute grouping by lot; TOWN records get hourly markers |
| minute | 270 | Incidents | Incidents | minute | NORMAL | open incidents / health records only |
| minute | 271 | Incidents.slice | Incidents | minute | NORMAL | hourly / daily dice in 60 / 96 slices of the subject lists (FULL near, STATISTICAL far); no midnight or top-of-hour lump |
| minute | 280 | CrimeFlow | CrimeFlow | minute | NORMAL | police / open cases only (ACTIVE) |
| minute | 290 | Fire | Fire | minute | NORMAL | lots with burning cells only (idle = zero) |
| minute | 300 | DisasterClock | DisasterClock | minute | NORMAL | running disasters only |
| minute | 305 | CrimeFlow.person_day | CrimeFlow | day (bucketed) | NORMAL | TOWN / STATISTICAL townies and residents: fraud + pressure dice once a day, bucketed by id (no midnight lump); also the criminal-life dice (`CrimeLifeTownie.person_day`, task 21: STATISTICAL, a handful of members, one job a month at most; guards, alarms and fences run in the daily `CrimeLifeFlow.on_day`, a few dozen records) |
| minute | 306 | CrimeFlow.sync | CrimeFlow | minute | NORMAL | keeps the bucketed job's ids equal to the living townies and residents |
| minute | 310 | Vacation | Vacation | minute | NORMAL | trips on absolute due minutes; idle = one emptiness test |
| minute | 320 | NeighborhoodService.after | NeighborhoodService | minute | NORMAL | Crowd.update loops only the lots near an anchor (Tiers.lot_distances, cached); crowd checks per lot every 10 min; NEAR / TOWN crowd on their turn, they leave / arrive without walks; far lots dropped |
| minute | 330 | WeatherFolk | WeatherFolk | minute | NORMAL | ACTIVE every minute, NEAR / TOWN folk on their turn with the exposure scaled to the period |
| minute | 215 | WeatherWorld.rain | WeatherWorld | minute | NORMAL | places only: lots near an anchor catch the owed rain on their plants, 2+ lots per minute (RainSlices); idle = zero; far lots wait for the daily catch-up |
| minute | 340 | LevelSystems | LevelSystems | minute | NORMAL | multi-floor buildings with folk (ACTIVE / NEAR) |
| minute | 400 | SocialDynamics.on_minute | SocialDynamics | minute | LOW | mood sync for the due folk (ACTIVE every minute); contagion only inside the ACTIVE set; conversations in progress |
| hour | 200 | hour/ensure_registered | SystemsManager | hour | NORMAL | residents only |
| hour | 205 | DaySlices | DaySlices | hour | NORMAL | runs 1/24 of every registered daily pass each hour (relationship decay, grudges, ...); idle = one call |
| hour | 210 | hour/WeatherWorld.on_hour | WeatherWorld | hour | LOW | garden plots always; plants: every lot only counts an owed rain hour (RainSlices waters the near ones over the next minutes, the daily catch-up the rest); weather steps are world-level |
| hour | 220 | hour/Holidays.on_hour | Holidays | hour | LOW | world-level |
| hour | 230 | hour/Goals.on_hour | Goals | hour | LOW | residents only (ACTIVE) |
| hour | 240 | hour/Story.on_hour | Story | hour | LOW | STATISTICAL townies: hourly dice |
| hour | 250 | hour/Family.on_hour | Family | hour | LOW | residents + townies in family records (small) |
| hour | 260 | hour/AccidentMarks.on_hour | AccidentMarks | hour | NORMAL | before the hourly dice: TOWN records get their markers; job markers are set around each slice when the dice are sliced |
| hour | 270 | hour/Incidents.on_hour | Incidents | hour | NORMAL | hospital + health upkeep, then starts a sliced pass of the hourly dice (Incidents.slice) |
| hour | 280 | hour/AccidentMarks.after_hour | AccidentMarks | hour | NORMAL | job markers removed again (unless sliced: done per slice) |
| hour | 290 | hour/CrimeFlow.on_hour | CrimeFlow | hour | NORMAL | places of everyone (O(people), a few lookups each) |
| hour | 300 | hour/DisasterClock.on_hour | DisasterClock | hour | NORMAL | running disasters only |
| hour | 310 | hour/Vacation.on_hour | Vacation | hour | NORMAL | active trips only |
| hour | 400 | hour/SocialDynamics.on_hour | SocialDynamics | hour | LOW | gathering markers and goals for the ACTIVE set |
| hour | 500 | hour/ScenarioGoals.poll | ScenarioGoals | hour | NORMAL | only while a scenario is active |
| day | 200 | day/ensure_registered | SystemsManager | day | NORMAL | residents only |
| day | 210 | day/Holidays.on_day | Holidays | day | NORMAL | world-level |
| day | 220 | day/Aging.on_day | Aging | day | NORMAL | residents + townies: O(people) cheap comparisons |
| day | 230 | day/Family.on_day | Family | day | NORMAL | residents + townie family records (small) |
| day | 235 | day/Succession.on_day | Succession | day | NORMAL | players whose household has nobody left (normally none) |
| day | 240 | day/Careers.on_day | Careers | day | NORMAL | residents' jobs; townie careers by daily comparison |
| day | 250 | day/WeatherWorld.on_day | WeatherWorld | day | NORMAL | garden plots + the rain catch-up of far plants (sliced over the day) |
| day | 260 | day/Economy.on_day | Economy | day | NORMAL | bills per household |
| day | 270 | day/RelationshipService.on_day | RelationshipService | day | NORMAL | known pairs, 1/24 per hour (DaySlices); ACTIVE and STATISTICAL pairs alike (data only) |
| day | 280 | day/Story.on_day | Story | day | NORMAL | STATISTICAL townies: daily dice (TOWN townies too) |
| day | 290 | day/Fire.on_day | Fire | day | NORMAL | burning / burnt lots only |
| day | 300 | day/Incidents.on_day | Incidents | day | NORMAL | Health.on_day, then starts the sliced daily dice (96 slices) |
| day | 310 | day/CrimeFlow.on_day | CrimeFlow | day | NORMAL | global passes and case upkeep; per-person dice are the bucketed daily job, grudges are sliced (DaySlices) |
| day | 320 | day/DisasterClock.on_day | DisasterClock | day | NORMAL | running disasters only |
| day | 330 | day/MarketTick.on_day | MarketTick | day | NORMAL | markets, shops, bank, rents (world-level) |
| day | 335 | day/LifeTick.on_day | LifeTick | day | NORMAL | places (staff), school and college records of residents, townie studies, the job board: all daily, O(places + townies) |
| day | 340 | day/StoryPacing.on_day | StoryPacing | day | NORMAL | world-level |
| day | 350 | day/Vacation.on_day | Vacation | day | NORMAL | active trips only |
| day | 360 | day/systems_day event | SystemsManager | day | NORMAL | event bus |
| day | 370 | day/autosave | SaveLoad | day | NORMAL | one autosave per day (when Main is not doing it) |
| day | 900 | day/Main.autosave | Main | day | NORMAL | player autosave interval |

## Level of detail: tiers for people and places (task 17.3)

**Mechanics.** `Tiers` (scripts/sim/tiers.gd, config data/tiers.json) puts every person in one of four tiers and keeps the tier SETS up to date incrementally (World.add_folk /
remove_folk hooks + a per-minute `Tiers` scheduler row at order 90, before the director). Anchors are the non-away folk of every household in the `Players` table plus the camera
focus (`Tiers.set_focus(tile)`; no anchor at all = everybody ACTIVE, which keeps tests and tiny worlds unchanged). `InterestArea` classifies a position with cheap line of sight:
same lot as an anchor = ACTIVE; both outdoors within 24 tiles = ACTIVE; from inside a building only the street within 8 tiles of it is seen; people inside another closed building are
NEAR; parks do not block; within 64 tiles = NEAR, beyond = TOWN. Promote at once, demote after 10 game minutes (hysteresis, no flapping), at most 60 ACTIVE (residents first, the
surplus is NEAR by distance with a stickiness bonus, decided before anything is assigned). The tiered population is the ambient crowd / staff (meta crowd / staff); residents,
visitors, responders and trip extras are always ACTIVE. `period_of(id)` = 1 (ACTIVE), 5 or 10 (NEAR near / far), 15 (TOWN in the world); `Tiers.due_folk(minute)` is the shared per-minute work list.

**TownSim** (scripts/systems/town_sim.gd) is the TOWN / STATISTICAL tier of townies not in the world: `where(townie, minute)` (sleep window by life stage and id, shift windows from
CommuteTownies, school, an evening outing to an open venue chosen by a per-(id, day) hash, else home), needs as closed-form curves of the clock, an hourly BUCKETED job (a townie
is visited at minute id % 60) that stores `needs / place / act / minute` in the townie record for TOWN townies (a controlled folk knows them, or their schedule puts them within 96 tiles
of an anchor); STATISTICAL townies cost nothing hourly (the daily dice of Story / Away / Incidents / CrimeFlow cover them). PROMOTION (`Crowd.spawn_npc`) builds the Folk's needs from the
curves blended with the stored ones (relaxing to the curve over 6 hours), at the lot's spawn tiles / gate (the start of the route); DEMOTION (`Crowd._remove`) writes needs and last
place back. The crowd picker weights townies whose schedule says they are at that lot and skips sleepers.

**Migrated systems** (all behave identically for the household): SimDirector loops the tier sets (ACTIVE every minute, NEAR / TOWN on their turn with the elapsed minutes applied);
Crowd.update loops only the lots near an anchor (`Tiers.lot_distances`, cached), keeps its own incremental index of crowd / staff per lot (no `all_folk()` scans), off-screen people
leave / arrive without walks (no path queries), the picker looks at a 60-townie window; AccidentMarks / WeatherFolk / SocialDynamics.on_minute use `Tiers.due_folk`; contagion runs inside
the ACTIVE set; the hourly / daily incident dice are sliced (`IncidentSlices`: 60 / 96 slices, candidate lists built once per pass, household object lists cached per pass); daily pair
passes are sliced over the day (`DaySlices`: relationship decay + social upkeep, grudges); the daily fraud / pressure / far-feud dice are the bucketed daily job `CrimeFlow.person_day`;
WeatherWorld waters plants only near an anchor (far lots count owed rain hours, caught up daily) and finds its few objects through an incremental index; `World.release_all` visits only
the objects a folk reserved; `Neighborhood.lot()` / `lot_ids()` and the per-person relationship pair index (`RelationshipService.keys_of`) replace scans.

**Rule for the entry points**: the old function (`Incidents.on_hour`, `RelationshipService.on_day`, `CrimeMurder.on_day`, `AccidentMarks.on_hour` ...) still runs everything at once (tests and
tools call it directly); the scheduler row calls the `*_sched` / `*_sliced` variant that slices. Statistical equivalence (same data, same per-subject chance per hour / day): the slow tests
incidents / accident / health / crime / crime_rates / determinism / weather / fire long runs pass unchanged.

### What every system declares (copy into the header comment and the done message)
1. **ACTIVE** (visible / near the controlled folk): what runs every minute, and for whom. Loop `Tiers.set_of(Tiers.ACTIVE)` / `Tiers.active()`, never `World.all_folk()`.
2. **NEAR** (off screen, same area): the cadence (`Tiers.period_of(id)` / `Tiers.due_folk(now)`), and how the elapsed minutes are applied (needs, exposure, odds scaled by the period).
3. **TOWN** (cheap record): what the record keeps (needs, place, act) and which job refreshes it (a bucketed hourly job, never a per-minute loop); how a PROMOTION rebuilds the full state and how a DEMOTION writes back.
4. **STATISTICAL** (far / no contact): the daily dice (same rates and data as the full version), preferably a bucketed daily job or a `DaySlices` pass.
5. **Places**: what only runs for lots near an anchor (`Tiers.lot_distances()` / `Tiers.tile_near(tile)`) and how far lots catch up (one daily pass, sliced).
6. **Cadence, active set, caps** as in the rules above, plus: no lump at the top of the hour or at midnight (slice it), nothing that scans all objects / all pairs / all townies per call.
7. The registry row's last column carries (1)-(5) in one line; the benchmark prints the tier sizes and `folk ticked per game minute`.

### Results at the big town (3 game days, same machine under load; details in docs/PERF_SCALE_RESULTS.md)

| | before (17.2, origin/main) | after (17.3) | budget |
|---|---|---|---|
| ms per game minute (total) | 43.4 | **22.1** | 20 |
| per frame at speed 3 (avg) | 8.7 ms | **4.4 ms** | 4 |
| worst game minute | 6485 ms (CrimeFlow.on_day 5.4 s) | **475 ms** (a rare crime event / midnight Careers + Story) | 12 |
| p99 / median minute | 528 / 19.3 ms | 103 / 15.1 ms | |
| town-level work (non-director) per frame | 6.9 ms | **3.1 ms** | 1 |
| folk ticked per game minute (needs / buffs / mood) | 61.4 | **13.9** | |
| tier sizes avg ACTIVE / NEAR / TOWN / STATISTICAL | n/a | 8 / 32 / 75 / 82 (ACTIVE max 41, cap 60) | ACTIVE <= 60 |
| folk in the world avg / max | 61 / 192 | 40 / 133 | |
| Incidents hourly (ms/min) | 9.5 (Incidents.on_hour) | 3.9 (Incidents.slice, incl. rare crime-event spikes) | |
| SocialDynamics.on_minute / contagion | 8.1 / 7.1 | 1.4 / 0.4 | |
| Crowd.update (NeighborhoodService.after) | 6.8 (7.0) | 2.8 (3.0) | |
| AccidentMarks (scan) | 3.4 (2.7) | 2.6 (2.0) | |
| SimDirector | 8.8 | 6.4 | |
| day jobs (CrimeFlow.on_day etc.) | 2.7 | ~1.3 (sliced) | |
| nodes (sim only) / static memory | 6 / 172 MB | 6 / 161 MB | bounded |

`today` (the game's own town): 6.8 -> 5.4-6.9 ms/min (machine load varies 30%), worst minute 113 -> 86 ms; `mini` (fast-tier town): 5.4-7.9. Not yet at budget at the big town: the household
`choose` (17.4), the remaining director cost of the ACTIVE / NEAR folk (about 14 folk ticked per minute at 0.4 ms), the Incidents slices that roll the ~200 subjects x 15 defs, midnight
(Careers.on_day, Story.on_day, CaseInvestigation) and the rare crime events (single hits of 300-500 ms) still exceed the 12 ms worst-frame budget.

### Remaining work (not done in 17.3)
- Fire / smoke / rooms are still world-level (they only cost where something burns); `WorldRooms` flood fills are not lazy per lot yet.
- Other per-object logic (spoilage, broken / dirty ticks) does not loop all objects today, so it has no place-tier gating yet; weather plants are the first place-tier system.
- The remaining midnight jobs (Careers, Story, Economy, MarketTick, CaseInvestigation) and the crime event handlers (burglary, street robbery, vandalism: 0.3-0.5 s per hit) need slicing / cheaper candidate search.
- (Done in 17.4) The camera focus: `CameraFocus` (scripts/sim/camera_focus.gd) makes where a camera looks a Tiers anchor, see "Round 4" below.
- Vacation extras (trip zone) are ACTIVE by rule; TownSim does not drive commute paths (CommuteTownies windows are its schedule).

### Round 3 (2026-10-19, after 17.3): cheaper dice, pickers, rain and midnight

Big town, 3 game days. Before = 17.3 on a quiet machine; after = this round with two long saga probes running alongside (so the rows matter more than
the absolutes; the dated section in `docs/PERF_SCALE_RESULTS.md` has the full tables):

| | before (17.3) | after | budget |
|---|---|---|---|
| ms per game minute | 23.4 | 17.6 | 20 |
| per frame at speed 3 (avg) | 4.69 ms | 3.51 ms | 4 |
| worst game minute | 465 ms (a vandalism / burglary handler inside an Incidents slice) | 263 ms | 12 |
| town-level work per frame | 3.29 ms | 2.44 ms | 1 |
| Incidents.slice (all the hourly dice) | 4.14 | 2.17 | |
| CareerShifts | 0.39 | 0.21 | |
| crowd/lot pick | 1.11 | 0.90 | |
| the midnight minute | 281 ms (Story, Careers, Economy, CrimeFlow, StoryPacing, MarketTick in one frame) | 110 ms; the LOW jobs run in the next minutes | |

What changed (the rules in the checklist above came out of it):
1. **Dice draw first** (`IncidentChecks._roll`): one draw per rolled subject against `IncidentRisk.max_rate(def)` (every risk entry at once, no prevent entry,
   the Surprises level, the empty-house factor at its maximum; cached per def). Only a draw under that bound evaluates the risk and prevent conditions,
   which were most of the cost of ~25 defs x ~200 subjects per hour. The odds are identical (the event happens exactly when the draw is under the real
   chance); the random stream is not (a prevented subject used to draw nothing), so the cross-platform hash baseline was regenerated.
2. **Offender pickers sample the town** (`CrimePerson.sample_townies`, 48 of the townies in id order from a random start): `CrimePetty._offender` and
   `CrimeBurglary.pick_burglar` weighed all 200 townies with `CrimePressure.risk` each, 15-20 ms per pick on a stub town and 300-500 ms inside a slice
   on the big one (the worst minutes of 17.3).
3. **Midnight**: the heavy day rows (Careers, WeatherWorld.on_day, Economy, RelationshipService, Story, CrimeFlow, MarketTick, StoryPacing, autosave) are
   LOW priority, so the frame budget (`SimScheduler.budget_usec`, 4 ms in main.gd and now in `perf_scale.gd` too, one game minute per frame there) moves
   them to the following minutes instead of one frame; `CaseInvestigation.on_day` (suspect scoring per open case, 100-200 ms) is a `DaySlices` pass.
   Daily jobs can now land up to 12 game minutes after midnight when every frame is over budget (a probe stepping an hour per frame sees the mood
   journal at 00:12); at speed 3 they trickle over the first minutes of the day.
4. **CareerShifts** loops the people with a job or a school place (`Careers.jobs` / `Careers.school`), not every folk in the world.
5. **Crowd picks** build `Story.free_townies()` and the residents once per `Crowd.update`, not once per pick.
6. **Accident scan**: the water objects (tubs, pools, ponds: hundreds in the big town) are bucketed by 16x16 chunk; a person checks the 3x3 chunks
   around them instead of every water object on the map.
7. **Rain**: `WeatherWorld._hourly_objects` groups the rain index by lot once; a rainy hour waters the plants of the lots near an anchor and counts one
   deferred hour per far lot, instead of visiting every plant on the map to find out that it is far (150-200 ms per rainy hour before).

Not done (17.4 below took choose and the spikes): the town-level budget (1 ms per frame; still about 2.4); the NEAR / TOWN ticks of the
director (about 0.3 ms per tick, 11-14 ticks a minute) and `accident/scan` (about 120 us per person) are the next per-minute items.

### Round 4 (task 17.4): worst minute, camera focus, household `choose`

Big town, 3 game days, same machine under load (other agents' Godot runs alongside; compare the counts and the spikes, not the absolutes). "before" is this branch before 17.4
(origin/main b5f2fbb: 19.8 ms/min, worst minute 310 ms); "before, rebased" is the same code after rebasing onto the household-chaos incidents (task 07), which added four hourly dice
whose `chaos` condition scanned every object of the town per roll; "after" is 17.4.

| | before | before, rebased | after | budget |
|---|---|---|---|---|
| worst game minute | 310 ms (rain: `weather/objects` 220 ms in each of the first rainy hours) | 200 ms (chaos dice at :01) | **152 ms** | 12 |
| the rain minute (every rainy hour) | 220-390 ms | | 39 ms peak (`systems/WeatherWorld.rain`) | |
| crime event hit (burglary / robbery / vandalism, one pick of a burglar) | 22 ms quiet machine (130-480 ms in a loaded slice) | | 8 ms (about 60 ms loaded) | |
| `CaseEvidence.suspects` (daily, per open case) | about 25 ms | | 9 ms | |
| `Story.on_day` / `Careers.on_day` (midnight, LOW) | 34-56 ms / 43-72 ms | | 8-14 ms / 27 ms | |
| household `choose` (benchmark) | 6.8 ms | | 6.8 ms (fresh state: 9.3 -> 9.0 with 230 candidates; 5-8% with a populated variety table) | 3 |
| ms per game minute / frame avg at speed 3 | 19.8 / 3.96 ms | 22.7 / 4.53 ms | 21.6 / 4.32 ms (the town has grown by 4 incident defs and 50 more folk in the world) | 20 / 4 |

What changed:
1. **Rain**: a state write drops the lot's room partition (decor depends on state), and `is_outdoor` per plant rebuilt it, so a park with 30 plants cost 90 ms and the first plant test of
   every lot paid a room build, every rainy hour. Now `_hourly_objects` only counts one owed hour per lot (`Weather._rain_deferred`, saved), `RainSlices` (a minute row, gated by "something is owed")
   waters the lots near an anchor 2+ per minute (outdoor tests first, then the writes: `WeatherWorld.water_lot`), and the daily catch-up works per lot, not per plant. Without a scheduler
   (tests) the near lots are watered at once as before.
2. **Crime hits**: `conscience` called `close_alive` which asked the pair table once per rank (5 x `bit_for` per pair); `RelationshipBits.others_by_bits` does one pass. 48 candidate burglars per pick:
   18 ms -> 6 ms. `CaseEvidence.suspects` counts company at a place and gossip about a person once per case instead of once per suspect (O(n^2) -> O(n)); same scores (`case_evidence_scan_test`).
3. **Midnight**: `Story._life_events` tests the cheap `partner` flag before the townie lookups (same pairs, same order, same dice); `ContentRules.on_day` skips object kinds without a daily rule.
4. **Chaos dice**: `Economy.objects_of` ran `refresh_objects` (two scans of every object of the town) on every call; the books now refresh only when `World._next_id` / object count change, and
   `IncidentSubject.household_objects` caches the household's objects for one incident slice (the chaos conditions asked for them 3-4 times per roll).
5. **Camera focus**: see below. 6. **choose**: `StoryPacing.interaction_mult`, `SkillInterest.mult` (per-decision memo in the profile cache), `AutonomyVariety.exempt` (memo by definition) and the
   profile key per object kind are computed once instead of once per interaction / candidate.

**Camera focus (the player sees what they look at).** `CameraFocus.look(source, tile)` sets an extra Tiers anchor where a camera looks: "cam" is the local camera (`LotView._apply_camera`; the
spectate camera of `CoopWaiting` also calls it when following a folk so the place is simulated before the camera glide arrives), `p<id>` is a remote co-op player's camera: the client sends
`CoopProto.CAMERA` (tile, at most every 2 s, only when the focus moved), the host keeps one source per connected player and drops it when they leave (protocol version 3). The focus moves only after
6+ tiles of camera travel, so panning does not reclassify the town. Only the local "cam" focus is saved. A far lot someone watches is therefore ACTIVE / NEAR (full sim), not TOWN / STATISTICAL.

Not done: `choose` is still ~6-9 ms (gather ~1/3: `_closed_reason` per interaction, pass 1 ~1/3: one `_profile` per distinct (interaction, object kind), path queries ~1/6); getting to 3 ms needs a
cross-decision cache of the need-independent part of the profiles or a candidate index per lot. `Economy.objects_of` still walks every object once per call (5 ms in the big town): an owner index
needs `Economy.owner` writes (aging, apartments, wills, burglary) to go through one setter. The remaining spikes (110-150 ms): `Crowd.update` spawn waves around 12:00, the sliced incident dice, `SocialDynamics.on_hour`.

## Scale benchmark

- `tests/perf_town.gd` - generates the town through the real game paths (`Neighborhood.start_game` -> `MapLots.build` -> `MapBuilder`, `LotLoader.place`, `Story.generate_townies`).
  Profiles: `today` (the unchanged game town: 160x136, 15 lots, 3 household folk + 12 townies), `mini` (160x106, 11 lots, 24 townies, 1 tower; fast tier), `big` (**320x272 = 4.0x the area**,
  63 lots: 9 offices, 4 apartment blocks, hospital / police / courthouse (all multi-floor templates), 3 `level_kit.add_tower` towers (6 storeys, lift + stairs), 7 cafes, 4 markets,
  3 gyms / libraries / schools, 3 parks, 20 townie homes; 200 townies; 44 incident defs; 8.7k objects, 23 buildings). The default game map is untouched: the generated layout and
  lot table are swapped in memory for the length of a run (`PerfTown.install` / `restore`; one tiny hook, `MapBuilder.size_override`, never set by the game).
- `tests/perf_scale.gd` (SLOW, its own runner) - plays N game days minute by minute (60 minutes of warm-up first), wraps every Clock listener, SystemsManager step (`prof`), SimDirector phase
  (`prof`) and PerfProf label (SystemsManager now also times each `_on_hour` / `_on_day` step under `hour/...`, `day/...` PerfProf labels; free when profiling is off). Reports ms/game-min by
  system, per-frame equivalents at speed 3, the worst minutes with what they spent it on, folk in the world, path queries per fill and per choose, candidates per choose, nodes, memory.
  Prints OVER BUDGET lines; FAILS on the load-independent limits (path queries per choose / fill, candidates, active-set cap, node and memory growth) and on wall-clock ceilings
  (the larger of 4x the budget and about 3x the baseline per profile, `CEIL` in the file: tighten them as steps land, never loosen). Appends a dated section to `docs/PERF_SCALE_RESULTS.md`.
  `powershell -File tools/run_scale.ps1 [-Profile big|today|mini] [-Days 3] [-NoWrite]` (about 3 minutes for the big town on a loaded machine; guard 900 s).
  Because the baseline is over budget, the benchmark passes today with OVER BUDGET lines; it fails on regressions of the counts and on the ceilings.
- `tests/perf_scale_small_test.gd` (fast tier, 4 s) - the `mini` generated town for 2-4 game hours: the generator still works and the counts stay bounded (no wall clock, no results file).
- `tests/perf_scale_view.gd` - the same town through `main.tscn` (LotView, FolkView rigs, HUD) at speed-3 pace (1 game minute per 5 frames), frame by frame: wall ms per frame net of the
  empty-frame floor, node / orphan / object counts, memory. Headless (no GPU, no draw calls). `powershell -File tools/godot_guard.ps1 -Seconds 600 -Args "--headless","--path",".","--script","res://tests/perf_scale_view.gd","--","big","1"`.

### Baseline (2026-10-18, before 17.2+; machine loaded by 9-11 other Godot runs, so compare ratios and counts, not absolutes)

Simulation only (headless, no views), 3 game days, ms per game minute (x 0.2 = ms per frame at speed 3):

| | today (15 lots, 12 townies) | big (63 lots, 200 townies, 4x area) | budget |
|---|---|---|---|
| ms / game minute (total) | 6.8 | **38.1** | 20 (4 ms/frame) |
| per frame average at speed 3 | 1.36 ms | **7.6 ms** | 4 |
| median / p99 / worst minute | 4.0 / 44 / 204 ms | 18 / 478 / **6576 ms** | worst under 12 |
| town-level work (non-director) per frame | 0.73 ms | **6.0 ms** | 1 |
| household `choose` (best round) | 5.3 ms | 6-11 ms | 3 |
| folk in the world average / max (crowd + staff) | 10.9 / 18 (8.2 / 15) | 46.8 / 149 (44.9 / 146) | ~50 active |
| path queries per game minute / per fill | 1.14 / 0.10 | 0.66 / 0.01 | per choose under 25 |
| candidates gathered per choose (household / NPC max) | 219 / 453 | 175 / 1994 | not bounded yet |
| Clock listeners: SystemsManager minute / hour / day | 2.2 / 0.84 / 0.09 | **10.5 / 9.5 / 3.1** | |
| SimDirector (folk ticking) | 3.1 | 8.1 | |
| SocialDynamics minute | 0.48 | **6.2** | |
| nodes (sim only: folk are not nodes) | 6 | 6 | |
| static memory, day 1 -> day 3 | 107 -> 108 MB | 142 -> 161 MB | bounded |

With the views (`perf_scale_view.gd`, 1 game day, speed-3 pace, wall ms per frame minus the 6.9 ms empty-frame floor): **today 10.0 ms/frame net**, **big 19.8 ms/frame net** (p99 115 ms,
worst 2.6 s on the day change), nodes 9.4k (today) / **18.3k** (big), orphan nodes 1.6k / **6.0k**, Objects 19k / 39k, static memory 174 / 232 MB. So the views are the largest
per-frame cost at both scales (about 8.5 ms of today's 10 is views, 12 of the big town's 20), and orphaned nodes are being created and not freed.

### Top 10 hotspots at the big scale, ranked (ms per game minute in the big town; the same item today in brackets)

| # | Hotspot | ms/game-min | Why it does not scale |
|---|---|---|---|
| 1 | **Views / rigs** (outside the sim table) | ~12 ms per frame net, on top of the sim | 18k nodes, 6k orphans, rigs rebuilt as folk appear; no culling / LOD / pooling (task 17 section 5) |
| 2 | `Incidents.on_hour` (Hospital, Health, `IncidentChecks.run("hour")`) | **8.3** (0.56) = 500 ms per hour, up to 900 ms | hourly dice for 44 defs x every folk / townie / lot; 15x the cost for 16x the people and lots |
| 3 | `SocialDynamics.on_minute` (`social/contagion` 5.2 [0.19], sync+record 0.6, conversation 0.36) | **6.2** (0.48) | `contagion` is about quadratic in the people present: 28x for 4x the folk |
| 4 | `Crowd.update` (`crowd/lots` 3.6 [0.37], `step_leavers` 2.2 [0.23], `drive` 0.7) | **6.4** (0.73) | every minute: all 63 lots x residents (`NeighborhoodLots.distance_to`), `crowd_folk()` re-scans `World.all_folk()`, the leaver pass scans all folk |
| 5 | Strangers in SimDirector (`other emergency+interaction tick` 3.0, `fill` 1.5, `needs` 1.4) | **5.8** (0.9) | ~44 crowd NPCs ticked every minute with full autonomy; no NEAR / TOWN cadence |
| 6 | Day change: `CrimeFlow.on_day` 2.4 (1.7-5.5 s in one frame), `Incidents.on_day` 0.46, `RelationshipService.on_day` 0.1 | **3.1** avg, the **6.6 s worst frame** | all-townie daily passes (pairs of townies for crimes / relationships) in a single frame |
| 7 | `AccidentMarks.on_minute` (`accident/scan` 2.1, `rescue` 0.6) | **2.7** (0.69) | scans every folk against every hazard each minute, crowd NPCs included |
| 8 | Household autonomy: `director/household fill` 1.24 + needs 0.53 + tick 0.24; `choose` 6-11 ms | **2.0** | `Autonomy.gather` returns up to 2000 rows (no spatial index) |
| 9 | `WeatherWorld.on_hour` 0.96 (spikes of 480 ms at 09:00-11:00) + `WeatherFolk.on_minute` 0.64 | **1.6** | walks all objects / lots on weather changes; per-folk exposure every minute |
| 10 | `SocialDynamics.on_hour` 0.76 + `Incidents` minute step 0.35 + `CareerShifts` 0.34 + `Away` / `StoryVisits` | **1.5** | per-minute polls that should be timed wake-ups (shifts, visits) |

Suggested owners: 17.2 (scheduler) takes #2, #6, #10; 17.3 (LOD tiers) #3-#5, #7, #9; 17.4 (cheap decisions) #8; 17.5 (nodes) #1.

### What blocks the target scale (found while building the big town)

- **Fixed story-to-lot link**: `Story.add_townie` gives every townie `lot = randi(1..6)` and `Neighborhood.residents_of` maps that onto the townie homes, so only 6 homes would ever have
  residents on a bigger map. The generator re-spreads the numbers over all townie homes; the real fix is an explicit `home_lot` per townie.
- **One workplace per career**: `data/careers.json` `workplace` is a single lot id, so every townie of a career commutes to the first office / cafe / gym; extra venues only get customers.
  Needs a per-townie workplace (nearest / assigned lot of that type). Hospital / police / courthouse are also one lot each (the generated town has one of each).
- **Lot registry is a list**: `Neighborhood.lot(id)` / `Venues.type_of_lot` scan the lot array (63 entries, called per folk per minute); `Neighborhood.lot_ids()` rebuilds an array on each call.
- **No global active-set cap**: `Crowd` is bounded per lot (`crowd_cap` 6) but not overall; the generated town reaches 149 folk in the world (146 crowd + staff) at opening times vs 47 on average.
- **One green and one `south_strip`** in `data/map_layout.json`; the generated layout reuses them (works, but a big town wants several parks).
- **Nothing counts nodes expanded**: only `Autonomy.path_queries` exists (no counter in `WorldPaths` / `NavField`); candidates per choose are measured by sampling `Autonomy.gather` at the end of the run.
- **The sim creates no nodes** (Folk are RefCounted), so the headless node count is a constant 6; node growth shows only in `perf_scale_view.gd`.
- The view run uses the headless dummy renderer: draw calls, GPU time and particles are not measured (needs a windowed run, see `tests/perf_shot.gd`).

---

## History: single-household speed-ups (round 1 and 2)

## Tools

- `tests/perf_probe.gd` - boots the real game (`main.start_new_game`), advances N game days minute by minute and times every Clock listener
  (minute / hour / day), SimDirector's phases (`director/...`) and each `SystemsManager._on_minute` step (`systems/...`):
  `powershell -File tools/godot_guard.ps1 -Seconds 300 -Args "--headless","--path",".","--script","res://tests/perf_probe.gd","--","2"`.
  Rows under 20 ms are hidden. The numbers include other processes on the machine: compare runs, not absolutes.
- `tests/perf_autonomy_test.gd` (fast tier) - load independent: fails if `Autonomy.choose` makes more than 12 real path queries per call
  (about 7 now; ~19 after round 1; one per candidate, ~100, before). The wall-clock check only fails at 8 ms x 3 = 24 ms (best of 5 rounds
  of 12 calls) and the measured numbers are printed: about 6 ms with ~9 other Godot runs going (round 1: 9-10 ms loaded, 26-40 ms before).
  All other timing assertions in the tests (`nav_perf`, `level_perf`, `level_route`, `nav_graph`, `world_big`, `world_regions`) are multiplied by
  `TestFixture.SLACK` (5): they catch a 10x regression, never a busy machine.
- `PerfProf` (`scripts/systems/perf_prof.gd`) - opt-in micro profiler used by `tests/perf_probe.gd` (rows indented under their hook: `accident/scan`,
  `after/Crowd.update`, `crowd/lots`, `social/sync+record` ...). `PerfProf.start()` / `PerfProf.stop(label, t0)` cost one boolean test when off.
- `tests/run_all.gd`: `--only=a+b` (use `+` through the guard, which splits its arguments on commas); any `*_longrun_test.gd` is slow by name.
- `--import` is not the slow part: about 12 s once after a `class_name` change, never inside a test run. If the class cache is stale (another agent
  added a `class_name`), run `Godot --headless --path . --import` directly under a `timeout`, not through the guard: the import itself prints the
  parse errors that make the guard kill it, so the cache never gets updated.
- `tools/godot_guard.ps1` - run Godot headless through it, always. It redirects output to a log, polls it, kills Godot at once on
  `SCRIPT ERROR`, `Parse Error` or `Failed to load script`, or after `-Seconds` without new output, prints the tail and exits non-zero
  (3 = killed, else Godot's exit code). Usage:
  `powershell -File tools/godot_guard.ps1 -Seconds 120 -Args "--headless","--path",".","--script","res://tests/run_one.gd","--","nav_perf_test"`
  (`-Args` can also be one comma-separated string; `-Tail N` lines to print, `-Log path`, `-Godot exe`; `-Seconds` is the time WITHOUT new output, not a total limit).
  The last line now also shows `cpu N s, wall M s` (CPU time of the real Godot process, sampled every 3 s): wall time moves with the other agents' runs, CPU time hardly does. Suggested `-Seconds`: 120 single
  test, 300 fast tier, 600 slow tier / cold import. A parse error in a file another agent is editing kills the run: retry in a minute.

## What was slow (2 game days, real game, 3 folk + crowd; machine loaded, so only the ratios matter)

| Listener | Before | After |
|---|---|---|
| whole run | 63 s | 36 s |
| SimDirector household autonomy (`_fill`) | 25.3 s | 10.5 s |
| SimDirector other folk needs/buffs/mood | 5.8 s | 0.8 s |
| SimDirector household needs/buffs/mood | 3.3 s | 2.2 s |
| SystemsManager `_on_minute` | 20.2 s | 13.5 s |
| - AccidentMarks | 13.2 s | 6.1 s |
| - NeighborhoodService.after (Crowd, lots, meetings) | 4.3 s | 4.5 s |
| - WeatherFolk | 1.4 s | 1.6 s |
| - Incidents (Health, pending) | 0.9 s | 0.9 s |
| SocialDynamics `on_minute` | 2.2 s | 2.4 s |
| `_on_hour` | 2.0 s | 2.2 s |

`play_smoke` 3 days headless: 46.8 s on the loaded machine after the changes (target 30 s; not reached here, see "Not done").

## Real causes and fixes

1. **`WorldIface.path_length` called `World.find_path` and took the length of the tile list.** So every autonomy candidate ran an
   uncached A* (P3's caches and distance fields in `WorldNav.path_length` were never used by autonomy). It now calls
   `World.path_length` (LRU per pair, invalidated by `nav.touch_tile / touch_edge` on wall / object changes, distance field after 3
   questions from one tile, unreachable targets fail fast). Only the test stub (no `path_length`) falls back to a path.
2. **Distance-free ranking first** (`Autonomy.choose`): every candidate gets an upper-bound score (`_bound_row`: profile score with the
   straight-line Chebyshev distance, no interaction tests, no path) - then real `evaluate` (tests + `path_length`) runs best-bound-first
   until the next bound cannot beat the 8th real score. The result is exactly what scoring everything gives (steps >= Chebyshev, memory
   bias is applied identically); about 19 path queries instead of ~100. Rows never examined stay in `last_debug` with
   `estimated = true` and their bound as score.
3. **Per-decision constants**: interactions offered per object kind cached (`_offered_by`, validated against the data table and the
   object's own list), actor-only tests of an interaction filtered once, trait refusals / trait multipliers / likes memoised per
   (trait set, interaction, object kind) (`_memo_for`), static tags / advertised needs memoised, active routines and buff multipliers
   computed once per decision (`Routine.active_routines`), debug need breakdown only built for the 8 detailed candidates,
   `Folk.trait_defs()` memoised, `Folk.memory_bias_map()` (one pass), `objects_near` radius 200 -> `NEAR_RADIUS` 40 (a lot is 32x24).
   Verified: on the big map `objects_near` / `folk_near` are lot-scoped for lot folk and 12-tile scoped (`STREET_REACH`) for street folk.
4. **Strangers** (household_id <= 0 with meta `visitor`: crowd NPCs, townies, visitors): needs / buffs / thresholds / mood are applied
   every `SimDirector.STRANGER_PERIOD` = 5 minutes with the elapsed minutes (decay is linear; staggered by folk id). Interactions,
   emergencies and autonomy still tick every minute; household members are untouched.
5. **`Folk.tick_needs`** looked every buff up once per need (70 lookups per folk-minute); the decay tables are fetched once per tick now.
6. **`AccidentMarks.on_minute`**: the "near water" check scanned the whole lot per folk per minute; the water objects are listed once per
   minute and the lot lookup only runs when one is within range (same result). Company counted twice per folk; once now.
7. **`Health.on_minute`**: folk without a health record that are not residents are skipped (they had an empty record created for them
   and 4 no-op ticks per minute); injury / illness ticks only run for people with a record. Rates and semantics untouched.

## Hooks in SystemsManager._on_minute (per minute, 2 days, loaded machine)

AccidentMarks 6.1 s, NeighborhoodService.after 4.5 s, WeatherFolk 1.6 s, Incidents 0.9 s, CareerShifts 0.2 s, StoryVisits / BabyCare /
NeighborhoodService.before / Away / Fire / DisasterClock each under 0.05 s. **Nothing was moved to hourly**: the heavy ones are exposure
markers (the acc_* buffs live 10-45 min and the road marker is a per-minute dice, so batching changes the odds) and the neighbourhood /
crowd upkeep; the incident, health, accident, fire and disaster tests exercise those every minute. The cost was in the implementation
(see 6, 7), not in the frequency.

## Round 1 leftovers (superseded by round 2 below)

The items of the old "Not done" list are all addressed in round 2 except where stated there.

## Round 2

- Fast tier: 225 s for 101 files (was 256 s with the same load before the last changes); the slowest files are hood_travel (12 s),
  incidents_core (10 s), content_run (10 s), commute (9 s), townie_needs (20 s -> still the biggest in the slow list, 42 s there).
  Per-file times are dominated by game minutes simulated (about 12 ms per minute with the crowd), so they shrink with the sim speed-ups above.
- Slow tier: 114 files, all passing, 1314 s here. Slowest: crime_longrun 194 s, fire_longrun 169 s, health_longrun 153 s, incidents_longrun 102 s,
  accident_longrun 82 s, systems_family_integration 79 s, weather_longrun 67 s, systems_integration 57 s, hood_sim 48 s, townie_needs 42 s,
  disaster_longrun 36 s, commute_longrun 23 s. Getting under 600 s needs these long runs shortened by their owners (`TestFixture.pick(full, quick)`
  for the loops, fewer simulated days); that was not done here because the files belong to the parallel crime / fire / health / disaster tracks.

## System cadence table: economy track (task 13; details in docs/ECONOMY.md)

All new systems are daily or weekly and event driven; nothing runs per minute. Off until `MarketEconomy.start()`.

| System | Tier | Cadence | Active set | Caps |
|---|---|---|---|---|
| MarketEconomy (prosperity, indexes, unemployment) | town | daily | ~12 townies | history 12 |
| ShopStock (shelves, deals, orders) | town | daily + on command | ~9 shops x <= 6 items | orders 40 |
| MarketWork (teen job, gigs, crafts, layoffs, benefit) | household | daily + events | the household's folk | gigs 2/day each |
| HousingProps / HousingRent | town | daily / weekly | <= ~12 properties | 5 listings |
| BusinessSim / BusinessDay (player and townie) | town | daily | open businesses (<= 10 slots) | reviews 8, townie businesses 5 |
| BankAccounts (interest, loan payments) | town | daily / weekly | households with savings or loans | 2 loans each |
| BankGamble (lottery, urges) | town | daily, draw weekly | ticket holders, people with addiction | addiction 0..100 |
| BankInsurance / BankWill | event | on payout / death | none | |
Machine: Windows, 16 logical cores, 8-9 other Godot runs from the other agents going all the time, so "quiet machine" numbers could not be
measured; every figure below is from the loaded machine (wall time was within 2-5% of CPU time in the test runs). Other agents' edits land
continuously (multi-floor, circadian, crime, buildings), which also changed what the same test costs; the tables say which is which.

## System cadence table: life areas (task 14; details in docs/LIFE.md)

Daily or event driven; nothing runs per minute. The one clock entry is `day/LifeTick.on_day`.

| System | Tier | Cadence | Active set | Caps |
|---|---|---|---|---|
| PlaceStaff (rosters, turnover, closures) | town | daily | ~8 places x a handful of names | one closure line per place per day |
| PlaceUse / PlaceMember (services, passes) | event | on a command / the visit's end | the person acting | one pending visit per person |
| EduSchool (homework, report cards, events, preschool) | household | daily + events | school-age residents (ACTIVE) | 8 report cards each |
| EduCollege / EduCourses | event | on a visit | the student | one lecture a day |
| EduTownies | town (statistical) | daily | alive adult townies | 2 degrees each |
| EduJobs (job board) | town | weekly refresh | one dice per career | 3 openings per career |
| HealthLifeDay / HealthCond (meters, conditions) | residents ACTIVE, townies STATISTICAL | daily | all residents + alive townies | 4 conditions |
| HealthRisk (incident multipliers) | event | inside the incident dice | tagged incidents only | |
| TownNews / PhoneState / SocialFeed / PhoneDay | event; invitations and townie posts daily | residents from teen up; alive townies | | news 150, inbox 6, feed 30 |
| EventServices / EventState | event | on a booking | host + ~10 guests | |
| PetState / PetDay | household, daily; strays weekly | households with pets | | 3 pets a home, 3 strays |
| LeagueState / ClubState / LifeFame | town, weekly / event | 4 teams, 3 clubs, people with fame | | 8 results |

### Runtime (`tests/perf_probe.gd`, 2 game days, 3 folk + crowd, loaded)

| Part | Round 1 end | Now |
|---|---|---|
| whole run | 32.0 s | 22.4 s |
| `play_smoke` 3 days headless | 46.8 s | 31.4 s (with a slow-tier run going in parallel) |
| `Autonomy.choose`, household folk | 9-10 ms | 6.0 ms (best round; 7.3 path queries) |
| SimDirector household fill (autonomy) | 9.6 s | 3.7 s |
| SystemsManager `_on_minute` | 11.7 s | 8.5 s |
| - AccidentMarks | 5.2 s (scan 4.9 s) | 2.2 s (scan 1.7 s) |
| - NeighborhoodService.after | 3.9 s | 3.9 s (Crowd.update 3.1-3.6 s: see 9.) |
| - WeatherFolk | 1.4 s | 0.94 s |
| - Incidents | 0.8 s | 0.75 s |
| SocialDynamics `on_minute` | 2.1 s (sync+record 1.3 s) | 1.5 s (sync+record 0.76 s) |
| SimDirector other emergency+interaction | 1.26 s | 1.0 s |

Where `Autonomy.choose` stands (ms per call, loaded, `PerfProf`): gather 2.4 (object pass 0.9, objects_near 0.35, folk/self pass 1.1),
bound rows 2.8 (of which building the ~80 (interaction, object kind) profiles about 2.2), real evaluation 0.7, detail+pick 0.2, debug record 0.1.
5 ms was not reached on this loaded machine; the earlier "7 ms quiet / 9-10 loaded" ratio suggests about 4.5-5 ms quiet, which I could not verify.

What changed (all behaviour-equivalent; the result of `choose` is the same, only the work differs):

1. `choose` stops at the best TOP_N (3) real scores instead of DETAIL_N (8) (the pick only depends on the top 3); the 8-row debug report is built
   only when `Autonomy.full_debug` is true (set by `TestFixture.reset`, so tests still see a row for every candidate; the game keeps closed rows,
   examined rows and the best ones). Path queries per choose 19 -> 7. Never-examined rows are no longer built in the game (150 dicts per decision).
2. Bound pass is one inline loop on cached per-group constants (`c0` = everything but distance and memory bias), memory bias parsed once into
   per-kind maps; profile keys come from `gather` (`pk`), the per-trait memo and the data validation are looked up once per decision.
3. `gather`: the folk / self interaction list is memoised (validated against the table), a folk whose traits refuse nothing skips the refusal
   lookups, the target-independent tests are decided once per interaction (not per (interaction, kind)), `mood_is` computes the mood once per
   decision (`Cond` opt-in key `#mood`), closed rows are shared read-only objects.
4. `Cond` called `push_warning` (about 2 ms each) on EVERY evaluation of an unknown condition key. Now once per key. NOTE for the crime owner:
   the interaction `organize_watch` (data/incidents/04_crime.json) uses `age_stage_is` in `tests`, which plain `Cond` does not know (only `SysCond`),
   so it is always false and the interaction can never run. I kept that behaviour (not a perf question) but it is probably a bug.
5. `Routine.evaluate`: the per-routine "once" log key is only formatted when the log is not empty.
6. Strangers (household <= 0 and meta `visitor`): `AccidentMarks` scans them once per 5 minutes (staggered by id; the road dice become
   1-(1-p)^5 so the chance over the period is the same; the markers last 10-45 min), `WeatherFolk` does their exposure once per 5 minutes with
   5 minutes of exposure / needs, `SocialDynamics` syncs their mood effects once per 5 minutes (their mood only changes when SimDirector ticks
   them every 5 minutes anyway), SimDirector checks their emergencies when their needs change (every 5 minutes). Households and all residents:
   untouched.
7. `AccidentMarks`: the list of water objects was rebuilt from ALL world objects every minute (the biggest single cost in the scan); now cached,
   invalidated by object count + the world's next id (and `AccidentMarks.reset_cache()` from `SystemsManager.reset_all`).
8. `WorldRegions.by_lot` was a linear scan over all regions on every call (used by `rect_of`, `entry_tile`, `distance_to`...): indexed.
   `Crowd.update` lists the visible residents once instead of once per lot; `NeighborhoodService._closing` groups the residents by lot once.
9. Not done: `Crowd.update` (1.2 ms/min) is mostly the real 10-minute upkeep of the ~8 lots near the player (staff, townie picking, `Folk.create`
   for arrivals); `SystemsManager._on_hour` (35-60 ms) and `Incidents.on_hour` (21 ms) are not minute costs. Household needs/buffs/mood
   (0.2 ms per folk-minute, `Mood.compute`) is next: it needs a "mood inputs changed" version counter on buffs / needs.

### Economy ledger
Loot `coins_add` now goes through `Economy.record(hid, n, reason)` (reason = the interaction's label, set in `Interaction.finish`, default "reward"):
it moves the money exactly like before, writes a ledger line, and repeats of the same reason on the same day share one line (with a `count`) so
snacks do not push bills and wages out of the 60-line ledger. Household -1 (NPC pocket money) and non-household ids stay out of the ledger and the
saves. Venue entry fees already went through `Economy.spend`. Tests: `systems_economy_test` (entry exists, merge, NPC excluded), `map_walk_test`
(every coin that left is a ledger entry).

## Test tiers

`fast` = default runner, `slow` = `-- --slow` (fast files + the SLOW list + every `*_longrun_test.gd`). Measured with `tools/godot_guard.ps1`
on the loaded machine.

### Fast tier

| | Files | Time |
|---|---|---|
| Round 1 end (HEAD at the start of round 2) | 101 | 237 s (sum of per-file times 226.6 s) |
| Now, the same 101 files | 101 | 212-220 s (three shuffles) |
| Now, everything in the tier | 119 | 252-262 s (18 files other agents added since: 40 s, e.g. circadian 11 s, bldg_gen 7.6 s) |

The 120 s goal was NOT met and cannot be with these cuts: 100+ files, each paying `new_game` (about 0.3-0.5 s, which now includes the building
generator) plus real simulated minutes at 6-10 ms each. What I cut (`TestFixture.pick` fast variants - the full length is unchanged in the slow
tier - or waits turned into conditions so they stop when the thing happened):

| File | Before | Now | How |
|---|---|---|---|
| townie_needs | 31.2 s | 18.4 s | fast: 14 h / 16 h of stranger watching instead of 30 h (full: 72 h -> 48 h) |
| weather_save | 8.8 s | 2.4 s | `WeatherKit.run_coarse`: hourly / daily signals only (what it checks lives there) |
| weather_effects | 11.6 s | 6.3 s | crops / frost / bills use `run_coarse`; events test 3 days instead of 4 |
| incidents_core | 10.5 s | 6.4 s | 40 / 50 / 25 / 30 days instead of 120 / 120 / 60 / 90 in the fast tier (the chaotic hit threshold scales: > 8 of ~17 expected) |
| hood_travel | 12.8 s | 9.9 s | `HoodKit.run_until(cond, max)` instead of fixed waits (meetings, hangout, closing time) |
| map_lots | 3.9 s | 6.8 s | 3 of the 5 world seeds in the fast tier (it still grew: the 43-lot map got more expensive for everybody, generated buildings) |
| start_solo_run | 9.9 s | 7.4 s | no edit: faster simulation |

Per-file growth that is NOT from this pass: hood_lots 4.6 -> 9.6 s and map_lots (generated buildings make every map build slower), content_run
9 -> 12.7 s and commute (circadian work of another agent).
Not done: sharing one built map between tests (snapshot / restore of World + Neighborhood statics): about 0.3 s x ~100 `new_game` calls = 30 s, but the
restore would have to reproduce the RNG and the id counters exactly; I did not risk it. `--import` is not part of any test run.

### Sharded fast tier (2026-10-19)

175 files take **586 s in one process on a quiet machine** (coop_net 56 s, cruise_needs 30, romance_run 28, townie_needs 25, coop_skip_run 22,
circadian 16, content_run 15, determinism 14 ...). `tools/run_fast.ps1` runs `run_all.gd --shard=k/6` six times side by side (each shard is a balanced
slice of the file list: the files are dealt heaviest first to the lightest slice, weights in `run_all.gd WEIGHT`, so the slices finish together) and
prints one summary with every FAIL line: **175 files, 0 failed, 144 s wall** with two other Godot runs going; 111-126 s per shard. That is how the
120 s target is met; the single-process tier is unchanged for `--only`, `--shuffle` and the slow tier.

### Final three fast runs (shuffle seeds 41, 52, 63)

```
---- 119 test files, 3 failed, 274.2 s ----   (bldg_edges_test, commute_test, incidents_ui_test)
---- 119 test files, 2 failed, 264.3 s ----   (commute_test, incidents_ui_test)
---- 119 test files, 1 failed, 268.5 s ----   (incidents_ui_test)
```
The failures belong to other agents' work in progress: `incidents_ui_test` "Surprises quick switch" (the OptionButton item count), `bldg_edges_test`
(new), `commute_test` ("late is not missed" etc.: passes at HEAD; passes here as soon as the working tree's `circadian` condition is taken out,
because Mira then cannot be asleep at 06:30), `content_run_test` ("musical folk ... guitar": fails with HEAD's `autonomy.gd` too, passed in two
of the three runs), `sim_basic` (mood playful vs happy: new mood data), `systems_family_integration` (slow tier, below).

### Slow tier (one run, loaded machine, 136 files): 1647 s (sum of per-file times), 8 files failed

Round 1 was 1314 s for 114 files. Per file (top 20, seconds; round 1 in brackets): bldg_apartments_run 171.9 (new, fails), story_pacing_longrun 163.1
(new, fails), crime_rates 120.4 (new), fire_longrun 117.5 (169), crime_longrun 114.0 (194; see below), health_longrun 99.4 (153),
systems_family_integration 87.2 (79), weather_longrun 77.9 (67), incidents_longrun 70.9 (102), accident_longrun 64.1 (82), systems_integration 58.5
(57), townie_needs 47.0 (42; the full version is now 48 h instead of 72 h), crime_child_abuse_rates 41.6 (new), circadian 39.3 (new; the full
version is now 9 days instead of 14), hood_sim 36.2 (48), disaster_longrun 22.2 (36), commute_longrun 21.5 (23), social_autonomy 16.3,
start_solo_run 15.0, content_run 14.5.

I shortened the full-length variants of fire / health / incidents / accident / disaster longruns by about a third (`TestFixture.pick` "full"
values; tolerances unchanged and they pass). crime_longrun: I tried 10 years instead of 16 and the burglary check ("> 0.15 a year per house") failed
once at 0.12 (it passed at 0.16 in the other run: the measured rate sits at the edge of the band at any length), so it is back to the original
length (its time in the table, 114 s, is from the 10-year attempt; the original is about 190 s).
The 600 s goal is NOT met and is out of reach: the fast files alone are about 260 s of the slow run, and the four files other agents added
(bldg_apartments_run, story_pacing_longrun, crime_rates, crime_child_abuse_rates) are 495 s on their own. They need a `pick` quick variant or shorter
spans from their owners (still in flux, so I did not touch them).
Failures in that run (all in other agents' areas): aging_life, bldg_apartments_run, commute_longrun, commute, crime_longrun (stat edge, see above),
incidents_ui, story_pacing_longrun ("weekly story beats 39 inside the 6-25 band"), systems_family_integration ("one pregnancy, one birth (6 / 5)":
passes at HEAD; fails identically with HEAD's `autonomy.gd`, director, social_dynamics and weather_folk swapped back in, so it is not from this pass).

### Vehicle layer (task 12b) - tier declaration
View only. Vehicles (at most `max_vehicles` = 46) exist only within `view_radius` of the camera focus or a player's folk; far vehicles are only timings (Transport.active, the bus timetable). Cadence: a 0.4 s bookkeeping pass (`VehicleView.sync`) and a per-frame move of the live vehicles (O(n^2) obstacle checks over at most 46, probe discs along each path). Hidden above game speed 2. The east side adds 76 tiles of map width (236 x 154); the big-town benchmark uses its own generated map (`MapBuilder.size_override`) and is unaffected.
