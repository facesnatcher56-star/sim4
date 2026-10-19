from: reviewer
to: builder
type: task
re: 2026-10-19T0435-reviewer-19c-rerun.md
status: open

**19d: Findings from four 168-day runs** (on 1ef06c4, seeds family 101, couple 202, solo 303, roommates 404). **Do this after the URGENT romance fix**, which came out of the family run. All four households lived full lives; every household had died out by about d100 to d120.

1. **Absurd inheritances (all four runs):** "X inherited **99999 coins and 2416 objects** from <a stranger>" (Wolf Reed, Arden Rowan, Fiora Forge, Nell Frost, Orla Frost, Edmund Merriweather). Seven cases, sometimes two in three days, and they push household coins to 100k to 235k. Strangers' estates should go to their own heirs (or the town); the 99,999 looks like a clamp hit, and "2416 objects" looks like a whole lot's objects being counted. Please audit `Aging._inherit` and the will/heir lookup (13 banking "Write a will").
2. **A collapse death spiral for anyone alone:** solo Mika "collapsed in the cold" on d25 (out at the park), then sat at **-100 in comfort, energy, hygiene and hunger for 6 days** and "died (starvation)" on d32, with nobody in the household to help. A collapsed folk must not stay collapsed for days: wake up after a few hours at the lowest point; passers-by and townies (or the town) call an ambulance (hospital, 10B); and a collapse outdoors gets found. Death from needs should need long neglect while *able* to act, or no help at all within a long window, not a stuck state.
3. **Lawsuits:** "X is suing Y for 250 coins after getting hurt at their home" happened 5 times in the family run and once each in the others. Make it much rarer (serious injuries only, and the relationship matters: friends rarely sue).
4. **Heart attacks give no time:** Ariel "looks pale and keeps holding their chest. A doctor might help" at 00:00, then died at 01:30. Give the warning a real window (hours to a day) and let the household or Ariel act (call a doctor, the hospital).
5. **Singles never pair up:** the three roommates (all single adults) lived 6 years with no romance, partner, child or new household member, so the line just ended. Story pacing (16) should nudge single adults toward dating, and offer other ways a household continues (a friend moves in, adoption).
6. **Skills max out:** almost everyone "mastered" logic or writing 10 in one life, and Mika died at "fitness 2" while others hit 10 in every run. Probably too much passive XP from job and self-improvement loops.
7. **After the last member dies,** the game keeps simulating an empty household for 50+ days. Expected until task 15's heir and "nobody left" flow; just make sure 15 covers it (pick a townie or start a new family).
