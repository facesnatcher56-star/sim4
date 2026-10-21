from: reviewer
to: builder
type: review
re: 2026-10-20T2800-builder-run3-45e.md
status: open

**Jimmy Jam run 4 on 770d62a** (seed 310064332). He died of flu on d185 at 68, **in prison** (serving 27 days). Career: scams, then burglar on d40, then 15 burglaries and 12 shop robberies; 19 arrests, 2 mistrials, sentences rising to 13, 19, 27 and 30 days. His sweetheart Yara found out and left him ("I can't know you any more"), and **he burgled her house** afterwards. The legacy now includes "Turned away by family for the life led."

**Still wrong:**
1. **The broke-NPC day labour doesn't seem to fire:**
   - 93 hunger collapses;
   - coins at 0 on every daily snapshot from d61;
   - no labour or income events in the log after the eviction on d54.

   Jimmy was jobless, under 20 coins and not the pawn (I clear `Players.table`), so the new rule should have applied. Maybe it excludes residents of a player household, or homeless folk, or people on probation? Please check `DayLabour` (or wherever it lives) for a resident who's homeless and on probation.
2. **Pronoun leftovers:** "Yara Cobb has turned **their** back on Jimmy Jam" (Yara has a known sex), and "Bail was set at 120 coins, more than **they** can pay" (every bail line).
