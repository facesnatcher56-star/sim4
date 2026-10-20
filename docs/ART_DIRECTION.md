# Art direction: visual looks (task 41 look test)

Owner: "our entire game is too light-hearted looking ... candy pastel floors, mint-green grass, pure white walls, flat even lighting, everything spotless."
This is the **look test**: a data-driven look switch, one new look (`grounded`, between the reviewer's A and B) next to today's `reference`, and one scene
built in-engine to judge it. The full pass waits for the owner's verdict.

## How the look system works

* `data/looks.json`: named looks (`reference`, `grounded`). `scripts/core/looks.gd` (`Looks`, static, no autoload) holds the current one.
* Choose it: Settings > Display > **Visual style**, or `--look=grounded` (user args after `--`), or env `SIM_LOOK=grounded`. The command line wins at startup.
  `Looks.set_look(id)` switches at runtime (no setting written); `Looks.bus.changed(id)` makes `LotView` rebuild floors, walls, shells, `WeatherView` rebuild its lamp
  lights, `LookOverlay` and the HUD theme re-read. Switching back to `reference` restores everything (tests/looks_test.gd).
* **View only**: nothing reads or writes sim state or rng (wear uses a tile hash, the dressing its own `RandomNumberGenerator`). The hash baseline is untouched.

### The knobs (per look)

| key | what it does | where it is read |
|---|---|---|
| `surfaces.<class>` {sat, val, tint, lift} | HSV saturation / value multiply, rgb tint multiply, additive lift per surface class: floor_wood, floor_tile, floor_carpet, ground, grass, road, sidewalk, sand, water, wall, roof, trim, awning, accent, glass, wood, leaf, sky | `Looks.grade` in `lot_chunks._floor_color`, `level_mesher`, `weather_scenery` (grass overlay, ground, trees), `weather_view._update_sky` |
| `palette.<floor type>` | absolute base colour per floor type (before grading) | `Looks.floor_color` |
| `material_class` | maps glb material names (`wall`, `roof`, `trim`, `awning`, `glass`, ...) to surface classes; `Looks.tint_tree` gives instantiated walls, doors, windows and shells their own tinted material copies (cached; window glass gets a per-building glow) | `lot_models` (walls), `lot_shells` (shells), dressing |
| `wear` {floor_dirt, stain_chance, stain_color} | deterministic per-tile grime and stains on interior floors and pavements | `Looks.floor_color` |
| `env` sun_warm / sun_white / sun_base / shadow_mult | sun colour, strength, shadow darkness | `WeatherView._update_sun` |
| `env` night_sky / twilight / twilight_mix / moon_* | night and dusk / dawn colours, moon | `WeatherView._update_sun` / `_update_sky` |
| `env` amb_day / amb_night / amb_energy_day / amb_energy_night / exposure_* | ambient light: **night darkness lives here** | `WeatherView._update_sun` |
| `env` saturation / contrast / brightness | whole-frame colour grade (Environment adjustments, Forward+) on top of the weather's own grey-out | `WeatherView._update_sun` |
| `env` fog_tint / fog_floor | haze colour and a permanent minimum haze | `WeatherView._update_sky` |
| `env` lamp_color / lamp_energy / lamp_range | indoor lamp, pendant, fireplace lights (the dark nights make them matter) | `weather_lamps.gd` |
| `env` window_glow / window_color | emission of building windows at night (some lit, some dark per building) | `Looks.set_night_glow` |
| `env` wet_dark / wet_color | roads and pavements darken and turn glossy in rain (a `wet` overlay mesh per chunk, lamps glint on it) | `lot_chunks.set_wet_overlay` |
| `env` vignette / grain | screen vignette and film grain | `LookOverlay` (one canvas shader, layer 2 under the HUD) |
| `ui` bg / panel / panel_hi / accent / text / muted / radius | HUD and menu theme: the grounded look drops the mint accent for muted brass, neutral grey panels, squarer corners | `UITheme` (the colours are now static vars, `UITheme.build()` re-reads them) |

Not done through the grade: the furniture and vehicle glbs keep their own colours, only the frame-wide saturation / contrast touches them (the full pass would
recolour them per kit).

### What `grounded` changes

Worn wood, grey-beige plaster, tired lino and stained grey-brown carpet (palette), grey-olive grass and darker asphalt, muted roofs and awnings, lower sun
ambient and a stronger sun (real contrast, a touch less saturation), a nearly dark night (ambient 0.22, moon 0.32) where lamps, bare bulbs, street lamps and lit
windows are the light, warmer and stronger indoor lamps, wet glossy streets in rain, vignette and grain, wear and stains on floors.

## The look-test scene (tests/art41_shot.gd)

`data/district_dressing.json` + `scripts/world/district_dressing.gd` + `scripts/world/dressing_tex.gd`: an optional dressing layer applied **by the shot script only**
(`DistrictDressing.apply(lot_view, "home", [groups])`), placed relative to a lot's top-left tile, so it can become a district's identity table later. Item kinds: glb
props (tinted), street lamps (one flickering, one broken), Forward+ `Decal` nodes with procedural textures (cracks, pothole, worn road markings, grime, stains,
peeling paint, graffiti), chain-link fence, boards and bars on the lot's window objects, litter, weeds / grass tufts, bare bulbs, a lit sign, a decor neighbour house.
The scene: the real map's home lot as the run-down house (furnished, then made poor: grime, broken TV / stereo, lino in the kitchen, mess, dishes, boxes, bare bulbs),
a tidy neighbour east of it with picket fence, garden and a car, the south street with lamps, a parked car and a beaten-up car, a bus stop with a lit timetable, cracked
pavement and a pothole. Walls are cut as in play (the home shell is always open), which is why exterior wear sits on the fence, yard and street and the wall wear
(boards, bars, peeling, tag) on the far walls.

Shots: `powershell -File tools/godot_guard.ps1 -Args "--path,.,--rendering-method,forward_plus,--resolution,1280x720,--script,res://tests/art41_shot.gd,--,coord/shots/art41,1280x720,grounded,day+dusk+night+rain+close"`
(a Forward+ window is required; Compatibility mode would drop the decals). Pass `reference` as the look to photograph today's look with the same dressing.

## Performance

`tests/bigmap_shot.gd perf` (windowed, Forward+, 1600x900, the whole 236x154 map, machine under parallel load so wall frame time is noisy; run twice per look, `SIM_LOOK=<id>`).
Second pair of runs (quieter), ms/frame, render cpu / gpu ms, draw calls:

| case | reference | grounded |
|---|---|---|
| home view, sunny | 10.5 ms, 1.54 / 0.89, 471 | 10.7 ms, 1.54 / 1.30, 468 |
| zoomed out, sunny | 13.0 ms, 2.29 / 1.00, 960 | 12.2 ms, 2.04 / 1.26, 842 |
| zoomed out, rain | 12.7 ms, 2.28 / 1.07, 985 | 12.0 ms, 2.03 / 1.30, 867 |
| home view, rain | 11.5 ms, 1.54 / 0.95, 472 | 12.1 ms, 1.59 / 1.33, 469 |

Frame time is the same within noise (the first pair of runs, under heavier load, was 11.5 to 20.8 ms for reference and 11.8 to 14.0 ms for grounded). The grounded look costs about
0.3 to 0.4 ms of GPU (vignette + grain canvas shader, the wet overlay, a few more lit pixels), no extra draw calls in the normal views. The decal and light dressing is not part of
the game (look-test shots only): about 20 `Decal` nodes, 12 omni lights, 150 small meshes; the full pass would put it through the chunk / tier systems (decals and props only near the camera).
The reference look does no extra work (`Looks.grade` returns at once, the overlay and the wet mesh are hidden).

## What the full pass would cost

| area | work | agent-sessions |
|---|---|---|
| District identity tables | a `district_looks` table per district (wall / floor sets, roof colours, street furniture, props, light colour, litter and wear level) read by the lot / shell builders; moving this test's dressing into per-district data and into the chunk / tier systems (decals and props only near the camera, MultiMesh for litter) | 2 to 3 (after task 40's districts exist) |
| State in the visuals (33-style) | dirt build-up of floors and walls from `World.mess` and cleanliness (a wear texture / decal per room), broken things, a poor flat looks poor, a rough block that gentrifies or declines with events | 2 |
| Lighting and weather mood | per-season grading, dusk / dawn tuning, wet walls, street lamp objects with real on / off / flicker / broken states, shop windows and signs, interior lights per room | 1 to 2 |
| Materials and kits | recolour the furniture and vehicle glbs per look (material classes already work for walls / shells), roofs and trees, a second set of wall textures (plaster, brick) | 2 |
| UI tone | convert the 260 direct `UITheme.ACCENT` / `MUTED` uses and custom-drawn bars to look-aware colours, sober icons, check high-contrast and colour-blind modes | 1 |
| Polish and perf | per-look budget run, screenshots, owner review round | 1 |
| **Total** | | **9 to 11** |

## Not covered by the look test

Night windows of the closed shells use one glow level per building (no per-room light); furniture is not recoloured; the rough district itself (task 40) does not exist,
so the dressing is applied to the home lot; the UI keeps a few hard-coded mint accents (`UITheme.ACCENT` is now look-aware, custom-drawn bars that use their own greens
are not); the grain / vignette are screen-space, not per-object; no corner-shop front (the bus stop is the street prop).


## Task 41a: the wear / poverty layer (dressing, props, decals, state in the visuals)

`grounded` is now the default look (`data/looks.json` "default", Settings > Display > Visual style, Reference stays selectable). View only: no sim state or rng (tile hashes and own generators).

| piece | what | where |
|---|---|---|
| Wealth score | a household's funds give 0..1 (`poverty` in `data/wear_layer.json`: 600 coins or less = 1, 4500 or more = 0); the player's lot reads the household, any lot can also declare a district wear level | `WearRules.poverty_score`, `WearLayer.lot_poverty / lot_wear / poverty_at` |
| Poor interiors | `data/object_poverty.json` is merged into the 33b rules: bed, single bed, sofa bed become a **mattress on the floor** (stained blanket, a dent, an old pillow; the unmade-bed parts are skipped), chairs are **broken** or recoloured **mismatched** (`_pick` 0..2, stable per object), the TV sits on a **cardboard box** with rabbit ears, sofas sag, other furniture gets a worn / grimy tint by score. Pseudo state keys `_poverty` and `_pick` are injected by `ObjectStateView.look_of` and never written to the object | `ObjectVisualRules._merge_poverty`, `ObjectStateView.look_of` |
| Mess clutter | per tile mess gives pieces (untidy 1, messy 2, squalid 4: dishes, clothes, boxes, bags, cans, bottles, paper, towels by room kind); they vanish when the mess is cleaned; a poor lot keeps a few boxes and bags. One MultiMesh per kind | `ClutterView`, `WearRules.clutter_for_tile`, `WearProps` |
| Wall grime | one world-space shader for the `wall` and `wood` classes of walls, window frames, doors: dirty base course, rain streaks, peeling paint, soot and moss on the **cut wall top**; `instance uniform wear` per wall (outside strong, inside lighter) from the lot's wear | `WearShader`, `WearWalls`, `lot_walls._build_wall_chunk` |
| Litter | muted paper, cans, bottles, bags, newspaper as real low-poly shapes in loose clusters | `WearProps.litter` |
| Tags | six tags (RAT, KOZ, SIX, NEK, DOA, VEX) with real letters, outline, fill, highlight, shadow, drips and an underline; decals sized to the texture's 512:192 aspect | `GraffitiTex` |
| Yard | clusters of grass in three heights with wide curved blades, broad-leaf weeds with dandelions, straw and brown clumps, dead patches (brown decal + dry stalks + bare soil) | `WearYard` |
| District wear | `data/district_dressing.json`: `presets` (rough 0.85, tired 0.5, tidy 0.08), `districts` (rough_row declares townie_b), `wear_map` (density per wear level, 0 below a `min_wear`). `WearView` builds a lot's dressing (litter, tags, cracks, weeds, dead patches, door stains, boarded windows) only while the camera is within 44 tiles, nothing when zoomed far out. Hook: `WearLayer.set_district_wear(id, 0..1)` makes a block improve or decline | `WearLot.plan / build`, `WearView` |

Shots: `tests/art41a_shot.gd` (Forward+): `powershell -File tools/godot_guard.ps1 -MaxSeconds 500 -Args "--path,.,--rendering-method,forward_plus,--resolution,1280x720,--script,res://tests/art41a_shot.gd,--,coord/shots/art41,1280x720,grounded,interior_before+interior_after+litter+graffiti+yard+exterior+street+district+bedroom"`.
Tests: `tests/wear_layer_test.gd` (fast).
