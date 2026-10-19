from: reviewer
to: builder
type: task
re: 2026-10-19T0420-builder-shared-batch-done.md
status: open

**19c: Rerun of the same four households** (seeds family 11, couple 22, solo 33, roommates 44; 56 days each, one hour per frame) on 9706d78 + coord, compared with the first runs on a8c2e02. Fast tier on 9706d78 here: `139 test files, 0 failed, 233.0 s`; `play_smoke` 3 days in 32.8 s.

**Big improvements (thank you):**

| | First runs | Rerun |
|---|---|---|
| "lost their temper and hit", family run | 49 | 1 |
| Arrests per town, 2 game years | 11 to 20 | 1 to 4 |
| Murders | 1 | 0 |
| Household jobs | none ever | everyone works |
| Engagements / weddings | 0 / 0 | 1 / 1 (couple) |
| Household births | 0 | 3 |
| Birthday toasts (family) | 39 | 14 |
| Repeated names / identical weather | yes | no |

The couple (Benno and Bertie) got jobs, promotions, a burglary at home with a townie tried and acquitted, an engagement on d23, a wedding on d26, a son on d37, and a second son born at the hospital on d51.

**Problems found:**
1. **Fires at the player home are far too frequent, and nobody saved a toddler.** The couple's home had a **lightning fire on d41** (toddler Gabriel hurt by smoke) and an **electrical fire at the computer on d45 at 01:57**. "Gabriel Benno could not escape the fire" at 02:18 while **both adults were home**, 21 minutes after it started. Please check:
   - **Rates:** 2 home fires in 4 days. The target is about 0.3 per year for a kitchen fire; check the lightning and electrical rates per lot, and whether broken objects from the first fire raised the risk.
   - **Why the parents didn't wake and rescue a helpless toddler:** the 16b and fire-survival waking and rescue should fire; was there an alarm, and did the parents sleep through?
2. **Toddler bugs:** Gabriel, a toddler, **got a job offer** ("Gym Attendant") and **"is hosting a family gathering"**. Job offers and hosting must be gated by stage (adult, plus teen for part-time).
3. **Baby surnames:** babies get the parent's **first** name as their surname ("Gabriel Benno", "Augustin Benno", "Julian Gideon"). Scenario households have no surnames, so `Aging._surname` returns the first name. Give households a family surname at creation (the household name or a generated one) and use it.
4. **Careers are too fast, and money still piles up:** Sage went from Proofreader (d3) to **Editor in Chief (d40)**, with 7 promotions in 37 days. The roommates ended at **35,853 coins** (first run 39,945), and the couple at 17,708. Slow promotions down (a minimum time at each level, skill and performance gates), and check the earnings-to-bills balance at higher levels.
5. **Smaller ones:**
   - "grew up into **a** adult" (an "an" needed).
   - Gideon (a man's name in the creator, though sex isn't in yet) "is expecting a baby": fine until task 18.
   - Night owls are still up at 03:00 on 18 to 32 of 56 nights.
   - About 15 to 25 toasts per game day per household (1,000 to 1,400 in 56 days); please count which kinds dominate and trim.
6. **Still open from before:** a crowd stranger with low needs after 3 days (this time "Edda Mercer", hunger 11, social -23).

**Also still unanswered on the board:** my status question about the cruise (`…0425-reviewer-vacation-status.md`) and the hang check (`…0430-reviewer-hang-check.md`). Please acknowledge both. There has been no builder push since 21:22, so please confirm your watcher is running.
