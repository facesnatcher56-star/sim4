from: reviewer
to: builder
type: bug
re: owner report
status: open

# 58: Orders must start instantly (owner)

**Owner:** "The game is not instantly responsive. When you tell your character to move somewhere, there's a delay before they ever start moving. It doesn't feel good; it should be instantaneous."

## Cause (reviewer read of the code)
At speed 1 there are 1 to 2 real seconds of standing still, and more at speed 2 and 3 relative to the motion. Three things stack:

1. **The order waits for the next game minute to start.** CommandActions._interact (the normal non-strict path, which covers go_here from a click and every pie entry) only calls `f.enqueue(it)`. Nothing starts it. It starts in SimDirector._fill during the next tick_folk, which runs once per game minute. At speed 1 that's up to 1 real second. (SimDirector.command, the strict path, does call `_fill(f)` right away; the normal path doesn't.)
2. **The walker doesn't take a step until the minute after that.** In tick_folk, `current.tick(minutes)` runs before `_fill`. So on the tick that starts the walk, the walk doesn't advance. `actor.tile` first changes on the following minute, another real second at speed 1.
3. **The drawn model only moves when `f.tile` changes** (FolkMotion._update_waypoints compares f.tile with _last_tile). So the model stands still until the sim tile moves, then walks after it.

## Fix
1. **Start it now.** After enqueueing a player order in CommandActions._interact, start it in the same frame if the character is free, or if the new order pre-empts the current one. Do the same as SimDirector.command: call the director's `_fill(f)`, or a public `start_now(f)`. Don't wait for the minute tick.
2. **Move now.**
   - When a walk starts, hand the view the whole planned route (Interaction.path / path3) at once, so FolkMotion begins walking the first segment in the same frame.
   - Between minute ticks, the view walks along the route at the sim pace (the 56 rate), using the clock's fractional minute (Clock._accum) instead of waiting for f.tile to jump.
   - The sim tile still advances on the minute, and the view stays within a tile of it. That's the same rule as 56: never snap, never wait.
3. **Make it feel immediate even when paused.** A click while paused should at least show the order (the path line or the destination marker, and the character turning to face it), so the player sees it registered.
4. **Same for object and person orders.** The character turns and sets off toward the object or person in the frame the entry is clicked.

Check by eye: at speed 1, click the ground and the character turns and starts walking in the same frame. Click again mid-walk and they turn to the new spot at once (the 47 replace rule). No test suite.
