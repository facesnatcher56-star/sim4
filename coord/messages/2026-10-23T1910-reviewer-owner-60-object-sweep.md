from: reviewer
to: builder
type: task
re: owner request
status: open

# 60: Place every object, use it, and make it look right (owner)

**Owner:** "The agent needs to try and place everything in the game down, and make sure all items work and look visually good."

Do this on a branch (agent/object-sweep) and post shots for review. Use the sweep tool approach (tools/sweep_run.gd) on an empty test lot. For **every buyable or placeable object** in Build/Buy and every object a template uses:

1. **Place it** at each rotation (0, 90, 180, 270), against a wall and in the open, and on an upper floor where that's allowed. Check that:
   - it sits on the floor (not floating, not sunk);
   - it lines up with the grid and the wall it's against, without poking through walls or neighbours;
   - its footprint matches what it looks like (no invisible blockers, no walk-through solid parts);
   - it can be picked up, moved and sold again.
2. **Use it.** Have the player's character run every action the object offers. Check that:
   - they walk to the right spot;
   - they face the object and play a fitting animation, with no clipping into it;
   - items held in hand show up (the guitar, the book, a cup);
   - the object changes state where it should (a lamp turns on, the TV screen, the bed is unmade, the stove heats up);
   - the effects actually happen (need, skill, money);
   - two people can share it only when that makes sense (a sofa yes, a toilet no).
3. **Look at it** in the grounded look, by day and night, close up and mid zoom. Check:
   - the scale against a person;
   - materials that aren't flat, broken or missing;
   - wear and poverty variants that read right;
   - no z-fighting or flicker;
   - lights that cast light;
   - nothing that's still a placeholder box.
4. **Fix what's wrong.**
   - Model fixes go through the blender/ pipeline.
   - Footprints, slots and offsets go in the data (objects.json, object_visuals.json, animation_map.json).
   - Behaviour goes in the interaction.
   - Anything too big to fix now goes in a short list for the owner.

## Report
- **One contact sheet per category** (seating, beds, kitchen, bathroom, electronics, decor, outdoor, work, civic and shop fittings) in coord/shots/objects60/. Each object gets an "in use" shot.
- **A table in the status message:** each object marked ok, fixed (what), or still wrong (what).
- **Rules:** no test suites; solo_smoke clean. The quiet-depth and freedom rules still apply: the player's menu shows what's physically possible, outcomes decide the rest.
