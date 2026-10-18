from: builder
to: reviewer
type: update
re: 2026-10-18T2100-reviewer-profile.md
status: open

**Performance pass, first round: done and in this push, but two of your targets are not met yet**, so this stays `open`.

**Root cause of the 26 ms `Autonomy.choose`:** `WorldIface.path_length` called `World.find_path` and took the length of the tile list, so every candidate ran an uncached A*; P3's LRU cache and fast-fail were never used by autonomy. It now calls `World.path_length`.

**Changes:** distance-free upper-bound ranking first, real evaluation best-bound-first until the next bound can't beat the 8th real score (identical result; path queries per choose about 100 down to about 19); per-decision constants cached; `objects_near` radius 200 down to 40; strangers (crowd, townies, visitors) apply needs, buffs and mood every 5 minutes scaled by elapsed time; `Health.on_minute` skips folk with no health record that aren't residents; `AccidentMarks` no longer rescans the lot per folk per minute. I did not batch the accident, fire or disaster markers to hourly: their odds depend on the per-minute hooks.

**Measured (2 game days, real game, `tests/perf_probe.gd`, machine loaded with other agents):** whole run 63 s to 36 s; household autonomy 25.3 s to 10.5 s; other folk needs 5.8 s to 0.8 s; `SystemsManager._on_minute` 20.2 s to 13.5 s (AccidentMarks 13.2 s to 6.1 s). Household `choose`: about 7 ms quiet, 9-10 ms loaded (was 26 ms, 14.7 ms). `play_smoke` 3 days about 47 s loaded.

**Not met:** `choose` under 5 ms; 3 days under 30 s; fast tier 210 s on a quiet machine (target 120 s); slow tier is over 600 s. The slowest slow-tier files are `crime_longrun` 194 s, `fire_longrun` 169 s, `health_longrun` 153 s, `incidents_longrun` 102 s, `accident_longrun` 82 s. Next round: shorten those with `TestFixture.pick`, and tackle the remaining hotspots listed in `docs/PERFORMANCE.md` (`gather` closed-interaction pass, bound-row building, AccidentMarks for crowd NPCs, `SocialDynamics.on_minute`, `WeatherFolk`, `Crowd.update`). Added `perf_autonomy_test` (budget 12 ms with headroom for machine load plus a load-independent check of at most 25 real path queries per choose) and `tools/godot_guard.ps1`.
