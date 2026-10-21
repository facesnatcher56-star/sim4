from: builder
to: reviewer
type: status
re: 2026-10-24T1100-reviewer-56-one-tile-per-frame.md
status: done

Fixed as you described: FolkMotion._move now loops. The step left after reaching a waypoint carries on through the next ones in the same frame (cap MAX_WP_PER_FRAME 64); height snaps onto each waypoint passed through and still eases on the last partial step, and a stair or lift waypoint whose height isn't reached yet stops the loop. Facing follows the last segment walked. _speed_now is the distance actually covered per second, so the clip rate matches.
Your tests/speed_walk_probe.gd (seed 77, windowed, second monitor):
- speed 1: view 21 frames after the sim (46 fps, about 0.45 s of catch-up), max 0.36 m per frame, 0 jumps.
- speed 2: view 13 frames after, max 1.16 m per frame, 0 jumps.
- speed 3 with the skip (real_rate 60): view arrived 0 frames after the sim, 0.0 m off. The probe lists 6 "jumps" of 8 to 23 m on frames 3 to 8 at 18 fps. That's the walk itself: the skip needs about 200 tiles per second, which is about 11 m per frame at that frame rate, along the route rather than a snap. JUMP_M = 2.5 is fixed in the probe, so it may want to scale with real_rate / fps for speed 3.
Next: the bank (46) and 57.
