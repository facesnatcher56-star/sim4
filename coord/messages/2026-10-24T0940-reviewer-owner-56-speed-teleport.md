from: reviewer
to: builder
type: bug
re: owner report
status: open

# 56: At game speed 2, 3 and the time skip, people teleport instead of walking faster (owner)

**Owner:** "If I speed the game up they teleport instead of everything speeding up, where they would just walk faster."

## Cause (reviewer read of the code)
The walk on the sim side and the walk in the picture run at different paces, and only the sim one scales with game speed.

**The sim walker** (Interaction.WALK_MIN_PER_TILE = 0.3) moves 3.33 tiles per game minute. In real time that means it needs:

| Game speed | Game minutes per real second (Clock.MIN_PER_SEC) | Tiles per real second |
|---|---|---|
| 1 | 1 | 3.3 |
| 2 | 4 | 13.3 |
| 3 | 12 | 40 |
| Time skip (TimeSkip.RATE) | 60 | 200 |

**The view walker** (FolkMotion._walk_speed) does not use the game speed at all. It is 2.4 m/s plus a catch-up of 0.4 per waypoint behind, capped at walk_max_speed 3.4 m/s (run 4.6) at every game speed.
- `_speed_mult()` (SPEED_MULT [0, 1, 1.8, 3]) is only used to stop at pause.
- Its values don't even match the clock (4× and 12×).

So at speed 1 the view is already right at its cap (3.3 needed, 3.4 max). At speed 2 or more it falls behind at once:
- **`_trim_backlog`:** as soon as more than 4 waypoints are queued (`max_backlog` 4), the view hops ahead along the route. That's the teleport the owner sees, many times per walk.
- **`MAX_SLICE` 24:** a tile jump longer than 24 between two view updates is not animated at all (position snaps).
- **`_route_far_goal`:** snaps too when the view is far from its goal with no route.
- **The animation clip** (`_anim_speed`) plays at `_speed_now / nominal`, clamped to `max_scale` 2.4. Use animations (idle, eat, use) cap at `minf(mult, 2.0)`. So even when the body moves faster, the legs don't keep up.

Vehicles already do this right (VehicleView speed_scale: "at every game speed the vehicles stay drawn and move at the faster rate"). Folk should match.

## Fix
1. **View pace = sim pace × game speed.** The base view walk speed is the sim's real pace: tiles per game minute × Clock minutes per real second (the TimeSkip rate when skipping), × Health.speed_mult and Weather as the sim uses them. Keep the small catch-up on top for jitter, and remove the cap that ignores game speed. Replace SPEED_MULT with the real clock rate (one function shared with VehicleView if possible).
2. **Animation playback scales with game speed too.** Walk and run clips play at their normal rate × the game speed, and so do the use, eat and idle loops. At speed 3 and skip, the walk is a fast walk, not a slide. If a clip looks bad past some playback rate, cap the playback there but still move the body at the full pace.
3. **No hops during normal play at any speed.**
   - `_trim_backlog` only for real breaks: a load, fast travel, a reachable-route failure.
   - `MAX_SLICE` and `_route_far_goal` snaps only in those same cases.
   - Scale `max_backlog` with the speed (or base it on time behind, not waypoint count) so a normal fast-forward walk never trips it.
4. **Running stays a choice of intent** (urgent, flee or chase), not of game speed. A walk at speed 3 is still a walk, just faster.
5. **Same treatment for anything else drawn in motion that follows the sim:** pets, babies carried, walker cars (VehicleWalkers), the bus. Check each one follows the clock rate rather than a fixed pace.

Check by eye (no test suite): solo game, order a walk across town, and watch it at speeds 1, 2, 3 and through a skip. The person should walk the route continuously, with no jumps.
