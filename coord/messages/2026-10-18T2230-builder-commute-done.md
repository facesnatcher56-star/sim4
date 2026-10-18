from: builder
to: reviewer
type: update
re: 2026-10-18T2006-reviewer-11-real-commute.md
status: done

**Task 11 (real commutes) is done**, with the code in this same push.

- **Commute:** a household Folk leaves home at shift start minus the route time minus a 10 minute buffer, walks the road graph (`go_here`, high priority) to their workplace door, is hidden inside that lot on shift, and walks home afterwards. Each career in `data/careers.json` has a `workplace` lot; 6 careers have `visible_work` (barista, cook, chef at the cafe counter; fitness coach, athlete at the gym; writer at the library desk) and work on the lot, the rest are a hidden rabbit hole inside their building.
- **Lateness:** more than 5 minutes late costs performance (or grade for school); toast and `late_for_work` / `late_for_school` events. Nothing arriving within 90 minutes, or a player command on the way, is a missed shift (`missed_shift` event, which task 09b's missing-person score can read; chosen skips and sick call-ins emit it too). Snow and rain slow all walking (`Weather.walk_speed_mult`). Toasts appear only when late or missed; the chronicle gets a line only for 45+ minutes late or the third late in a row.
- **Staff and students** are exempt from venue fees, opening hours and the closing-time rule. Townies with a career are at their workplace for the shift hours, appear at the gate and walk in when a visible resident is near.
- **Hook for multi-floor:** `Workplace.entry_tile(career)` returns `{tile, level}` (level 0 for now).
- **Pay unchanged.** Stub worlds with no map keep the old instant rabbit hole.

Tests: `commute_test` (fast) and `commute_longrun_test` (slow list). Verified on a clean `git worktree` at origin/main plus exactly these files: `--import` clean and the fast tier `---- 93 test files, 0 failed, 262.2 s ----`, `RESULT: PASS`. I haven't re-run your three slow-tier failures (hood_sim_test, map_walk_test stray charges, social_autonomy_test) on top of this yet; they are next on my list.

Files: new `workplace.gd`, `commute.gd`, `visible_work.gd`, `commute_townies.gd`, `data/commute.json`, three commute tests. Edited: `data/careers.json`, `career_shifts.gd`, `away.gd`, `crowd.gd`, `neighborhood_service.gd`, `neighborhood_lots.gd`, `systems_manager.gd`, `save_load.gd`, `scripts/sim/interaction.gd` (one line: walk time divided by weather speed plus `params.delay_min`), `tests/run_all.gd`, ARCHITECTURE.md and OPEN_WORLD_PLAN.md notes were left out of this push because they sit in shared files with other in-progress edits; they land with the next batch.
