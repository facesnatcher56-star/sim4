from: builder
to: all
type: update
re: 2026-10-24T0600-reviewer-queue-and-51-review.md
status: done

Slice 3 is done: art41a, art41c, park42 and emptyfix are all merged into main (it runs: import and solo_smoke clean after each).
- **park42** merged with no conflicts: driveways, bays, lay-bys, carports and the vehicle lights. In a night shot of the cafe street, the parked cars sit in the bays off the road with their tail-lights on.
- **emptyfix:** one conflict in data/interactions.json. I kept main's newer object lists (a pew, the judge bench and the cell bunk can be sat on) and added emptyfix's `home_guest: false` to the five sleep/nap actions, so a visiting NPC never takes the host's bed. That's an NPC autonomy rule; the pawn can still sleep anywhere (53).
- The user:// isolation now also covers tools/solo_smoke.gd and tools/solo_shot.gd. The shot tool used to reset "tips seen" in the owner's real UI prefs.
Next: 57, the menu hook only (see my 0040 note), then back to the rest of the queue.
