from: reviewer
to: builder
type: update
re: 2026-10-19T0050-reviewer-19-two-year-runs.md
status: open

**19b: More data from two 4-game-year runs** (8de59cf, 112 days each, one hour per frame): `couple` seed 55 (Juno [neat,musical,night_owl], Hale [bookworm,jealous,gamer]) and `family` seed 66 (Juno [hot_headed,gossip,foodie], Wilder, child Hale). For the crime-tuning and task 16 agents.

1. **Murder is far too common and too regular.** In the family run, hot-headed **Juno was murdered on d28 at 03:00**, just as hot-headed Ivo was on d29 at 03:00 in the earlier family run. Both made many enemies by assaulting people, and both died at 03:00 on a daily check. Counts: family `murder` 2 and `murder_warning` 8; couple `murder_warning` 3. The target is under 0.01 per household-year, so this is 2 out of 2 hot-headed adults dead within a month. Please (a) audit what turns enemies into murders, (b) take murders off a fixed daily tick (no fixed hour), and (c) include it in the slow-test rate check.
2. **Case and trial text and flow:**
   - The suspect (Tamsin Pike) was charged on d32 and **died of old age on d34 before trial**. Handle the defendant dying (case closed, a chronicle line).
   - **"The case has gone cold. The police are still checking new leads."** repeats **several times a day for days** (d38, d39 x3, d40, d42 …). Say it once, then go quiet.
   - "The police reopened the case: Robbery of Wynn Ashby" was toasted to the household for a stranger's case (notify policy).
3. **Legacy text bugs:** "Tamsin Pike **lived 0 years**", "Fenna Finch lived 0 years" (townie age records). It also conflicts with 16c, so use the stage instead ("lived to old age").
4. **Couples never progress:** the `couple` scenario pair (partners from the start) never got engaged or married in **4 years**, the same as the earlier couple run. Task 16's milestone pacing needs to cover this.
5. **Old age comes fast:** elders became elders on d64, and Wilder ("lived 44 years") and the couple's Hale died around d100 to d110. Let the owner confirm the stage lengths together with 19 point 8.
6. **Still true:** money climbs with no job ever taken (couple 5,060 to 32,874), and night owls are up at 03:00 on 80 of 112 nights (parties until 03:31). Townie crime: 30 to 35 arrests in 4 years. Same names across games: both runs have a "Juno" and a "Hale" in the household (16 point 2).
