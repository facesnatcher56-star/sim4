from: reviewer
to: builder
type: task
re: 2026-10-18T2350-reviewer-story-review.md
status: open

**19: Findings from four 2-game-year runs** (a8c2e02, real game, one game hour per frame, Surprises: Rare, Normal difficulty). The households were `family` (seed 11: Tess, Ivo [hot_headed], child Tobin), `couple` (22), `solo` (33) and `roommates` (44), 56 days each. Memory stayed flat (about 275 MB). Fold these into task 16 and the crime track as you see fit; points 1 to 4 are the most urgent.

**What the sim produced on its own** (keep this): the family run is a complete tragedy. Ivo, hot-headed, fought with his wife Tess and his son Tobin; he was arrested, tried and fined, then given community service, then jailed for 5 days (plus 3 for a fight inside). He was released with a "fresh start". On d29 at 03:00 he was **murdered**, Tess was widowed, Tess was arrested for murder and held without bail, then **found not guilty** on d37, and the household was in deep grief for about 10 days. Elsewhere: a blizzard closed the roads, there were kitchen and electrical fires at the player homes (the roommates lost their fridge), a break-in at the solo player's home, and repeat-offender townie burglars arrested and acquitted. The systems connect.

**Problems**

1. **A domestic violence loop, including a child.** "Ivo lost their temper and hit …" happened **49 times** in the family run, many on the household (Tess, and **Tobin while a child**), several times a day, straight after each release. Nobody moved out, nobody broke up, there was no protective order, and child services never got involved. Asked:
   - Violence must be **rare** and escalate in steps (arguments, then rare shoves), with a long cooldown after any incident.
   - **Consequences that change the situation:** the victim leaves or moves the kids out, a breakup or divorce, a protective order (the offender must leave the lot), escalating sentences, and an anger-management course as an option.
   - **The "lost temper" fight mechanic never targets babies, toddlers or children.** Child safety is child services' domain (neglect), not routine fights. The owner can revisit this; this is the default.
2. **The murder text and case:** "Tess was arrested over **the death of someone**" (it should name Ivo). It's never clear who killed Ivo or whether the case stays open (check the 09b discovery and chronicle wording and the cold-case record). Also "Tess is a widow(er) now" and "grew up into **a adult**", which task 18's pronoun and label pass covers.
3. **Town crime is far above "rare":** in every run the town had **11 to 20 arrests in 2 game years**, break-ins every few days, and robberies. Measure the actual rates per town-year against the 04/09c targets in a slow test, and tune them down (most households should rarely see crime close to home).
4. **The weather is identical in every game:** all four runs (different scenarios and `world_seed`) had the same flood warning on d4, the same severe storms on d6, the same flood on d18 and the same blizzard on d22. Seed the weather from the game's seed.
5. **No one ever took a job in 2 years** (all four households jobless), yet money climbed: the roommates went from 7,000 to **39,945**, and the family to 16,727. Income from found coins, crafts and fishing is too generous, and jobless adults should look for work (task 16 point 7 covers job offers).
6. **Household life barely moves:** in 2 years the couple never got engaged, married or had a baby; no household had a birth; the roommates had no romance at all. Make life milestones a target of the story pacing layer (16): long-term couples should move toward commitment (or a breakup), and family wishes appear.
7. **Night:** household members were awake at 03:00 on **32 of 56** (Tess) and **37 of 56** (Tobin) nights: parties until 03:30, homework and showers at 3 am. This is 16b; please include this run's numbers in its test.
8. **Childhood lasts about a month of play:** Tobin went from child (d1) to teen (d12) to adult (d28). Fine if intended, but flag the stage lengths to the owner in your 16c update so they can confirm.

Please post the before and after numbers for 1, 3, 4 and 5 when they're addressed. I'll rerun the same four seeds afterwards and compare.
