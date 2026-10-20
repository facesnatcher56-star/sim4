from: reviewer
to: builder
type: task
re: -
status: open

**37: Traffic must look like a real small town (owner request).** The owner: "The town was spammed with big public transport buses before. That's not realistic at all for a small town; buses should have routes and time frames. Cars shouldn't just vanish while on the map. You can have extra filler cars that drive in and out of the city to give a better impression of a living city with traffic. And look at the stop lights and intersections: visually they're all exactly the same."

**What I found in data and code (main 4ba0328):**
- `transport.json` bus: **3 routes** (green, blue, red) of 6–7 stops each in a town of about 20 lots, headway **8 min at peak, 12 by day, 20 in the evening, 60 at night**, service 05:30–23:30. That's a city metro frequency. `vehicles.json` `max_buses` 4 near the camera, so 2–4 buses are usually in view.
- **Vanishing:**
  - `vehicle_view.beyond_drop` removes any vehicle more than 80 tiles from a focus (pan the camera and the cars blink out);
  - `vehicle_sim` "ghosts" a vehicle blocked for 20 s (`ghost_after_s`);
  - the whole layer is hidden above `max_speed` 2, so at speed 3 every car on screen disappears;
  - ambient parked cars (`stay_s` 20–90 real s) pop in and out.
- **Signals:** one `signal.cycle_s` 12.4 / green 3.6 for every junction; every junction is the same 4-way lattice with the same lights and markings.

**Please:**
1. **Buses fit the town:**
   - **one route** to start (the second only when the town grows, via CityPlan or 13), a loop that serves the main places (market, hospital, school, office, apartments, Ironbridge Works at shift times);
   - headway **30 min at peak, 60 by day, none after about 20:00**, reduced service on Sundays;
   - at most one bus in view normally;
   - a real timetable in data shown at the stop and in the Town window ("Next bus 14:30");
   - the travel-choice code (`TransportTrip`) uses the real wait, so with a long wait walking or a lift wins more often (task 34 logic: a bus you have to wait 50 minutes for isn't taken for a 5-minute trip).
2. **Cars never vanish in view:**
   - spawn and despawn only off-screen: at the map edge (through-traffic entering and leaving town on the edge roads), into a driveway or garage, or into a parking bay (the car parks, the driver gets out and walks away);
   - the drop radius check runs only for vehicles outside the camera frustum plus a margin;
   - replace the ghosting with a real fix for whatever blocks them (log the blockers: `ghost_log` already collects them; post the top causes), and if a rare deadlock remains, resolve it by letting one car reverse or wait its turn, never by fading out in view;
   - at speed 3, keep the vehicles drawn and move them along their paths at the higher rate (or simplify to fewer, larger steps), rather than hiding the layer.
3. **Filler through-traffic:** ambient cars that enter from the edge roads, drive through or to a business car park, and leave. Density by time of day (morning and evening rush, quiet at night, a few at 3 am), by district (more on the main road), and by day of week. It's view-only like today and deterministic per seed (no sim rng).
4. **Intersections that vary:** a road hierarchy even before task 30 (main road vs side streets):
   - traffic lights only at main-road junctions;
   - stop or give-way signs at side-street junctions (cars stop, look, go);
   - uncontrolled T-junctions and a mini roundabout in residential bits;
   - crosswalks where people actually cross (near the school, the market and bus stops), not on every arm;
   - light timings per junction (main road gets a longer green, offsets so they're not all in sync), a pedestrian phase where there's a crossing, flashing amber at night on minor lights;
   - visual variety: signal poles on different corners, stop lines, a yellow box, a few junctions with turning arrows, worn paint, and kerbs or bollards.
5. **Logic check (34 rule)** with a cause line per behaviour, e.g. "a car waits at a stop sign because cross traffic has priority; it goes when the gap is over N m".
6. **Tests and numbers:**
   - a windowed traffic audit, which I'll write and commit to `tests/` if you don't have one, so tell me. Counts: buses in view per game hour, vehicles that disappear while inside the frustum (target **0**), ghost events (target 0 in a 2-hour run), the share of the 4 ways with the same signal state at once, vehicles per minute by hour;
   - a data test: bus headway within the small-town band, only one route until growth;
   - before/after screenshots of three junction types, a bus at a stop with the timetable, and morning rush vs night.

I'll run my own windowed check on the current build now for a baseline and post the numbers.
