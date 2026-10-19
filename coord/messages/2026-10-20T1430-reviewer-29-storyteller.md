from: reviewer
to: builder
type: task
re: -
status: open

**29: A storyteller that adds chaos and unpredictability (owner request, "like RimWorld").** The owner: "you always have to add a little bit of chaos and unpredictability to keep it a video game, kind of like RimWorld." Today the drama is fixed per-incident dice, plus `StoryPacing`, which only nudges small social odds and never creates events. Add a real storyteller layer on top of the existing systems (incidents, crime, chaos, city, story threads), data-driven, deterministic (co-op), working town-wide and per household.

1. **Storyteller personalities**, picked at New Game (next to difficulty) and changeable in settings. The host's choice applies in co-op.
   - **Calm:** long quiet stretches, mostly small and good events, rare big ones, with long recovery after a bad one.
   - **Classic** (the default): tension builds in waves (small → medium → big, then a breather), and big events are spaced out.
   - **Chaotic:** anything, any time, including bad luck stacking on bad luck; still respects the owner's hard rarity rules.
   - **Custom:** sliders for frequency, severity, good/bad balance and "mercy after disaster".
2. **A drama budget, the core mechanic:** each household (and the town) gains points over time. The storyteller spends them on events weighted by size (small, medium or big). Its choice depends on the household's state:
   - money, so a rich household gets a burglary, an audit or a gold-digger, and a poor one gets a windfall, a job offer or an eviction scare;
   - mood, relationships and recent losses (mercy, except for Chaotic);
   - stage of life;
   - how long since the last notable event.

   It never leaves a household with nothing notable for more than N days (Calm 10, Classic 5, Chaotic 3; data).
3. **An event deck from everything that already exists** (good and bad), plus new **twists**:
   - a stranger arrives in town;
   - a secret comes out;
   - an anonymous letter;
   - an old flame returns;
   - a rival moves in next door;
   - a mysterious inheritance;
   - a pet turns up on the doorstep (when pets exist);
   - a celebrity visits;
   - a job headhunter;
   - a contest;
   - a lost wallet (keep it or return it?);
   - a neighbour asks a favour;
   - a power struggle at work;
   - a scandal involving the mayor.

   Many twists are a **choice for the player** with consequences (moral weight and reputation from 21 and 23), and autonomous resolution for townies.
4. **Arcs, multi-day stories** with setup, escalation, climax and resolution (built on `StoryThreads`):
   - a feud between neighbours;
   - a stalker or obsessive admirer (non-sexual, safety-focused, ends with police or resolution);
   - a rising criminal in town;
   - a family secret;
   - a business going under;
   - a town crisis (an epidemic, a factory closure, a crime wave, a drought);
   - a romance triangle;
   - a missing person.

   At most one big arc per household at a time, and the town has its own arc slot.
5. **Foreshadowing and readability:** rumours, warnings and small signs before big events ("strange cars on the street at night", "the mayor's aide looks nervous"), so the chaos feels fair. A short **Storyteller log** in the Town panel lists "what happened and why" in plain words, with no spoilers.
6. **Town cycles:** booms and busts (13), crime waves, flu seasons, heat waves and cold snaps, election scandals (12), all scheduled by the town budget so the town has eras.
7. **Hard rules stay:**
   - murder, serial killers, child abuse and disasters keep their extreme rarity (the storyteller can't raise them beyond a capped multiplier);
   - "Mature life events" is respected;
   - the player can turn any category off ("everything optional");
   - human trafficking and sexual content stay out.
8. **Tests:**
   - per personality, over 5 seeds × 168 days, measure notable events per household-week, the longest quiet gap, big-event spacing, and the deaths and crimes per town-year (they stay within ±20% of today's for Classic; Chaotic up to a capped higher band; Calm lower);
   - no pile-on: for Classic, at most one big bad event per household per 7 days;
   - determinism and save/load of the budget and arcs;
   - the co-op hash is updated on purpose.

Suggested order: after 19i (pregnancy, news flood, bills) and 14, and alongside or before the newspaper if the owner wants it, since the newspaper is where storyteller events get read. I'll measure each personality in long runs once it lands.
