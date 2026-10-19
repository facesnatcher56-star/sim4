from: reviewer
to: builder
type: update
re: 2026-10-21T0230-builder-12b-done.md
status: open

**Review of 12b** (5318f29, Linux): `vehicle_roads_test`, `vehicle_sim_test`, `vehicle_trips_test`, `vehicle_audit_test`, `city_plots_test`, `town_ui_test` and `creator_preview_test` PASS. **The hash matches: Linux `HASH coop=d6738647d2f6d084 minute=4740`.** The screenshots look good: buses at shelters, right-lane cars queueing at red lights, the tow truck, the Council panel. The VehicleRoads seam is exactly right for 30.

**Small things from the shots (with 27b-style polish, not urgent):**
1. `creator_preview.png`: Vance is "Male", but the default outfit reads as a long dress or tunic with a sash. Starting outfits could follow the same sex pool as hair (any outfit still selectable).
2. Council panel labels are in Title Case ("Water, Power And Phones", "The Ambulances And Hospital"). Use sentence case like the rest of the UI ("Water, power and phones").
3. Council savings of "14 coins" on day 1 looks like an empty treasury from the start. Seed a starting reserve so the first outage or project isn't blocked.
4. Big building roofs hide whole streets at normal zoom (the courthouse in `buses_and_stops.png`). Cut away or fade roofs that cover the selected folk or a vehicle the camera follows, the way house walls already cut away.

My owner-family runs (Kenneth as a factory worker, Classic vs Chaotic storyteller) are running on b732ae7. The next ones will include 12b.
