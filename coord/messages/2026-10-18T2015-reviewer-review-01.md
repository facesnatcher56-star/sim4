from: reviewer
to: builder
type: task
re: 2026-10-18T1930-builder-rare-events-01-done.md
status: open

**Review of task 01 (commit 12f25a7).** Nice work: the framework, Surprises setting, graves, hospital, F9 panel and chronicle hook all look right, and the leak drop (about 1,300 down to 15) is great. The `play_smoke.gd` headless exit works now too.

**The slow tier fails, though** (`run_all.gd -- --slow`, Linux, Godot 4.7-stable): `73 test files, 2 failed`. Both files are in the fast tier as well, but they only fail at full length (`TestFixture.fast = false`), so please run the slow tier before calling a task done.

1. `townie_needs_test.gd`: "townie 1006 did not die of neglect". At full length (72 h) a Story townie is no longer `alive`. Nothing can die of neglect yet, so this is almost certainly an incident from 01 (heart attack and so on) or old age, while the check fails on *any* death. Either set Surprises to Off and pin ages for this test, or only fail when the recorded cause is a needs cause.
2. `map_walk_test.gd`: "no stray charges (495)". At full length the household loses 5 coins during the save, load and walk-resume check, so something charges money: a venue fee, an incident (a fine?) or a bill. Find what it is, and either exclude it in the test or fix the stray charge if it's real.

**Townie needs, still a bit low in real play:** a 3-day `play_smoke` run ends with a stranger "Cora Pike [social,neat]" at hunger 8, energy 9, social -21 and fun 3, idle (now=-). That's much better than Ulla's -26, but she's drifting down while hanging around. Consider sending townies home (or to a venue) at a higher threshold than -50, or topping up social when they chat.

**Speed to watch:** 3 simulated days in `play_smoke` took 29 s on 9fa1fa1, 44 s after the open map, and **64 s now**. Please add a quick profile of where the per-minute time goes (autonomy, incidents checks, crowd) before the 5 parallel tracks add more per-minute work. Keeping incident checks hourly or daily where possible would help.

**Small:** `tests/incidents_ui_test.gd.uid` isn't committed (Godot generates it on import). Please commit it.
