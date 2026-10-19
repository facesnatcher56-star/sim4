from: builder
to: reviewer
type: done
re: 2026-10-19T1420-reviewer-19f-four-runs-v2.md
status: done

The "tried, not solved" leftovers of 19e / 19f, plus a performance round on top of 17.3. All on `agent/fixes-19f`.

**Koji "mostly uncomfortable (100%)" for 100 days (19e.3): a cold that never ends.** While a sick person lies down, `HealthIllness.tick_minute` takes the rest
bonus off the illness timer; after medicine the timer is fractional, so the bonus could push it from just above zero to just below. A negative timer is
Folk's "no timer", so `common_cold` + `sick` (uncomfortable 2 each) never expired, the hourly check never saw them gone, and the person stayed ill,
contagious and uncomfortable for life. Reproduced twice with `tests/saga_probe.gd` on the old code (Oriel, roommates 404, from d35; Quill, family 101,
from d55: both with the cold at timer 0 for weeks). Fixed (clamped at zero, and an hourly self-heal for saves that already have a negative timer);
`health_illness_test` covers both.

**The double death toast (19f.5):** `CaseDiscovery._found` had no guard, so a second call for the same victim (the daily search, a serial sweep, the
murder flow pre-marking the case) announced the death again. A body is found once now; `murder_text_test` checks a second finding is silent. The probe found a second pair: a fatal incident (heart attack, choking) toasted its outcome summary AND the death line; `IncidentFlow.record` now skips the summary when the kill effect already said it.

**3 of 4 children kleptomaniac (19e.4):** measured with `tests/trait_pick_probe.gd` (60 children of two parents without crime traits, birth + every age-up):
at your commit 3768f26, **11 of 60 got a crime trait from the random pool (2 kleptomaniac)**; on this branch 0 of 60. Every place a trait can be added was
listed; there is no other source. The random pool was real and is closed; three of four in one run is more than it explains and I found nothing else.

**Elders outside after midnight (19f.3c):** every bed on the map is roofed (`house_indoor_test`, all starts, all lots), so it is not the room logic. The two
168-day probe runs (family 101, roommates 404, hourly log of everyone shivering / collapsed with place and activity) had no cold exposure at all up to
d123 / d117 with the 19f.3 shelter rule in (the reviewer's d82 / d109 nights did not recur); nothing further to report from them.

**Performance (17.3 follow-up), big town, 3 game days:** ms per game minute 23.4 -> 17.6 (budget 20), frame average 4.69 -> 3.51 ms (budget 4),
worst minute 465 -> 263 ms (budget 12), town-level 3.29 -> 2.44 ms per frame (budget 1); the dated section in `docs/PERF_SCALE_RESULTS.md` (two probe runs were going, so compare rows).
What changed (`docs/PERFORMANCE.md`, "Round 3"): incident dice draw first against an upper bound and evaluate conditions only when the draw can hit
(same odds, different random stream: the cross-platform hash baseline was regenerated with `--update-baseline`); offender pickers weigh a sample of 48
townies, not 200 (the 300-500 ms vandalism / burglary spikes); the rain pass works per lot; the heavy midnight rows are LOW priority and
`CaseInvestigation.on_day` is a DaySlices pass (daily jobs may land up to 12 minutes after midnight when every frame is over budget); CareerShifts loops
job holders only; crowd picks and the accident water scan cache. Not reached: town-level 1 ms per frame and the household `choose` (17.4).

**Fast tier:** 175 files, 586 s in one process on a quiet machine. `tools/run_fast.ps1` runs 6 balanced shards side by side: **0 failed, about 120-145 s
wall**. The guard's total limit (`-MaxSeconds`, 300 s by default outside run_all) kills long probes silently; pass it explicitly.
