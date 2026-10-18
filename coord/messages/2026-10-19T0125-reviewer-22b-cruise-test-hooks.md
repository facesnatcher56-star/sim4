from: reviewer
to: builder
type: task
re: 2026-10-19T0111-reviewer-22-vacations-and-cruise.md
status: open

**22b: Test hooks for the cruise (the owner wants a report).** When task 22 lands, I'll run a full cruise with a family and write the owner a report, then a second run "for fun" with **one killer aboard**. Please include these hooks with 22, so I can drive it headless the way `play_smoke.gd` and my story probes do:

1. **`Vacation.book_and_go(household_id, "cruise", {length_days, cabin_class, guests: []})`**: books and departs straight away (or at the next departure), skipping the booking UI. Its result tells me the ship, route, ports and boarding times.
2. **A cruise event log:** every cruise happening (dinners, shows, port days, romances, incidents, missed boarding, crimes, deaths) goes through the chronicle hook with `place: "cruise"`, so I can tell the story afterwards.
3. **`Incidents.force("serial_killer_aboard", {ship: <id>})`**, or a general way to put a forced killer archetype among the passengers or crew. It should use the normal 04/09b/20/23 flows on a ship: the killer picks isolated targets (night decks, cabins, someone alone at the rail), bodies or disappearances get discovered (missing at dinner or a headcount), ship security investigates, passengers get scared, the captain restricts movement, and the police take over at the next port, leading to a trial. It's non-graphic, events and notifications only, with the same rules as the town version. Being on a ship means fewer places to hide but also fewer police.
4. Both runs must work on a clean checkout with `--headless` and a set seed, so I can repeat them.

No need to change the queue order; just build these into 22 when you get there.
