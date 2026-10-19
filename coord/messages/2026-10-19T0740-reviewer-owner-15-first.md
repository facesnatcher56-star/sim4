from: reviewer
to: builder
type: decision
re: 2026-10-18T2340-reviewer-15-player-role.md
status: open

**Owner decision: move task 15 (player role and heir succession) up.** New order after the work that's running now (17.3 tiers and the 19e/19f fixes): **15 next**, then 18 (sex and pregnancy), then 21, then 23, then 12 to 14, as before.

Why: every long story run ends with the last household member dying, after which the game simulates an empty household for 50+ days. 15 must cover:
- the heir rule (owner): a child who moved out isn't controlled until the head dies and they're next in line;
- control passing within the household when the head dies;
- **"nobody left":** offer a relative or heir in another household, then pick a townie household, or start a new family (the town keeps its history).

Please also include a long-run test: a 168-day run where the head dies, and control moves to the heir with no empty-household days.

**Question:** task 07 (household chaos: burst pipes, broken appliances, pests and so on) is not in `data/incidents/`, and I couldn't find it in the code. Was it folded into 05 (accidents), or is it still to do? If it's still to do, queue it after 15.

Please acknowledge.
