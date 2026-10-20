from: reviewer
to: builder
type: review
re: 2026-10-22T1800-reviewer-zack-chaotic-run.md
status: open

**A full life run the owner asked for: a solo "Zack", random seed 544219630, storyteller Custom at frequency 1, severity 1, balance 0.3, mercy 0, run until death** (main 8425654, headless, 110 days in 1,395 s). Autonomy is still on (36 isn't built). He died of old age on d109 at "age 51"; nobody was left, so the nobody-left flow moved a neighbour family, the Kettles, into the home on d111.

The world was suitably rough:
- hail damage and a sweetheart hurt (d8), then a recession;
- three break-ins at his home (d33, d40, d94), all followed by arrests and court;
- vandalism (d83), identity theft taking 600 coins (d82), a burst pipe (d101);
- a neighbour feud over a hedge (d76 to d83), a small-claims case he won (d63);
- a cold, the flu, heat dizziness and a toothache;
- 9 townie deaths (one choking), muggings of up to 3,185 coins, electrical and fireplace fires.

**Logic problems (34 rule), most important first:**
1. **Ages don't make sense:** an elder at 43, retired at 43, dead of "old age" at 51. With `days_per_year` 4 the elder stage starts at day 172, which is 43 "years". Either the shown years must follow the stages (an elder should read about 65 or more, and death from old age about 75 to 95), or the stage days must move. The owner will notice this immediately. Please propose the fix.
2. **Collapsed from hunger on day 7** of a solo life with thousands of coins (a 220-coin hospital bill on d8). Why didn't he eat? It's likely the bare home has no fridge or stove and the autonomy doesn't buy or go out for food. Under 36 the player decides, but the cheap-food floor (36 point 4) must exist and be reachable.
3. **Jobs need a computer** again: offers on d2, d6, d20, d27, d32 and d37 (see the Zack run message).
4. **A midlife crisis at 30** (d25: "quit the job, a midlife crisis") came 5 days after getting the job. That's the age problem from item 1 again, plus a cause line: a midlife crisis needs midlife.
5. **The romance stalled:** sweethearts on d16, dates on d33 and d42, then nothing for 67 days, no proposal and no break-up. Her father Arlo died on d76, and there was no grief line or visit from Zack. Check that the storyteller or romance moves a long sweetheart pair one way or the other, and that a partner's family death reaches them.
6. **The heir flow:** the Kettles moved in, and 31 minutes later "Moss Kettle and Zadie Kettle are engaged!" They're already one family moving in together, so "engaged" right on arrival reads oddly. They should arrive as a couple, or the engagement should come later.
7. **Pronouns:** "Zack slipped and bruised themselves", "Get them something to eat", "caught themselves" for a male folk. `Sexes.fill` isn't used on those toasts.
8. **Retired at police level 1** after 38 days, with a pension of 24 coins/day. That follows from the age bug.
