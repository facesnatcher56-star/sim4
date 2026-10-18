from: reviewer
to: builder
type: task
re: 2026-10-18T2230-builder-commute-done.md
status: open

**11b: Transport, pulled forward from task 12.** From the owner: people don't walk to work or around town every day unless the place is very close. They drive, take the bus, or get a ride. Commutes (11) are walking-only right now, so move the **transport part of task 12** up to right after the performance job and the open fixes, before multi-floor (10) if they don't clash, or in parallel.

**1. Choosing how to travel** (every trip: work, school, venues, visits, errands):
- **Walk** only if it's close (around 10 minutes on foot, tune it), or as a fallback.
- Otherwise pick by what the person has and can afford, and by time, weather and traits:
  - Own **car** (fastest door to door, but costs fuel and parking).
  - **Bus** (cheap, fixed stops and timetable, some walking to the stop).
  - **Taxi** (fast, expensive).
  - **Bike** (cheap, slower than a car, not in snow).
  - **A lift** from a household member or friend going the same way.
- **Weather** pushes people off foot and bike. Active or outdoorsy folk like walking and cycling; lazy folk prefer the car.
- **Kids:** a **school bus**, or a parent drives them, or they walk if the school is close. Toddlers and babies go with an adult.

**2. Cars**
- Households can own cars. The starting household gets one depending on scenario funds, and more can be bought (a car dealer, or later from 13).
- Cars park on the home lot driveway or the street, and at destinations (parking spots, lots, the garage from 10).
- Fuel or charging, upkeep, insurance (13), and breakdowns (rare) with a tow and repair.
- Driving skill, plus learner's permits and licences for teens.
- Cars are visible on the roads (you already have car assets): they drive the lane polylines, stop at junctions and park.

**3. Public transport**
- **Bus routes** with visible buses, stops on the sidewalk, a timetable (more at rush hour, fewer at night), fares, and waiting at the stop (bench, rain, chatting with others waiting).
- **Taxis:** call one (by phone later, 14), it arrives and drives you.

**4. Townies use it too.** Near townies drive or bus visibly; far townies use it statistically. The number of cars and buses on screen stays capped, and only what's near the camera or the household is simulated in full.

**5. Ties to other tasks**
- **Traffic accidents** (05) happen to drivers and pedestrians.
- Drunk or reckless driving (09c), with police stops (04).
- Lateness (11) depends on the mode, traffic and the bus timetable.
- Car theft is a crime (04/09c).
- Snow and ice slow cars (06).
- The town budget (12) pays for the bus service.

**Performance:** follow the rule. Vehicles move along precomputed lane routes (no per-minute A* for them), only near ones get nodes, and far trips are just a travel time.

**Tests:** a folk who lives far from work takes the car or bus and is faster than walking; a folk next door walks; rain moves a cyclist to the bus; a kid takes the school bus; a household with no car and no money walks or takes the bus; the bus runs its timetable; a parked car blocks a parking spot; the vehicle cap holds on a busy map.
