# One continuous neighborhood — plan (decided)

User rules: ONE big seamless map (~160x120 tiles, extensible). Static things (terrain, roads, sidewalks, lots, buildings, trees) always exist and may be rendered (chunked + culled). Dynamic things (people, cars, animals, ambient crowds, simulated props) are simulated/rendered ONLY when a player Folk can perceive them (distance AND line of sight). Everything else runs on the cheap statistical sim (Away / NeighborhoodService / Story). Keep it simple: small files (<~400 lines), no god files.

## Key facts about the current code
- The sim does not step tiles: `Interaction.start()` computes `path_length` once, sets `travel_left = n * WALK_MIN_PER_TILE`, `_arrive()` teleports. Only FolkView animates the walk along `World.find_path`. So statistical and Active sim already share one logical model; long walks just mean a long travel time.
- Autonomy cost: `path_length` (full A*) per candidate; `objects_near` radius 64. Must be bounded (radius ~24, skip far candidates, cache).
- `World` is one global grid; `WorldRooms` flood-fills the whole grid when dirty — must become region-limited/lazy.
- `Neighborhood` currently swaps lots (stash/load); it becomes a registry of lots at map coordinates.

## Data model
- Keep one `World` autoload, grid 160x120. New `scripts/world/world_regions.gd`: regions {rect, kind(home|venue|townie_home|park|road), venue_type, owner, template, entry, label}; `region_at(tile)`; `can_build(tile)` true only in the player's lot (hook into place/edit/buy).
- Chunks 16x16 are an index only (`chunk_of`, chunk -> object ids), not storage.
- `LotLoader.apply(template, origin)` places all templates once at map build using origins from data/neighborhood.json (translate wall edges, objects, spawn/entry/bedroom/staff).
- Static = floors/roads/walls/fences/trees; Dynamic = objects with state, Folk, vehicles, animals. Objects stay WorldObjects (data), only node instancing is gated by activity.
- Save version bump; old saves dropped. One world dict + regions; Neighborhood saves pantry/visits/meetups only.

## Pathfinding
- New `world_nav.gd`: portal graph (lot entry tiles + road/sidewalk junctions, edge weight = tile distance). find_path: same region/near (<32 tiles) -> bounded-window tile A*; else A* to entry portal + graph route + A* from entry portal. Cache portal routes by region pair and path_length by tile pair (LRU ~256), invalidate on wall/object changes. path_length across regions may return cached portal distance (exact path only needed in Interaction.start()).
- Autonomy: skip candidates > ~40 tiles (Manhattan); `objects_near` radius 24; far errands (market/cafe) chosen by a venue-level scheduler.

## Interest / LOD (`scripts/sim/interest.gd`, class Interest)
- Tiers: ACTIVE (full sim + render), NEAR (full sim, no render, autonomy every 3rd tick), FAR (statistical: existing sys_away stay).
- API: is_active(tile), tier_of(folk), refresh() once per game minute, active_rects(), active_chunks().
- Area per player Folk: indoors = current room + rooms through doorways + windows/doors visibility; outdoors = radius ~24 with LOS blocked by wall edges (bounded flood fill / ray test, windows transparent for LOS, buildings opaque from outside). Cached, recomputed on tile step or wall change.
- Transitions: FAR->ACTIVE places the folk at a plausible tile (along cached route at elapsed fraction, or free slot at their venue); ACTIVE->FAR only if out of view > ~10 min (hysteresis ~5). Crowd/staff per venue region, spawned only when region ACTIVE/NEAR. Director ticks ACTIVE every tick, NEAR every 3rd, hard cap ~12 autonomy folk per tick.

## Rendering
- Per-chunk floor meshes (re-mesh on floors_changed per chunk); road/sidewalk floor types. Walls per chunk, nodes only for Active chunks +1 margin; merged static mesh per far building. Objects instanced only in Active chunks. Interior detail + cutaway only for buildings containing/adjacent to a player Folk. Camera follows selected Folk, free pan clamped to map. Dim chunks outside Active set (simple). Budget < 2k draw calls.

## Ambient life (after tiers)
- Pedestrians: lightweight visual-only entities spawned at the edge of the Active bitmask, walk the sidewalk graph, despawn leaving it. Cars: position along lane polylines, no physics, capped (~6 per 100 road tiles in Active). Animals: 0-3 in Active parks. Blender: car x2, trees, road pieces, fence, mailbox, streetlamp, bush, house shells/roofs.

## Gameplay integration
- Travel panel becomes a map overview; "Go" sends the Folk walking (goto_tile) to the lot entry; optional fast-travel = Away travel time. Venues' check_entry/charge_entry run at the door. Work/school rabbit-hole stays. Story visitors spawn at the home entry/map edge. Start picker places the chosen home template at the player's origin on a pre-made map.

## Phases (each leaves the game playable)
P1 big grid + static render + clamped camera (world.gd size, world_save, world_rooms region-limited, lot camera/chunk meshes, world_regions). 
P2 lots placed on the map (LotLoader origin, Neighborhood registry-only with thin wrappers, neighborhood.json origins, Economy owner per object, per-chunk walls).
P3 hierarchical pathing + walking between lots (world_nav, world_paths bounded/cached, world_iface, autonomy radius, interaction, folk_motion segmented, travel panel).
P4 interest tiers (interest.gd, director tier lists, away materialize, crowd/neighborhood_service per region, instance gating).
P5 ambient life (ambient_ped/car/view + Blender assets).
P6 map overview UI, minimap, saves, start picker changes.
Parallel: P1 + Blender assets; P2 || P3 after P1 once WorldRegions/WorldNav interfaces are fixed; P4 after P2/P3; P5 after P4; P6 after P2.

## Fallbacks
Rooms cost -> per-lot lazy rooms. A* cost -> distance-only beyond 24 tiles. LOS cost -> distance + room-based interest. Wall node count -> merged mesh per building. Fog -> chunk visibility only. Neighborhood rewrite breakage -> keep old API as wrappers.

## Not building
Per-chunk storage streaming, physics vehicles, per-tile fog-of-war textures, full visual sim of FAR folk, save diffs, multi-floor buildings, navmesh.
