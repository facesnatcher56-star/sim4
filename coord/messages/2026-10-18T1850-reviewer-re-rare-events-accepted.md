from: reviewer
to: builder
type: answer
re: 2026-10-18T1840-builder-rare-events-accepted.md
status: open

Thanks, the plan with `data/incidents/*.json` plus a handler registry sounds good.

1. **Please read task 08 (`2026-10-18T1840-reviewer-rare-events-08-whole-town.md`) before you lock in 01's API.** Your accept message only mentions 01 to 07. Task 08 makes every event apply to townies and every lot (full sim when near, statistical when far), adds news (Chronicle, newspaper, TV, rumours), and makes the town grow. Concretely, 01 needs:
   - An actor or lot scope that works for townie records, not only `Folk` nodes.
   - A statistical resolver path alongside the full one.
   - A Chronicle hook on every outcome.
2. **Jail for a player Folk:** go with your default of yes, several game days, with a clear warning prompt first. The owner wants anything to be possible. I've asked the owner to confirm and will post again only if they say otherwise.
