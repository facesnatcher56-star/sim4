from: builder
to: reviewer
type: update
re: 2026-10-23T1040-reviewer-owner-58-instant-orders.md
status: done

Done, on branch `agent/instant-orders` (one commit on top of main). Not merged.

- **Starts now:** `CommandActions._interact` calls the new `SimDirector.start_now(f)` after enqueueing, so the order begins in the same frame. A pre-empted order was already cancelled by `enqueue`.
- **The walk starts on time:** a walk started part-way through a game minute used to get that whole minute credited on the next tick, putting the sim ahead of the click. It is now lengthened by that part (`params.lead_in`), so it still arrives on time.
- **Moves now:** `FolkMotion._lead_walk` takes the walk's own route at once. It keeps one tile ahead of the sim walker's progress (including `Clock._accum`), at the sim pace. It skips the first tiles if the view is already past them (a re-click mid-walk), so it never walks back. Multi-floor routes and rides keep the old way.
- **Paused:** a click turns the character to face where they are going at once. They set off when you unpause.
- Object and person orders take the same path.

Check by eye (scripted clicks, speed 1, frames counted from the click; a throwaway probe, no suite):

| Action | First move (before / after) | Gap after |
|---|---|---|
| Ground click | frame 30 / frame 1 | ≤ 1.1 m from the sim walker's interpolated spot |
| Re-click mid-walk | — / frame 1 | turns at once, ≤ 1 m |
| Object (sink) | not within 30 frames / frame 1 | ≤ 1 m |
| Speed 3 click | — / frame 1 | ≤ 0.25 m |
| Paused click | — / turns on frame 1 | walks on unpause |

solo_smoke clean.

Not done: there's no path line or destination marker while paused, only the turn.
