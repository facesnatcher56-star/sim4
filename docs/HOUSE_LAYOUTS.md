# Generated house layouts (no two homes alike)

Rule: every home in the neighbourhood (player home options, townie homes, any generated house) has its own floor plan, and venues
do not look like copies of homes. `HouseGenerator` builds the lots procedurally (deterministic per seed), validates them with the
real World, and writes `data/generated_lots.json` in the same schema as `data/lot_templates.json`.

## Files
| File | What |
|---|---|
| `scripts/world/house_generator.gd` | `HouseGenerator`: API (`template(id)`, `ids()`, `pool(kind)`, `venue_pool(type)`, `make_home(spec, taken)`), attempt loop, export |
| `house_plan.gd` / `house_rooms.gd` / `house_doors.gd` | working model (walls, objects, reachability), room treemap + hall / bands, front door, spanning-tree doors / arches, windows |
| `house_furnish.gd` / `house_cands.gd` | furnishing engine (item rules, runs, rows) + candidate generators (wall, corner, facing, beside, seat, rug...) |
| `house_yard.gd` | path, fence + gate, garden door patio, yard pieces |
| `house_score.gd` | quality gate (layout stage + final stage) and per-layout stats |
| `house_signature.gd` | `plan_sig` / `layout_sig` (translation, mirror, rotation invariant) and `similarity` |
| `house_venues.gd` / `house_batch.gd` | venue alternates (rooms given as rectangles) / whole-set generation with the uniqueness registry |
| `data/house_rules.json` | footprints, room types (size rules, floors, item lists), styles, link costs, yard items |
| `data/house_specs.json` | the 22 home specs (+ townie characters), `venue_rooms` item lists, the 21 venue alternates |
| `data/generated_lots.json` | OUTPUT: 43 lots (one per line). Do not edit by hand |
| `tools/gen_houses.gd` | regeneration |
| `scripts/ui/house_thumb.gd`, `tests/house_sheet_shot.gd`, `tests/house_iso_shot.gd` | floor-plan contact sheet / in-game iso screenshots |
| `tests/house_gen_test.gd`, `house_unique_test.gd`, `house_world_test.gd`, `house_kit.gd` | tests (fast tier) |

## Regenerate
```
Godot --headless --path . --script res://tools/gen_houses.gd                       # committed set (seed bump 0)
Godot --headless --path . --script res://tools/gen_houses.gd -- --seed=7           # a different, equally valid set (adds 7 to every spec seed)
Godot --headless --path . --script res://tools/gen_houses.gd -- --dry --only=small_03,cafe_v2   # print stats, write nothing
```
Needs `Godot --headless --path . --import` once after adding class files. `tests/house_gen_test.gd` fails when the file is stale
(the generator is deterministic, so regenerating gives the identical file).
Add a home: append a spec to `data/house_specs.json` `homes` (id, size, style, label, desc, public / private room lists, hall 0|1|2, seed,
optional `extras`, `decor`, `yard`) and regenerate. Add furniture rules: edit `data/house_rules.json` `rooms.<type>.items`.

## Data format (`generated_lots.json`)
`{"version", "seed_bump", "notes", "lots": {id: template}}`. A template is a `lot_templates.json` lot, in ABSOLUTE tiles of the default
32x24 lot (LotLoader translates by the lot origin exactly as for the hand-made templates):
`label, description, kind ("home"|"venue"), floors [{rect:[x0,y0,x1,y1] inclusive, type}], walls [{a,b,type: wall|fence|door}], objects [{def,tile,rot}]
(doors / windows are wall-mounted objects, rot = edge N/E/S/W), spawn [[x,y]...], entry [x,y], price`, homes also `size, style, bedroom [x,y]`,
venues also `venue, variant, staff [{role,tile,hours?}]`.
Fence gates are one-edge `door` wall segments on the fence line (so the lot connects to the street).

### Footprints (same outer shell and entry side as the template a home replaces; door on the south wall)
| class | shell tiles (x,y,w,h) | fence (vertices) | replaces |
|---|---|---|---|
| small | 5,5,10,7 | none | `small` (studio / flat) |
| medium | 4,4,14,11 | 2,2 - 26,21 | `medium` (family home), `townie_a` |
| large | 3,3,22,14 | 1,1 - 29,23 | `large` (estate), `townie_c` |
| classic | 4,4,16,12 | 2,2 - 30,22 | `classic` |
| venue | 5,4,22,14 (park: whole lot) | - | the 7 venue templates: same shell, south door (tile column 15; `school_v2` 7), same spawn / entry tiles `[15,19]...` |
Home front doors sit at a different column per layout (the path and fence gate follow it). Venue spawn tiles are unchanged and the forecourt is open stone.

## Mapping (DONE: LotPicker)
`scripts/world/lot_picker.gd`: on a new game `LotPicker.pick(world_seed, start_id, home)` draws one template per lot WITHOUT replacement (home first, then
townies, then venues in neighbourhood.json order), deterministic per seed. Pools: home = `starts[].pool` (small / medium / large / classic; classic also offers the
hand-made house); `townie_a/b/c` = their own id + the medium / small / large pool (`lots[].pool`); venues = `venue_pool(type)`. The picks go into the regions
(`region.template`, saved with the world; `Neighborhood.template_of(lot)` reads them) and `Neighborhood.world_seed` is saved in the neighbourhood block, so a
loaded game never re-rolls. `NewGame.start` opts: `world_seed` (default random), `home_template` (default drawn from the pool). The start picker shows the
drawn home on each card (`ScenarioCard.set_home`) with a "Reroll home" button (another layout of the same pool). All lots are 32x24 rects, so every
footprint fits (`map_lots_test`: entry walkable, every object / staff post / spawn reachable from the street gate, 5 world seeds x 5 scenarios, all
11 layout signatures pairwise distinct, save/load keeps template ids). `Neighborhood.start_game(template, seed = 1)` is the deterministic entry for tests.
Screenshots: `SHOT_SEED=n godot ... tests/bigmap_shot.gd -- prefix shells:0 <lot>:30:12:sunny:lot=<id>:0`.

## How a home is built (so it makes sense to the player)
Rooms: treemap of room rectangles (open-plan "zones" - living / kitchen / dining / sleep - share one wall-less group, even L-shaped), optionally around a 1-2 tile hall
or as a public band + private band so every bedroom touches a day room. Doors: a spanning tree over the room adjacency graph with costs
(bedrooms open onto the hall / living room, the main bedroom may have an ensuite, never bedroom-to-bedroom, bathroom-to-kitchen or bedroom-to-kitchen),
arches between day rooms, front door on the south wall into a living room or hall, garden door on a day room (not small homes).
Furniture: per room type item lists (TV against a wall, sofa facing it, coffee table + rug, armchairs facing the table, bed with nightstands and wardrobe, kitchen run
fridge-counter-stove-sink, bathroom run toilet-sink-shower/tub, dining table + chairs, ...). EVERY placement is checked: door tiles stay free and all
doors / object use-slots stay reachable from the entry. Windows go on exterior walls, never behind tall furniture. Different floor materials per room type (style tables).
Quality gate (retry with the next sub-seed on any failure): min room area / width / aspect and max area, all rooms connected, bedrooms reach a full bathroom without crossing
another bedroom, entry leads to a living space, bathrooms equipped, kitchen has fridge+stove+counter+sink, a table within 9-12 tiles of the stove, bedrooms have a bed + storage,
windows in every habitable room with an exterior wall, nothing on doorways, object count / variety per size class (`footprints.*.min_objects/min_kinds`).

## Uniqueness proof (tests/house_unique_test.gd)
`plan_sig` = hash of the wall geometry only, canonical over mirror / rotation / translation; `layout_sig` adds doors, windows and furniture cells.
`make_home` rejects any candidate whose signatures are already `taken` (hand-made templates included). Numbers for the committed set:
22 homes -> 22 distinct floor plans (plus 4 hand-made, all different), 43 lots -> 43 distinct layouts (plus 11 hand-made), most similar pair of homes (interior walls + furniture
Jaccard over the best symmetry) 0.26, venue alternates vs original and each other at most 0.15.

## Rough edges
- Furniture is placed by rules, so rooms are tidy rather than quirky; "cluttered" (townie_b) is just more items via `extras` / `decor`.
- No multi-storey, curved or L-shaped shells; the footprint is fixed by the template class. Halls are straight 1-2 tile strips.
- No garage door / driveway: the garage is a concrete-floored workshop room with a bench.
- Yard pieces hug fences and walls; no landscaping beyond path, garden plots, patio.
- The `park` alternates change the path network and zones but keep the pond as two fishing spots (no water floor tile exists).
- Venue staff posts: cafe / market behind island counters, gym / school free tiles, library beside a desk; office has none (as before).
