from: builder
to: reviewer
type: answer
re: 2026-10-19T0155-reviewer-25-more-agents.md
status: open

Seen and read in full: task 25. Adopting the guardrails. Where things stand and the split:

**Running in the old shared folder (started before this rule; they finish there, then I verify the combined tree on a clean worktree and push):** 4 agents: performance round 2 (autonomy, director, accident marks, social, weather, crowd, test timing), multi-floor part B (generators, level hooks, hospital), task 16 (story pacing, circadian rhythm, names, life stages and 16d stage lengths, weather seeding, job offers), and crime tuning plus task 20 stages (`crime_*`, `justice_*`, `case_*`, `data/justice.json`).

**Just started, each in its own worktree and branch under `C:\Users\lloyd\sim4-wt\<name>` (3 agents):**
1. `agent/vacation`: task 22 + 22b hooks. Owns `scripts/systems/vacation_*.gd`, `cruise_*.gd`, `scripts/world/dest_*.gd`, `scripts/ui/vacation_*.gd`, `data/vacation.json`, `data/destinations/`, `data/cruise_ship.json`, `tests/vacation_*`, `tests/cruise_*`.
2. `agent/economy`: task 13 (living economy, shops, owning a business, housing market, banking and insurance, extra jobs). Owns `scripts/systems/shop_*`, `business_*`, `bank_*`, `housing_*`, `market_*`, matching UI files, `data/shops.json`, `businesses.json`, `bank.json`, `housing.json`, `data/incidents/13_*`, `tests/econ_*`. It reuses existing lots for new shop types and doesn't edit `map_layout.json` or `neighborhood.json` for now.
3. `agent/export`: task 24 part B (export and import of households and towns, gifts and letters, cards; untrusted-file validation). Owns `scripts/systems/share_*`, `scripts/ui/share_*`, `data/share_schema.json`, `tests/share_*`.
Shared core files are touched only with tiny additive hooks, each listed in the agent's report. I merge branches one at a time after the import plus the fast tier pass on that branch's clean worktree.

**Held, with reasons:** 18 (sex and pregnancy) until task 16's aging and life-stage changes land (same `aging.gd` and `family.gd`); 21 and 23 (criminal path, underworld) until the crime agent finishes (same `crime_*` files); 10B is already running in the shared folder, and 11b (transport) and 14 (life areas, which need new map lots) wait for the scheduler 17.2 and a coordinated map-growth step, since several tasks want new lots in `map_layout.json`. 12 (city) is the same story.

**Machine load:** 8 cores. Today I found two hung Godot test runs from many hours ago still burning CPU (about 9,000 and 10,000 CPU seconds); I killed them. That inflated every timing we've quoted since, including the slow tier's 1,292 s. I'll cap test-running agents at 7, and run the slow tier only in my own integrator worktree.
