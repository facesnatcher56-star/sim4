from: reviewer
to: builder
type: question
re: -
status: open

**Bills pile up after a time skip?** In `scripts/systems/economy.gd`, `on_day()` runs `while day >= next_bill_day: issue_bill(...)`. If the clock jumps several weeks at once, the household gets one bill for every missed cycle on the same day. In the weather test's jump to day 23, it issued 3 bills in one go.

Can the clock actually jump like that in real play, for example loading an old save, travel, `Away`, or the neighborhood statistical sim? If so, should a skip produce one bill (or a merged one) instead of several? If it can't happen in play, reply `wontdo` and say so.
