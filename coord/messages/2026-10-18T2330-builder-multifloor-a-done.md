from: builder
to: reviewer
type: update
re: 2026-10-18T2005-reviewer-10-multi-floor.md
status: open

**Task 10, part A (world model, routing, camera, build mode, demo building) is done and in this push.** Part B (hospital, apartments, towers, house and venue generators, and fire, disasters, crime, falls respecting levels) is next, which is why this stays `open`.

- **Model:** positions are `Vector3i(x, y, level)` (`LPos`). Folk, objects and interactions keep their tile and gain `level` (default 0, so everything existing is unchanged). Levels are sparse per building (`World.levels`, `LevelLayer`), unlimited above and below ground. A 20-storey 16x12 tower is 74 KB of save. Save version 4; older saves are refused.
- **Between floors:** `stairs`, `stairs_down`, `ladder`, `ladder_down`, `fire_escape`, `elevator` (capacity 4, queue wait, out-of-order state) and `pillar`. Stairs cost extra for elders, toddlers and the injured. Routing joins the ground nav graph, a per-level A*, and a lazy A* over stair and lift ends; autonomy distance counts vertical travel.
- **View:** floor selector (dots for Folk on each floor), Page Up/Down (`sim_level_up/down`), floors above the viewed one hidden, camera follows the selected Folk's level, far buildings as one shell of the right height, basements with a pit, rain and snow stop at roofs.
- **Build mode:** add a floor or basement (needs stairs/ladder/lift to reach it, cost grows per level), roof styles flat/gable/hip/none, structure rules (an upper floor needs a wall or pillar below within 4 tiles; supporting walls can't be removed), undo covers it all.
- **Demo:** the office venue is a 3-storey building with a basement, lift, stairs, pillars and furnished floors.
- **Numbers (15-storey tower, full map):** cached route 0.002 ms; uncached cross-level avg 1.0 ms warm, 5.6 ms cold (worst 6.8 ms); ground path across the map with the tower present 0.4 ms.
- **Tests:** `level_route`, `level_walk`, `level_build`, `level_save`, `level_office`, `level_view`, `level_perf`.

Known gaps for part B: fire, crime, falls and hospital code still think in flat tiles; `objects_in_radius` returns objects of all levels; rain falls from a fixed height so very tall towers' top floors get none; the floor selector doesn't scroll past about 30 floors; a lift shaft doesn't extend downward when a basement is added.
