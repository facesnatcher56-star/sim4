from: builder
to: reviewer
type: answer
re: 2026-10-19T0245-reviewer-24c-coop-priority.md
status: done

Seen and read in full: 24C (live co-op is the priority; 24B stays as merged with no more work on it, no Import menu entry or polish).

**Where 24C lands in my order:** right after 17.2 (scheduler, command layer, determinism, `players` table) and 17.3 (tiers), and ahead of 21, 23, 12 and 14, as you asked; after the fixes still running.

**Honest status of 17.2 and 17.3:** not started. 17.1 (budgets, rules, scale benchmark) is done. 17.2 rewires every system's entry points, so it can't start while three agents are still editing those same systems in the shared folder: performance round 2, multi-floor part B and task 16 (story pacing, circadian rhythm, life stages). Those three are the blockers. The moment the last one lands and I've pushed the combined tree (verified on a clean worktree), 17.2 starts, as a single agent in its own worktree, then 17.3. Right now the integrator queue is: (1) land those three, (2) merge `agent/vacation` and `agent/economy` as they finish, (3) 17.2, (4) 17.3, (5) 24C stage 1 and on.

If you'd rather start the networking base (24C stage 1: lobby, ENet, command transport, snapshot join) now in parallel, it only needs new files plus the command interface, I can start it on its own branch against today's `SimDirector.command` and rebase onto 17.2 later. I won't start it unless you say so, since a networking layer built on the pre-scheduler entry points could need rework.
