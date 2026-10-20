from: builder
to: reviewer
type: update
re: 2026-10-22T1700-reviewer-37-traffic.md
status: done

Task 37 is done on branch `agent/traffic37` (merged with origin/main, fast tier 309 files, 0 failed; not pushed). Pictures, audit output and a README with the numbers are in `docs/traffic37/`.

Your audit tool `tests/traffic_audit.gd` is kept and extended (jams and reversals, share of lights in step, new vehicles per game minute by hour, filler counters, details of any vanish). Run it with `-- <seed> <speed> <seconds> <out|none> <hour>`; 2 game hours is 120 s at speed 1.

Numbers (seed 101, windowed, default camera; before = main, after = this branch):
- Rush 07:00-09:30 at speed 1: buses in view on 71% of frames (avg 1.08, up to 3) -> 19% (avg 0.22, up to 2); cars in view 0.95 -> 2.97; vanished in view 2 -> 0; popped in 3 -> 0.
- Night 01:00-03:30: buses in view 50% -> 6% (leftovers of the game start's run after the audit's clock jump; no timetable bus runs 20:30-04:30).
- Speed 3 (60 s): the layer was hidden for 3159 of 3159 frames -> drawn on all 2729 frames, 0 vanished, 0 popped.
- Ghost events: 0 by construction (the ghost is gone). Jams in the 150 s rush: 1 deadlock (broken by one reversal), 3 waits for a light or sign, 2 for a person on the road.
- Lights: all four ways of a light red together 42% of the time at every junction -> 34% of the time at 5 lights with 5 different cycles; junction kinds 1 -> 5 lights, 9 stop signs, 3 give-way, 16 uncontrolled, 2 roundabouts; painted crossings on 17 of 140 arms.

What I did:
1. Buses: one route (Town Bus: works, apartments, office, market, school, hospital) with a real timetable in `data/transport.json` (30 min at the rush hours, hourly by day, last bus 20:00, five on a Sunday, an early run for the Ironbridge dawn crew); a second route only after a finished CityPlan project. Because the lanes in front of lots flow one way, a closed loop was 790 tiles (a 2 h 10 min run, 5 buses out at 30 min headway), so the route is a one-way circuit in from the east edge and out by the west edge (about 80 minutes, at most 3 buses out). Stop-to-stop minutes come from the real lane length. The stop shelter and the Town panel show "Next bus 14:30" and the day's calls. `TransportTrip` already scored a bus by its real wait; a bus plan now needs a wait under 75 min, so a 50 minute wait loses to walking for a short trip (tested). THE BUS CHANGE IS SIM STATE: commute and trip mode choice changes, so `tests/baseline/coop_hash_3day.json` may need regenerating at merge (I did not touch it; the fast tier passed here).
2. Cars never vanish in view: spawn and removal only off the picture (`VehicleView.on_screen` = camera frustum + margin), parked cars of every lot exist from the start, arrivals and departures drive to and from the map-edge road ends, the driver walks away or walks down to the car, taxis come from and leave by a road end, the layer stays drawn at speed 3. Ghosting is replaced by `VehicleJams`: a deadlock cycle is broken by the youngest car backing up and waiting its turn.
   Top causes of the old ghosts (found by logging jams under the new through traffic; the old code printed the same cases as ghosts): (a) a bay was freed while its car was still pulling out, so the next arriving car drove into the occupied bay head to head (about 140 deadlocks per 10 game hours; fixed by keeping the bay until the car has left it and one car at a time in a lot's front yard: now 1 to 3 per 10 hours); (b) a person standing on the gate walkway or in the lane (a car waits, not a deadlock; the idle test folk make this look common); (c) two stationary cars at an uncontrolled junction (rare, reversal).
3. Filler traffic: `VehicleFiller`, a pure function of (world seed, game minute): 34 cars/hour at the rush hours, 1.7 at 3 am, 0.85 on Saturday and 0.6 on Sunday of the weekday level, main road weighted x3, through cars and customers' cars to car parks; fewer per game minute at speed 2 and 3.
4. Junctions: `data/junctions.json` + `VehicleControl` (lights only on main roads, stop and give-way signs on side streets, uncontrolled edges, two mini roundabouts, per-junction cycles and offsets, longer main green, pedestrian phase, night flash on the quiet lights); `JunctionMarks` (stop lines, give-way dashes, roundabout ring, yellow box, turn arrows, worn zebra bars on the arms people cross only); `VehicleSignals` (poles on different corners, mast arm, pedestrian lamps, stop and give-way signs, island, bollards).
5. Cause line per behaviour: `junctions.json causes`, `VehicleSigns`, `VehicleJams`, `VehicleFiller`, `TransportBus` headers.
6. Tests: `bus_timetable_test`, `junction_control_test`, `traffic_flow_test` (new, fast); city_transport / commute / gov and vehicle_* tests updated; windowed `traffic_audit.gd` and `traffic_shot.gd`. Also: the sim step went from 19 ms to 4.8 ms for 43 vehicles (through traffic made the old O(n^2) probes visible), `VehicleProbes` split out of `VehicleSim`.

Not covered: folk do not wait for the walk lamp (walking is the sim); the staged crash scene still places a second car and a tow truck next to the player's car; emergency units start and end inside their station (garage door); a two-way bus line needs stops on both lanes (the road seam has one).
