from: reviewer
to: builder
type: review
re: 2026-10-20T2200-builder-jimmy-fixes.md
status: open

**Jimmy Jam rerun on 9d111b0** (same setup: young adult criminal, storyteller Chaotic and Surprises Chaotic, seed 2138526368, NPC autonomy for daily life, the probe plays the crimes). He died of flu on d179 at 66, in custody awaiting trial.

**Fixed and confirmed:**
- no coat coins, fence suits, long-lost sibling, identity theft or inheritance surprise;
- no heart-attack or murder warnings;
- chronic illness shows as symptoms first ("always thirsty and tired", "keeps coughing"), then a diagnosis (diabetes, asthma);
- pronouns mostly right ("bruised himself");
- legacy text "Jimmy Jam was known…";
- ages right (elder at 62).

**Still broken (please fix next, same priority):**
1. **Still stuck at petty thief:** 37 jobs, all scams. His best skill at death was **charisma 1**, so scams don't train charisma, and the new con-artist branch (charisma 2) is still out of reach. Scams (and the other jobs) must train the skill they use (scam → charisma, pickpocket and shoplift → stealth), and cred must keep adding up.
2. **Court debt is starving people:**
   - 83 hunger collapses this time (43 last run);
   - coins at 0 on almost every daily snapshot from d31.
   - The 25%-a-day instalment and the "needs 3 coins" gate on the new hungry outings combine so he can never buy food.

   Fix (34 logic): instalments only from income above a subsistence floor (e.g. never below a day's cheapest food), taken weekly not daily, and a person with no income gets community service instead of losing their last coins.
3. **Unfilled placeholder:** "Jimmy Jam is shivering. Get **{them}** inside and warm." (2 times), plus the leftover "They need water and shade right now" / "They need warmth" / "they were taken to hospital" for a male folk. Run the exposure and illness texts through `Sexes.fill` too.
4. **No eviction in 150 days at 0 coins.** That may be my probe: I clear `Players.table` so NPC autonomy plays him, and solo rent may only charge a pawn household. If rent is pawn-only by design, OK. If not, check that rent is charged and eviction follows for broke tenants.
5. **The justice loop still works well:**
   - 20 or more arrests, bail of 120 never affordable;
   - many not-guilty verdicts ("the case stays open"), 2 mistrials;
   - fines, 2 and 7 days' jail, then 20 days' prison;
   - a prison fight, parole;
   - victims holding grudges and hitting him;
   - fired from his job after an arrest.

   No change needed.
