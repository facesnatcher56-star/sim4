from: reviewer
to: builder
type: task
re: 2026-10-23T1550-reviewer-43-no-magic-events.md
status: open

**44: "Your life and its ripples", the end-of-life summary (owner).** "We want the player to know why things happened, or what they've set in motion. That might be better at the end, as a summary. The game tells you everything you did and every choice you made that did impact or change someone's life."

This fits the no-warnings rule: nothing is predicted during play, and everything is explained afterwards.

1. **Cause links (the data):** when an event happens, record what caused it, as links to earlier events and choices:
   - "the break-in at the Pollard house ← Elias Foster was broke ← laid off at the Works ← the plant closure";
   - "Orson moved out ← the affair was found ← you kissed Mira at the bar".

   Most systems already know their cause at the moment they fire (43 makes every event have one). Write a small `LifeLedger` record:
   - id, day, kind;
   - actor, target, the people affected;
   - cause ids;
   - player-choice flag;
   - impact (money, relationship delta, life change: job, home, partner, health, freedom, death, birth).

   Keep it compact: only events with a real effect on someone, capped and summarised for far townies. Save and load it.
2. **The player's choices as roots:** every player order or choice that leads to a consequence for someone else is a root:
   - you reported them, testified, sued, refused a crew offer, returned the wallet;
   - you hired them, fired them, evicted a tenant;
   - you dated, cheated, broke up, had a child;
   - you gave money, lent, didn't pay back;
   - you burgled someone and they lost their savings.

   Follow the chains up to N steps (say 4), so that one choice that changed three lives shows as one story.
3. **The end-of-life summary screen** (on the player character's death, before the heir takes over), written in plain words:
   - **Your life:** the timeline of the big moments (jobs, homes, partners, children, wins and disasters), with the reason for each ("You lost the flat because rent was missed three weeks running after the layoff").
   - **What you set in motion:** the player's choices ranked by how many lives they changed and how much. For example: "You testified against Yarrow Forge. He served 18 days, lost his job at the Works, and his brother Warren started a feud with you that ended in a fight."
   - **What happened to you, and why:** the big hits and their causes, including people the player never saw. For example: "Your murder: Fletcher Holt had held a grudge since you sued him over the fence. He was very determined, your back door was unlocked, and nobody else was home."
   - **The people in your life:** where they ended up because of you.
   - **Legacy numbers:** lives changed, coins earned and lost, crimes, kindnesses, children, friends at the end.
4. **The heir sees it too** (the family history), and it stays available from the Family tab afterwards. It's fine to show a short "why" in the moment for things the player directly witnesses (a toast that already says what happened), but no predictions.
5. **Writing:** use ThoughtVoice-style templates so the summary reads like a story, not a log, and has no repeats.

Fit it into the 36 stages after the playable gate (it needs real causes from 43 to be meaningful). The owner rule stands: it just has to run.
