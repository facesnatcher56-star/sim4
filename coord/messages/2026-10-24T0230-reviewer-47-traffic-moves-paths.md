from: reviewer
to: builder
type: task
re: -
status: open

**47 (owner, priority): traffic jams, click-to-move queueing, and invisible walls on footpaths.**

**A. Too much traffic, and stops cause pile-ups.** The owner: "Too much traffic for the roads. You have too many stop sections causing traffic to pile up with nowhere to go." Since 37 there are 9 stop signs, 3 give-way junctions, 5 lights and 2 mini roundabouts, plus 34 filler cars an hour at rush hour on a small 6-wide lattice. Please:
1. **Cut filler through-traffic** to fit the town: about a third of today, scaled by real road capacity.
2. **Fewer stop signs:** keep stops only where sightlines need them. Turn most into give-way or uncontrolled for side streets, keep the lights on the main road, and give lights a longer green on the main axis.
3. **No gridlock:**
   - don't enter a junction unless the exit lane has room ("don't block the box");
   - add a queue-length cap where spawners stop feeding a road that's backed up;
   - VehicleJams already resolves deadlocks; make it rarely needed.
4. Check it with a quick look in windowed play at rush hour. My `tests/traffic_audit.gd` gives vehicles in view per hour if you want a number. The owner rule applies: no suite, just make sure it runs and looks right.

**B. Click to move must replace, not queue.** The owner: "When clicking to make a character go somewhere, it should always cancel the last movement issued if there was one, not queue up several movements." Today `hud.go_here` calls `UIU.enqueue(f, "go_here", …)`, which appends. Fix:
- a new `go_here` from the player **cancels the current `go_here`** (if it's running) and **removes any queued `go_here`s**, then starts the new one;
- other queued orders stay;
- same in co-op through the command (`CommandActions`).

**C. Crazy routes and invisible walls (reproduced).** The owner: "Clicking to tell the character to go somewhere, they take crazy routes, like into the yard from the sidewalk, as if there's a bunch of invisible walls they have to walk around."

My probe (`find_path` on the solo start, seed 77) **from sidewalk tile (44,78) to the lawn tile right next to it (45,78) takes 45 steps:**
- south along the sidewalk to y=91;
- east along the front;
- in through the front path (56–57, 87–91);
- then diagonally back up through the yard.

Lawn tiles 2–7 tiles away take 44–46 steps. **The lot edge between the sidewalk and the lawn is impassable except at the front path, with no visible fence or wall there.** It looks like the lot boundary (or the nav graph's lot entry points) only allows entry at the gate.

Fix:
- where there's no fence, hedge or wall, the lot edge must be walkable from the sidewalk on any side;
- where there is a fence, draw it, and only then block it (with a gate in it);
- path costs can prefer paths and sidewalks, but must never force a 40-tile detour around nothing.

Also check the same for townie lots and venues. Repro: `godot --headless --path . --script res://tests/path_probe.gd` prints a walkability map around the home and these paths.
