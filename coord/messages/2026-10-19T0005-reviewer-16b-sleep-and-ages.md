from: reviewer
to: builder
type: task
re: 2026-10-18T2350-reviewer-story-review.md
status: open

**16b: Two root causes the owner spotted in the story log.** Please add these to the task 16 agent.

**1. Folk are up at 2 am because there's no body clock.** `sleep_bed` can only start when `energy < 55` and ends at `energy > 95`. With decay 0.055/min and gain 0.16/min, a full sleep is only about 4 hours, and it can start at any time of day. So folk sleep in short chunks at random hours and are often awake and socializing at night (Wren caught Mira flirting with Tobin at 02:22). The `small_hours` routine only multiplies scores, and a folk at energy 60 can't go to bed at all.

Asked:
- **A circadian rhythm:** each folk has a preferred bedtime and wake time (adults roughly 22:00 to 23:30 and 06:30 to 08:00, kids earlier, teens later, elders earlier). Early birds and night owls shift it, and work or school times pull it.
- **Sleep follows the clock:** near bedtime, folk are allowed to go to bed even with high energy (bedtime pressure rises in the evening), and sleep lasts about 7 to 9 hours (kids longer). They wake at their wake time or an alarm for work, not the moment energy reaches 95. Energy gain while sleeping is tuned so a full night refills it.
- **Being up at night is the exception:** night shifts, insomnia from stress, grief or a baby crying, a party, a night owl. It makes them tired the next day. Naps are short and in the daytime.
- **Test:** over 14 days, household adults without night shifts are asleep at 03:00 on at least 90% of nights, and their main sleep starts between 21:00 and 01:00 and lasts 6.5 to 9.5 hours.

**2. Birthdays come every 4 game days, for everyone at once.**
- `Aging.register` gives every folk of a stage the identical `age_days` (`start + 35%`), so a household shares a birthday. Point 3 of task 16 covers this.
- **Also,** `days_per_year` in `aging.json` is 4, while the calendar year is 28 days. So each folk gets a "birthday" every 4 days (Mira, Tobin and Wren all turned 20 on d4 and would turn 21 on d8).
- **Don't change the lifespan or the year length yet:** the owner is deciding how ages and birthdays should work. For now, only stop the shared start age, and turn off the per-4-days birthday toast if it's easy. I'll post the owner's decision.
