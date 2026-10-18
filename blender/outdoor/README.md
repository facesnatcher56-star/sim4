# Outdoor / neighborhood kit (Blender 5.1, scripted)

Regenerate: `"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background --python blender/build_outdoor.py`
Filter: `ONLY=car_sedan_red,tree_*` (comma list, trailing `*` = prefix) rebuilds only those and merges the manifest.
Previews: `... --python blender/outdoor/render_preview_outdoor.py -- tiles|props|vehicles|buildings|scene` -> `assets/preview_outdoor_<sheet>.png`
(`assets/preview_outdoor.png` = the assembled sample street). Outputs: `assets/models/outdoor/*.glb`, `assets/models/manifest_outdoor.json`
(file, footprint, bounds, node list, size), `blender/outdoor/footprints.json` ({id: [w, d, h]} metres; tiles = metres).
Sources: `lib.py` (helpers, palette, registry) + `roads.py vehicles.py nature.py furniture.py buildings.py animals.py` (all exec'd into one namespace by build_outdoor.py; reuses Builder from build_all.py, which is not modified).

## Conventions
1 unit = 1 m, +Y up, origin = footprint centre on the ground, FRONT faces -Z, flat-shaded palette materials (no textures). Tiles are 1x1 m, 0.05 thick, top at y=0 (like floor_tile.glb).
Materials that Godot should recolour/toggle keep fixed names: `body` (car paint), `leaves` (season tint), `wall`, `roof`, `trim`, `glass`, `door_paint`, `water` (translucent), `lamp_glow` (emissive; also `headlight`/`taillight`).

## Road kit (1x1 tiles; build a 4-wide road: edge, line, line(rot 180), edge(rot 180))
`road_asphalt`, `road_line` (yellow line on the +X edge, runs along Z; rotate for other edges), `road_line_dash`, `road_edge` (white line near -X), `road_crosswalk` (bars along Z), `road_corner` (rounded intersection corner: paving block in the -X,-Z corner, rotate 90 steps), `road_t` (through-line + stop stub), `road_cross`, `road_dead_end` (barrier on -Z edge), `sidewalk`, `sidewalk_curb` (curb stone on -Z edge, road on that side), `sidewalk_corner` (curb on -Z and -X), `curb_ramp`, `curb_straight`, `curb_corner` (bare curb stones), `ground_grass|dirt|gravel|sand`.
Curb stones stand 0.035 above y=0 (everything else flush). See `assets/preview_outdoor.png` for a worked intersection (rotations used there: render_preview_outdoor.py `scene_street`).
Pond: `pond_water` (full), `pond_edge` (sand on -Z, water +Z), `pond_corner_out` (water quarter in +X+Z), `pond_corner_in` (sand quarter in -X-Z); nodes `land`, `water`; water surface y=-0.012 (recessed).

## Vehicles (nodes `body`, `wheel_fl|fr|rl|rr`; wheel pivots at the axle centre, spin about X)
`car_{hatchback,sedan,van}_{red,blue,white,yellow}` (3.9 / 4.5 / 4.8 m), `bus` (9 m). Body paint = material `body`.

## Nature
`tree_{oak,pine,ornamental}_{l,s}` (nodes `trunk`, `leaves` [+ `blossom` on ornamental]; footprint = trunk tile, crowns overhang; l ~5-6 m, s ~3 m), `bush_round`, `bush_flowering` (+`flowers`), `flower_bed` (2x1; `bed`,`leaves`,`flowers`), `rock_small|large|cluster`, `grass_tuft`.

## Street furniture
`street_lamp` (`pole`, `lamp_head` emissive), `fence_{picket,wood,hedge}_{straight,corner,gate}` (1 m along X on a tile edge like wall.glb; corner arms along +X,+Z; gate has `gate_leaf` hinged at x=-0.42), `mailbox_street` (`mailbox`,`flag`), `bus_stop` (3x2, open front -Z), `trash_can`, `bench_street` (2x1, back +Z), `picnic_table` (2x2), `swing_set` (3x2; `frame`,`swing_l`,`swing_r` pivot on the top bar, rotate about X), `slide` (1x3), `sandbox` (2x2), `fountain` (3x3; `fountain`,`water`), `sign_blank` (`post`,`sign_face`), `fire_hydrant`.

## Building shells (nodes `body` + `roof`; hide `roof` when a player Folk is inside)
Footprint = the template's WALL bounding box from data/lot_templates.json (door side is south there, so rotate the shell 180 deg about Y; the door is at model x=+0.5, i.e. mirrored from the template door tile). Roof/eaves/portico overhang up to ~0.7 m (library portico 2 m in front).

| id prefix | template | footprint w x d (m) | height (m) |
|---|---|---|---|
| house_small_{a,b,c} | small | 10 x 7 | ~4.9 |
| house_medium_{a,b,c} | medium | 14 x 11 | ~5.4 |
| house_large_{a,b,c} | large | 22 x 14 | ~6.4 |
| townhouse_{a,b,c} | (none) | 7 x 10, 2 floors | ~7.6 |
| cafe_{a,b}, gym_{a,b}, library_{a,b}, market_{a,b}, school_{a,b} | cafe/gym/library/market/school | 22 x 14 | 4-9 |
| office_{a,b} | office | 22 x 14, 3 floors | 9.4 |
Variants a/b/c differ in `wall`, `roof`, `door_paint` colours. Interiors are separate; shells are solid.

## Animals (segmented rigid nodes, pivots at joints, node animations exported as glTF clips)
`dog`, `cat`: nodes `body head tail leg_fl leg_fr leg_bl leg_br`; clips `Idle`, `Walk`. `bird`: `body head tail wing_l wing_r leg_l leg_r`; clips `Idle`, `Walk`, `Fly`.
Clips are 24 fps, set loop mode in Godot. Pedestrians: reuse folk_adult.glb.

Test: `Godot --headless --path . --script res://tests/run_one.gd -- outdoor_assets_test`.
