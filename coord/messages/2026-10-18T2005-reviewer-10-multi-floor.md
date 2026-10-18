from: reviewer
to: builder
type: task
re: -
status: open

**10: Multi-floor buildings, with no fixed limit on floors.** From the owner. The whole world is single-storey today (and `docs/OPEN_WORLD_PLAN.md` lists multi-floor under "Not building"). The owner wants buildings to have **as many floors as they need**, above and below ground, especially businesses: a hospital, office towers, apartment blocks, a courthouse, a police station, a parking garage.

**Priority:** start this **right after the current parallel batch (02, 03, 05, 06)** and **before** the crime and legal track (04, 09, 09b). Every new system adds more code that assumes a flat grid, so it gets more expensive the longer it waits. If you can run it in parallel without clashing with 02 to 06 files, even better.

**1. World model**
- Every tile position gets a **level** (int; 0 = ground, negative = basements, no fixed max). Use `Vector3i` or a `(tile, level)` pair consistently across `World`, `WorldPaths`, `WorldObjects`, `WorldEdit`, `WorldRooms`, `WorldRegions`, the sim (`Folk.tile`, interactions, reservations) and saves.
- Floors, walls, rooms and objects live per level. A level only exists where a building has it (no full-map grid per level). Store levels sparsely per building or region so a 20-storey tower doesn't cost a 160x120 grid per floor.
- Bump the save version; old saves are refused as usual.

**2. Getting between floors**
- **Stairs** (2x1 or so, they connect level n and n+1), **elevators** (one shaft object spanning levels, with a short wait and a capacity, plus an out-of-order state), **ladders** for basements and attics, and **fire escapes** on the outside.
- **Pathfinding:** A* inside a level, with stairs and elevators as portals in the existing portal graph. Autonomy distance counts vertical travel (stairs are slower for elders, toddlers, injured and exhausted folk). Elevators are preferred for long climbs and carrying things.

**3. Camera and view**
- **Floor up/down controls** (buttons plus Page Up/Page Down). Levels above the viewed one are hidden, and the viewed level uses the existing cutaway walls.
- The camera follows the selected Folk's level. Folk on other floors show as a faint marker or icon.
- Buildings far from the camera render as one merged exterior shell of the right height, with interiors only for the active building.

**4. Build mode**
- Add a floor above or a basement below, and place walls, floors, objects, stairs and elevators per level. A roof on the top level, with roof styles.
- **Structure rules:** an upper floor needs walls or supports under it, and there's no floating floor. A level can only be added while a staircase or elevator reaches it.
- **Cost grows** with each level.

**5. Buildings that use it** (update the venue and house generators and the lot templates):
- **Hospital:** multi-floor, with ER on the ground floor, wards, surgery and a maternity floor, so births can happen there, and a morgue in the basement (non-graphic, just a room). It replaces task 01's hidden hospital rabbit hole with a real place, keeping the statistical mode for far townies.
- **Office tower:** each career or company has its own floor (ties into task 11, real commutes).
- **Apartment buildings:** several households per building, one unit per floor or several per floor. This is good for task 08's town growth and gives player kids somewhere to move out to.
- Courthouse, police station with cells in the basement, a parking garage, and a school with 2 floors.
- Houses: 1 to 3 floors plus an optional basement (the tornado shelter from task 06 lives here).

**6. Systems that must respect levels**
- **Fire** (03) spreads upward faster, and stairs and elevators become exits. Use the fire escape, and don't take the elevator in a fire.
- **Accidents** (05): falls on stairs, and an elevator getting stuck (rare).
- **Disasters** (06): tornado shelter in the basement or a ground-floor bathroom, floods hit basements first, and earthquakes risk upper floors more.
- **Crime** (04): burglars use ground-floor doors and windows.
- **Rooms, comfort and line of sight** are per level.
- **Weather:** snow and rain only reach the top roof.

**Tests:** paths across levels (stairs, elevator, mixed), save and load with several levels, structure rules, fire spreading upward, a performance probe with a 15-floor tower plus the full map (frame time, path cost), and a slow test that runs an apartment building with several households for game days.
