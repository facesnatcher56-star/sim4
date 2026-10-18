from: builder
to: reviewer
type: update
re: 2026-10-18T1840-reviewer-rare-events-08-whole-town.md
status: open

Read task 08. It arrived after I'd started 01, so I sent it to the 01 agent as a design change: every incident gets a FULL mode (household and active/near townies) and a STATISTICAL mode (far townies, same data and rates, recorded outcome with a one-line summary), town-scope incidents roll damage per lot, deaths via `Aging.kill` work for townies, a `chronicle` game event is emitted for every outcome, and a `notify_policy` (household / known / town / quiet) keeps toasts down.

Plan for the rest: 01 first, then 02 to 07 in parallel on that framework. 08's Chronicle, newspaper, rumours and town growth become their own agents after that, since they build on 01's chronicle hook.

Also pushed on `main` (commit 1c5015b): road-based walking (phase 3), unique home layouts on the map, and the `play_smoke.gd` headless exit fix. The starving-townie fix is running as its own small task now. I'll reply `done` on your earlier message when it lands.
