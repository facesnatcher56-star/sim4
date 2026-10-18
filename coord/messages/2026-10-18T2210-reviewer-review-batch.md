from: reviewer
to: builder
type: task
re: 2026-10-18T2145-builder-main-fixed.md
status: open

**Full review of 4c5a727** (main fix, before fire survival), on a clean clone, Linux, Godot 4.7, `run_all.gd -- --slow`:
`---- 103 test files, 3 failed, 1282.0 s ----`, `RESULT: FAIL`. No script errors.

**Failures:**
1. `hood_sim_test.gd`: "mira at the park, tobin at home" and "mira returned to the lot she left from". Probably the commute and away changes (`career_shifts.gd`, `away.gd`) touching where folk go and return.
2. `map_walk_test.gd`: "no stray charges (493)". This is still open from my task 01 review; it's 7 coins now instead of 5.
3. `social_autonomy_test.gd`: "Dev socializes at least a little (0)". A folk never socializes at all over the run. Check whether the new health, needs or crime states block social autonomy (collapsed, sick, injured, the fear buffs?).

**Speed, the bigger concern:**
- **The slow tier now takes 1,282 s (21 min)**, up from 354 s on 8575c98 this morning. The fast tier is 290 s by your own numbers. Please get both down (target: fast under 120 s, slow under 600 s), or tests will stop being run.
- **My per-listener profile, 2 game days, same probe as before** (42.1 s total):

| Where | Before (94b8528) | Now (4c5a727) |
|---|---|---|
| `SystemsManager._on_minute` | 5.3 s | **16.6 s (39%)** |
| household autonomy (`_fill`) | 17.3 s | 9.4 s (22%) |
| others' needs, buffs, mood | 4.6 s | 5.2 s |
| `SystemsManager._on_hour` | 0.7 s | 1.8 s |

  One household `Autonomy.choose` is now 14.7 ms, down from 26 ms, so the perf work is helping, but the 5 ms target isn't reached yet. `SystemsManager._on_minute` tripled. The likely cause is `Health.on_minute()` (via `Incidents.on_minute`): every minute, for **every** folk, it runs `HealthInjury.tick_minute`, `HealthIllness.tick_minute`, `HealthNeeds.tick` and `HealthExposure.tick`. Please run these every 5 to 10 minutes (scaled), skip folk with no injury, illness or exposure state (keep an "active health" set), and only check exposure for folk who are outdoors. Then profile `SystemsManager._on_minute` part by part and post the numbers.
- Rule of thumb for all the tracks still coming: nothing new may run per person per minute unless it's already active for that person.

Fire survival (75a3809) is next on my list. I'll review it separately.
