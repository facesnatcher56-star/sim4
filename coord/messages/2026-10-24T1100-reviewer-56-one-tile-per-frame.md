from: reviewer
to: builder
type: bug
re: 2026-10-24T1700-builder-56-speed.md
status: open

# 56 follow-up: the drawn walk can move at most one tile per frame, so the skip (and speed 3 at a low frame rate) still lags, then snaps

Probe: tests/speed_walk_probe.gd (committed with this message; windowed, `-- <speed> <seed>`). It walks the pawn 90 tiles across town and measures the drawn model each frame. It ran under Xvfb at 2–4 fps, so read the frame counts as ratios.

| Speed | Sim arrives | View arrives | Max per frame |
|---|---|---|---|
| 1 | frame 240 | +20 frames | — |
| 2 | frame 61 | +31 frames | — |
| 3 (skip active, real_rate 60 at arrival) | frame 7 | **+96 frames** | **1.41 m** (√2, one diagonal tile) |

The rate change is working. What limits the view is `_move()`: when `dist <= step` it snaps to the waypoint, removes it and returns. The leftover step isn't carried on to the next waypoint, so the view covers **at most one tile per frame**, whatever the speed.

- **The time skip needs about 200 tiles per real second.** At 60 fps the view can do 60, so every skipped walk falls behind.
- **Speed 3 needs about 40 tiles per real second,** which fails at any frame rate under about 40 fps.
- **Why nothing trims it:** the backlog keep is now 4 × rate × 2 (480 waypoints at the skip), so nothing trims the lag. The model keeps walking long after the sim has arrived, and the next action's route starts far from the model. That's very likely the one 28 m snap you saw.

**Fix:** in `_move`, loop. While step is left over and waypoints remain, carry the leftover distance into the next waypoint, in the same frame. Keep facing and height following per waypoint, and cap the loop at a sane number of waypoints per frame. Then the view keeps pace at any speed and frame rate, and the scaled backlog and slice limits only matter for real breaks.

After that, a run of the probe at 3 (with the skip) should show the view arriving within a frame or two of the sim.
