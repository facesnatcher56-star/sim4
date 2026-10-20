from: reviewer
to: builder
type: task
re: 2026-10-23T1000-builder-41-37-done.md
status: open

**41: the owner approves the new look.** "Definitely like the new look better." Please go ahead with the full art pass (your 9–11 session plan), making "Grounded and gritty" the default, with Reference kept in Settings for now. Fold in my notes on the look-test scene:
1. The run-down house **interior is too nice**: a good bed, lamps, tidy rooms. A poor interior needs cheap, mismatched, broken furniture (a sagging mattress on the floor, a broken chair, a boxed TV), stains, clutter and dirt that build up. This ties into "state shows in the visuals".
2. **The litter reads as confetti** (bright saturated squares). Use muted colours and real shapes (crumpled paper, cans, bags, bottles).
3. **The graffiti is simple squiggles.** It needs tags with bulk and colour (a handful of decals with outline and fill), sized to the wall.
4. **The overgrown yard grass is spiky and uniform,** like a crop. Mix heights, clumps, weeds, a dead patch and some brown.
5. **Exterior wear** barely shows because the home shell is cut. Put wear on the cut-wall tops, the outer base course, the door, the porch, and the window frames you can see.

**42: Parking and vehicle lights (owner):** "Make sure all cars have driveways to park in if the house allows it, or a garage, or you'll need extra road for parallel parking as well, where it makes sense. Headlights should have beams etc. that match them."
1. **Every parked car has a real place** (34 rule: a car parks where a person would park it):
   - **driveway:** the lot generator adds a driveway (a paved strip from the kerb, with a dropped kerb) on lots with room, leading to a garage or carport where the house type has one;
   - **garage:** a car parked in a garage is hidden or shown inside with the door state;
   - **on-street parallel parking:** marked bays along streets where it makes sense (residential streets without driveways, the town centre, the rough district), on a parking lane wide enough (widen those road segments by a lane, or mark one kerb lane), not across crossings, junctions, bus stops, driveways or hydrants;
   - **car parks** for businesses (the existing bays and Station Street Car Park);
   - **no** cars on sidewalks, lawns or in the middle of lanes. In the look-test shots the beaten-up car seems to sit across the kerb and footway; check.
   - Ambient and townie cars pick a free legal spot; if none is free they circle or use the car park (that's the existing `search_min` logic).
   - A test: across 3 seeds × a game day, every parked vehicle's footprint sits inside a driveway, garage, marked bay or car park, with 0 overlaps with footway, crossing or junction tiles.
2. **Vehicle lights that match:**
   - headlights cast **beams** on the road (a spot light with a soft cone near the camera, a projected light-pool decal or a cheap additive cone further out, under the 17.3 tiers);
   - taillights glow red, **brake lights** brighten when slowing, indicators blink at turns, reversing lights show when backing up (VehicleJams);
   - emergency vehicles' blue and red light up their surroundings;
   - lights come on at dusk, in rain and in fog, and are off when the car is parked;
   - the beam's direction and length follow the car (low beam, about 15–20 m);
   - the budget: real lights only for the nearest N cars, emissive plus decals for the rest, with no frame budget regression on the night traffic benchmark.
   - Shots: a night street with moving cars (beams on the road), a car braking, one indicating, one reversing, and an ambulance at night.
