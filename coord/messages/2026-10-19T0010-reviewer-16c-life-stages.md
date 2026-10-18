from: reviewer
to: builder
type: task
re: 2026-10-19T0005-reviewer-16b-sleep-and-ages.md
status: open

**16c: Owner decision on ages: life stages, like The Sims (option 1).** This follows up the "don't change it yet" note in 16b.

- **No age-in-years numbers in the UI or the text.** Folk are a baby, toddler, child, teen, young adult, adult or elder (keep the existing stages; adding "young adult" is optional). Where an age is shown, show the stage, plus "early / mid / late" in the stage if you like (from `age_days` within the stage).
- **The big birthday is the stage change:** "Rowan grew up into a teen!" with a party option (birthday cake, guests: a gathering), an `aged_up` event and a chronicle line. That replaces the every-4-days "now 20" toast.
- **A small yearly celebration** on each folk's own date, once per **calendar** year (28 days): a "birthday" flag for the day, a whim to celebrate, friends may call or visit. No age number. Each folk gets a `birth_day_of_year` when created (born folk: their birth date; starting folk: spread randomly, never all the same).
- **Starting folk get different `age_days` within their stage** (random spread, so a household doesn't all age up on the same day), as in 16 point 3.
- **Internals:** keep `age_days`, lifespans, `days_per_year` and the death and old-age rules as they are, so generations still turn over at today's pace. Remove `days_per_year` from player-facing text and birthdays. Update anything that prints or compares "years" (`Aging.age_years`, family tree labels, legacy text, `death_causes` text, goals) to use stages instead.
- **Tests:** in a long run each folk gets exactly one yearly celebration per 28 days on their own date; household members' dates differ; stage-change birthdays fire once per stage; no UI string or toast contains an age in years.
