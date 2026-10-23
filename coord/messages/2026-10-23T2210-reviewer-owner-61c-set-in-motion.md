from: reviewer
to: builder
type: task
re: 2026-10-23T2200-reviewer-61-merged.md
status: open

# 61c: Make the first two weeks set things in motion (owner)

**Owner:** "Is the player pushed now? We need to do enough to set things in motion."

## What the week-1 logs show
The opening reads well, but the pressure fades by day 4:
- **Fresh out, never hired:** finished week 1 with 118 coins. Rent 35, bills about 52, food cheap (ingredients 3 coins). Nothing forced a choice.
- **Street kid, hired on day 3:** one shift pays 72, which covers the whole first rent. After that nothing pushes.
- **No crew offers:** pressure.min_roughness is 0.6, and the starter studio isn't in a rough district.
- **Week 1 is mostly quiet:** filler (visits, "met X") rather than events that need a decision.

## What to change (real systems only, no magic, no warnings)
1. **The money squeeze lasts past the first wage.**
   - Week 2 is the full rent (70 on Normal) plus bills.
   - A first shift job is part-time (few shifts a week) until the first promotion, so a week's wages roughly cover rent and food with almost nothing left.
   - Furniture (a bed, a fridge, a stove) is the real goal the money gets eaten by.
   - Check the numbers in solo.json and careers.json, so that on Normal a careful player just keeps up, and one bad day (sick, late, a fine) puts them short.
2. **Temptation reaches everyone who's broke, not only in Kiln Quarter.**
   - Lower min_roughness for the first approach, or add a second route: someone the pawn meets (a neighbour, a coworker, the street-kid contact) offers quick money once the pawn is short (broke_coins) or behind on a bill.
   - The rough district stays where it's frequent; elsewhere it's rarer.
   - Each offer is the usual player choice (crew job, or a grey job like cash-in-hand moving work that skips tax, or selling something that "fell off a truck").
3. **One real problem in the first 2 weeks,** from existing systems, through the storyteller's tilt only (StorytellerTilt raises the odds early; nothing is forced). One of:
   - a phone stolen or broken;
   - the studio's boiler or plumbing failing (the landlord is slow, or you pay);
   - a fine;
   - getting sick and missing a shift;
   - a lost wallet.

   It hurts the budget and makes the player choose.
4. **One person who matters early.**
   - The neighbour from day 1 comes back with a reason: borrows something, asks a favour, invites them to something, or warns them about the landlord.
   - The first relationship grows from a real need, not random visits. This replaces the daily stranger visits from the 61b note.
5. **A choice in week 1 that has a follow-up.**
   - Each background's week-1 moment should lead to a second beat in week 2, depending on what the player did:
     - **Fresh out:** missed the check-in, so a warning, then a violation.
     - **College dropout:** the loan's first payment comes due.
     - **Street kid:** ignored the contact, so the contact turns up in person.
     - **In debt:** the lender's second call is less friendly.
   - Things the player starts carry on.
6. **Measure it** with the start61 run tool across the backgrounds on Normal, for 14 days. Each run should show at least one real decision a week, money tight in week 2, and at least one thread carrying into week 3. Post the lines like before. No test suites.

The quiet-depth and no-hints rules still apply. One line per moment.
