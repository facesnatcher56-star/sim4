from: reviewer
to: builder
type: task
re: 2026-10-23T1540-reviewer-owner-security-determination.md
status: open

**43: No magic events (owner rule).** "No events or things like that should magically just happen because the game said so. We have checks and balances built in to help with these things."

**The rule:** every event that touches a person must come from the world's own systems:
- a real cause (someone or something that does it, physically able to do it, per 34 and the security and determination rule);
- the conditions that make it possible;
- the checks that can stop it (locks, skills, money, relationships, the police, insurance, traits, being somewhere else).

**What the storyteller can do:** tilt the odds of real causes (more pressure, a crime wave that comes from real poverty, a tougher economy, more townies passing by), and choose which real thread to push. It must **never** create an outcome directly ("you were robbed", "you got the flu", "a relative died and left you money", "laid off") without that system's own causes and checks running.

**Examples on main that break the rule** (from the code read and the runs):
- **"Your home found N coins tucked inside an old coat"**: coins from nowhere, 7 times in 40 days.
- **Identity theft** (`chaos_money`): money drained with no culprit and no case.
- **The inheritance surprise** (`ChaosKin.inheritance`): kills a townie relative to pay out. Deaths must come from real causes; a relative's real death can then go through the real will.
- **"A long-lost sibling at the door"**: a relative created from nothing. Only allowed if that person already exists in the family tree (generated at world start) and has a reason to look you up now.
- **Storyteller cards that force incidents** (force burglary, force a cold, force a layoff, force a pipe burst): they must instead raise the chance of the real roll, which then runs its own conditions and checks.
- **Layoff cards** that close a job without the employer, economy or plant state behind it.
- **The midlife crisis at 30–31**, on a timer rather than from age and life state (also the age scale).
- **Small claims "damaged fence"** with no fence and no damage event.
- **The `wrong_arrest` card** is text only; wrongful arrests must come from the evidence system.
- **Arcs** (`rising_criminal`, `missing_person`, `admirer`) whose stages are story text with no real people acting.
- **Statistical townie outcomes** are fine for people far away (that's the tier system), but anything that reaches the **player** must run in full.

**Please:**
1. **An audit table** in `docs/MAGIC_EVENTS_AUDIT.md`: every storyteller card, arc stage, chaos and life incident, and "surprise" coin or object. For each: what real cause produces it, what checks can stop it, and the verdict (OK / convert to an odds tilt / give it a real cause / remove).
2. **Fix the clear ones** in the same pass. Owner rule: no test suites; it just has to run.
3. **List** the ones where the real cause would need a new system, for the owner to decide.

This goes with 36 (solo), since solo play makes every magic event visible. Keep it lean and data-driven.
