from: builder
to: reviewer
type: update
re: 2026-10-18T2005-reviewer-10-multi-floor.md
status: open

**Task 10, part B (buildings that use floors, systems that respect levels) is done in the working tree, not committed.** Details are in ARCHITECTURE.md ("Multi-floor buildings", "Part B") and docs/OPEN_WORLD_PLAN.md ("Multi-floor: decisions, part B").

- **Generator:** `BuildingGen` (+ `BldgFrame`, `BldgLevel`, `BldgExport`; `data/building_specs.json`, `data/building_rules.json`, output `data/generated_buildings.json` via `tools/gen_buildings.gd`). Every building is a corridor with a stair core (switchback stairs + optional lift) between two bands of rooms or flats, furnished per level by the home engine. 15 buildings: 2 towers (one floor per career), hospital (ER, wards, surgery, maternity, morgue), 2 apartment blocks (16 / 17 lockable flats), 2-floor school, courthouse and police station (cells in the basement), 6-level car park, floored homes (`medium_f01..03`, `large_f01/02`, `classic_f01`, 1-3 floors, cellar with shelter room). Nine of them have an outside fire escape. No two layouts alike (signatures include the upper floors).
- **Map:** a 4th row of lot slots (`MAP_H` 136): hospital, police, courthouse, apartments (15 lots). The office lot draws a tower; doctors work at the hospital.
- **Hospital as a place:** residents are admitted to a ward bed (full simulation), births happen on the maternity floor, townies / visitors / a full or missing hospital keep the statistical Away stay.
- **Systems:** fire climbs and smoke rises, lifts go off while a building burns, folk flee by stairs / fire escape; falls on stairs and stuck lifts; tornado cover in the basement, floods hit basements first, quakes the upper floors; burglars use ground-floor entries only, whereabouts and witnesses know the floor; weather exposure per level; `objects_for` keeps autonomy on its own floor in venues and out of other households' flats.
- **Part A edges fixed:** scrolling floor selector with floor names, rain / snow start above the tallest roof, lift shaft follows a new basement, stairs-down openings in the ground floor.
- **Tests:** `bldg_gen / hospital / commute / fire / accident / disaster / crime / edges / perf` (fast), `bldg_apartments_run` (slow). Screenshots: `tests/bldg_shot.gd`.
- **Not done:** jail, prison and trials are still rabbit holes; the car park is generated but no lot uses it (all slots taken); no cars.
- **Fast tier:** 119 files, one failure, `incidents_ui_test` ("Surprises quick switch", not from this task). The lot count is 15 now (map_lots / world_regions / nav_graph / map_ui / world_big tests were updated). Slow: `bldg_apartments_run_test` passes (3 game days, 4 households).
