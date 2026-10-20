# Task 37: traffic that looks like a small town

Owner: "The town was spammed with big public transport buses before... buses should have routes and time frames. Cars shouldn't just vanish while on the map. You can have extra filler cars that drive in and out of the city... And look at the stop lights and intersections: visually they're all exactly the same."

Branch `agent/traffic37`. Everything is view only except the bus timetable (a sim read: `TransportTrip` mode choice, so the coop hash baseline moves; regenerate at merge).

## What changed, in one line each (cause lines are in the data and the code comments)

| Item | Now |
|---|---|
| Buses | One route (works, apartments, office, market, school, hospital) with a real timetable in `data/transport.json`: 30 min at the rush hours, hourly by day, last bus 20:00, five buses on a Sunday, an early run for the Ironbridge dawn crew. The second route (East Link) only runs after a finished CityPlan project. The minutes on the sign come from the real lane route length. Stop shelters and the Town panel say "Next bus 14:30". `TransportTrip` already scores a bus by its real wait, so a 50 minute wait loses to walking (no bus plan beyond `max_wait` 75). |
| Vanishing | `on_screen` (camera frustum + margin) gates every spawn and removal: parked cars of every lot exist from the start (nothing pops in when the camera pans), arrivals and departures drive to and from the map-edge road ends, the driver walks away / walks down to the car, a vehicle at the end of its way waits until it is off screen, the layer stays drawn at speed 3, the 20 s ghost is gone. |
| Jams | `VehicleJams`: a cycle of waiting vehicles is broken by the youngest backing up a few metres and waiting its turn; a person on the road, a bus at its stop or a light is not a deadlock and is only logged. `sim.ghosted` is always 0. |
| Filler traffic | `VehicleFiller`: through cars and customers' cars from the road ends, a pure function of (world seed, game minute); by hour, weekday/weekend, day of week, road (main road weighted x3); fewer starts per game minute at speed 2 and 3. |
| Junctions | `data/junctions.json` + `VehicleControl`: lights only on main roads (one big crossing, four quiet ones), stop and give-way signs on the side streets, uncontrolled junctions at the edges, two mini roundabouts, zebra only on the arms people cross (school, market, bus stops), per-junction cycle and offset, longer main green, pedestrian phase, night flash on the quiet lights, stop lines, give-way dashes, yellow box, turn arrows, worn paint, poles on different corners, mast arm, bollards. |
| Performance | sim step 19 ms to 4.8 ms for 43 vehicles (grid, cached body points, path tables). |

## Numbers (windowed `tests/traffic_audit.gd`, seed 101, 1280x720, default camera; `audit/*.txt` hold the raw output)

| | before (main) | after |
|---|---|---|
| Rush 07:00-09:30 at speed 1: buses in view | on 71% of frames, avg 1.08, up to 3 at once | on 19% of frames, avg 0.22, up to 2 |
| Rush: cars in view (avg per frame) | 0.95 | 2.97 |
| Rush: vanished while in view / popped in | 2 / 3 | 0 / 0 |
| Night 01:00-03:30: buses in view | 50% of frames, avg 0.58 | 6%, avg 0.06 (leftovers of the game start's run after the audit's jump in time; no timetable bus runs 20:30 to 04:30) |
| Night: vanished / popped in | 0 / 1 | 0 / 0 |
| Speed 3 (60 s = 19 game hours): layer hidden | 3159 of 3159 frames, no vehicle | 0 of 2729 frames, avg 2.12 cars + 0.43 buses in view, 0 vanished, 0 popped |
| Ghost events | the mechanism existed (20 s of blocking, then a car drives through another) | 0 by construction; in the 150 s rush: 1 deadlock (two cars at an uncontrolled junction), broken by one reversal, 3 waits for a light or sign, 2 for a person on the road |
| Lights: all four ways of a light in the same state | 42% of the time, at every junction | 34% of the time, at 5 lights with 5 different cycles (about 14 to 22 s) |
| Junction kinds | 1 (30 identical 4-way lights, zebra on every arm) | 5 lights, 9 stop signs, 3 give-way, 16 uncontrolled, 2 roundabouts, painted crossings on 17 of 140 arms |

Headless `tests/traffic_flow_test.gd` (pretend camera, 100 s of rush): 0 vanished in view, 0 popped in, 0 ghosted, 60 filler cars started.
Bus geometry: the lanes in front of lots flow one way (west), so a bus goes round blocks between stops. A closed loop through the six stops was 790 tiles (a 2 h 10 min run, up to 5 buses out at the 30 minute rush headway), so the route is an open circuit: in from the east edge at the works, apartments, office, market, school, hospital, out by the west edge: 596 tiles with the drive in and out, about 80 minutes on the sign, at most 3 buses out at once, about 0.2 in the default view. A rider can only ride forward along the circuit (hospital to works has no bus).

Vehicles per game minute entering the layer (windowed audit, speed 1, includes the seeded cars of the first minutes): 07h 1.3, 08h 0.47, 09h 0.32, 02h 0.03, 03h 0.0 to 0.03 (a few a night); at speed 3 the same road holds the same number of cars (starts per game minute fall to 0.07 to 0.17). The data curve (`vehicles.json filler`): 34 cars/hour at 07:00 and 17:00 on a weekday, 1.7 at 03:00, 0.85 of the weekday level on Saturday, 0.6 on Sunday, weekend peak at noon.

## Pictures

`before_*` is origin/main, `after_*` this branch (`tests/traffic_shot.gd`).

- Junction types: `*_junction_big_light`, `*_junction_quiet_light_crossing`, `*_junction_stop_sign`, `*_junction_roundabout` (the old build has the same crossing on every corner), `*_junction_roundabout_b`, `*_junction_uncontrolled_T`, `*_quiet_light_night` (flashing amber / red).
- A bus at its stop with the timetable: `after_bus_stop_*` (the label "Next bus 13:43").
- Morning rush against night: `*_rush_0800`, `*_night_0300` (wide view).

## Not covered

- Pedestrians do not wait for the walk lamp (folk walking is the sim; the lamp and the all-red pedestrian phase are for the cars and the picture).
- The crash scene (a second car and a tow truck placed by the crash of a player's trip) still appears next to the player's car; it is staged, not through traffic.
- Emergency units start and end inside their station (garage door).
- The audit jumps the clock; real play does not, so the night bus count there is higher than a played night would give.
- The bus cannot turn back (one-way lanes in front of lots), so it is a one-way circuit; a two-way line needs stops on both lanes of a road, which the road seam does not model.
