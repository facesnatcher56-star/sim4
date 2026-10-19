from: reviewer
to: builder
type: task
re: 2026-10-20T1430-reviewer-29-storyteller.md
status: open

**29 amendment from the owner (please give it to the storyteller agent now):** "We want it NOT predictable, and we don't have to do the same exact method RimWorld did. It doesn't even have to directly hit the player or the household. It can be around the household or somewhere in the city, because we're going to expand the city to be a lot bigger to create more randomness." So:

1. **No visible rhythm.** Drop strict "build up, spend, breather" waves as the core. Use a hidden, wandering chaos level per district and per household (a noisy random walk with occasional sudden jumps), so quiet and busy spells come at irregular lengths. Keep a few soft guards: a maximum quiet gap so nothing goes dead, a pile-on cap for Classic, the hard rarity caps. The personalities set the walk's average, its noise and the jump chance, not a schedule.
2. **Most events happen somewhere in the city, not to the household:** a fire two streets away, a robbery at the corner shop, a crash on the avenue, a scandal at the town hall, a flood in the lower district, a celebrity at the café across town. Their effects **ripple outward** by distance, relationship and news:
   - **Nearby:** sirens, smoke, a road closed, a detour, neighbours talking, a power cut on the block, a worried moodlet.
   - **People you know:** a friend is hurt, so visit them in hospital; a coworker is arrested, so a job opens up; a relative's house burns, so they ask to move in.
   - **The town:** news, rumours, prices, an election, insurance costs.

   So the household feels the city's chaos mostly second-hand, sometimes first-hand.
3. **Emergent chains instead of scripted arcs where possible:** one event raises the odds of related ones nearby ("contagion"): a burglary → more burglaries on the street → a neighbourhood watch → a vigilante → a wrong arrest. A fire → an insurance fraud investigation → a lawsuit. A factory closure → layoffs → more petty crime in that district → a rally at city hall. Keep the explicit arcs from 29 as a smaller share.
4. **Districts matter:** chaos and event mix differ by district (downtown: crime, protests, traffic accidents; suburbs: domestic drama, burglary, house fires; industrial: workplace accidents, layoffs, pollution; waterfront: floods, smuggling with the cruise and port). This should work with today's map and scale up when the map grows (task 30).
5. **Perception decides what the player sees:** full detail near anchors (the tiers), summaries and news far away, with nothing lost; a far event can still pull the household in later.
6. **Tests:** irregularity (the gaps between notable household events shouldn't be periodic: check autocorrelation or a coefficient of variation band); at least 60% of notable events per 168 days happen outside the household but within the town, with a measurable ripple (moodlets, visits, detours) on the household; the rarity caps and quiet-gap guard hold.
