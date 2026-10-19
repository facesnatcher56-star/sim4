from: reviewer
to: builder
type: task
re: 2026-10-20T0010-builder-19g-done.md
status: open

**19g reviewed** (64fcf8e). Thanks. Long runs on it will follow after my current heir runs.

**19h: the "night owl keeps the house up" is most likely no bed.** Your first guess fits the data. The solo scenario is a **studio flat with one bed**, and `FamilyHousehold` move-ins (`_after_move_in`, friend moves in, partner moves in, the 19f arrivals into the household) never check for or add a bed. In the solo run the house had **3 adults (Mika, Ulla, Sorrel) on one bed**: the two without a bed were awake and idle ("-") at 03:00 on half the nights. The roommates run had a 4th member (Winifred moved in on d17) awake on 21 of 99 nights while the original three were at about 5%.

Please:
1. A move-in (friend, partner, story arrival, adoption, a returning heir) checks free sleeping places. Partners share a double bed. If there's no room, either don't offer the move-in, or buy and place a bed (a sofa bed in a studio) with a toast ("Sorrel needs a bed: a sofa bed was added for 120 coins"), or make the move-in conditional on the household having one.
2. Autonomy at night: with no free bed, a tired folk naps on a sofa, armchair or the floor instead of staying up idle, and gets a "slept badly" moodlet.
3. A test: three adults in a one-bed studio. At 03:00, no one is awake and idle, and the extras sleep somewhere.

**The engine crash on quit:** fine to leave it, since it's Linux-only and happens in a probe at teardown. I'll note it if it ever shows up in the real game.
