from: reviewer
to: builder
type: task
re: -
status: open

**New program from the owner: danger, death and rare events.** The owner wants the world to be able to throw *anything* at the household: deaths from many causes (not only old age), crime including robbery and murder, accidents, illness, fires and natural disasters. Most of it should be **exceedingly rare**, things a player may never see in a whole playthrough. Keep everything in the game's existing tone: no gore, deaths shown as an event and notification (a short collapse or fade-out, grief, a grave), not graphic.

Finish the open townie-needs and `play_smoke` task (`2026-10-18T1815-reviewer-review-open-map.md`) first. A starving townie is closely related to task 02. This is a long backlog meant to keep you busy. Work through the tasks below **in order** (01, 02 ...). Each one is a separate message, so reply to each when it's done. Post a `type: update` after each one with what landed and the test results. If you think of more events that fit, add them and say so in your update. Pull between tasks in case I've posted changes.

**Read task 08 before starting:** every event must work for townies and every lot too, not only the player household, and news has to travel through the town. Design 01 with that in mind.

**Rates and calendar:** a game year is 28 days (4 seasons x 7) and a Folk lives about 200 to 230 days, so about 7 to 8 years. All rates below are **per household per game year** unless stated, with the "Surprises" setting at its default. Tune the data so long-run tests land close to the targets.

**Shared requirements for every task:**
- Data-driven: rates, conditions and outcomes live in a new `data/incidents.json` (or that file plus the existing ones), not in code.
- Every event has a **force hook** (`Incidents.force("house_fire", ...)`) for tests and for a debug menu. Add a hidden debug panel (for example F9) that lists all events and can trigger any of them on the selected Folk or lot.
- Every event can be **prevented or softened** by something the player can do (smoke alarm, lamps, fitness, skill, doctor, locks and so on). It must never be pure bad luck with no counterplay, except the "act of nature" disasters.
- Warning signs where it makes sense (smoke, a cough, a threatening thought bubble), so attentive players can react.
- Save/load safe, reset in `reset()`, deterministic with the seeded rng.
- Tests: one focused test per event (forced) plus a long-run statistical test (`-- --slow`) that simulates many game years with the default setting and checks the rates against the targets (within a sensible tolerance), and that nothing crashes or stacks.
