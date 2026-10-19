# Vacations, travel and the cruise ship (task 22 / 22b)

Players book a holiday (any computer or the Travel Desk: interaction "Plan a Holiday" opens `VacationDialog`; or `Vacation.book_and_go` from code),
pay travel + lodging + spending money (the unspent part comes back), the travellers leave (hidden journey), live the holiday in a **holiday map that is
loaded into a zone of the Southwoods strip for the duration of the trip**, and come home with souvenirs, photos, a glow and stories.
A **cruise** is the same trip with a five-deck ship, a timeline of ports of call, a programme, crew and passengers, rare incidents and left-behind rules.

## Files (ownership)
| Area | Files |
|---|---|
| Data | `data/vacation.json` (config, 4 destinations with weather + events, content block: objects / interactions / buffs), `data/cruise_ship.json` (ship, classes, fees, packages, ports, crew, programme, sea, incident numbers), `data/destinations/{beach,mountain,city,camping,ship}.json` (maps, lot-template format, ship uses `levels`), `data/incidents/22_cruise.json`, `data/death_causes/22_cruise.json` |
| Map tools | `tools/vacation_gen.py` builds `data/destinations/*.json` (the output is committed) |
| World | `scripts/world/dest_defs.gd` (map registry), `dest_loader.gd` (load / unload a zone) |
| Systems | `vacation.gd` (state, API, command door, clock hooks, save), `vacation_cost.gd` (quote, rules), `vacation_trip.gd` (life cycle), `vacation_work.gd` (leave, school), `vacation_home.gd` (empty house, burglary odds), `vacation_life.gd` (locals, weather, events, photos), `vacation_return.gd` (what comes home), `vacation_log.gd` (story log + chronicle), `vacation_content.gd` |
| Cruise | `cruise.gd` (API, timeline), `cruise_route.gd` (itinerary), `cruise_shore.gd` (ports, boarding, left behind, flights), `cruise_life.gd` (programme, seasick, romance), `cruise_crew.gd` (crew + passengers), `cruise_incidents.gd` (handler), `cruise_crime.gd` (ship cases, security, police handover), `cruise_killer.gd` (22b) |
| UI | `scripts/ui/vacation_dialog.gd` |
| Tests | `tests/vacation_{kit,maps,trip,life,ui}_*`, `tests/cruise_{trip,incidents,killer,longrun}_test.gd`, `tests/vacation_shot.gd` (windowed screenshots) |

## How a trip runs
`booked -> outbound -> there -> inbound -> done` (`VacationTrip`, driven by absolute due minutes, so a clock jump or a load changes nothing).
* **Booking** `Vacation.quote(hid, dest, opts)` / `book` / `book_and_go`. opts: `length_days`, `who` (default the household), `guests` (townie friends, max 3), `cabin_class` (inside / ocean / suite), `package` (standard / honeymoon (married) / anniversary (couple)), `sitter`, `depart_min`, `travel_min`, `seed`. Refused with a plain reason when someone is busy (hospital, custody, away), children would be home alone, or the bills still to come would not be covered. A busy traveller postpones the departure (30 min steps, up to 8 h, then it is called off with a refund).
* **Journey**: `Away` reason "vacation" (hidden, needs keep ticking). **Arrival**: the map goes into a free zone (`DestLoader.load_zone`, lot id `trip_<zone>`), the party is placed on it, locals appear. **Return**: hidden journey home, zone unloaded, `VacationReturn.apply`.
* **Work and school**: paid leave per year = `base_paid_days + paid_days_per_level x level` (data); a lost work day uses a paid day (pays the wage) or is unpaid (performance penalty); school days lost cost grade points unless a holiday. `CareerShifts` does not send a traveller to work (`Vacation.on_trip`).
* **Home while away** (`VacationHome`): bills still come and auto-pay (the report lists them), plants lose water and wilt unless a sitter was paid, mail and papers pile up, an EMPTY house multiplies the burglary incident's rate (x3, x0.6 with a sitter, x0.5 with a `burglar_alarm`; hook `IncidentRisk.effective_rate` via the incident tag `burglary_odds`).
* **Return effects**: unspent money back, "vacation glow" + "well rested" buffs, a memory (`Folk.remember "vacation:<dest>"`), souvenirs and photos (collections per household, shown in the dialog), stories told to up to 4 friends (gossip item + the `travel` topic + a friendship bump), chronicle line, history entry.

## Destinations
Beach resort (sunbeds, pool, surf, beach bar, hotel rooms), mountain cabin (cabin, lake fishing, trails, campfire, skiing when it snows), big city (museum, restaurants, shops, hotel, club, pickpockets), camping (tents, campfire, bugs, rain). Each has local people (generated `Folk`, crowd driver), its own weather table (rain / heat / snow buffs for people outdoors) and a data-driven event list (`destinations.<id>.events`). New destination = a JSON entry + a map from `tools/vacation_gen.py`.

## The cruise
* **Ship map**: 5 decks on a 32 x 22 zone: -1 crew + inside cabins, 0 promenade (reception, dining hall, buffet, shops, atrium bar + piano, medical bay, gangway), 1 entertainment (kids' club, theatre with stage and seats, casino stub, nightclub, bar, library), 2 sun deck (pool, hot tubs, spa, gym, bridge), 3 suites and ocean-view cabins. Lifts from the promenade up, stairs down to the crew deck.
* **Itinerary** (`CruiseRoute`): day 0 sail 17:00, odd days port days (dock 08:00, shore 09:00, last call 15:30, auto-board 16:00 and 16:30, sail 17:00), even days at sea, last day home quay 07:00 / disembark 09:00. Ports load a destination map into a second zone.
* **Missing the ship**: whoever is still ashore (or busy with a player-chosen action, or `Cruise.command(.., "linger")`) when it sails is **left behind**: stressed (buff), pays `flight_base + per day left` (can go into debt), flies home alone (10 h) and arrives late; the others go on.
* **Life on board**: welcome buffet, safety drill, captain's dinner + formal night (first sea day), talent show, deck party, theme nights, shows, farewell dinner; seasickness (rough seas, storms), shipboard romance with passengers (real townies), drama. Honeymoon / anniversary packages add a welcome and a buff.
* **Incidents** (`22_cruise.json`, lot scope while a household member is `on_cruise`, force with `Incidents.force(id, {lot: "home:1"})`): `cruise_storm`, `cruise_norovirus` (Health illness kind `norovirus`, spreads, cancels shore days), `cruise_fire` (`Fire.ignite`, the crew put it out after 25 min), `cruise_overboard` (search and rescue, `rescued` / `victim` force keys; a loss is `Aging.kill "overboard"`), `cruise_cabin_theft`, `cruise_brawl` (cases held by ship security, handed to the police at the next port).

## 22b test hooks
* `Vacation.book_and_go(hid, "cruise", {length_days, cabin_class, guests: [], seed})` -> `{ok, trip, ship: {id, name, decks, cabin_class, package}, route: [{day, kind, port, label}], ports: [{day, port, label}], boarding: {open_min, all_aboard_min, sail_min}, boarding_min, sail_min, arrive_min, return_min, home_dock_min}`.
* Every happening goes through `VacationLog.note` -> `Events.game_event("chronicle", {kind: "cruise_<tag>", text, day, subjects, severity, public, place: "cruise", trip, tag})` (`place: "vacation"` for other trips); `VacationLog.entries(trip_id)` keeps the last 300 for the story.
* `Incidents.force("serial_killer_aboard", {ship: <trip id or ship id>, delay_hours, killer})`: `CruiseKiller` puts a killer among the passenger townies. Isolated victims at night (a hidden disappearance: the victim leaves the deck), noticed at dinner or the morning headcount (`CaseDiscovery` "missing"), passengers frightened (`ship_scare`), the captain restricts movement (no shore leave, programme cancelled, `confined` curfew), ship security investigates every hour (`CruiseCrime.security_hour`, small ship: everybody's movements are in the log, so the bonus per victim), may detain the killer in the brig; the town police are held off at sea (`ship_hold` on the case, hooks in `CaseInvestigation.work` and `CaseDiscovery.on_day`) and take over at the next port or the home quay (`CruiseCrime.handover`): the cases go into the normal flow, an arrest runs `JusticeProcess.arrest` (charges, trial, sentence). `CruiseKiller.status(trip_id)` for reports. Non-graphic: notifications and chronicle only.
* Repeatable headless: everything random comes from the trip's seeded stream (`Vacation.rng_for`, saved with the trip), the incident stream and the justice stream; the same seed gives the same story (`cruise_killer_test` runs a voyage twice).

## Tiers, cadence, active set, caps (docs/PERFORMANCE.md rules)
| System | Tier behaviour | Cadence | Active set | Caps |
|---|---|---|---|---|
| `Vacation` trip machine | idle = one `trips.is_empty()` check (0.0002 ms per call) | per minute, only compares due minutes | trips in progress | one trip per household; history 40, log 300 |
| Destination zone (`DestLoader`) | the destination is FULL (ordinary lot, rooms, routing, autonomy); the town is on its cheap layer: travellers do not wake venue crowds (`player_near` skips `trip_zone`), the home lot is summarised by `VacationHome` | load + unload of the ship 23 ms (the small maps less) | zones in use | 4 zones (ship + port = 2) |
| `VacationLife` | locals are crowd-style NPCs (`CrowdDrive`, no full Autonomy); weather and events are dice | NPC upkeep, weather check and events hourly; weather roll daily | trips that are "there" | locals <= 8, roster only; photo captions 40 per trip |
| `VacationHome` | STATISTICAL (a few numbers) | daily | households with an empty house | none |
| Cruise timeline | exact-minute entries consumed in order; programme / ports / sailing are data | per minute (entry compare), hourly stochastic checks | cruises that are "there" | timeline ~10 entries per day; crew 11 + passengers 8 |
| `CruiseIncidents` / `CruiseKiller` / `CruiseCrime` | FULL on the ship, dice at hourly cadence from the incident framework | hourly | cruises that are "there" | cases cap of the justice track (160); 3 killer victims per run |
Measured (this machine, loaded): a 3-traveller holiday with 6 locals and full autonomy costs 5.7 ms per game minute (the same household at home with the town running: 8.6 ms); loading + unloading the ship 23 ms; `Vacation.on_minute` with one trip 0.009 ms, idle 0.0002 ms.

## Shared-file hooks (all tiny, listed for the scheduler refactor 17.2)
`SystemsManager` (reset_all, `_minute_steps`, `_on_hour`, `_on_day`, game-event routing: one line each), `SaveLoad` (snapshot + restore), `SysContent` (install order), `IncidentRisk.effective_rate` (burglary odds), `IncidentFlow` (`last_force`, forced ctx visible to handlers), `CaseInvestigation.work` / `CaseDiscovery.on_day` (`ship_hold`), `CareerShifts.on_minute` (skip travellers), `NeighborhoodLots.player_near` (skip travellers), `Neighborhood.label_of` (zone label), `WorldRegions.remove_region`, `hud.gd` (dialog + event), `tests/run_all.gd` (SLOW list).

## Rough edges
* The travel agency is a Travel Desk object (buy it like a computer, or place it in any venue template), not a lot of its own: the map has no free lot slot.
* Cabins are priced by class and the party starts in its own cabin, but beds are not owned: autonomy sleeps in the nearest bed on the ship.
* The swimming pool uses the hot tub model (4 x 2 footprint); the casino is a window display (slot machines only look); crew are not a career yet.
* The killer is always a passenger (a townie); victims who are townies simply stop being on deck, so the grave appears when the body is found.
* Locals and passengers are crowd-style NPCs: they come and go with needs, are not saved, and are respawned after a load.
* A cruise has a sea state (calm / breezy / rough, storms from the incident) instead of a destination weather table; ports have no weather roll of their own.
