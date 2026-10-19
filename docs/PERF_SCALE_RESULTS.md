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

## 2026-10-19 03:50:06  today  (15 lots, 11 townies, map (160, 154), 3.0 days)

- **ms/game-min 6.90** | frame avg 1.38 ms (budget 4) | worst minute 112.8 ms (budget 12) | p99 34.3 | median 4.98 | town-level 0.81 ms/frame (budget 1) | by day: 6.27, 7.29, 7.13
- tiers (avg active / near / town / statistical): [4.0, 8.3, 4.4, 0.0]; ACTIVE max 14 (cap 60); folk ticked per game minute 5.6; at the end [7, 1, 6, 0]
- folk in world avg 12.5 / max 20; crowd+staff avg 9.5 / max 17; path queries 2295 (0.53/game-min, 24189 fills); choose(household) 6.46 ms, 6.7 paths, 403 cands; choose(npc) 8.56 ms, 6.2 paths, 403 cands; 
- nodes max 6 / end 6 (day 1: 6), orphans 1, objects 4466, resources 282, static mem 119 MB (day 1 116 MB); build 0.4 s, run 34 s wall

- slow minutes (> 30 ms): Day 1 09:00  113 ms: hour/WeatherWorld.on_hour 97; weather/objects 85; weather/cozy 8; hour/Goals.on_hour 5; weather/puddles 4 / Day 1 10:00  109 ms: hour/WeatherWorld.on_hour 96; weather/objects 88; weather/cozy 8 / Day 1 11:00  94 ms: hour/WeatherWorld.on_hour 85; weather/objects 75; weather/cozy 10 / Day 4 01:00  84 ms: hour/WeatherWorld.on_hour 66; weather/objects 65; DaySlices 6 / Day 3 01:00  82 ms: hour/WeatherWorld.on_hour 57; weather/objects 57; DaySlices 19 / Day 2 03:45  67 ms: systems/SimDirector 60; director/household fill (autonomy) 58; systems/AccidentMarks 4; accident/scan 4 / Day 4 04:00  63 ms: systems/SimDirector 30; director/household fill (autonomy) 28; hour/WeatherWorld.on_hour 19; weather/objects 19; systems/AccidentMarks 4 / Day 2 13:00  60 ms: hour/WeatherWorld.on_hour 44; weather/objects 41; DaySlices 4

- scheduler: 54 jobs, deferred 0 (pending at end 0), timed fired 0; ms per game minute by system: SimDirector 2.84, Incidents 0.87, AccidentMarks 0.77, NeighborhoodService 0.72, SocialDynamics 0.47, WeatherFolk 0.35, WeatherWorld 0.18, Tiers 0.18, CareerShifts 0.17, LevelSystems 0.07, CrimeFlow 0.03, DaySlices 0.02, Goals 0.02, TownSim 0.01

| group | row | ms/game-min | total ms | calls |
|---|---|---|---|---|
| listener | min  scheduler minute jobs (all but the director) | 3.715 | 16048 | 4320 |
| listener | min  SimDirector | 2.842 | 12277 | 4320 |
| director | director/household fill (autonomy) | 1.010 | 4362 | 12960 |
| systems | systems/AccidentMarks | 0.768 | 3318 | 4320 |
| systems | systems/NeighborhoodService.after | 0.718 | 3102 | 4320 |
| leaf | accident/scan | 0.594 | 2566 | 4320 |
| leaf | after/Crowd.update | 0.581 | 2508 | 4320 |
| director | director/household needs/buffs/mood | 0.577 | 2493 | 12960 |
| systems | systems/Incidents.slice | 0.560 | 2420 | 4320 |
| systems | systems/SocialDynamics.on_minute | 0.414 | 1790 | 4320 |
| leaf | crowd/lots | 0.396 | 1709 | 4320 |
| director | director/other needs/buffs/mood | 0.382 | 1651 | 11229 |
| director | director/other fill (autonomy) | 0.357 | 1544 | 11229 |
| systems | systems/WeatherFolk | 0.355 | 1533 | 4320 |
| listener | hour scheduler hour jobs | 0.306 | 1324 | 72 |
| systems | systems/Incidents | 0.305 | 1316 | 4320 |
| leaf | social/sync+record | 0.277 | 1196 | 4320 |
| director | director/household emergency+interaction tick | 0.243 | 1052 | 12960 |
| director | director/other emergency+interaction tick | 0.226 | 977 | 11229 |
| systems | systems/Tiers | 0.178 | 768 | 4320 |
| leaf | hour/WeatherWorld.on_hour | 0.177 | 764 | 72 |
| systems | systems/CareerShifts | 0.168 | 725 | 4320 |
| leaf | accident/rescue | 0.166 | 716 | 4320 |
| leaf | weather/objects | 0.161 | 696 | 72 |
| leaf | crowd/lot spawn | 0.145 | 626 | 721 |
| leaf | crowd/drive | 0.111 | 478 | 4320 |
| systems | systems/LevelSystems | 0.071 | 308 | 4320 |
| leaf | crowd/lot pick | 0.070 | 301 | 1754 |
| leaf | crowd/step_leavers | 0.068 | 292 | 4320 |
| leaf | social/contagion | 0.065 | 279 | 4320 |

## 2026-10-19 03:50:53  mini  (11 lots, 24 townies, map (160, 106), 3.0 days)

- **ms/game-min 7.94** | frame avg 1.59 ms (budget 4) | worst minute 62.0 ms (budget 12) | p99 38.2 | median 5.68 | town-level 0.91 ms/frame (budget 1) | by day: 7.67, 8.49, 7.67
- tiers (avg active / near / town / statistical): [4.1, 11.6, 11.5, 0.0]; ACTIVE max 22 (cap 60); folk ticked per game minute 6.2; at the end [6, 0, 22, 0]
- folk in world avg 15.4 / max 30; crowd+staff avg 12.6 / max 27; path queries 1760 (0.41/game-min, 26949 fills); choose(household) 6.22 ms, 8.0 paths, 267 cands; choose(npc) 8.79 ms, 7.3 paths, 267 cands; 
- nodes max 6 / end 6 (day 1: 6), orphans 1, objects 3893, resources 282, static mem 117 MB (day 1 115 MB); build 0.3 s, run 38 s wall

- slow minutes (> 30 ms): Day 4 01:00  62 ms: hour/WeatherWorld.on_hour 50; weather/objects 50 / Day 2 08:00  57 ms: hour/WeatherWorld.on_hour 44; weather/objects 40 / Day 4 00:01  57 ms: systems/Incidents.slice 53; incdef/guest_theft 44 / Day 4 00:00  57 ms: day/Story.on_day 15; day/Careers.on_day 9; day/CrimeFlow.on_day 4; day/MarketTick.on_day 4 / Day 3 00:00  56 ms: day/Careers.on_day 12; day/Story.on_day 8; day/MarketTick.on_day 7; hour/WeatherWorld.on_hour 6; day/CrimeFlow.on_day 5 / Day 2 12:09  54 ms: systems/SimDirector 45; director/other fill (autonomy) 41 / Day 2 05:45  53 ms: systems/SimDirector 48; director/household fill (autonomy) 47 / Day 2 16:47  52 ms: systems/SimDirector 45; director/other fill (autonomy) 44

- scheduler: 54 jobs, deferred 0 (pending at end 0), timed fired 0; ms per game minute by system: SimDirector 3.39, Incidents 1.05, AccidentMarks 0.96, NeighborhoodService 0.75, SocialDynamics 0.51, WeatherFolk 0.38, Tiers 0.20, CareerShifts 0.17, WeatherWorld 0.10, LevelSystems 0.09, CrimeFlow 0.06, TownSim 0.04, DaySlices 0.03, Goals 0.01

| group | row | ms/game-min | total ms | calls |
|---|---|---|---|---|
| listener | min  scheduler minute jobs (all but the director) | 4.261 | 18408 | 4320 |
| listener | min  SimDirector | 3.389 | 14639 | 4320 |
| director | director/household fill (autonomy) | 0.993 | 4292 | 12960 |
| systems | systems/AccidentMarks | 0.944 | 4078 | 4320 |
| systems | systems/Incidents.slice | 0.754 | 3258 | 4320 |
| systems | systems/NeighborhoodService.after | 0.748 | 3230 | 4320 |
| director | director/other fill (autonomy) | 0.741 | 3199 | 13989 |
| leaf | accident/scan | 0.728 | 3143 | 4320 |
| leaf | after/Crowd.update | 0.603 | 2605 | 4320 |
| director | director/household needs/buffs/mood | 0.575 | 2483 | 12960 |
| director | director/other needs/buffs/mood | 0.470 | 2030 | 13989 |
| systems | systems/SocialDynamics.on_minute | 0.439 | 1898 | 4320 |
| systems | systems/WeatherFolk | 0.380 | 1639 | 4320 |
| leaf | crowd/lots | 0.372 | 1606 | 4320 |
| director | director/other emergency+interaction tick | 0.306 | 1320 | 13989 |
| systems | systems/Incidents | 0.296 | 1278 | 4320 |
| leaf | social/sync+record | 0.290 | 1254 | 4320 |
| listener | hour scheduler hour jobs | 0.251 | 1085 | 72 |
| director | director/household emergency+interaction tick | 0.251 | 1082 | 12960 |
| leaf | accident/rescue | 0.207 | 896 | 4320 |
| systems | systems/Tiers | 0.202 | 873 | 4320 |
| systems | systems/CareerShifts | 0.171 | 738 | 4320 |
| leaf | crowd/drive | 0.142 | 613 | 4320 |
| leaf | crowd/lot spawn | 0.102 | 440 | 504 |
| leaf | hour/WeatherWorld.on_hour | 0.101 | 434 | 72 |
| leaf | incdef/catch_cold | 0.088 | 381 | 4320 |
| systems | systems/LevelSystems | 0.088 | 380 | 4320 |
| leaf | crowd/lot pick | 0.085 | 368 | 677 |
| leaf | weather/objects | 0.085 | 366 | 72 |
| leaf | crowd/step_leavers | 0.082 | 355 | 4320 |

## 2026-10-19 03:51:45  big  (63 lots, 197 townies, map (320, 272), 3.0 days)

- **ms/game-min 22.11** | frame avg 4.42 ms (budget 4) | worst minute 474.7 ms (budget 12) | p99 103.3 | median 15.05 | town-level 3.14 ms/frame (budget 1) | by day: 17.89, 23.80, 24.65
- tiers (avg active / near / town / statistical): [8.1, 31.9, 74.6, 81.5]; ACTIVE max 41 (cap 60); folk ticked per game minute 13.9; at the end [6, 22, 107, 62]
- folk in world avg 39.9 / max 133; crowd+staff avg 37.4 / max 127; path queries 2396 (0.55/game-min, 60231 fills); choose(household) 11.21 ms, 7.0 paths, 267 cands; choose(npc) 14.98 ms, 6.4 paths, 1364 cands; 
- nodes max 6 / end 6 (day 1: 6), orphans 1, objects 11240, resources 283, static mem 161 MB (day 1 146 MB); build 2.2 s, run 103 s wall

- slow minutes (> 30 ms): Day 4 00:00  475 ms: day/CrimeFlow.on_day 249; crimeday/CaseInvestigation.on_day 215; day/Story.on_day 61; day/Careers.on_day 46; day/Economy.on_day 33 / Day 4 04:12  471 ms: systems/Incidents.slice 468; incdef/burglary 465 / Day 2 23:11  395 ms: systems/Incidents.slice 390; incdef/street_robbery 386 / Day 3 01:05  370 ms: systems/Incidents.slice 363; incdef/burglary 360 / Day 3 00:00  344 ms: day/CrimeFlow.on_day 146; crimeday/CaseInvestigation.on_day 117; day/Careers.on_day 47; day/Story.on_day 46; day/MarketTick.on_day 27 / Day 2 02:46  255 ms: systems/Incidents.slice 252; incdef/trespassing 247 / Day 1 11:00  237 ms: hour/WeatherWorld.on_hour 188; weather/objects 181; hour/SocialDynamics.on_hour 18; hour/AccidentMarks.on_hour 14 / Day 1 09:00  223 ms: hour/WeatherWorld.on_hour 173; weather/objects 159; hour/AccidentMarks.on_hour 16; hour/SocialDynamics.on_hour 11; weather/puddles 9

- scheduler: 54 jobs, deferred 0 (pending at end 0), timed fired 0; ms per game minute by system: SimDirector 6.39, Incidents 4.26, NeighborhoodService 3.05, AccidentMarks 2.80, SocialDynamics 1.57, WeatherFolk 0.72, CrimeFlow 0.72, Tiers 0.53, CareerShifts 0.52, DaySlices 0.42, TownSim 0.34, WeatherWorld 0.31, LevelSystems 0.16, Careers 0.03

| group | row | ms/game-min | total ms | calls |
|---|---|---|---|---|
| listener | min  scheduler minute jobs (all but the director) | 14.244 | 61535 | 4320 |
| listener | min  SimDirector | 6.386 | 27587 | 4320 |
| systems | systems/Incidents.slice | 3.864 | 16692 | 4320 |
| systems | systems/NeighborhoodService.after | 3.045 | 13154 | 4320 |
| leaf | after/Crowd.update | 2.812 | 12150 | 4320 |
| systems | systems/AccidentMarks | 2.594 | 11206 | 4320 |
| leaf | crowd/lots | 2.034 | 8787 | 4320 |
| leaf | accident/scan | 2.032 | 8780 | 4320 |
| director | director/other needs/buffs/mood | 1.810 | 7819 | 47271 |
| systems | systems/SocialDynamics.on_minute | 1.354 | 5848 | 4320 |
| listener | hour scheduler hour jobs | 1.267 | 5472 | 72 |
| director | director/other emergency+interaction tick | 1.236 | 5338 | 47271 |
| director | director/household fill (autonomy) | 1.187 | 5126 | 12960 |
| director | director/other fill (autonomy) | 1.161 | 5016 | 47271 |
| leaf | crowd/lot pick | 1.140 | 4926 | 1358 |
| systems | systems/WeatherFolk | 0.724 | 3127 | 4320 |
| leaf | social/sync+record | 0.627 | 2710 | 4320 |
| director | director/household needs/buffs/mood | 0.609 | 2630 | 12960 |
| leaf | incdef/catch_cold | 0.555 | 2400 | 4320 |
| leaf | accident/rescue | 0.551 | 2381 | 4320 |
| leaf | CrimeFlow.person_day | 0.547 | 2364 | 4320 |
| systems | systems/Tiers | 0.530 | 2288 | 4320 |
| systems | systems/CareerShifts | 0.521 | 2251 | 4320 |
| leaf | crowd/drive | 0.480 | 2073 | 4320 |
| leaf | incdef/slip_fall | 0.427 | 1845 | 4320 |
| leaf | DaySlices | 0.420 | 1815 | 56 |
| leaf | social/contagion | 0.391 | 1688 | 4320 |
| systems | systems/Incidents | 0.384 | 1659 | 4320 |
| leaf | crowd/lot commute | 0.352 | 1520 | 3404 |
| leaf | incdef/burglary | 0.347 | 1501 | 4320 |

## 2026-10-19 17.3 tiers (LOD for people and places): before (origin/main 4c513df, 17.2) vs after (agent/tiers), big town, 3 game days, same machine under load

| big | before | after |
|---|---|---|
| ms/game-min | 43.44 | 22.11 |
| frame avg at speed 3 | 8.69 ms | 4.42 ms |
| worst / p99 / median minute | 6485 / 528 / 19.3 ms | 475 / 103 / 15.1 ms |
| town-level (non-director) per frame | 6.92 ms | 3.14 ms |
| folk ticked per game minute | 61.4 | 13.9 |
| folk in the world avg / max | 61.4 / 192 | 39.9 / 133 |
| ACTIVE avg / max (cap 60); NEAR / TOWN / STATISTICAL avg | n/a | 8.1 / 41; 31.9 / 74.6 / 81.5 |
| path queries per game minute | 0.45 | 0.55 |
| Incidents hourly | 9.54 ms/min | 3.86 (Incidents.slice) |
| social/contagion, SocialDynamics.on_minute | 7.14, 8.13 | 0.39, 1.35 |
| Crowd.update (crowd/lots, step_leavers) | 6.82 (3.89, 2.23) | 2.81 (2.03, ~0.1) |
| accident/scan | 2.66 | 2.03 |
| SimDirector | 8.81 | 6.39 |
| day jobs | 2.71 | ~1.3 |
| nodes / static memory (day 1 -> end) | 6 / 153 -> 172 MB | 6 / 146 -> 161 MB |

Biggest spikes before: Day 4 00:00 6485 ms (CrimeFlow.on_day 5410, Incidents.on_hour 316, RelationshipService.on_day 291), Incidents.on_hour 700-2300 ms at midday. After: a rare crime event inside an
Incidents slice (300-500 ms), midnight Careers / Story / CaseInvestigation (about 250-330 ms), the first rainy hour's object index (about 180 ms once).

## 2026-10-19 05:26:18  big  (63 lots, 200 townies, map (320, 272), 3.0 days)

- **ms/game-min 17.56** | frame avg 3.51 ms (budget 4) | worst minute 262.6 ms (budget 12) | p99 83.8 | median 12.29 | town-level 2.44 ms/frame (budget 1) | by day: 15.64, 23.27, 13.78
- tiers (avg active / near / town / statistical): [6.2, 30.4, 65.8, 96.8]; ACTIVE max 45 (cap 60); folk ticked per game minute 11.8; at the end [3, 12, 57, 131]
- folk in world avg 36.5 / max 160; crowd+staff avg 34.1 / max 126; path queries 2897 (0.67/game-min, 51034 fills); choose(household) 9.73 ms, 7.3 paths, 176 cands; choose(npc) 9.79 ms, 6.0 paths, 572 cands; 
- nodes max 6 / end 6 (day 1: 6), orphans 1, objects 11146, resources 288, static mem 159 MB (day 1 148 MB); build 2.0 s, run 83 s wall

- slow minutes (> 30 ms): Day 1 11:01  263 ms: hour/WeatherWorld.on_hour 193; weather/objects 190; systems/Incidents.slice 25; systems/NeighborhoodService.after 24; after/Crowd.update 24 / Day 1 10:01  253 ms: hour/WeatherWorld.on_hour 193; weather/objects 187; systems/NeighborhoodService.after 28; after/Crowd.update 28; crowd/lots 27 / Day 1 09:01  250 ms: hour/WeatherWorld.on_hour 194; weather/objects 187; systems/NeighborhoodService.after 28; after/Crowd.update 27; crowd/lots 27 / Day 3 13:02  209 ms: systems/NeighborhoodService.after 195; after/Crowd.update 195; crowd/lots 195; crowd/lot pick 93; crowd/lot staff 46 / Day 2 13:02  202 ms: systems/NeighborhoodService.after 135; after/Crowd.update 134; crowd/lots 133; crowd/lot staff 42; crowd/lot pick 41 / Day 3 01:00  186 ms: DaySlices 164; hour/AccidentMarks.on_hour 9; hour/CrimeFlow.on_hour 5 / Day 4 01:00  184 ms: DaySlices 164; hour/AccidentMarks.on_hour 8; hour/CrimeFlow.on_hour 5 / Day 2 08:01  179 ms: hour/WeatherWorld.on_hour 110; weather/objects 105; systems/NeighborhoodService.after 40; after/Crowd.update 40; crowd/lots 39

- scheduler: 54 jobs, deferred 4835 (pending at end 7), timed fired 0; ms per game minute by system: SimDirector 5.37, Incidents 2.80, NeighborhoodService 2.63, AccidentMarks 2.25, SocialDynamics 1.19 (3967 deferred), WeatherFolk 0.61, CrimeFlow 0.55 (3 deferred), DaySlices 0.50, Tiers 0.44, TownSim 0.31 (484 deferred), WeatherWorld 0.31 (75 deferred), LevelSystems 0.14, CareerShifts 0.10, Careers 0.03 (3 deferred)

| group | row | ms/game-min | total ms | calls |
|---|---|---|---|---|
| listener | min  scheduler minute jobs (all but the director) | 11.417 | 49322 | 4320 |
| listener | min  SimDirector | 5.375 | 23218 | 4320 |
| systems | systems/NeighborhoodService.after | 2.628 | 11354 | 4320 |
| systems | systems/Incidents.slice | 2.468 | 10661 | 4320 |
| leaf | after/Crowd.update | 2.426 | 10482 | 4320 |
| systems | systems/AccidentMarks | 2.071 | 8945 | 4320 |
| leaf | crowd/lots | 1.732 | 7483 | 4320 |
| leaf | accident/scan | 1.594 | 6884 | 4320 |
| director | director/other needs/buffs/mood | 1.324 | 5719 | 38074 |
| director | director/household fill (autonomy) | 1.233 | 5326 | 12960 |
| systems | systems/SocialDynamics.on_minute | 1.036 | 4476 | 4261 |
| director | director/other emergency+interaction tick | 1.005 | 4343 | 38074 |
| leaf | crowd/lot pick | 0.938 | 4053 | 1232 |
| director | director/other fill (autonomy) | 0.893 | 3859 | 38074 |
| listener | hour scheduler hour jobs | 0.757 | 3269 | 72 |
| systems | systems/WeatherFolk | 0.611 | 2638 | 4320 |
| director | director/household needs/buffs/mood | 0.573 | 2476 | 12960 |
| leaf | social/sync+record | 0.534 | 2307 | 4261 |
| leaf | DaySlices | 0.498 | 2153 | 56 |
| leaf | accident/rescue | 0.465 | 2011 | 4320 |
| leaf | CrimeFlow.person_day | 0.464 | 2004 | 4320 |
| leaf | crowd/drive | 0.452 | 1953 | 4320 |
| systems | systems/Tiers | 0.439 | 1898 | 4320 |
| systems | systems/Incidents | 0.322 | 1391 | 4320 |
| leaf | TownSim.hourly | 0.314 | 1357 | 4320 |
| leaf | hour/WeatherWorld.on_hour | 0.304 | 1314 | 71 |
| leaf | crowd/lot commute | 0.294 | 1270 | 3216 |
| leaf | weather/objects | 0.288 | 1243 | 71 |
| leaf | incdef/slip_fall | 0.282 | 1218 | 4320 |
| leaf | social/conversation | 0.275 | 1188 | 4261 |

## 2026-10-19 06:53:53  big  (63 lots, 196 townies, map (320, 272), 3.0 days)

- **ms/game-min 21.60** | frame avg 4.32 ms (budget 4) | worst minute 152.4 ms (budget 12) | p99 86.9 | median 16.40 | town-level 2.87 ms/frame (budget 1) | by day: 16.21, 23.84, 24.77
- tiers (avg active / near / town / statistical): [10.5, 37.0, 79.4, 70.9]; ACTIVE max 60 (cap 60); folk ticked per game minute 17.3; at the end [36, 5, 117, 39]
- folk in world avg 48.0 / max 157; crowd+staff avg 46.1 / max 154; path queries 2695 (0.62/game-min, 74741 fills); choose(household) 6.84 ms, 6.0 paths, 2024 cands; choose(npc) 22.66 ms, 6.0 paths, 2024 cands; 
- nodes max 6 / end 6 (day 1: 6), orphans 1, objects 11384, resources 293, static mem 166 MB (day 1 149 MB); build 2.2 s, run 100 s wall

- slow minutes (> 30 ms): Day 3 12:01  152 ms: systems/Incidents.slice 60; systems/NeighborhoodService.after 32; after/Crowd.update 32; crowd/lots 30; systems/SimDirector 29 / Day 2 17:01  144 ms: systems/Incidents.slice 56; systems/NeighborhoodService.after 44; after/Crowd.update 44; crowd/lots 43; hour/SocialDynamics.on_hour 27 / Day 2 12:01  142 ms: systems/Incidents.slice 53; systems/SimDirector 45; systems/NeighborhoodService.after 19; after/Crowd.update 19; crowd/lots 17 / Day 3 15:01  132 ms: systems/Incidents.slice 50; hour/SocialDynamics.on_hour 42; systems/SimDirector 20; systems/NeighborhoodService.after 12; after/Crowd.update 12 / Day 2 13:02  131 ms: systems/NeighborhoodService.after 78; after/Crowd.update 78; crowd/lots 77; crowd/lot pick 32; hour/SocialDynamics.on_hour 24 / Day 3 17:01  131 ms: systems/NeighborhoodService.after 52; after/Crowd.update 52; crowd/lots 50; systems/Incidents.slice 41; crowd/lot pick 29 / Day 2 12:12  130 ms: systems/NeighborhoodService.after 80; after/Crowd.update 80; crowd/drive 78; systems/SimDirector 18; systems/AccidentMarks 11 / Day 2 16:01  127 ms: systems/Incidents.slice 60; systems/NeighborhoodService.after 27; after/Crowd.update 26; crowd/lots 25; hour/SocialDynamics.on_hour 20

- scheduler: 55 jobs, deferred 5334 (pending at end 8), timed fired 0; ms per game minute by system: SimDirector 7.23, AccidentMarks 3.14, NeighborhoodService 2.95, Incidents 2.86, SocialDynamics 2.02 (3992 deferred), WeatherFolk 0.76, Tiers 0.57, WeatherWorld 0.39 (74 deferred), DaySlices 0.32, TownSim 0.30 (961 deferred), CareerShifts 0.30, CrimeFlow 0.29 (3 deferred), LevelSystems 0.18, StoryVisits 0.02

| group | row | ms/game-min | total ms | calls |
|---|---|---|---|---|
| listener | min  scheduler minute jobs (all but the director) | 13.773 | 59499 | 4320 |
| listener | min  SimDirector | 7.227 | 31219 | 4320 |
| systems | systems/AccidentMarks | 2.951 | 12750 | 4320 |
| systems | systems/NeighborhoodService.after | 2.943 | 12716 | 4320 |
| leaf | after/Crowd.update | 2.737 | 11825 | 4320 |
| systems | systems/Incidents.slice | 2.482 | 10721 | 4320 |
| leaf | accident/scan | 2.333 | 10079 | 4320 |
| director | director/other needs/buffs/mood | 2.176 | 9402 | 61781 |
| leaf | crowd/lots | 1.830 | 7908 | 4320 |
| systems | systems/SocialDynamics.on_minute | 1.797 | 7765 | 4263 |
| director | director/other emergency+interaction tick | 1.494 | 6456 | 61781 |
| director | director/household fill (autonomy) | 1.395 | 6025 | 12960 |
| director | director/other fill (autonomy) | 1.226 | 5297 | 61781 |
| leaf | crowd/lot pick | 0.984 | 4251 | 1384 |
| systems | systems/WeatherFolk | 0.762 | 3293 | 4320 |
| leaf | social/sync+record | 0.743 | 3212 | 4263 |
| leaf | social/contagion | 0.652 | 2818 | 4263 |
| leaf | accident/rescue | 0.609 | 2630 | 4320 |
| listener | hour scheduler hour jobs | 0.592 | 2558 | 72 |
| director | director/household needs/buffs/mood | 0.579 | 2501 | 12960 |
| systems | systems/Tiers | 0.570 | 2464 | 4320 |
| leaf | crowd/drive | 0.569 | 2458 | 4320 |
| leaf | choose/gather | 0.433 | 1872 | 496 |
| leaf | choose/pass1 | 0.419 | 1811 | 496 |
| leaf | choose/eval | 0.411 | 1777 | 496 |
| leaf | social/conversation | 0.389 | 1682 | 4263 |
| systems | systems/Incidents | 0.369 | 1595 | 4320 |
| leaf | crowd/lot commute | 0.352 | 1520 | 3690 |
| systems | systems/WeatherWorld.rain | 0.349 | 1508 | 3727 |
| leaf | p1/_profile | 0.342 | 1476 | 26213 |
