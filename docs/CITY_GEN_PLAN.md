# Task 30: a bigger, varied city (design, cost estimate, plan)

Status: DESIGN ONLY. No game code was changed. Written 2026-10-19 on `agent/citydesign30` (from origin/main 1e2548b) in answer to
`coord/messages/2026-10-20T1605-reviewer-30-bigger-varied-city.md`. Every number marked "measured" comes from a Godot headless run
on this machine (loaded, below-normal priority, so compare ratios; the method is in "How the numbers were measured" at the end).
Everything marked "estimate" is arithmetic from measured numbers, not a run.

## 1. Verdict in one page

**Does "keep the tile grid, make the layout procedural, draw it smooth" work with the real code? Yes, with three changes to the proposal.**

1. **Lots stay axis-aligned rectangles; they do not become polygons.** The land around a lot is polygonal (parcels), but the lot
   itself (what is a `WorldRegions` lot, what `LotLoader.place` stamps, what a room partition floods, what `InterestArea` measures)
   stays a `Rect2i`, of any size from a set of bands, in four orientations. 83 uses of `["rect"]` in about 45 files, the per-lot room
   partition (`WorldRooms`), tier distances, `PlayerLots` build rules and the placement loader all assume a rectangle. The cost is
   that a lot beside a curved street is a rectangle whose street-facing edge is a few tiles off the kerb; the gap becomes front
   garden, verge, hedge or driveway. That is how real suburbs on a grid look anyway.
2. **`NavGraph` is derived from the floors, not from authored polylines.** Trace the `sidewalk`/`crosswalk` (and later `shoulder`) tiles
   into nodes and runs. Then it works for any road shape, for old saves, for co-op clients (they load floors from the host snapshot),
   and for growth (re-trace one chunk). It also keeps the existing `floors_match` safety idea.
3. **The road rasteriser is integer-only; floats are allowed only in the mesh.** Splines are sampled with Q16.16 de Casteljau,
   tiles are classified by integer squared distance to the sampled centreline. The smooth road mesh is view code and may use floats.
   A golden-hash test of a generated city run on Windows and Linux catches any drift.

**What I would do in a different order than suggested:** do the plumbing that every bigger map needs (lot registry, orientation, nav
from floors, chunk eviction, crowd gating) and a **district generator on axis-aligned roads first**, judge how it looks and plays, and
only then add curves. Curves are the most expensive and riskiest item (about 3 of the ~13 sessions) and districts, road hierarchy,
varied lot sizes, a river and a rail line already give most of the "not all the same" feeling on a straight-road base.

**Cost:** about 11 to 16 agent-sessions for everything (central estimate 13), about 7 to 9 for "varied, bigger grid city without
curves". Biggest risks: curve visuals (tile staircase versus smooth mesh), per-lot memory at 10x (about 1 MB per lot, measured),
the cold route cost of the nav graph at 10x (0.95 ms today to 22.8 ms, measured), and the number of tests that assume the one 15-lot map.

## 2. What the code does today (facts the plan rests on)

| Area | Fact (file) |
|---|---|
| Map | `World.MAP_W x MAP_H` = 160 x 154 (24,640 tiles). `MapBuilder.build` paints a lattice from `data/map_layout.json`: 5 vertical x 5 horizontal roads, `road_w` 6 (asphalt 4 + a sidewalk each side), pitch 38 x 30, one 32 x 24 lot rect per slot, a green with a pond, a "south strip" of woods (holiday zones live in it: `DestLoader`). |
| Regions | `WorldRegions`: `regions` is a dictionary of `{id, rect: Rect2i, kind, entry, door, lot, template, lines...}`; `_tile` is a per-tile region id (a `PackedInt32Array`, painted by rectangle); 16 x 16 chunk index; `to_dict`/`from_dict` write rects. `LOT_KINDS` = home, venue, townie_home get their own room partition. |
| Lots | `LotLoader.place(template, w, origin)` only translates: fixed 32 x 24 templates (`data/lot_templates.json`, `generated_lots.json` 22 homes+venues, `generated_buildings.json` 11 multi-floor buildings), gate column fixed (`MapBuilder.GATE_X = 15`), gate always on the south edge (`WorldNav._make_exit` does `g + (0,1)`, `NeighborhoodLots.street_tile`). No rotation, no mirror, no other size. |
| House generator | `HouseGenerator.make_home(spec)` produces a 32 x 24 template (`HousePlan.lot := Rect2i(0,0,32,24)`, `HouseAudit.audit` default lot the same). Four footprints in `data/house_rules.json`: classic, small (10x7 shell), medium (14x11), large (22x14). 22 specs. It is an OFFLINE batch (`tools/gen_houses.gd`, `HouseBatch`): measured 51-53 ms for a small, 184-222 ms medium, 481-647 ms large, 242-458 ms classic home per template (1-20 tries each). |
| Lot registry | `Neighborhood.lots()` reads the static table `data/neighborhood.json` (15 lots, each with a `pos` on a 5 x 4 grid used for travel minutes (`Neighborhood.distance` is Manhattan on `pos`) and the travel panel's button grid). The perf benchmark swaps that table in memory (`PerfTown.install`), which proves the seam exists. |
| Nav | `WorldNav` (lot interior A*, street leg, sidewalk graph, lot interior A*). `NavGraph.build(layout)` makes nodes/runs only from the lattice; runs are axis-aligned (`line()` steps with `signi`), node ids are packed in 16 bits (`& 0xFFFF`, so at most 65,535 nodes), `_sp` is a full Dijkstra from each source node and `_sssp` caches one per node with no bound. Roads are crossed on crosswalk runs only. |
| Rendering | `lot_chunks.gd`: 16 x 16 chunks, one floor quad per tile (plus a grass tint and a snow quad per grass/lawn/etc. tile = up to 12 vertices per tile), centre lines from region `lines` (axis-aligned rectangles), crosswalk bars from tile neighbours, trees only on `park` kind grass. Chunks are built lazily when near the camera (6 per frame) and **are never freed** (only hidden). `_update_chunks` loops over all chunks every frame. |
| Tiers | `Tiers`/`InterestArea`: distances in tiles (active 24, near 64, town 96) from anchors to lot RECTS (`lot_distances` loops the lot list). Map-size agnostic. |
| Traffic (12) | `TransportTraffic.zone_of_tile` splits the map into 4 quadrants using `data/transport.json` `map: {w:160,h:136}`; `junction_at` and `light_phase` use the lattice (`vroads_x`, `hroads_y` from `map_layout`). Utilities zones are the same four quadrants (`data/city.json` zones). |
| Growth (12.6) | `CityPlan`: projects are records; "every slot of the street grid is taken" (docs/CITY.md). `StoryGrowth` uses `CityPlan.extra_capacity()` as a number. |
| Vehicles (12b) | Not started: branch `agent/vehicles12b` has no commits beyond old main. It will want the road graph, lanes, lights, parking. |
| Save | `SaveLoad` version 4; world dict has `floors_rle`, `regions`, `walls`, `objects`, `levels`; **the world is self-contained in the save** (nothing is regenerated on load), except `NavGraph`, which is rebuilt from `MapBuilder.layout()` (static JSON) and `floors_match` silently turns it off (plain tile A*) if the floors disagree. Co-op: the host sends `SaveLoad.snapshot` (JSON -> zstd -> 32 KB chunks, cap 96 MB raw); the client restores it, it never regenerates the map. `CoopHash` hashes folk tiles, needs, coins and object count. Share files (`.sim4town`) embed a full save, validated with a tree-node cap `max_nodes` 600,000 and 32 MB. |

## 3. Does tile-grid-plus-splines work? What exactly breaks

### 3.1 What works as proposed
- **Keep the tile grid for the sim.** Walls on tile edges, rooms, objects, A*, tiers, determinism, the save format all stay.
- **Roads as splines in data, rasterised to tiles, drawn as a smooth mesh.** Fine. Diagonal and curved roads become 8-connected
  staircases of `asphalt`; `WorldPaths` already searches with diagonals, and region lookups are per tile.
- **Per-district style tables, lot-size bands, house footprints in 90-degree steps.** Fine (the generator already takes a
  `footprint` from data; `HousePlan.lot` is a parameter).
- **Tiers and chunk streaming** are already distance based and map-size agnostic in the sim (measured below).

### 3.2 What I would change in the proposal (with reasons)

| Proposal | Counter | Why |
|---|---|---|
| Lots are polygons clipped to the grid | **Lots are rectangles (size band x 4 facings). Parcels are polygons only inside the generator.** Leftover parcel land becomes `yard` ground that belongs to the lot's owner (fenced or not) or to a verge. | `["rect"]` is read in about 45 files; `WorldRooms` partitions by rect; a room "touching the partition border is outdoor"; `LotLoader.place` stamps a rectangular template; `InterestArea.rect_dist`; `PlayerLots` build rule is per region tile. Polygon lots would touch all of these for a look that a rectangle plus a garden gives. |
| NavGraph rebuilt from centrelines and sidewalk polylines | **NavGraph traced from the sidewalk/crosswalk tiles** (a tile-graph skeleton: nodes at tiles that are not degree 2, runs between them, runs stored as explicit tile lists, not `line()`). | Always consistent with the floors (and with old saves, growth, co-op); no second source of truth; one tracer for lattice, curves, roundabouts. A spike (0.5 session) must prove the tracer on a diagonal road and a roundabout before committing (the thin 8-connected ribbon next to a staircase has L-corner ambiguities; a 4-connected ribbon rule fixes it, but it must be shown). |
| Vehicles (12b) follow lane polylines | Fine, but 12b must be built against a small **`RoadNet` interface** (lanes, junction nodes, signal type, route), implemented now by an adapter over the lattice. Then stage 4 only swaps the implementation. | Otherwise 12b hard-codes `vroads_x/hroads_y` like `TransportTraffic.junction_at` does today and has to be rewritten. |
| Rotate houses in 90-degree steps, maybe 45 later | 90-degree yes (a pure transform at placement time). **45 degrees: no** (walls are tile edges; there are no diagonal walls). | The edge convention `Vector3i(x,y,dir)` (dir 0 north edge, 1 west edge) maps cleanly under 90-degree rotation and mirror; not under 45. |
| 4-10x area | Treat **lot count and area separately.** Target 100-200 lots resident on ~4-6x area; 10x area is mostly woods, farms, river, rail yard and hills. | Measured memory is about 1 MB per resident lot (section 6); area itself is cheap (floors are 8 + 4 bytes per tile). |
| Hills or terraces | Cosmetic only (render height from a heightmap with flat lot pads) or skip. The sim has no height. | Out of scope for the sim; walls, rooms and camera assume a flat plane. |

### 3.3 Determinism rule (spline rasterisation)
- All generation that decides what is a road, a lot, a template, a style is **integer or fixed-point**: Q16.16 stored in GDScript `int`
  (64-bit); de Casteljau with `(a * (65536 - t) + b * t) >> 16`; a fixed number of subdivisions chosen from the integer control polygon
  length (`isqrt` by Newton on ints); distances compared as integer squares; no `sin/cos/pow/sqrt/atan` and no `float` in the sim
  path. `RandomNumberGenerator` (PCG) is platform independent, but I would use `randi()` with integer mapping and never `randf()`
  thresholds on a generated structure. Dictionary iteration is insertion ordered in Godot 4 (fine); never iterate `Array.sort()` results
  with ties on an unstable key.
- Floats only in `RoadMesh`, kerb/lamp placement and anything purely visual.
- Why it matters even though co-op clients load the host's snapshot: (a) Windows (builder) and Linux (reviewer) must generate the
  same city for tests; (b) growth (stage 6) must run identically on every co-op machine because co-op applies commands and compares
  `CoopHash`; (c) a seed must mean the same city after a patch only if the generator is frozen per `gen_version`, so the save stores the
  generated result, not just the seed.
- Test: `city_gen_golden_test` hashes (floors RLE, lot table, road net) for 3 seeds against committed constants, run in both
  environments; any change to the generator is then a deliberate "regenerate the golden" commit.

### 3.4 What breaks, by file/class (from reading and `grep`)

**Must change (stage 1 plumbing unless noted):**

| Where | Break | Fix |
|---|---|---|
| `MapBuilder` (220 lines) | The lattice builder, `slot_origin`, `lot_rect(lot_id)`, `road_floor`, `GATE_X`, the road regions with axis `lines`. | Becomes the `classic_grid` preset behind a `CityMap` provider; new `CityGen` produces the same outputs (floors, regions, lot table) from a seed. `MapBuilder.build` stays for the legacy map. |
| `MapLots` | Calls `MapBuilder.build`, places each template at `rc.position`. | Takes the lot table from the provider; passes orientation/mirror to the loader. |
| `LotLoader.place` / `entry_of` / `building_rect` | Translate only; entry in template coords; 32 x 24 assumptions in the generated templates. | Add `LotXform` (rotate 0/90/180/270, mirror) applied to floors, wall lines, objects (`rot`, wall-mount edge rot, multi-tile footprints via `HousePlan.footprint`), spawn, entry, staff, bedroom; multi-floor (`LotLevels`, stairs, lifts) is a sub-task. |
| `WorldNav._make_exit`, `NeighborhoodLots.street_tile/gate_tile`, `MapBuilder.GATE_X`, `Crowd` (gate use), `FireBrigade`, `CrimeLifeHeistRun`, `UnderworldDialog` (all read `["entry"]`/gate) | "Gate is on the south edge, street tile is gate + (0,1)". | Region gets `facing` (S/W/N/E) and `entry`; `street_tile = entry + facing`. Callers use one helper. |
| `NavGraph`, `WorldNav.is_active` | Built from `MapBuilder.layout()`; axis-aligned runs; 16-bit node ids; unbounded `_sssp`; full-graph Dijkstra for every cold plan. | Trace from floors; runs as tile lists; A* with a distance heuristic or a two-level (district backbone) search; bounded caches; node id packing widened or replaced by an array heap. |
| `WorldRegions` | Road regions are rects (`kind: road`, `axis`, `lines`) painted into `_tile`; `to_dict` saves rects. | Roads are NOT regions of a bounding rect (a curved road's bbox would cover its neighbours). Road tiles keep floors `asphalt/sidewalk/crosswalk`; `kind_at` returns `road` through a small per-tile mask or a road-id byte array; labels from the RoadNet. Add `district` byte per 8 x 8 cell (zone lookup). |
| `lot_chunks.gd` (397 lines) | Centre lines from region `lines` (axis-aligned), crosswalk bars from neighbour tiles, one quad per tile, never frees chunks, trees only on `park`. | Markings and kerbs from `RoadMesh` (a separate view file); merge runs of identical tiles into larger quads; evict far chunks; tree scatter by district/floor; bucket `_marks` by chunk (today O(chunks x marks) per full rebuild, 42 ms for 1,147 x 400, measured). |
| `Neighborhood` (registry), `data/neighborhood.json`, `travel_panel.gd` | Static 15-lot table; `pos` on a 5 x 4 grid for travel minutes and the UI. | Lot table generated per game and saved; `pos` derived from the rect centre; travel minutes from path length or street distance; the travel panel needs a real map view (list/scroll/zoomed minimap) instead of 20 buttons. |
| `TransportTraffic.zone_of_tile`, `junction_at`, `light_phase`; `data/transport.json map`, `data/city.json zones`; `Utilities` zones | Quadrants of a 160 x 136 map; lights at lattice junctions. | `CityMap.zone_at(tile)` from the generated districts (zone = district id group); lights from `RoadNet` junctions by class (avenue x avenue signalled, street x street priority/none, roundabout none). |
| `CityPlan`/`StoryGrowth` (12.6) | Projects are records. | Stage 6. |
| `Story.add_townie` (`lot = 1..6`), `Neighborhood.residents_of`, `careers.json` single `workplace` lot ids, hospital/police/courthouse as single lots | Already listed as "What blocks the target scale" in docs/PERFORMANCE.md. | Explicit `home_lot` and per-townie nearest workplace; several fire/police stations by district. (Needed for any bigger map; stage 1/3.) |
| `Crowd.update` -> `crowd/lots` | Every minute over all lots x residents: 1.43 ms/min at 63 lots (measured 2026-10-19 run), grows linearly. | Only lots returned by `Tiers.lot_distances(64)`. |
| `SaveLoad` (VERSION 4), `WorldSave` | No map-kind or road data; NavGraph depends on static layout. | Version 5 with a `citymap` block; v4 loads as `classic_grid` (see 5). |
| `data/share_schema.json` | `max_nodes` 600,000 for a shared town; unknown top keys refused. | Raise/redo the node count, add `citymap` to the allowed world keys (section 6). |
| `DestLoader` (holiday zones), `south_strip` | Zones sit in the woods strip at `south_strip.y + below_strip`. | Provider exposes `reserved_strip()`; the generator keeps a woods strip (or the zones move to a far corner). |
| `PerfTown`/`perf_scale.gd` | Builds `cols x rows` lattices by swapping `map_layout`. | New profile "city" generated by `CityGen` at 4x/6x/10x. |

**Tests that depend on the map (and what happens):**
- Directly on `MapBuilder`/`MapLots`/layout/`NavGraph`: `map_lots_test` (asserts every lot region == layout slot, 15 lots), `nav_graph_test` (15 gates, all pairs connected, `path_length == find_path size`), `world_regions_test` (MapBuilder layout, rooms at scale, determinism), `world_big_test`, `world_camera_test`, `perf_town`, `perf_scale`, `perf_scale_small_test`.
- Through `hood_kit.new_game` (49 test files): hood_sim/save/travel/lots, `map_walk_test` (walk times 8-45 minutes, arrival, mid-walk save), `map_ui_test`, `tiers_map_test`, `tiers_test`, `town_sim_test`, `commute_test`, `bldg_*`, `city_commute/services/..._test`, `coop_*` (hash, home lot, waiting, net, players, skip run), `determinism_test`, `crowd_floor_test`, `vacation_maps_test`, `succession_kit`.
- Hash-based: `coop_hash_baseline_longrun_test` (positions and object count change with the map: regenerate the baseline on purpose, like 19i), `determinism_test`.
- **Mitigation that keeps almost all of them green:** the old lattice stays as map kind `classic_grid` and remains the default of `Kit.new_game` until the very last stage; a `map` option (`Kit.new_game("small", ..., {map = "city_small"})`) selects the generated kind. Only 6 map-specific tests are rewritten; a dozen (nav, tiers, travel, walk, crowd, commute, vacation) get a second run on a generated city; the default flips in one commit at the end with one hash regeneration.

## 4. Proposed design

### 4.1 Modules (each under ~400 lines, no god file)

All in `scripts/city/` (new folder), pure sim (RefCounted) except `road_mesh.gd`:

| Module | Job |
|---|---|
| `city_map.gd` | The provider seam: `kind` (`classic_grid` or `generated`), `zone_at(tile)`, `district_at(tile)`, `lots()`, `roads()`, `facing(lot)`, `to_dict/from_dict`. `classic_grid` wraps today's code unchanged. |
| `city_gen.gd` | Orchestrator: seed + preset -> districts -> road network -> raster -> parcels -> lots -> placement list. Integer only. |
| `city_districts.gd` | Macro layout: a coarse (e.g. 16 x 16 tile) cell raster assigned by seeded region growing / Voronoi on ints: downtown, old town, suburb, industrial, waterfront, park/woods, farmland, with adjacency rules (industrial near the rail and water; suburb ring; countryside at the edge). |
| `road_net.gd` | Road graph: nodes (junction kind: T, cross, roundabout, dead end, cul-de-sac bulb) and edges (class: highway, avenue, street, lane; width; integer control points; lanes; sidewalk on/off). The interface 12b and Traffic use. |
| `road_raster.gd` | Spline sampling (Q16.16) and tile classification by integer squared distance: asphalt, kerb ring -> sidewalk, crosswalk cuts at junction arms, shoulder for lanes, bridge decks over water. |
| `parcels.gd` + `lot_fit.gd` | Free land components between roads; walk the frontage of each block, place rect lots of band-sized width and fitted depth with an integral image of free tiles; facing = direction to the nearest ribbon tile snapped to 4; leftover = yard / verge / hedge. |
| `lot_xform.gd` | Rotate/mirror a template into world coordinates; the one place that knows the edge convention. |
| `city_style.gd` + `data/city_districts.json` | Per-district style tables (below). |
| `nav_trace.gd` | Floors -> NavGraph nodes/runs (replaces the lattice builder). |
| `city_save.gd` | The `citymap` block (below). |
| `road_mesh.gd` (view, floats) | Smooth asphalt/kerb/sidewalk/line/crosswalk meshes from the RoadNet per chunk. |

### 4.2 District style table (data, `data/city_districts.json`)
For each district: label, road class mix and block size range (downtown 24 x 20 blocks, old town irregular 12-30, suburb curved with
cul-de-sacs, industrial 60 x 40, countryside lanes), lot size band weights, template pool tags (`terrace`, `suburban`, `estate`,
`shopfront`, `tower`, `warehouse`, `farm`), colour palettes and roof types (the models/colour tints already exist per style in
`house_specs.json`: `modern`, `cosy`, `artist`...), floors (new floor types for cobble, gravel, field, rail, concrete yard with
`FLOOR_DEFS` colours), tree species/density, street furniture (lamps, benches, bins, mailboxes, hydrants: the 12.5 objects), sidewalk
yes/no/one-side, street-name pool, zone (utilities/traffic zone group), and which kinds the growth system may zone there.

### 4.3 Road hierarchy and junctions
- Classes: highway (8 wide, no sidewalk, grade-separated crossings only at bridges/ramps; ring or one road out), avenue (6-7: lights), street (6: the current profile), lane (4, shoulder, no kerb).
- Junction kinds are explicit nodes: crossing, T-junction, roundabout (a circular asphalt ring of radius 4-6 plus 4 crosswalk arms: integer disc test), mini-roundabout (suburb), cul-de-sac bulb (disc), dead end.
- Traffic lights only at avenue x avenue; roundabouts and street x street have none. `TransportTraffic.light_phase` takes a `RoadNet` junction id.

### 4.4 Water, rail, bridges
River/coast = `water` floor (already blocks via `FLOOR_DEFS blocks`) painted by a seeded polyline with integer width; a bridge is a road edge with `deck` tiles over water; `NavGraph` crosses water only on deck tiles (they are sidewalks/asphalt). Rail line = a RoadNet edge of class `rail` painted `rail` floor (blocked except at level crossings, which are crosswalk-like with a signal state); trains are visual only at first. Port = a district with big lots and a quay of `concrete`.

### 4.5 Save format (`SaveLoad` VERSION 5)
- World dict gains `citymap`: `{kind, gen_version, seed, preset, districts (RLE of cell ids), roads (edges: class, ints), junctions, lots (id, rect, facing, template, mirror, district, zone), zoning plots (empty parcels with rect, facing, allowed kinds)}`. Plain ints and strings, so it is deterministic JSON and small (estimated 50-150 KB at 6x; floors RLE grows from 36-130 KB to a few hundred KB because diagonals break runs).
- `floors_rle`, `regions`, `walls`, `objects` stay as today. **Nothing is regenerated on load**; NavGraph is traced from the loaded floors.
- v4 saves: no `citymap` -> `kind = classic_grid`, NavGraph traced from floors (or the old builder), everything else unchanged. A v4 fixture test is mandatory (the repo has `hood_save_test`, `level_save_test` patterns).
- Co-op: unchanged mechanism (snapshot is the world). Clients never need the generator; growth (stage 6) runs on all machines from saved state plus the saved `CityState.rng`, integer only.
- Share files: add `citymap` to the allowed `world` keys and make the validator's `max_nodes` count lot/object arrays by size, not nodes: at 300 lots (about 40k objects) the object arrays alone approach 600k nodes (estimate: ~10-15 nodes per object; today 4.5k objects, big profile 11.4k objects).
- `CoopHash` needs no new field (positions are already hashed); the baseline test is regenerated once when the default map flips.

## 5. Stage plan

Sessions = one agent working one task to merge (like 12b). Effort ranges are honest, risk is about surprises, not difficulty.
"Parallel" means safe next to other queued work (see section 7).

### Stage 0: `RoadNet` seam in 12b (0.3 session, risk low) - done INSIDE 12b
- Deliverable: `RoadNet` interface (lanes with polylines + direction, junction ids and signal kind, `route(a, b)`, parking spots), with a `LatticeRoadNet` adapter over `map_layout`. 12b vehicles and `TransportTraffic` use only that.
- Test: vehicles drive the same lanes on the lattice; nothing hard-codes `vroads_x`.

### Stage 1: plumbing for any bigger/varied map (1.5-2 sessions, risk medium)
No visible change; the lattice is the only map, but nothing assumes it any more.
- `CityMap` provider + `classic_grid`; generated lot table saved in the world (not `data/neighborhood.json`); `facing` and `LotXform` (rotate/mirror for single-floor templates, with property tests: 4 rotations = identity, mirror twice = identity, `HouseAudit.audit` passes on every transformed template of the 22 generated homes + hand templates); entry/gate helper replaces `g + (0,1)`; `NavTrace` replaces the lattice builder and the 16-bit node packing; explicit `home_lot` and per-townie workplace; district/zone lookup; save v5 with `citymap` + v4 fixture; `Kit.new_game` `map` option.
- Tests: `nav_graph_test` and `map_walk_test` pass unchanged on `classic_grid` through the traced graph (same `path_length == find_path size` invariant); `lot_xform_test`; `city_save_test` (round trip, v4 load, co-op snapshot restore, hash equal); share validator test with `citymap`.
- Performance risk: low; the tracer scan must be incremental per chunk (estimate 30-60 ms full scan at 10x in GDScript; not measured).

### Stage 2: generator and districts on axis-aligned roads (2.5-3 sessions, risk medium: design quality)
- `CityGen`, districts, RoadNet with classes and junction kinds restricted to straight segments (so T-junctions, dead ends, varied block sizes, avenues/streets/lanes, lot-size bands, four facings, a rail line and a straight river with bridges).
- Content: lot-size bands (small terrace about 16 x 14, suburban 24 x 20, current 32 x 24, estate 40 x 30, shopfront 16 x 18, warehouse 48 x 32) -> extend `house_rules.json` footprints and `HousePlan.lot`; **offline template pool**: about 150 homes (50 ms to 650 ms each = a few minutes per batch of the tool, uniqueness gate via `HouseSignature`), plus venue/building variants and per-district style tags; runtime variety from 8 transforms x palette x roof. Runtime generation of homes at new-game time is not an option (300 lots x ~0.25 s = ~75 s).
- Style tables, floor types, trees by district, street names. First presets: `town_small` (about 4x area, 60-100 lots), `town_large`.
- Tests: `city_gen_golden_test` (3 seeds, hash of floors+lots+roads, both OSes); `city_gen_rules_test` (every lot has a ribbon tile within N tiles of its entry, no lot overlaps a road, rail crossings only at crossings, every venue type present, all lot doors mutually reachable, parcels cover); `city_gen_balance_test` (district shares and lots per band within ranges, home lot exists in a suburb); visual shots via `tests/bigmap_shot.gd`.
- Perf risk: new game load: `MapBuilder.build` 69 ms (today, measured) to 1.48 s at 10x lattice; plus lot placement about 25 ms per lot (`big` profile build 2.0 s for 63 lots + townies, measured) = 4-8 s at 150-300 lots. Needs a progress bar; lot placement can be sliced over frames behind it.

### Stage 3: scale and streaming (2-3 sessions, risk HIGH; may start in parallel with stage 2)
- Chunk eviction/LOD in `lot_chunks`: free chunks beyond `KEEP_EXTRA` + hysteresis, merge identical tiles into big quads, share the grass tint/snow overlays as one big plane with a shader or limit them to the visible window; tree scatter budget per chunk; bucketed marks.
- Hierarchical nav: A* on the traced road graph (heuristic = distance) or a two-level search (districts as clusters); bound `_sssp`/`_plans`/`_legs` caches by memory.
- `Crowd.update` and any "all lots" loop gated by `Tiers.lot_distances`; `InterestArea`/`Tiers` scale check at 6x and 10x; `Crowd`/hospital/police lists by district; lot hydration (below) if the budget demands it.
- A **"city" benchmark profile** in `tests/perf_scale.gd` (generated 4x/6x, 100-200 lots, 300-500 townies) next to `today`/`big`; budgets as stated by the owner: frame avg 4 ms, worst minute 20 ms (the file uses 12 ms for the worst frame; keep the existing limits).
- Optional sub-stage **lot hydration** (1+ session, very risky): lots far from every anchor keep only their template id and a diff (object state, fridge, wear, mess) and are placed on approach (placement is about 25 ms per lot, so ahead of the camera and sliced). It would take resident memory from about 1 MB per lot to a few KB, but every system that iterates `World.objects` (weather, accidents, fire, utilities, incidents) must tolerate absent lots. I recommend NOT doing it unless the owner wants well over 200 lots; 4-6x area with 100-200 resident lots needs only about 200-300 MB (estimate from the measured 1 MB/lot).
- Tests: `chunk_evict_test` (memory returns after leaving an area), `nav_scale_test` (generated 6x city: all door pairs reachable, cold route budget), `crowd_scale_test`, the new benchmark.

### Stage 4: curved roads, smooth meshes, cul-de-sacs, roundabouts (2.5-3 sessions, risk HIGH visually)
- Spike first (0.5 session): trace ribbon graph from a rasterised diagonal, an S-curve and a roundabout; decide thin 4-connected ribbon vs analytic offset; show screenshots of tile staircase versus mesh.
- `RoadRaster` splines (Q16.16), `RoadMesh` (asphalt, kerbs, sidewalk strips, lane lines, crosswalk bars, per chunk, built from RoadNet edges that touch the chunk), curved street generation in suburbs/old town, cul-de-sac bulbs, roundabouts, junction fillets; lot fitting along curves (stair-stepped setbacks, hedges/driveways fill the gap).
- Tile floors under a curve are painted by the rasteriser, but drawn with the colour of the nearest of {asphalt, sidewalk, grass} by coverage so no grass-coloured staircase shows beside the mesh; walkers walk on tiles, so a walker may appear up to half a tile off the mesh kerb. I would accept that; measure with screenshots in the spike.
- Tests: `road_raster_test` (golden hash both OSes, no gaps along a curve, ribbon connectivity, crosswalk at every arm), `road_mesh_test` (vertex counts bounded, deterministic), `nav_curve_test`, visual audit (`tests/visual_audit.gd`): no folk on asphalt except on crosswalks, no building on a road.
- Perf risk: mesh build per chunk (the synthetic 3-mesh 16 x 16 quad builder costs 0.60 ms per chunk, measured; the real `_floor_color` string parsing per tile will make it 1-2 ms, not measured); keep within `BUILDS_PER_FRAME`.

### Stage 5: special districts (1.5-2 sessions, risk medium)
- Meandering river/coast, port, bridges as decks, rail line with level crossings and (view-only) trains, highway out of town with an edge ramp, farms/lake/woodland at the edge, parks; sidewalk-free lanes with shoulders; `NavGraph` `FLOORS` extended (shoulder, deck).
- Tests: bridges connect banks, no building in water, crossings signalled, travel panel shows districts.

### Stage 6: growth on real land (1-1.5 sessions, risk medium)
- The generator leaves zoned **empty plots** (`citymap.plots`: rect, facing, district, allowed kinds). `CityPlan` projects pick a plot by zoning and district; scaffolding and workers are objects in the plot; completion places a real template through `LotXform` and registers a lot (`Neighborhood` lot table, `WorldRegions.add_region`, nav re-trace for that chunk, `Tiers` lot list refresh), a chronicle line, `StoryGrowth` capacity from the real building. New roads for outer growth are out of scope (only infill and edge plots).
- Co-op: runs from saved state and `CityState.rng`, integer only; command-replay test.
- Tests: `city_growth_real_test` (plots shrink, lot appears, townies move in, save/load mid-construction, hash equal host/client).

### Total
| | Sessions |
|---|---|
| 0 (inside 12b) | 0.3 |
| 1 plumbing | 1.5-2 |
| 2 generator + districts | 2.5-3 |
| 3 scale + streaming | 2-3 (+1 with hydration) |
| 4 curves + meshes | 2.5-3 |
| 5 special districts | 1.5-2 |
| 6 growth | 1-1.5 |
| **Total** | **11-15 (central 13), 7-9 for "varied grid city, no curves" (stages 0-3 + part of 5)** |

## 6. Measurements (stated honestly)

All numbers: Godot 4.7 headless on this Windows machine, load not controlled. Full method in section 9.

**Lattice scaled to N x today's area** (synthetic: same road profile and pitch; `MapBuilder.build` + `NavGraph`, no lots):

| N | Map | Tiles | Chunks | Nav nodes | Nav runs | Ribbon tiles | `MapBuilder.build` | NavGraph build | `refresh_blocked` | Cold `plan` (avg of 60 random routes) | `_sssp` cache after 60 routes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 161 x 156 | 25,116 | 110 | 260 | 340 | 2,740 | 69 ms | 2.3 ms | 3.3 ms | 0.95 ms | +1.2 MB |
| 2 | 237 x 216 | 51,192 | 210 | 532 | 700 | 5,684 | 205 ms | 7.2 ms | 8.0 ms | 2.32 ms | +1.2 MB |
| 4 | 351 x 306 | 107,406 | 440 | 1,120 | 1,480 | 12,080 | 460 ms | 11.4 ms | 18.2 ms | 7.60 ms | +2.7 MB |
| 6 | 427 x 366 | 156,282 | 621 | 1,632 | 2,160 | 17,664 | 709 ms | 14.1 ms | 22.5 ms | 10.07 ms | +2.1 MB |
| 10 | 579 x 486 | 281,394 | 1,147 | 2,944 | 3,904 | 32,000 | 1,479 ms | 37.6 ms | 54.2 ms | **22.83 ms** | +5.9 MB |

Reading: building the map and graph is cheap; **a cold route grows with the graph** (full Dijkstra from up to 4 source nodes; 0.95 ms to
22.8 ms), and the unbounded `_sssp` cache grows with the number of distinct source nodes. An organic city has more nodes per area than
the lattice (curve vertices, bulbs), so assume 2-3x these node counts. 65,535 nodes (16-bit packing) is not close, but fix it anyway.
With the existing route caches the warm cost stays tiny; the risk is the first request of each pair after any wall/object change in
the ribbon, and a lot full of walkers heading to a new destination.

**Real towns through the game's own code paths** (`PerfTown`, 1 save snapshot each):

| | today (15 lots, 160 x 154) | big (63 lots, 320 x 272 = 3.5x tiles) |
|---|---|---|
| Build (map + lots + townies) | 0.4 s | 2.0 s |
| Static memory after build (before 92 MB) | 123 MB | 142 MB |
| Objects (benchmark history) | 4.5k | 11.4k |
| Save snapshot / stringify | 25 ms / 36 ms | 71 ms / 112 ms |
| Save JSON / zstd | 0.43 MB / 0.05 MB | 1.73 MB / 0.16 MB |
| world part: floors RLE / regions / objects / walls | 36 KB / 5 KB / 0.19 MB / 0.03 MB | 130 KB / 17 KB / 0.68 MB / 0.09 MB |
| Parse / restore | 35 ms / 129 ms | 85 ms / 355 ms |
| Nav nodes (lattice) | 260 | 900 |

Slope from the benchmark history (docs/PERF_SCALE_RESULTS.md, 2026-10-19: today 119 MB static with 4,466 objects; big 166 MB with 11,384
objects): about **1 MB and 6-7 KB per object per resident lot**. 100 lots would be about 200 MB; 300 resident lots about 400 MB (estimate).

**Sim cost at 4x** (fresh run today, `tools/run_scale.ps1 -Profile big -Days 1 -NoWrite`, 63 lots): frame avg 3.26 ms (budget 4), worst
minute 134 ms (budget 12), town-level 2.15 ms (budget 1), household `choose` 7.95 ms (budget 3). `crowd/lots` 1.43 ms/min and
`Incidents.slice` 2.3 ms/min are the loop-over-everything costs that grow with lot and townie counts. The 2026-10-19 3-day run: 21.6
ms/game-min, frame avg 4.32 ms. **The sim already scales to ~4x with tiers; 6-10x needs the loops gated by tier distance (stage 3).**
The VIEW side was 19.8 ms/frame net at the big town (2026-10-18, `perf_scale_view`), larger than the sim, and chunk/lot view culling
is not solved at that scale yet.

**Chunk rendering** (synthetic): 3 meshes x 256 quads per chunk = 0.60 ms; the visibility loop over 1,147 chunks = 0.148 ms per frame;
mesh memory estimate about 90 bytes per quad x up to 3 quads per grass tile = roughly 80 MB if every chunk of a 10x map were built and kept
(estimate, not measured); eviction is required.

**House templates:** 22 specs, 50 ms-650 ms each offline; no runtime generation.

## 7. Recommended order against the other queued work

| Item | Interaction with this task | Recommendation |
|---|---|---|
| 12b vehicles | Touches the same view and map code; wants the road graph and lanes. | **First.** Ask 12b to implement against `RoadNet` (stage 0), including its "give projects real lots" item only as a plot-list stub, not by extending the lattice (stage 6 will do it). |
| 29 storyteller (and 29b city-wide ripples) | Pure sim; 29b ripples should ask `CityMap.zone_at` instead of quadrants. | Independent; merge before stage 1 as the reviewer asked. Tell 29b to use a `zone_of(tile)` function, nothing more. |
| 28 inherited health, 14 life areas, 23b underworld, careers 31 | No map code. They each regenerate the co-op hash baseline. | Independent. Do not run a hash-baseline-changing task in parallel with the stage that flips the default map. |
| 19i | Merged (hash line). | none |
| Industrial careers (message 1620) | An industrial district needs workplaces; the generator would create them. | Make careers reference a lot TYPE and pick the nearest lot (needed by stage 1 anyway). |

Suggested sequence: 12b (with stage 0) -> [29, 28, 14, 23b in any order] -> stage 1 -> stage 2 -> stage 3 (may overlap stage 2) -> owner
reviews screenshots of a straight-road generated city -> stage 4 (only if wanted) -> 5 -> 6. The default map flips to the generated
city at the end of stage 3 (4-6x, grid with districts, no curves) so the owner gets value early.

## 8. Open questions for the owner

1. **How big, in play terms?** 100-150 lots on ~4x area (comfortable for memory and the 4 ms frame), 200+ lots (needs lot hydration, +1-2 sessions and a lot of risk), or the same lot count spread thinly over a bigger countryside?
2. **Are curves a must or a nice extra?** The cheapest convincing step is districts, hierarchy, varied lot sizes, a river and a rail line on straight roads (about 7-9 sessions). Curves add about 3 sessions and the biggest visual risk.
3. **New games only?** The plan keeps old saves on the old map (`classic_grid`). Is that acceptable, or must existing towns be converted (not planned; the houses would have to be moved)?
4. **Which districts must be fully playable** (every shop and house enterable), and which may be scenery (farms, port, countryside) with a few destinations?
5. **Home placement:** can the player choose a district (suburb/old town/downtown flat) at New Game? (Planned: yes, three choices.)
6. **Trains and highways:** decoration only, or part of transport (12 has buses, taxis, cars)? Commuting by train is a new system (about 1 session).
7. **Hills:** cosmetic only or skip? (Recommend skip.)
8. **Loading time:** is a 5-10 second New Game with a progress bar acceptable for a 150-lot city (lot placement is about 25 ms each)? The alternative is pre-generated saves of a few fixed cities.
9. **Co-op:** how far apart may two players' cameras be? Each camera is a Tiers anchor (ACTIVE cap 60); two distant districts roughly double the view cost.
10. **Growth:** should the player (or the mayor) be able to choose plots, or only the planners? Outer growth (new roads) is out of scope here; is infill enough?

## 9. How the numbers were measured

- Import: `tools/godot_guard.ps1 ... --import` in the worktree, then probes as `--script` files kept in the scratchpad (not committed; the task allowed only this file).
- Lattice table: `MapBuilder._layout` and `MapBuilder.size_override` set in memory (exactly the hooks `PerfTown` uses), `MapBuilder.build(World)`, `NavGraph.new().build(layout)`, `floors_match`, `refresh_blocked`, then 60 random `plan()` calls between ribbon tiles (fresh graph, so cold). Layouts: k = round(5 sqrt(N)) roads each way at the original 38 x 30 pitch.
- Real town table: `PerfTown.build("today"|"big", 777)` then `SaveLoad.snapshot`, `JSON.stringify`, zstd compress, parse, `SaveLoad.restore`.
- Chunk numbers: a synthetic GDScript quad batcher mimicking `lot_chunks._MeshArrays` (not the real mesher), and a copy of the `_update_chunks` visibility loop over 1,147 chunks.
- House generator: `HouseGenerator.make_home` on two specs per size with a fresh `taken` registry and seed +5000.
- Sim: `powershell -File tools/run_scale.ps1 -Profile big -Days 1 -NoWrite`.
- Not measured: real view cost at scale, mesh memory, tracer scan time, lot placement per lot in isolation (inferred from 2.0 s / 63 lots), anything on Linux.
