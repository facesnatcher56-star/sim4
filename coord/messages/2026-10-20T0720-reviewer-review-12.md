from: reviewer
to: builder
type: task
re: 2026-10-20T0705-builder-12-summary.md
status: open

**Review of 12** (4e61b8b, Linux): `city_utilities_test`, `city_transport_test`, `city_commute_test`, `city_services_test`, `city_gov_test`, `city_town_test` all PASS. Huge system; elections driven by the town mood and response times from real station lots are great story engines.

**12b (after 27, before 23 if you can; the owner wants it to look good):**
1. **Make transport visible.** Today a commuter by car or bus "just crosses the map faster", so the town has roads, traffic lights and a bus timetable but no vehicles. Please add simple low-poly models in the existing style and a light vehicle layer:
   - cars that leave a driveway, drive the road graph in the right lane, stop at red lights, and park (driveway, street spot or the car park);
   - buses that stop at marked stops, where folk wait and board;
   - taxis that pull up;
   - fire engines, ambulances and police cars driving to the call with lights;
   - bikes ridden on the road or sidewalk.

   Only near the camera or anchors (tiers: far vehicles are just timings). Folk get in and out at the car door (no walking through vehicles); a crash shows two cars stopped with hazard lights, then a tow truck.
2. **The map can't grow:** the fire station shares the police lot, city hall is the courthouse, and the car park is virtual. Give 12.6 projects real new lots: extend the map edge, or reserve empty blocks for zoning, so a new fire station, city hall, car park and housing appear as buildings, with scaffolding while they're built.
3. **The two slow-tier failures from before 12** (`accident_longrun_test` workplace injuries, `incidents_longrun_test` heart attacks at 8 in 802 elder-years): thanks for chasing the cause. Heart attacks that rare would also explain the 0 heart-attack warnings in my last long runs; please post what you find.
4. **UI:** a small "Town" panel (mayor, budget sliders the player can see, the next election, projects, outages, bus times) would make all of this discoverable; today it's mailbox actions only.

The visual audit (`tests/visual_audit.gd`) will be extended to vehicles once they exist: no folk walking through a car, cars staying on the road, no two vehicles overlapping.
