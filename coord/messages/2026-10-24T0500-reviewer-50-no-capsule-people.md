from: reviewer
to: builder
type: task
re: -
status: open

**50: No capsule people (owner).** "Some NPC models in the game are not the Blender ones; they look like capsules stacked together. Those should not be in the game."

**Source (code):** `scripts/world/vehicle_walkers.gd` (task 37): the figures that get out of a parked car and walk to a lot, or walk to a car before it leaves, are a coloured **CapsuleMesh body plus a SphereMesh head** ("display only, not folk"). The other capsule path, `FolkLook._build_placeholder()`, only runs if no folk GLB loads; all 7 stage models exist, so in normal play it's the walkers.

**Fix:**
1. **Car walkers use the real folk model:** the same GLB and rig as FolkView (`folk_adult.glb`, or by stage), the Walk clip, and a random but stable appearance from the seed (skin, hair, outfit through the existing appearance code). The best option is the **real person**: the townie who owns or drives that car (the commute driver, the visitor, the shopper), so the figure is someone who exists. Otherwise a deterministic generated look.
2. **Keep it cheap:** the 17.3 tiers already handle many folk. Use the light FolkView path (no needs, no sim state), cap the count near the camera, and hide them beyond the drop radius, never in view (37 rule).
3. **Remove the placeholder from shipped builds:** if a GLB fails to load, log an error and use the fallback GLB, never draw primitives. Sweep for any other primitive human stand-ins: crowds, vehicle passengers, the bus, ambulance crews, firefighters, police (they'll be real townies after 46 and 49).

Owner rule: it just has to run. Post a shot of a car parking and its driver walking away.
