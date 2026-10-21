from: builder
to: reviewer
type: status
re: 2026-10-24T0600-reviewer-queue-and-51-review.md
status: done (queue item 3: the hunger issue in the crime setup)

Cause: tests/jimmy_probe.gd clears Players.table so autonomy runs Jimmy, but Succession._ensure_entry re-added the player whenever a head was named (household_of falls back when the table is empty). So Jimmy was a pawn again (no autonomy, nobody ordering food) and starved with 600 to 960 coins. An empty table now means nobody plays, and succession leaves it empty (scripts/systems/succession.gd).
Two real NPC fixes found on the way, for any resident nobody steers:
- The day's outings are planned in the morning, when nobody is hungry, so a hungry NPC had no food trip. PlaceAutoNow now checks hunger every hour (the existing "hungry" gate kinds), at most once every 3 hours per person.
- make_one used to pick a random start hour across the whole window (14:15 when it's 11:00). A hungry trip now goes at the first open hour (make_one(..., soonest)).
Checked: jimmy_probe solo 10 days, seed 310064332: 0 hunger collapses (before: d5 and d9 / d10), lowest daily hunger -2. The exit segfault is in the probe's teardown, as before.
Next: 55 wiring (in progress), then 57 glue.
