from: reviewer
to: builder
type: update
re: 2026-10-21T1700-builder-32-complete.md
status: open

**Review of task 32 on 3d82911/b3134f3 (Linux): the hash matches, `HASH coop=1d7095e438458f03 minute=4740`.** Hover sweep on the default New Game (now an empty home): 0 windows, 0 doors; the screen is clean, with a compact folk panel and docked tips (`coord/shots/pov-2/empty_home_start.png`).

**Behaviour, measured with a new tool `tests/pov_activity_mix.gd` (committed here), family 101, 3 days, household folk:**
- **Furnished home:** distinct interactions per folk-day **20–41**, top non-need repeat ≤ 4 (apart from Zinnia's `work_gym` ×17, which is her job task at the gym, fine), **idle 1–14%** of awake time. Your targets are met.
- **Empty home (the new default) with nobody playing:** distinct per folk-day falls from 24–30 on day 1 to **4–11 by day 3–4**, and **idle 33–57%** of awake time, mostly `daydream`. The unattended household never furnishes, so it sits in an empty house. A player will normally buy things, but the world runs without the player (an AFK player, or co-op guests who don't log in).

**Please (small, 32f):**
1. **In an empty or under-furnished home, autonomy goes out more:** park, café, library, a friend's house (the 14b outings and the 32c plans), instead of daydreaming at home. Optionally, after N days unplayed, buy the basics automatically from the moving-in allowance (an "auto-furnish when nobody plays" rule, like the bill autopay).
2. **Getting Started still says "A parent finds work — At the computer choose Look for Jobs"** in an empty home with no computer. Point the hint to the job board in Town (the Jobs tab), or "buy a computer".
3. **The pendant-light label pops up over empty rooms** (`empty_home_start.png`: "Pendant Light" over an empty floor). In an empty house the lights are the only objects, so they win every hover. Keep ceiling lights for Build/Buy, or only when the floor point is inside the light's own small footprint.

Telling the owner the rebuilt exe is ready.
