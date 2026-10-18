from: reviewer
to: builder
type: task
re: -
status: open

**15: The player's role, as decided by the owner.** Please check the current code against this and close the gaps. This fixes the player experience the other tasks build on. Put it after multi-floor part B and transport, unless something conflicts sooner.

1. **You control your household, like The Sims.** Direct commands to any household member, and Folk run themselves when left alone (current behaviour). You never control townies or other households.
2. **The world runs without you** (already agreed): businesses, elections, crime, the economy and town growth all carry on whether the household joins in or not.
3. **Succession (heir rule):**
   - When a household member **moves out** (a grown kid), they become a townie household. **The player does not control them.** They keep living in the town sim, statistically when far.
   - The household has a **head** (the main Folk). When the head dies, control passes to the **heir**. Default line: spouse or partner in the household → the eldest adult child (**even if they've moved out**, in which case the player switches to that child's household and the old home carries on as a townie household or is sold) → other children by age → siblings → anyone left in the household.
   - The player can **pick the heir** in the family panel at any time.
   - If nobody in the line is alive, the player chooses any townie, or starts a new family in the same town (the town and its history continue).
4. **Goals:** open-ended, with no "end". Optional aspirations and wishes (existing), plus a **legacy score** across generations: wealth, skills, careers, reputation, relationships, family size and achievements. A family history screen (ties into the Chronicle from 08 and the family tree).
5. **Camera:** follows the selected Folk on the big map (and across floors), but the player can pan anywhere in town and click any building to see what's happening (read only for things that aren't the household).
6. **Big events pause briefly and ask:** fire, a crime in progress, an arrest, a trial verdict, a death in the family, a disaster warning, a murderous-rage warning (04). The game drops to pause with a short prompt and choices, so the player is never just watching something terrible happen. A setting turns auto-pause off.

**Tests:** heir succession for each step of the line, including the moved-out child (the control switch and the old home carrying on); a pick-the-heir override; the "nobody left" flow; the legacy score is computed and saved; the auto-pause fires for each event type and respects the setting.
