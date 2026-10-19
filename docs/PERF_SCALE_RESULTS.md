# Scale benchmark results

Appended by `tests/perf_scale.gd` (tools/run_scale.ps1). One section per run; compare the `ms/game-min` and `frame avg` lines between runs (a regression over 10% needs a written reason in the done message). Machine load is not controlled: compare the load-independent counts first.

## 2026-10-18 18:16:40  today  (15 lots, 12 townies, map (160, 136), 3.0 days)

- **ms/game-min 6.82** | frame avg 1.36 ms (budget 4) | worst minute 204.3 ms (budget 12) | p99 44.4 | median 4.02 | town-level 0.73 ms/frame (budget 1) | by day: 6.47, 7.20, 6.79
- folk in world avg 10.9 / max 18; crowd+staff avg 8.2 / max 15; path queries 4911 (1.14/game-min, 47216 fills); choose(household) 5.34 ms, 4.7 paths, 219 cands; choose(npc) 6.20 ms, 8.0 paths, 453 cands; 
- nodes max 6 / end 6 (day 1: 6), orphans 1, objects 4269, resources 212, static mem 108 MB (day 1 107 MB); build 0.3 s, run 31 s wall

- slow minutes (> 30 ms): Day 2 00:00  204 ms: day  SystemsManager._on_day 122; hour SystemsManager._on_hour 75; day/CrimeFlow.on_day 45; day/Incidents.on_day 39; hour/Incidents.on_hour 38 / Day 4 00:00  202 ms: day  SystemsManager._on_day 149; day/CrimeFlow.on_day 80; hour SystemsManager._on_hour 48; day/Incidents.on_day 34; hour/Incidents.on_hour 32 / Day 3 00:00  161 ms: day  SystemsManager._on_day 110; day/CrimeFlow.on_day 57; hour SystemsManager._on_hour 45; hour/Incidents.on_hour 35; day/Incidents.on_day 24 / Day 1 09:00  139 ms: hour SystemsManager._on_hour 132; hour/WeatherWorld.on_hour 110; hour/Incidents.on_hour 19 / Day 1 10:00  134 ms: hour SystemsManager._on_hour 127; hour/WeatherWorld.on_hour 83; hour/Incidents.on_hour 40 / Day 1 11:00  133 ms: hour SystemsManager._on_hour 126; hour/WeatherWorld.on_hour 87; hour/Incidents.on_hour 37 / Day 1 18:00  129 ms: hour SystemsManager._on_hour 119; hour/Incidents.on_hour 86; hour/WeatherWorld.on_hour 28; hour (res://scripts/systems/social_dynamics.gd):<GDScript#-9223371965635492217>.on_hour 4 / Day 1 19:00  114 ms: hour SystemsManager._on_hour 104; hour/Incidents.on_hour 75; hour/WeatherWorld.on_hour 24; hour (res://scripts/systems/social_dynamics.gd):<GDScript#-9223371965635492217>.on_hour 5

| group | row | ms/game-min | total ms | calls |
|---|---|---|---|---|
| listener | min  SimDirector._on_minute | 3.135 | 13544 | 4320 |
| listener | min  SystemsManager._on_minute | 2.221 | 9595 | 4320 |
| director | director/household fill (autonomy) | 1.448 | 6256 | 12960 |
| listener | hour SystemsManager._on_hour | 0.839 | 3626 | 72 |
| systems | systems/NeighborhoodService.after | 0.833 | 3600 | 4320 |
| leaf | after/Crowd.update | 0.727 | 3139 | 4320 |
| systems | systems/AccidentMarks | 0.694 | 2997 | 4320 |
| leaf | hour/Incidents.on_hour | 0.559 | 2414 | 72 |
| leaf | accident/scan | 0.558 | 2409 | 4320 |
| director | director/household needs/buffs/mood | 0.528 | 2282 | 12960 |
| listener | min  (res://scripts/systems/social_dynamics.gd):<GDScript#-9223371965635492217>.on_minute | 0.475 | 2050 | 4320 |
| director | director/other fill (autonomy) | 0.381 | 1647 | 34256 |
| leaf | crowd/lots | 0.369 | 1595 | 4320 |
| systems | systems/WeatherFolk | 0.304 | 1313 | 4320 |
| systems | systems/Incidents | 0.291 | 1259 | 4320 |
| director | director/other emergency+interaction tick | 0.266 | 1151 | 34256 |
| leaf | hour/WeatherWorld.on_hour | 0.248 | 1070 | 72 |
| director | director/household emergency+interaction tick | 0.235 | 1014 | 12960 |
| leaf | social/sync+record | 0.231 | 1000 | 4320 |
| leaf | crowd/step_leavers | 0.225 | 973 | 4320 |
| director | director/other needs/buffs/mood | 0.225 | 972 | 34256 |
| leaf | social/contagion | 0.185 | 799 | 4320 |
| leaf | accident/rescue | 0.128 | 553 | 4320 |
| leaf | crowd/drive | 0.125 | 541 | 4320 |
| listener | day  SystemsManager._on_day | 0.088 | 381 | 3 |
| listener | hour (res://scripts/systems/social_dynamics.gd):<GDScript#-9223371965635492217>.on_hour | 0.051 | 219 | 72 |
| leaf | social/conversation | 0.047 | 205 | 4320 |
| systems | systems/CareerShifts | 0.046 | 199 | 4320 |
| leaf | day/CrimeFlow.on_day | 0.042 | 183 | 3 |
| leaf | after/ambient+meetings+meetups | 0.039 | 171 | 4320 |

## 2026-10-18 18:17:28  big  (63 lots, 195 townies, map (320, 272), 3.0 days)

- **ms/game-min 38.09** | frame avg 7.62 ms (budget 4) | worst minute 6576.3 ms (budget 12) | p99 478.2 | median 18.18 | town-level 6.00 ms/frame (budget 1) | by day: 31.41, 42.56, 40.30
- folk in world avg 46.8 / max 149; crowd+staff avg 44.9 / max 146; path queries 2832 (0.66/game-min, 202173 fills); choose(household) 10.57 ms, 6.0 paths, 175 cands; choose(npc) 12.30 ms, 5.6 paths, 1994 cands; 
- nodes max 6 / end 6 (day 1: 6), orphans 1, objects 10803, resources 212, static mem 161 MB (day 1 142 MB); build 1.9 s, run 170 s wall

- slow minutes (> 30 ms): Day 4 00:00  6576 ms: day  SystemsManager._on_day 6211; day/CrimeFlow.on_day 5540; hour SystemsManager._on_hour 334; day/RelationshipService.on_day 313; hour/Incidents.on_hour 279 / Day 3 00:00  3975 ms: day  SystemsManager._on_day 3628; day/CrimeFlow.on_day 3136; hour SystemsManager._on_hour 325; hour/Incidents.on_hour 275; day/Incidents.on_day 235 / Day 2 00:00  3710 ms: day  SystemsManager._on_day 3388; day/CrimeFlow.on_day 1742; day/Incidents.on_day 1474; hour SystemsManager._on_hour 310; hour/Incidents.on_hour 224 / Day 4 02:00  2216 ms: hour SystemsManager._on_hour 2192; hour/Incidents.on_hour 2098; hour/WeatherWorld.on_hour 83; hour (res://scripts/systems/social_dynamics.gd):<GDScript#-9223371965635492217>.on_hour 20; hour/AccidentMarks.on_hour 6 / Day 2 22:00  1719 ms: hour SystemsManager._on_hour 1673; hour/Incidents.on_hour 1622; hour/WeatherWorld.on_hour 36; hour (res://scripts/systems/social_dynamics.gd):<GDScript#-9223371965635492217>.on_hour 36; hour/AccidentMarks.on_hour 8 / Day 2 14:00  1451 ms: hour SystemsManager._on_hour 1279; hour/Incidents.on_hour 1223; hour (res://scripts/systems/social_dynamics.gd):<GDScript#-9223371965635492217>.on_hour 109; min  (res://scripts/systems/social_dynamics.gd):<GDScript#-9223371965635492217>.on_minute 36; hour/WeatherWorld.on_hour 35 / Day 1 11:00  1411 ms: hour SystemsManager._on_hour 1344; hour/Incidents.on_hour 853; hour/WeatherWorld.on_hour 471; hour (res://scripts/systems/social_dynamics.gd):<GDScript#-9223371965635492217>.on_hour 30; min  SystemsManager._on_minute 16 / Day 2 15:00  1349 ms: hour SystemsManager._on_hour 1155; hour/Incidents.on_hour 1093; hour (res://scripts/systems/social_dynamics.gd):<GDScript#-9223371965635492217>.on_hour 114; hour/WeatherWorld.on_hour 39; min  (res://scripts/systems/social_dynamics.gd):<GDScript#-9223371965635492217>.on_minute 36

| group | row | ms/game-min | total ms | calls |
|---|---|---|---|---|
| listener | min  SystemsManager._on_minute | 10.496 | 45344 | 4320 |
| listener | hour SystemsManager._on_hour | 9.511 | 41087 | 72 |
| leaf | hour/Incidents.on_hour | 8.284 | 35785 | 72 |
| listener | min  SimDirector._on_minute | 8.068 | 34852 | 4320 |
| systems | systems/NeighborhoodService.after | 6.564 | 28359 | 4320 |
| leaf | after/Crowd.update | 6.396 | 27632 | 4320 |
| listener | min  (res://scripts/systems/social_dynamics.gd):<GDScript#-9223371965635492217>.on_minute | 6.185 | 26717 | 4320 |
| leaf | social/contagion | 5.217 | 22537 | 4320 |
| leaf | crowd/lots | 3.563 | 15393 | 4320 |
| listener | day  SystemsManager._on_day | 3.062 | 13228 | 3 |
| director | director/other emergency+interaction tick | 3.012 | 13013 | 189213 |
| systems | systems/AccidentMarks | 2.697 | 11650 | 4320 |
| leaf | day/CrimeFlow.on_day | 2.411 | 10417 | 3 |
| leaf | crowd/step_leavers | 2.151 | 9291 | 4320 |
| leaf | accident/scan | 2.112 | 9122 | 4320 |
| director | director/other fill (autonomy) | 1.457 | 6294 | 189213 |
| director | director/other needs/buffs/mood | 1.364 | 5894 | 189213 |
| director | director/household fill (autonomy) | 1.243 | 5368 | 12960 |
| leaf | hour/WeatherWorld.on_hour | 0.959 | 4144 | 72 |
| listener | hour (res://scripts/systems/social_dynamics.gd):<GDScript#-9223371965635492217>.on_hour | 0.756 | 3266 | 72 |
| leaf | crowd/drive | 0.674 | 2910 | 4320 |
| systems | systems/WeatherFolk | 0.644 | 2783 | 4320 |
| leaf | social/sync+record | 0.592 | 2558 | 4320 |
| leaf | accident/rescue | 0.573 | 2477 | 4320 |
| director | director/household needs/buffs/mood | 0.533 | 2303 | 12960 |
| leaf | day/Incidents.on_day | 0.455 | 1968 | 3 |
| leaf | social/conversation | 0.359 | 1552 | 4320 |
| systems | systems/Incidents | 0.349 | 1508 | 4320 |
| director | director/household emergency+interaction tick | 0.241 | 1040 | 12960 |
| leaf | hour/AccidentMarks.on_hour | 0.176 | 761 | 72 |


## 2026-10-18 18:33:37  VIEWS big  (63 lots, 200 townies, map (320, 272), 1 day(s), main scene + LotView + FolkView, headless)

- 26.70 ms/frame avg wall, NET of the 6.90 ms empty-frame floor 19.80 ms (p99 114.8, worst 2598.1 ms wall); nodes max 18268 end 17272 (day 1: 17272), orphans 5998, objects 39444, static mem 232 MB, folk avg 38.0 max 82

## 2026-10-18 18:35:54  VIEWS today  (15 lots, 12 townies, map (160, 136), 1 day(s), main scene + LotView + FolkView, headless)

- 16.90 ms/frame avg wall, NET of the 6.90 ms empty-frame floor 10.00 ms (p99 34.6, worst 242.6 ms wall); nodes max 9409 end 9333 (day 1: 9333), orphans 1556, objects 19170, static mem 174 MB, folk avg 11.3 max 18

## 2026-10-18 17.2 scheduler refactor: before (origin/main 597cb66) vs after (agent/scheduler), 3 game days, same machine under load (9+ other Godot runs)

The refactor moves every Clock listener into the SimScheduler without changing what runs or in which order (a real 3-day game gives the identical state hash before and
after: `tests/state_hash_probe.gd`). It adds no savings by itself (those come from the tiers, 17.3); the point is the cost of the scheduler layer itself and the new knobs
(frame budget with LOW deferral, bucketing, timed wake-ups, emptiness gates). Counts are load independent; ms are not.

| profile | ms/game-min before -> after | frame avg (speed 3) before -> after | town-level per frame before -> after | worst minute before -> after | deferred |
|---|---|---|---|---|---|
| mini | 7.40 -> 6.76 | 1.48 -> 1.35 ms | 0.83 -> 0.78 ms | 311 -> 370 ms | 0 |
| today | 5.92 -> 6.03 | 1.18 -> 1.21 ms | 0.70 -> 0.73 ms | 196 -> 180 ms | 0 |
| big | 38.20 -> 39.86 | 7.64 -> 7.97 ms | 6.12 -> 6.37 ms | 6168 -> 5049 ms | 0 |

Per system, big town, ms per game minute (before -> after; the old "listener" rows are now per-job rows of the scheduler):

| system | before | after |
|---|---|---|
| all minute jobs except the director (SystemsManager steps + SocialDynamics) | 11.01 + 6.00 = 17.0 | 18.96 |
| hour jobs (SystemsManager._on_hour + SocialDynamics.on_hour) | 10.22 + 0.79 = 11.0 | 10.59 |
| SimDirector (folk ticking) | 7.59 | 8.01 |
| NeighborhoodService.after (Crowd.update) | 6.83 | 7.44 |
| SocialDynamics.on_minute | 6.00 | 6.90 |
| AccidentMarks | 2.72 | 2.98 |
| day jobs | 2.58 | 2.29 |
| WeatherFolk / Incidents / CareerShifts / LevelSystems | 0.61 / 0.32 / 0.31 / 0.16 | 0.63 / 0.32 / 0.43 / 0.17 |

Deferred counts are 0 because the benchmark runs with `budget_usec = 0` (unlimited, deterministic); the game sets 4 ms in main.gd and marks only the hourly world jobs and
SocialDynamics as LOW. The overhead of the scheduler layer is within the noise of the machine (about +4% on the big town, one list walk and one `is_valid` per job per tick).
