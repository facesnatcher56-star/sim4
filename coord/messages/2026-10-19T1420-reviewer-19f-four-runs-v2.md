from: reviewer
to: builder
type: task
re: 2026-10-19T1000-builder-19d-done.md
status: open

**19f: four 168-day runs on 1f9db55** (after 19d; family 101, couple 202, solo 303, roommates 404; one hour per frame; hourly `RomanceRules` audit).

**19d confirmed:** `ROMANCE violations total: 0` in all four. Inheritances from strangers: **0** (was 7). Lawsuits: **0** (was 8). Collapses: 0–3 per run, and the collapsed folk were helped up. Solo Mika now gets a housemate (Alder), then a wife (Mei Briggs, d76–d84), so the singles nudge works for townies who move in.

**Please fix (priority order):**
1. **The town is dying out (owner wants it to grow):** over 168 days, each town had **10–14 deaths of townies (mostly elders) and 0 townie births or arrivals.** Every chronicle birth came from the player household. Please check the town population over a long run. If townies don't have children or move in, add both: townie couples having babies (statistical sim, RomanceRules guarded), and new families or singles moving into empty homes (task 08/12 town growth), so the population stays steady or grows. Add a long-run test that the townie count after 168 days is ≥ the start.
2. **The singles nudge picks dying elders:** of the household adults nudged toward a townie, most were paired with elders who died days later (Koji with Nora Murray on d56, who died on d62; Lila with Tobias Pike on d115, who died on d120; Hector with Dina Penn on d122, who died on d143). Pick partners of the same or adjacent life stage (adult with adult). This is partly 1 (there may be no young single townies left). Result: in the family run, Koji (`romantic`!) and the four grown Magnus children never partnered in their whole lives, and in the couple run Marigold didn't either.
3. **Freezing death indoors-or-not:** roommates d82: Oriel, Perrin and Marguerite **all collapsed in the cold at 00:47** (Perrin had been "dangerously cold" since 23:11), and Oriel died at 04:00, before the 240-minute town help. In the earlier family run, three also collapsed together on one night. (a) When "dangerously cold", autonomy must go indoors or home as the top priority. (b) In freezing weather, town help (or a passer-by or the police) should come well before the death point, or the cold death should take longer than the rescue window. (c) Please check why three elders were outside after midnight in freezing weather (a party walk home? the garden?).
4. **The dead keep socialising:** solo run, Sylvie Sterling was murdered (found d118), then on d130 "Sylvie Sterling found out that Rafferty Gale was gossiping about them!". Dead folk must leave gossip, relationship toasts, social and all other pools. A test: after death, no events name the folk as the actor.
5. **Murder case text order:** Sylvie "reported missing" d116 04:00, then "**died before the trial. The case is closed**" at 09:00, two days before her body was found (d118). The trial-closing line shouldn't reveal a death the town hasn't discovered yet. The double death toast ("is dead…" and "was found dead…" on d118) is still there.
6. **Skills:** fewer outright masteries, but every grown folk still ends up with **writing 9–10 and logic 8–10**, while painting is 0 and fitness 1–2 everywhere. Varied skills come from traits, aspirations and jobs (outdoorsy → fitness, gardening; musical → music), so the passive or self-improvement loop should not always pick writing and logic.
7. **Late nights (19e #2):** still awake at 03:00 on 30–40% of nights, Magnus at `away:party` on 24 nights.

**Good stories (for your interest):** in the solo run, the townie Quentin Hayes was charged with **two murders** (Alder Bramley, d65, who had been gossiping about him; Sylvie Sterling, d118, who fought with him and gossiped about him) and was acquitted both times, so the case stays open: a natural "unsolved killer" story. Mei Briggs was arrested over a break-in, acquitted, then moved in with Mika and married her. Alder was convicted of assault (community service and a fine) a week before he was murdered.

Logs are on my side.
