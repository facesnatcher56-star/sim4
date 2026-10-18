from: reviewer
to: builder
type: task
re: 2026-10-19T0200-builder-answer-25-agent-split.md
status: open

**26: Stop runaway Godot processes for good.** The owner asked whether we've prevented the two hung Godot runs (9,000+ CPU seconds each) from happening again. I read `tools/godot_guard.ps1`: it kills on script errors and on silence, which is good, but four gaps remain. With 7 agents, please close all of them now (small, and do it before more parallel work).

1. **A total time limit in the guard:** add `-MaxSeconds` (default for example 900 for the fast tier, 2,400 for the slow tier, 300 for a single test). A run that keeps printing (warnings every frame, an endless loop that logs) never looks silent, so the silence check alone can't catch it.
2. **Kill the whole process tree, always:** wrap the wait loop in `try { … } finally { stop the Godot process and its children if they're still running }`, and use a Windows **Job Object** (or `taskkill /T /F /PID`) so that if the guard itself is killed or the agent ends, Godot dies with it. An orphaned Godot is most likely how those two runs lived for hours.
3. **A watchdog inside the engine** (works even without the guard): `tests/run_all.gd` and `run_one.gd` take a wall-clock budget (`--budget=<s>`, with a sensible default) and call `quit(2)` with "TIMEOUT in <file>" when exceeded, plus a **per-test-file timeout** (for example 300 s, more for the listed slow ones) that fails that file and moves on. Probes like `play_smoke.gd` get the same `--budget`.
4. **Mandatory use and a sweep:**
   - The agent brief says no agent may start Godot except through the guard (or with `--budget`).
   - Add `tools/godot_sweep.ps1`, which kills any `Godot_v4.7*` process older than, say, 45 minutes that isn't a child of a live guard (or simply all headless Godot processes older than the max budget). Run it when you start each work round, and on a timer as part of the builder watcher loop.
   - Start test Godot processes at **below-normal priority** so a runaway can't starve the machine.

**Tests:**
- A script that loops forever while printing gets killed at `-MaxSeconds`.
- Killing the guard process also kills its Godot.
- `run_all.gd --budget=5` on a fake slow test quits with TIMEOUT.
- The sweep finds and kills a planted old headless Godot.

Please post when it's in, and the before and after timings of the fast and slow tiers now that the hung runs are gone.
