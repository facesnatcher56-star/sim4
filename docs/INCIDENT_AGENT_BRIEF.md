# Shared brief for every incident-task agent (02..09)

Read first: CLAUDE.md, ARCHITECTURE.md ("Incidents (rare events)"), docs/INCIDENTS.md (schema, handlers, worked examples), coord/messages/2026-10-18T1830-reviewer-rare-events-00-plan.md (program rules) and 2026-10-18T1840-reviewer-rare-events-08-whole-town.md (everything applies to townies/lots: FULL mode near, STATISTICAL mode far, chronicle hook, notify_policy), plus your own task message(s).

Standing rules (owner): think as the PLAYER (warnings, counterplay, readable text, no jargon/ids, they/them pronouns, NON-GRAPHIC tone: events are shown as notifications/short collapses/fades, never gore); keep it SIMPLE; small focused files (<~400 lines), no god files; decide directly.

Conventions:
- Your content goes ONLY in your own files: data/incidents/NN_<task>.json, data/death_causes/NN_<task>.json, scripts/systems/<task>_*.gd (+ handlers), tests/<task>_*_test.gd. Do not edit shared data files. Buffs/objects/interactions go in your incident file's `content` section (ContentMerge). Small additive hooks in shared code (systems_manager, hospital, story...) are OK: re-read the file right before editing, keep edits minimal, and list them in your report. Other agents work in parallel on other tasks — never revert their changes.
- Every event: data-driven rates (per household per game year, 28-day years, Rare default), force hook (`Incidents.force`), prevention/softening counterplay, warning signs where realistic, save/load safe, reset-safe, deterministic seeded rng, statistical version for far townies, chronicle hook, notify_policy so toast volume stays low.
- Tests: one focused test per event (forced) in the fast tier (keep each file fast; whole fast tier must stay near ~140 s: if you add long sims put them in `tests/<task>_longrun_test.gd` and add that file name to the SLOW list in tests/run_all.gd with a tiny edit), plus a slow long-run statistical test checking rates against the task's targets.
- Windowed screenshots (tests/*_shot.gd patterns) of new visuals/UI; Read them and fix obvious problems. Delete throwaway screenshots/scripts before finishing.
- Tools: Godot exe C:\Users\lloyd\AppData\Local\Godot47\Godot_v4.7-stable_win64_console.exe; `--headless --path . --import` after class_name changes (retry if another agent is importing; ignore their transient parse errors and report); run single tests with `--headless --path . --script res://tests/run_one.gd -- <name>`; fast tier `--script res://tests/run_all.gd`; slow `-- --slow`. Blender 5.1 at C:\Program Files\Blender Foundation\Blender 5.1\blender.exe for any new models (blender/ build_extra pattern; keep models simple; box fallbacks exist).
- Do not commit or push. Final report: what landed, per-event target rate vs measured, hooks you added in shared files, tests with exact result lines, rough edges, and extra events you added.

## Hung-run rule (all agents)
Headless Godot does NOT quit on a script error or parse error: it hangs until something kills it. Always run Godot through the guard, never bare:
`powershell -File tools/godot_guard.ps1 -Seconds 120 -Args "--headless","--path",".","--script","res://tests/run_one.gd","--","<test_name>"`
It kills Godot immediately on SCRIPT ERROR / Parse Error / Failed to load script, or after N seconds with no output, prints the tail of the log and exits non-zero. Use -Seconds 120 for single tests, -Seconds 300 for the fast tier, -Seconds 600 for slow tests/--import on a cold cache. Never leave a command without a timeout; if a run is killed, read the log, fix the error, rerun. If the same run hangs twice, stop and report instead of retrying.

## Multiplayer-ready rules (task 24 part A, all agents, from now on)
1. Every player action is a COMMAND `{player_id, folk_id, action, args, game_minute}` through one command layer (`SimDirector.command` today; build-mode, career, travel and dialogue choices too). UI code never mutates sim state directly.
2. Determinism: all randomness from seeded rng streams owned by systems (no unseeded `randf()`/`randi()`/`RandomNumberGenerator.new()` without a seed in sim code); the sim never reads frame time or the OS clock; the per-minute order is stable. Same seed twice => same state hash after N days.
3. The sim is separate from the view: no sim decisions in view code; view state is never saved as sim state.
4. Everything is serialisable at any minute (mid-interaction, mid-trip, mid-fire, mid-trial) and loads identically.
5. Keep `household_id`s generic: use the `players` table (player id -> household id) once it exists; never assume household 1 is the player in new code.
