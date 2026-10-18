# Performance notes

## Tools

- `tests/perf_probe.gd` - boots the real game (`main.start_new_game`), advances N game days minute by minute and times every Clock listener
  (minute / hour / day), SimDirector's phases (`director/...`) and each `SystemsManager._on_minute` step (`systems/...`):
  `powershell -File tools/godot_guard.ps1 -Seconds 300 -Args "--headless","--path",".","--script","res://tests/perf_probe.gd","--","2"`.
  Rows under 20 ms are hidden. The numbers include other processes on the machine: compare runs, not absolutes.
- `tests/perf_autonomy_test.gd` (fast tier) - fails if `Autonomy.choose` for a household folk on the full map takes more than 12 ms
  (best of 5 rounds of 12 calls; about 7 ms on a quiet machine, 9-10 ms with ~9 other Godot runs going, 26-40 ms before) or makes
  more than 25 real path queries per call (about 19 now; it was one per candidate, ~100). The target is 5 ms; 12 catches a return of
  the old behaviour without flaking on a busy machine.
- `tools/godot_guard.ps1` - run Godot headless through it, always. It redirects output to a log, polls it, kills Godot at once on
  `SCRIPT ERROR`, `Parse Error` or `Failed to load script`, or after `-Seconds` without new output, prints the tail and exits non-zero
  (3 = killed, else Godot's exit code). Usage:
  `powershell -File tools/godot_guard.ps1 -Seconds 120 -Args "--headless","--path",".","--script","res://tests/run_one.gd","--","nav_perf_test"`
  (`-Args` can also be one comma-separated string; `-Tail N` lines to print, `-Log path`, `-Godot exe`). Suggested `-Seconds`: 120 single
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

## Not done / next candidates

- `Autonomy.choose` is ~7-10 ms, not 5: `gather` (~4 ms, of which ~2.7 ms is the closed-interaction pass: cooldown, trait refusal and
  actor-only tests for ~190 (interaction, kind) pairs) and building ~120 bound rows (~3 ms) dominate. Ideas: cache closed reasons
  per folk per game minute, group-level bounds (profile x nearest object) before expanding objects.
- `play_smoke` 3 days is still above 30 s on this loaded machine. Remaining per-minute cost: AccidentMarks scan of crowd NPCs,
  `SocialDynamics.on_minute` (Emotions.sync for every folk), `WeatherFolk.on_minute`, `Crowd.update`.
- Batching AccidentMarks for strangers every 5 minutes would need the road dice scaled (1-(1-p)^5) to stay equivalent.

## Test tiers (measured on the loaded machine, ~9 other Godot runs; the reviewer's quiet Linux box is roughly 1.5-2x faster)

- Fast tier: 225 s for 101 files (was 256 s with the same load before the last changes); the slowest files are hood_travel (12 s),
  incidents_core (10 s), content_run (10 s), commute (9 s), townie_needs (20 s -> still the biggest in the slow list, 42 s there).
  Per-file times are dominated by game minutes simulated (about 12 ms per minute with the crowd), so they shrink with the sim speed-ups above.
- Slow tier: 114 files, all passing, 1314 s here. Slowest: crime_longrun 194 s, fire_longrun 169 s, health_longrun 153 s, incidents_longrun 102 s,
  accident_longrun 82 s, systems_family_integration 79 s, weather_longrun 67 s, systems_integration 57 s, hood_sim 48 s, townie_needs 42 s,
  disaster_longrun 36 s, commute_longrun 23 s. Getting under 600 s needs these long runs shortened by their owners (`TestFixture.pick(full, quick)`
  for the loops, fewer simulated days); that was not done here because the files belong to the parallel crime / fire / health / disaster tracks.
