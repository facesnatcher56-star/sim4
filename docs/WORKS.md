# Industrial careers and the works (task 31)

Data: `data/careers_works.json` (careers, merged into the careers table by `Data._merge_career_files`; `works` = numbers and texts; `content` = station objects and work interactions). Lot: `works` ("Ironbridge Works"), template in `data/lot_templates.json`, venue type `works` in `data/venues.json`, slot [4,2] of `data/map_layout.json` (the map grew by one road column: `World.MAP_W` 200). The industrial district comes with task 30; the careers only name the lot id, so they can move.

## Careers
| Career | Path | Tier of danger | Layoff weight | Night / late shift |
|---|---|---|---|---|
| `factory_worker` | Line Hand, Machine Operator, Line Lead, Plant Supervisor, Plant Manager | 2 | 1.5 | Swing, Night Line |
| `warehouse_worker` | Picker and Packer, Forklift Driver, Dispatcher, Shift Leader, Logistics Manager | 1 | 1.2 | Evening Run, Night Dock |
| `construction_worker` | Labourer, Bricklayer, Crane and Plant Operator, Foreman, Site Manager | 3 | 1.6 | Dawn Crew; rained off in thunderstorms and snow |
| `mechanic` | Garage Hand to Garage Owner | 1 | 0.8 | Late Garage |
| `utility_tech` | Meter Reader to Chief Engineer | 2 | 0.6 | Night Control Room |
Adults and elders only (`Careers.why_not_work`; `teen_careers` is unchanged). Skills: handiness, fitness, logic (charisma for the top level). Each career shows its work on the lot (`visible_work`: `work_line`, `work_pallets`, `work_site`, `work_bay`, `work_panel` at `assembly_line`, `pallet_rack` / `forklift`, `site_materials`, `vehicle_lift`, `control_panel`) and trains its skills while doing so. Without a map the old hidden shift is used.

## Rules
- **Injuries (05)**: `Works.injury_tier` = max(accident table `physical_careers`, career `injury_tier`). 1 physical, 2 x2 dice, 3 adds the hazard marker `acc_job_hazard` (x1.5). Workplace injuries feed `WorksEvents.hurt`, which raises the strike chance.
- **Layoffs (07b, 13)**: `layoff_mult` weights the recession dice (`MarketWork._layoffs`, `MarketEconomy._townie_jobs`); the `layoff` incident has risk_mults for heavy industry and for the grid / garage.
- **Closures**: `WorksEvents.close_works(career, cause)`: residents get 40 hours of severance and the `laid_off` buff, townies start looking, chronicle line. Daily dice grow with the recession and the layoff weight.
- **Strikes**: `WorksEvents.schedule_strike(career, days, cause)`: announced today, out from tomorrow. A strike day is no penalty and no pay (union members get strike pay), townies of that career are not at work, a grid strike stops the repair bonus. It ends in a 3 to 8 percent raise (`WorksEvents.raises`, paid through `WorksPay.adjust_pay`) or in nothing.
- **Unions**: join / leave by command; 2 percent dues per shift; a third of industrial townies are members (id based).
- **Overtime**: opt-in per job (`works` command, `overtime`), on a busy day (25 percent) two extra hours at time and a half, costs energy and gives `overtime_worn`. It is paid, not played out as a longer shift.
- **Utility networks (12.1)**: every tech in town (residents and townies) shortens outages: `WorksUtility.crew_mult` (+6 percent each, up to +30) in `UtilityEvents`.
- **Townies**: take these jobs (`data/story.json` careers); a quarter work the night shift (`WorksPay.townie_shift`, used by `CommuteTownies.window`).
- **Command**: `Commands.run({action: "works", args: {action: "join_union" | "leave_union" | "overtime" {on} | "status"}})`.

## Storyteller hooks (task 29)
Call these from the storyteller; both are safe at any time and return false / 0 when nothing happens.
- `WorksEvents.schedule_strike(career: String, days: int = -1, cause: String = "") -> bool` (days -1 = 2 to 5). Game events `works_strike`, `works_strike_over {won}`, `works_off_day {why}`.
- `WorksEvents.close_works(career: String, cause: String = "") -> int` (people who lost work). Game event `works_closure`.
- `WorksEvents.strike_chance(career)` / `closure_chance(career)` give today's dice; `WorksEvents.raises`, `WorksEvents.counts` are readable state.
State is saved in the city block (`systems.city.works`). Clock row: `day/WorksEvents.on_day`.

## Tests
`tests/works_careers_test.gd` (fast), `tests/works_map_test.gd` (real map: lot, stations, commute), `tests/works_longrun_test.gd` (slow: strike and closure rates, recession, promotion cadence).
