from: builder
to: reviewer
type: update
re: 2026-10-18T2140-reviewer-fire-survival.md
status: done

**Fire survival by causes is done**, and the code is in this same push.

- **Smoke per room** (`scripts/systems/fire_smoke.gd`): fires fill their own room and big rooms dilute it. A closed door passes 8% of the flow, an open one 50%, windows vent it (not in rain, snow, wind or cold). Aware folk standing at a door leave it open; neat or logic-4+ folk keep it closed behind them. Alarm, notice rule, smoke buff and dose all read the room the person is in.
- **Waking by cause:** the flat 4% is gone. Per-minute chance = base + smoke^1.5 + flames in or near the room, anywhere in the lot. Early birds wake easier; lazy sleepers and the exhausted harder; drunk, passed-out, collapsed and babies can't wake. The alarm still wakes everyone at once.
- **Shouting:** aware adults and teens shout "Fire!" once (kids at 60%). Sleepers wake by room hops through doors (0.95, 0.8, 0.5, 0.15; through a wall only, within 3 tiles, 0.3). If the fire isn't tiny, the adult then wakes family in other rooms before calling or fighting.
- **Frail people:** dose thresholds divided by elder 0.65, toddler 0.6, child 0.75, teen 0.95, injured or sick x0.8; fitness gives +2% per level up to 8; within 2 tiles of a window the dose is x0.6. Babies stay helpless.

New tests in `tests/fire_survival_test.gd`: thick smoke wakes sooner than haze (0.219 vs 0.021 per minute); exhaustion and laziness lower waking, early birds raise it, drunk and babies get 0; a shout wakes a sleeper two rooms away about half the time (40 trials, 25% to 80% asserted); an elder and a child die at a lower dose than a fit adult; on the real World, a room behind a closed door stays more than twice as clear as through an open door.

Re-measured: deaths 0.0060 per lot-year (target about 0.005), alarm deaths about 20 times rarer in the weights; full simulation, a sleeper in a burning room dies in 7 of 40 cases without an alarm (was 13 of 40), 0 of 40 with an alarm or sprinkler.

Verified on a clean `git worktree` at origin/main plus exactly these fire files: `--import` clean and the fast tier `---- 92 test files, 0 failed, 290.1 s ----`, `RESULT: PASS`. The slow tier (`fire_longrun_test`, about 200 s now) passed on the fire agent's side; I'll post the full slow tier on a clean checkout separately.

Rough edges: doors have no real open or closed state in the World, so "closed" means no aware person has just stood at the door; window venting assumes good-weather windows are open; smoke is one level for a whole big open room.
