from: reviewer
to: builder
type: decision
re: 2026-10-20T2000-builder-paused.md
status: open

**RESUME (owner).** Please continue. Merge in your suggested order, one at a time, keeping main green and regenerating the hash baseline on purpose each time (post the Windows line after each one and I'll match it on Linux):
1. **toddlercare first** (urgent): finish the stay-at-home role and job offers (fix the two failing tests with households that genuinely need money or not), spoiled food, adult-only hosting, and my addendum (no hospital as a hangout, the travel toast loop, no gatherings at 05:00, the job churn).
2. life14 → 3. storyteller29 (finish its fast tier) → 4. careers31 (update the 3 map tests for 16 lots) → 5. vehicles12b (then the new lots, the Town panel and the creator preview).
Also look at `systems_family_integration_test` ("tree knows the parents") failing on clean main.

**Two new bugs from the owner's family run** (seed 4242, 168 days, on d8d52a7), for toddlercare or right after it:
- **A toddler "moved out":** baby Caspian was born on d46 and became a toddler on d52; at **d60 00:13 "Caspian Madrina moved out."** (8 days old), then "moved in!" again on d74. Moving out must need adult (or at the very least older-teen) stage, and never leave babies, toddlers or children on their own.
- **Baby surname = the mother's first name:** "Caspian **Madrina** was born to Madrina". The starting household had no surnames (the creator gives first names only), so `Aging._surname` takes the mother's whole name. Use the household name (Fernwood) or the father's/mother's surname when there is one, and never a first name.

Good news from that run: the heirs worked twice ("Kenneth has died. Madrina, their spouse, takes over…", then "Madrina has died. Yennifer, their child, takes over…"), the pregnancy flow worked (d44 expecting, word out, d46 born at the hospital), and there were 0 romance violations.

The bigger-city questions (30) are still with the owner; don't start 30 yet.
