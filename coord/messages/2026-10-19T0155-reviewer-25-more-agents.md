from: reviewer
to: builder
type: task
re: -
status: open

**25: The owner wants more agents in parallel to speed things up, and fast.** Please scale up now, with these guardrails, which are the lessons from today's broken `main` (shared folder) and the inflated test times (a loaded machine):

1. **One git worktree and branch per agent.** No two agents ever edit the same working folder. Each agent works on `agent/<task>` in its own `git worktree`.
2. **A single integrator (you)** merges finished branches into `main` one at a time: rebase onto `main`, run the import plus the fast tier **on that branch's clean worktree**, merge, push. If two branches touch the same file, merge the smaller one first and have the other rebase.
3. **Split by file ownership:** before starting an agent, list the files and data it owns. Tasks that only add new files and data (`data/incidents/NN_*.json`, new `scripts/systems/<feature>_*.gd`, new UI panels) can run in parallel freely. Tasks that touch shared core (`world.gd`, `autonomy.gd`, `director.gd`, `systems_manager.gd`, `clock.gd`, save and load) go **one at a time**, coordinated with 17.2 (the scheduler), which touches every system's entry points.
4. **Keep the machine responsive:** cap the number of agents running tests at once (roughly the CPU core count minus one), let the rest write code while waiting, and run the slow tier only in the integrator's worktree.
5. **Good parallel candidates right now:**
   - **file-separate:** 18 (sex and pregnancy: new systems plus data, but coordinate `aging.gd`/`family.gd` with the task 16 agent), 21 and 23 (crime path: new files on top of 04/09/20), 22 (vacations and cruise: new maps and venues), 13 and 14 (economy and life areas: mostly new venues, data and systems), 24B (export and import), and the skills expansion when posted;
   - **shared core, so after 17.2:** 10B (multi-floor part B: world core) and 11b (transport: paths and commutes).
6. **The same rules for every agent:** `docs/PERFORMANCE.md` (tiers, cadence, active sets, caps), the multiplayer-ready rules (24A), non-graphic and abstract content, townie statistical versions, and done messages with code in the same push and test lines from a clean worktree.

Please reply with how many agents you're starting, which tasks each one has, and the file ownership split, so the owner and I can see it. I'll keep reviewing each merge as it lands on `main`.
