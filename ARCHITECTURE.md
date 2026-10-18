# sim-4 — Architecture & Contracts

Godot 4.7 (GDScript). Original life-sim inspired by the *mechanics* of The Sims. Use ORIGINAL names/assets: characters are **Folk**, money is **Coins**, etc. Do not copy EA content.

Godot exe: `C:\Users\lloyd\AppData\Local\Godot47\Godot_v4.7-stable_win64_console.exe`
Blender: `C:\Program Files\Blender Foundation\Blender 5.1\blender.exe` (use `--background --python`)
Headless tests (details in **Tests** below): `Godot --headless --path . --script res://tests/run_all.gd` (fast tier, < 1 min); add `-- --slow` for the long simulations.
After adding / removing a `class_name` file run `Godot --headless --path . --import` once so the global class cache is rebuilt.

## Principles
1. **Logic is separate from rendering.** All simulation (`scripts/sim/`) is plain `RefCounted`/`Node` code with NO dependency on visuals, so it is testable headless. 3D scenes only *display* state.
2. **Grid-based world.** Logic uses `Vector2i` tiles (1 tile = 1 m). 3D position = `Vector3(x+0.5, 0, y+0.5)`. Buildings can have floors: a position is then `Vector3i(x, y, level)` (see "Multi-floor buildings"); a bare tile is level 0.
3. **Data-driven.** Needs, traits, buffs, objects, interactions, careers are JSON in `data/`. New content = new data.
4. **One generic `Stat`** reused for needs, skills, relationship tracks, object state.
5. **Event bus** (`Events` autoload) for decoupling; UI listens, sim emits.

## Autoloads (project.godot)
- `Events` — `scripts/core/events.gd` — signal bus (see below)
- `Data` — `scripts/core/data.gd` — loads every `data/*.json` into dictionaries at startup
- `Clock` — `scripts/core/clock.gd` — game time, speed (0,1,2,3), emits `minute_passed`, `hour_passed`, `day_passed`
- `World` — `scripts/world/world.gd` — grid, objects, folk registry, pathfinding (A*)
- `SimDirector` — `scripts/sim/director.gd` — ticks all folk & autonomy each game minute

## Signals on `Events` (exact names — all agents must use these)
```
signal folk_added(folk_id: int)
signal folk_removed(folk_id: int)
signal need_changed(folk_id: int, need: String, value: float)
signal mood_changed(folk_id: int, mood: String, intensity: int)
signal buff_added(folk_id: int, buff_id: String)
signal buff_removed(folk_id: int, buff_id: String)
signal interaction_started(folk_id: int, interaction_id: String, target_id: int)
signal interaction_finished(folk_id: int, interaction_id: String, success: bool)
signal queue_changed(folk_id: int)
signal thought(folk_id: int, text: String)          # balloon text
signal object_placed(object_id: int)
signal object_removed(object_id: int)
signal object_state_changed(object_id: int, state: String)
signal coins_changed(household_id: int, amount: int)
signal relationship_changed(a: int, b: int, track: String, value: float)
signal skill_changed(folk_id: int, skill: String, level: int)
signal notification(text: String, kind: String)
signal selection_changed(kind: String, id: int)      # kind: "folk" | "object" | "none"
signal game_event(event_name: String, payload: Dictionary)   # generic event for goals/careers
```

## Core classes (scripts/sim/) — names & public API are the CONTRACT
- `Stat` (RefCounted): `id, value, min, max, decay_per_min, thresholds`; `tick(minutes)`, `add(delta)`, `set_value(v)`, `ratio()`.
- `Folk` (RefCounted): `id, name, age_stage, traits: Array[String], needs: Dictionary(String->Stat), skills: Dictionary, buffs: Array, tile: Vector2i, queue: Array, current: Interaction, household_id`; `get_mood()`, `has_trait(t)`, `add_buff(id)`, `remove_buff(id)`, `to_dict()`, `static from_dict(d)`.
- `Interaction` (RefCounted): runtime instance of an interaction def: `def_id, actor_id, target_id, elapsed_min, state`; `can_run(folk, obj) -> bool`, `start()`, `tick(minutes)`, `finish(success)`.
- `Autonomy` (static): `choose(folk) -> Dictionary{interaction_id, target_id, score, reason}`; keeps a debug breakdown in `last_debug`.
- `Mood` (static): `compute(folk) -> {mood, intensity}`.
- `Cond` (static): evaluates a condition dictionary (see below) → bool.
- `Loot` (static): applies an array of reward dictionaries to actor/target.

## World API (scripts/world/world.gd) — contract
```
World.width, World.height
World.is_walkable(tile) -> bool
World.find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]   # A*, doors walkable, walls not; on the big map: lot gate -> sidewalks / crosswalks -> lot gate (WorldNav)
World.add_wall(a: Vector2i, b: Vector2i)   # wall segment on tile edge (edge-based walls)
World.place_object(def_id: String, tile: Vector2i, rot: int) -> int   # returns object_id, -1 if blocked
World.remove_object(object_id: int) -> bool
World.get_object(object_id) -> WorldObject
World.objects_in_radius(tile, r) -> Array[WorldObject]
World.add_folk(folk: Folk, tile) ; World.get_folk(id) ; World.all_folk() -> Array[Folk]
World.reserve(object_id, slot_idx, folk_id) -> bool ; World.release(object_id, slot_idx, folk_id)
World.save_dict() -> Dictionary ; World.load_dict(d)
```
`WorldObject` (RefCounted): `id, def_id, tile, rot, state: Dictionary, slots_reserved`. `state` is the ONLY copy of an object's state (sim code goes through `WorldIface.state_get/state_set/state_add`, which write through `World.set_object_state`; there is no Stat mirror).
The `World` autoload (`class_name WorldGrid`) keeps the public API above as one-line delegates to small helper classes that hold a back-reference: `WorldPaths` (tile A*), `WorldNav` (+ `NavGraph`, `NavField`, `LruCache`: hierarchical big-map routing), `WorldEdit` (walls / floors), `WorldObjects` (place / remove / queries / state), `WorldRooms` (lazy per-lot room partitions; roads / parks / open ground = one `STREET` room), `WorldBuild` (buy / sell / undo), `WorldSave` (starter lot, save_dict / load_dict, run-length floors on big maps), `WorldRegions` (regions {rect, kind home|venue|townie_home|park|road, owner, template, entry}, per-tile region lookup, `can_build`, 16x16 chunk index + dirty floor chunks). Add new World features to the matching helper, not to world.gd.
Big map (THE game): `World.MAP_W x MAP_H` (160x120, the only place the size is set). New games and loads always use it: `Neighborhood.start_game(template)` -> `MapLots.build(World, home_template)` = `MapBuilder.build(World)` (data/map_layout.json: roads, 11 lot rectangles with regions, a green with a pond, a wooded south strip) + `LotLoader.place(template, World, rect.position)` for every lot with `World.regions.enforce = false`, then enforcement on (only the home region is buildable). With NO regions (a plain 32x24 lot: world_test, `LotLoader.apply`, thumbnails) everything is buildable, the grid is one room partition and `Neighborhood.lot_at` answers "home". `find_path` goes through `World.nav` (`WorldNav`): same lot / same park = tile A* restricted to that rectangle; anything else = A* to the lot's street gate (`region.entry`, next to the sidewalk; open ground uses the nearest sidewalk), a route over the sidewalk / crosswalk graph built from data/map_layout.json (`NavGraph`: roads are crossed on crosswalks only), A* from the destination gate in. `path_length` across lots = leg + graph distance + leg (no tile list), cached in small LRUs (dropped by `nav.touch_tile / touch_edge` on any wall / blocking-object change); many in-lot questions from one tile build one `NavField` Dijkstra; unreachable targets (fenced gate, blocked sidewalk run, walled-in tile) fail without searching the map. Plain 32x24 worlds and `WorldNav.enabled = false` use `WorldPaths` alone. Street props must not block the 1-wide sidewalk.
Sim door on the big map: `WorldIface.objects_near` returns only the objects of the folk's OWN lot (`WorldObjects.objects_in_lot_of`, chunk index) and `WorldIface.folk_near` only the folk of that lot (street folk meet street folk) - autonomy never walks into another lot.

## Data schemas (data/*.json)
**needs.json** `{ "hunger": {"label":"Hunger","min":-100,"max":100,"start":60,"decay_per_min":0.07, "thresholds":[{"below":-60,"buff":"starving"},{"below":-20,"buff":"hungry"}], "icon_color":"#e8a33d"} , ... }`
Needs: hunger, energy, bladder, hygiene, social, fun, (comfort optional).

**buffs.json** `{ "hungry": {"label":"Hungry","mood":{"uncomfortable":1},"duration_min":0 /*0 = while-condition*/, "need_decay_mult":{"fun":1.2}, "autonomy_mult":{"hunger":1.5}, "thought":"I'm hungry..."} }`

**moods** are: happy, sad, angry, tense, bored, energized, uncomfortable, focused, flirty. Mood = argmax of summed buff weights; intensity 1–3 by thresholds 1/3/6.

**traits.json** `{ "neat": {"label":"Neat","need_decay_mult":{"hygiene":1.3},"autonomy_mult":{"clean":1.5},"likes":["tag:clean"],"dislikes":["tag:messy"],"refuses":[], "buffs_on":{"messy_room":"annoyed"}} }`
Traits must change *decisions* (autonomy weights, refusals), not just numbers.

**objects.json** `{ "fridge": {"label":"Fridge","size":[1,1],"price":600,"tags":["kitchen","food"],"model":"res://assets/models/fridge.glb","slots":[{"offset":[0,1]}],"state":{"stock":{"min":0,"max":10,"start":10}},"advertises":{"hunger":3.0},"interactions":["grab_snack","cook_meal"]} }`
- `advertises`: need → strength used by Autonomy.

**interactions.json**
```
"sleep_bed": {
 "label":"Sleep", "kind":"super", "duration_min":480, "posture":"lie",
 "tests":[{"stat_below":["energy",40]}],            # Cond list, AND'd
 "per_min":{"energy":0.35,"hunger":-0.02},           # stat deltas per game-minute while running
 "on_finish":[{"add_buff":"well_rested"}],           # Loot list
 "on_cancel":[],
 "autonomous":true, "priority":"normal",
 "advertises":{"energy":5.0},                        # optional override
 "thought":"So sleepy..."
}
```
**Cond** keys: `stat_below[stat,val]`, `stat_above`, `has_trait`, `lacks_trait`, `has_buff`, `mood_is`, `skill_at_least[skill,level]`, `object_state_eq[key,val]`, `object_state_above[key,val]`, `time_between[h1,h2]`, `coins_at_least`, `relationship_above[track,val]`, `not:` wrapper, `any:` list (OR).
**Loot** keys: `add_buff`, `remove_buff`, `stat_add[stat,val]`, `skill_xp[skill,val]`, `object_state_add[key,val]`, `coins_add`, `relationship_add[track,val]`, `fire_event[name]`, `notify[text]`, `consume_item[id]`.

## Autonomy scoring (implement exactly)
```
for each candidate (interaction, target):
  if not tests pass or refused by trait or reserved: skip
  score = sum over (need, strength) in advertises: urgency(need) * strength
  urgency(v) = ((max - v)/(max-min))^2 * 10        # quadratic: low needs dominate
  score *= product(buff.autonomy_mult[need]) * product(trait.autonomy_mult[interaction tag])
  score += like/dislike bonus (+1.5 / -3)  ;  score -= 0.15 * path_distance
  score *= (1 + memory_bias(folk,target))        # remembered good/bad experiences, in [-0.5,+0.5]
pick weighted-random among top 3 (weights = score), reason string recorded for debug UI.
```
Implementation notes: `gather()` takes an optional `closed` array; interactions that cannot run for ANY target (cooldown, trait refusal, the actor's own target-independent tests) are not expanded per target and appear as one skipped summary row in `last_debug` instead. Target-independent score parts (advertised needs, buff / trait multipliers, routine) are cached per (interaction, object kind) inside one `choose()`; the full per-candidate breakdown is only built for the best 8. `Interaction.can_run` / `def_runnable` also enforce a folk interaction's `social.requires`, so queued and autonomous paths cannot bypass it.

## Folder layout & OWNERSHIP
Files stay small (aim < 400 lines). Big static classes are split by responsibility; the original class keeps its state (`static var`s, `reset`, `to_dict` / `from_dict`) and the part-classes read it through the main class name.

| Path | What | Owner |
|---|---|---|
| `scripts/core/` | `Events`, `Data`, `Clock` autoloads | code-health |
| `scripts/sim/` | `Stat`, `Folk`, `Interaction`, `Autonomy`, `Mood`, `Cond`, `Loot`, `Routine`, `SimDirector`; `SimEnv` (finds Events / Data / Clock without autoload identifiers so sim code runs under `--script`), `WorldIface` (the sim's only door to the World), `StubWorld` (test World) | code-health |
| `scripts/systems/` | gameplay systems, one class per concern; see below | code-health |
| `scripts/world/` | `world.gd` (+ `world_*.gd` helpers), `neighborhood.gd` (+ `neighborhood_lots.gd`), `lot_loader.gd`, `starter_house.gd`, `world_object.gd` | code-health |
| `scripts/world/*view*.gd`, `lot_*.gd`, `folk_*.gd`, `weather_*.gd`, `scenes/world/`, `assets/` | rendering | visual |
| `scripts/ui/`, `scripts/main.gd`, player-facing text in `data/*.json` | UI and wording | ux/text |
| `data/*.json` | all content: needs, buffs, traits, objects, interactions, careers, goals, social, weather ... | structure: code-health; wording: ux/text |
| `tests/` | see **Tests** | code-health (`ui_*`, `*_shot.gd`, `anim_*` belong to ux / visual) |
| `ARCHITECTURE.md`, `project.godot` | | lead |

### scripts/systems layout (classes split by responsibility)
- `SystemsManager` wires Clock / Events to the systems; `SysUtil` = shared helpers (time, rng, JSON-int helpers `to_ints`, `int_keys`, `ints_in`, `has_int`); `SysCond` = Cond keys of the systems layer; `SaveLoad` = whole-game snapshots (VERSION 3 = the one continuous map: regions in the world dict, Neighborhood saves only bookkeeping; older saves are refused with "old save from an earlier version" - `SaveLoad.is_old`, labelled and disabled in the Load dialogs).
- Content: JSON in `data/content_sys.json`, `data/content_family.json`, `data/weather.json`, `data/holidays.json`, `data/venues.json` ("content") is merged into the shared tables by `ContentMerge`; `SysContent` / `FamilyContent` / `WeatherContent` / `NeighborhoodContent` / `SocialContent` add only the parts computed in code. `SysContent.install_all()` installs systems + family + weather.
- Relationships: `RelationshipService` (pair store, history, event handlers, save) + `RelationshipBits` (labels, flags, compatibility, describe) + `RelationshipRomance` (trust / tension / bond, stages, breakups) + `RelationshipKnowledge` (knowledge, secrets, gossip, reputation, topics).
- Social engine: `SocialDynamics` (resolve, hooks, clock) + `SocialScoring` (success score, tiers, `requires` / reasons) + `SocialActions` (special actions, gossip, rumors) + `SocialConflict` (arguments, cheating) + `SocialGatherings` (gatherings, karaoke, goals / markers); `Conversation`, `Emotions`, `Crowd`.
- Family: `Family` (people store, linking, births, events) + `FamilyTree` (graph queries, tree) + `FamilyMarriage` + `FamilyHousehold` (move out / in, adoption, death); `Aging`, `Genetics`, `BabyCare`.
- Work: `Careers` (data, hiring, offers, upkeep) + `CareerProgress` (performance, promotion, daily tasks) + `CareerShifts` (attendance, school); `Economy`, `Goals`, `Away`.
- Weather: `Weather` (model, forecast, multipliers, save) + `WeatherFolk` (markers, exposure, minute tick) + `WeatherWorld` (hourly / daily effects); `Seasons`, `Holidays`.
- Town: `Story` (townies, daily life) + `StoryVisits` (visits, invites; guests appear on the road <= 30 tiles from the door and walk in); `Venues`, `NeighborhoodService`.
- Sharing (task 24 part B, docs/SHARING.md): `Share*` classes export / import households (as townies with fresh ids, strangers to the town, distinct looks), whole towns (into a NEW save slot) and gifts / letters / cards. Files are untrusted JSON in `user://exports/`: `ShareValidate*` rebuilds them from known fields with caps (`data/share_schema.json`). `ShareState` is saved as `systems.share`; UI: Pause menu > Share (`ShareHub`).
- Neighbourhood (all lots exist at once, nothing is swapped or parked): `Neighborhood` = registry + thin API (`where` / `lot_of` / `lot_of_selected` / `folk_at` derived from tiles, `travel` / `can_travel` / `go_home` / `movable` / `walk_minutes`, pantry, visits, meetups, save) + `NeighborhoodLots` (tile -> lot lookups, entry / spawn tiles, the per-minute region watcher: venue entry rules, arrival toasts, groceries) + `NeighborhoodTravel` (walk = player `go_here` tagged with the lot, time = path length x `Interaction.WALK_MIN_PER_TILE` (0.3) min, the route is computed once by `Interaction.start`, FolkView follows slices of it; a trip cut short by something urgent is resumed (`NeighborhoodLots.on_walk_cut` / `resume_walk`); `{fast:true}` = hidden Away "travel"; `{instant:true}` teleport; `free`, `quiet`) + `MapLots` (build the map with all lots). `LotPicker` draws every lot's template without replacement from the generated pools per game (`Neighborhood.world_seed`, saved; picks live in `region.template`), so no two lots share a layout (docs/HOUSE_LAYOUTS.md). `Crowd` + `CrowdDrive` = ambient NPCs per venue lot (cap per lot, populated only while a resident is within 40 tiles, emptied beyond 64). `Economy.owner`: home objects = household, everything else -1 (community).
- The old class names still answer the calls the UI makes (thin delegates at the bottom of each main class, e.g. `RelationshipService.bit_label`, `Family.tree_for`, `SocialDynamics.reason_unavailable`). New code should call the part-class directly.

## Tests
```
Godot --headless --path . --script res://tests/run_all.gd                       # FAST tier (~45 s): everything except the long simulations
Godot --headless --path . --script res://tests/run_all.gd -- --slow             # + weather_longrun, systems_integration, hood_sim, family_integration, sim_longrun, social_autonomy (~5 min)
Godot --headless --path . --script res://tests/run_all.gd -- --shuffle[=seed]   # random file order (prints the seed); every order must pass
Godot --headless --path . --script res://tests/run_all.gd -- --only=sim_basic,world_test
Godot --headless --path . --script res://tests/run_one.gd -- <test file base name>      # one file, full length
```
- A test file is any `tests/*_test.gd`, `sim_*.gd` or `world_*.gd` with a `run() -> Array` of failure strings. Kits (`*_kit.gd`, `sim_testkit.gd`) are helpers.
- Isolation: `tests/fixture.gd` (`TestFixture.reset()`) runs before and after every file and from `sim_testkit.setup()`: it resets Folk ids, every system's static state, rng seeds, the World / Clock autoloads and the content hooks. Tests must not rely on state left by another file; if a new static `var` is added to a system, reset it in that system's `reset()` (called by `SystemsManager.reset_all()`).
- Speed: long simulations read `TestFixture.fast` / `TestFixture.pick(full, quick)`; the runner sets `fast` unless `--slow`. The SLOW list lives at the top of `run_all.gd`.
- Autonomy perf probe (3 folk, 3 game days, furnished room): ~21 s before -> ~16 s after the candidate pre-filtering / profile cache (see `Autonomy`).

## Definition of done (every agent)
- Code runs under Godot 4.7 with no errors/warnings in `--headless --quit` import.
- Tests under `tests/` pass via the headless runner. Report exact commands run and results.
- Do not edit files you don't own; if a contract is wrong, say so in your report.

## View layer chains (scripts/world)
Big view classes are split as an inheritance chain of small files (each `extends` the previous by path; only the last has the `class_name`):
`LotView` = lot_state > lot_camera > lot_models > lot_chunks (per-chunk floor / overlay meshes, road markings, MultiMesh trees, near-camera chunk sets) > lot_walls (wall / door nodes per chunk, only near the camera) > lot_picking > lot_build > lot_shells (building shells seen from outside: hidden with their interior while no player folk is in / next to the building; click on a lot in the zoomed-out overview flies to it) > lot_view; the camera follows the selected folk on the big map, pan is clamped to the map, zoom cap 110 = the whole map (34 in the single lot, camera distance grows with the zoom);
`FolkView` = folk_data > folk_look > folk_motion > folk_view; `WeatherView` = weather_state > weather_scenery > weather_precip > weather_lamps > weather_view.
Visual harnesses (windowed, read the PNGs): tests/visual_shot.gd (camera/hour/selection/build ghost), gallery_shot.gd (every object x 4 rotations),
furniture_shot.gd (every age on every seat/bed), perf_shot.gd (frame time), bigmap_shot.gd (160x120 map screenshots + `perf` probe; `-- prefix name:zoom:hour:weather:tx,tz|home|follow|lot=cafe:rot`, control specs `go:<lot>[:fast]`, `walk:<lot>[:min]`, `play:<s>[:speed]`, `min:<n>`, `shells:0|1`, `sel:<id>`).

## New-game flow & scenarios
Title -> **New Game** (`ui/start_picker.gd`: cards from `ui/scenario_card.gd`, difficulty buttons, Customise, big Start; **Solo Start + Normal pre-selected**) ->
optional `ui/household_creator.gd` (`folk_editor.gd` + live 3D `folk_preview.gd`; Free Play adds the home chooser) -> `main.start_new_game(h, start_id, opts)`.
`opts` = `{scenario, difficulty, funds}`; the world is built by the UI-free `NewGame.start(mgr, household, start_id, opts)` (tests call the same code).
- **Data** `data/scenarios.json`: `difficulties` (funds_mult / bill_mult / need_mult), `scenarios` (home `start_id`, base `funds`, `start_hour`, `folk[{stage, rel}]`, `tips`, `goals`).
  Funds = scenario funds x difficulty, **independent of home size** (home size only changes space and bills through `lot_value_rate`). `data/neighborhood.json` `starts` keep a neutral 5000 for the `--autostart` path.
- **Household dict** (`HouseholdSetup`): `{name, folk:[{name, stage, traits, aspiration, appearance, rel}]}`; `rel` is relative to the first member (none|partner|spouse|child|parent|sibling).
  `validate()` returns a plain-language reason or "". `create_folk` runs BEFORE `SystemsManager.new_game` (Aging reads `age_stage`), `apply` AFTER it (aspirations, `FamilyMarriage.marry`, `Family.link_parent`, partner bits).
- **State** `Scenario` (static, saved as `systems.scenario`, reset by `SystemsManager.reset_all`): `active_id`, `difficulty`, `done`, `progress`, `finished`. Hooks: `Scenario.bill_multiplier()` (Economy.compute_bill), `Scenario.need_drain()` (Folk.decay_mult, household members only).
- **Goals** `ScenarioGoals` (event / events / jobs / cond checks, rewards in coins + satisfaction points, events `scenario_goal_done`, `scenario_finished`); HUD `ui/scenario_tracker.gd` ('Getting Started', collapsible, then a 'What next?' card pointing to Goals).
- Tests: `tests/start_*_test.gd` (kit `start_kit.gd`); screenshots `tests/start_flow_shot.gd -- picker|picker_hard|creator|creator_family|game_<id>|flow|tracker|nudge out.png`.

## Incidents (rare events)
Danger, illness, crime, disasters and lucky finds are one data-driven framework. How-to with two worked examples: `docs/INCIDENTS.md`.
- **Data**: `data/incidents.json` (config, `handlers`, `content`, no incidents) + every `data/incidents/*.json` (merged by id, file-name order; each later task adds ITS OWN file so agents never share one). `data/death_causes.json` + `data/death_causes/*.json` for causes of death. `00_framework_examples.json` has `heart_attack`, `minor_fall`, `found_money`, `townie_mishap`.
- **Classes** (`scripts/systems/`): `Incidents` (state, API, clock hooks, save) / `IncidentDefs` (load + validate) / `IncidentRisk` (yearly rate -> per-check chance, risk and prevent multipliers) / `IncidentCond` (conditions) / `IncidentSubject` (adapter: a Folk, a far Story townie or a lot looks the same to conditions) / `IncidentChecks` (hourly and daily dice over every person and lot) / `IncidentFlow` (warning -> pending -> outcome, history, toast, chronicle) / `IncidentEffects` (kill, injure, hospital, coins, handlers) / `IncidentContent` (merges the `content` sections: buffs injured / sick / grief tiers, `grave` and `urn` objects, Remember / Mourn). `DeathCauses`, `Graves`, `Hospital`, `ChronicleHook` are the other parts.
- **Two resolution modes from the same data**: FULL (the household and any Folk on the map, incl. visiting townies: real handlers, real objects) and STATISTICAL (far townies / far lots: dice only, outcome from the incident's `statistical` block, one-line summary such as "The Ashby house had a kitchen fire, no one hurt"). `Incidents.resolve_statistical(id, subject)`. Town scope rolls once for the town, then damage PER LOT (home = full, others statistical).
- **Rates**: `base_rate_per_year` x Surprises multiplier x risk entries; a game year = `config.year_days` = 28 days; per-check chance = rate / checks per year (hour = 672 per year, day = 28); folk scope is per person, lot per household, town per town. `Incidents.measured_rate(id)` = triggered / exposure (subject-years that passed the conditions), used by the long-run test.
- **Surprises** (Settings > Gameplay): off / rare / normal / chaotic = x0 / 1 / 3 / 10, `Incidents.surprise_mult()`. Stored per save (`systems.incidents.level`); a new game takes it from the settings file. Old age (`Aging._check_deaths`) never looks at it.
- **API**: `Incidents.force(id, {folk_id | townie_id | lot, outcome, warn})`, `list()`, `active()` (warned and waiting), `history(n)`, `stat(id)`, `register_handler(name, Callable)` or a `handlers` entry in a data file, `insurance_fn` / `insurance_cover(amount, hid)` (task 06), `call_doctor(folk_id)` (cost + check-up + defuses warned incidents; task 02 builds the real doctor on it). Debug panel: F9 (`IncidentDebug`, action `sim_debug_incidents`).
- **Chronicle hook**: every incident outcome, death, birth and wedding emits `Events.game_event("chronicle", {kind, text, day, subjects, lot, severity, public})` (`ChronicleHook.note`); `Incidents.history` entries carry the same fields. The Town Chronicle / newspaper (task 08) listens to it. Toasts follow each incident's `notify_policy` (household / known / town / quiet); a toast is never needed for the chronicle.
- **Deaths**: `Aging.kill(id, cause)` is the only way to die. It works for Folk and for Story townies (`DeathCauses.kill_townie`), applies per-cause text, grief (tier buff + length, family 100%, friends 60%, townies you knew 50%, children get `child_text`), an emotional memory, a legacy sentence, a grave, the chronicle entry and emits `folk_collapsing` first (LotView sinks and shrinks the model: a quiet collapse, no gore).
- **Graves** (`Graves`): a non-blocking `grave` / `urn` object on an open lawn tile of the home lot (park for townies) with a record `{name, born, died, cause}` saved in the incidents block; hover text, interactions Remember / Mourn. Models: `blender/build_memorials.py`.
- **Hospital** (`Hospital`): `admit(id, severity, reason)`, `discharge(id)`, `is_in(x)`, `injure`, `fall_ill`; a hidden Away (reason "hospital") with the hidden `in_hospital` buff, a bill by severity (insurance first, an ordinary bill if the household cannot pay), folk-panel chips (Injured / Unwell / In hospital); far townies use the statistical stay (`config.hospital.townie_death_chance`).
- **Health** (task 02, `Health` + `HealthNeeds/Collapse/Exposure/Illness/Injury/Content/Handlers`): starvation / exhaustion / hypothermia / heatstroke stages with a Collapsed state and rare deaths (deterministic, not Surprises dice), contagious colds and flu, food poisoning from spoiled food, injury severity with slow walking and activity limits, doctor and medicine. API table in `docs/INCIDENTS.md` ("Health API").
- **Ownership**: framework files above = task 01. Later tasks add data files plus their own handler scripts and never edit these classes; extend by data and `register_handler`.

## Crime and justice (tasks 04 / 09 / 09b / 09c)
Data: `data/justice.json` (table `justice`: rates, evidence weights, charges and sentence options, trial score, prison, civil, careers, traits, petty offences, pressure, blackmail, revenge, crime rate), `data/incidents/04_crime.json` + `09_justice.json` (incidents, buffs, interactions, objects), `data/death_causes/04_crime.json`.
- **State** (`JusticeState`, saved as `systems.justice`): the CASE RECORD dictionaries (fields documented in `CaseStore`), criminal records, inmates, grudges (rage per ordered pair), queued events, hourly whereabouts log, serial-killer run, civil cases, blackmail, revenge chains, town crime rate. Own seeded rng. `CrimeFlow` is the single door (reset / on_minute / on_hour / on_day / on_game_event, one line each in `SystemsManager`).
- **Flow**: crime (`CrimeBurglary` visible townie burglar / guest theft, `CrimeStreet` robbery, `CrimeAssault` from screaming arguments, `CrimeMurder` motive -> warning -> final countdown -> act, `CrimeSerial`, `CrimePetty`, `CrimeFraud`, `CrimeBlackmail`, `CrimePressure`) -> `CaseStore.create` -> `CaseDiscovery` (witnessed = reported, hidden = missing score / body / owner notices / audit) -> `CaseInvestigation` + `Police` (hard evidence only the culprit leaves vs capped soft evidence from `CaseEvidence`: motive, alibi from `CrimePlace` whereabouts, record, reputation, gossip) -> `JusticeProcess` (arrest, charges, bail, lawyer, plea) -> `Courthouse` + `JusticeTrial` (scored verdict) -> `JusticeSentence` -> `Prison` (behaviour, parole, visits, release) -> `JusticeAppeal`; `JusticeCivil` (lawsuits from `accident_on_property`, divorce, inheritance, small claims); `CrimeRevenge`; `CrimeRate`.
- **Everyone is a person id** (`CrimePerson`): Folk and Story townies are handled by the same code (full when near, records only when far). All spatial logic is in `CrimePlace` (one file to change when floors arrive).
- **Player**: `JusticePlayer.ask` (prompts via `CasePrompt`, default answer without UI), `hold` (Away reasons custody / jail / prison / court / service), status chips; `CaseBoard` (F10). Careers police officer / detective / lawyer / judge (`JusticeCareers`, interaction `work_case_file`); a record closes some jobs (`Prison.job_ok`, hooked into `Careers.qualify`).

## Commutes (task 11)
Work and school are real trips on the map. `data/careers.json` gives each career a `workplace` lot id (and, for a few, `visible_work`); school kids go to the `school` lot. Config + the `work_*` interactions: `data/commute.json`.
- `Workplace` (lot / door / desk tile, planned walk minutes = route x 0.3 min x injury x weather, `entry_tile(career)` -> `{tile, level}` = the multi-floor hook, coworkers, door greetings), `Commute` (trip state machine `out -> in -> home`, lateness, missed shift, save/load), `VisibleWork` (barista / cook / chef at the cafe counter, fitness coach / athlete at the gym machines, writer at the library desk work ON the lot via `Away.begin_visible`), `CommuteTownies` (townies with a career are statistically at their workplace during the shift; near the player they appear at the gate, walk in as `coworker` crowd and walk out afterwards).
- Flow (`CareerShifts.on_minute`): leave when `now + route + buffer >= shift start`; a `go_here` (high priority, `params.commute`) walks to the door; staff / students are exempt from fees and opening hours (`Commute.exempt` in `NeighborhoodLots._on_enter`, `Commute.on_shift` in `_closing`); at the door the folk is placed on its desk / post and goes `Away` INSIDE the lot (hidden) or works visibly; at shift end it walks home. Pay, performance and the existing events are unchanged (`Away` keeps `start_min = max(arrival, shift start)`). No map / no workplace lot (stub test worlds) -> the old instant rabbit hole.
- Events: `left_for_work|school`, `arrived_at_work|school`, `late_for_work|school` (minutes, penalty, streak), `missed_shift` (every no-show incl. chosen skips; `kind`, `why`), `returned_home`. Toasts only when late / missed; chronicle line (`late_for_work`) only for >= 45 min or the third late in a row. `Interaction.start` now divides walking by `Weather.walk_speed_mult_at` (everyone walks slower in snow) and adds `params.delay_min` (traffic wait from `Traffic.provider`).

## Multi-floor buildings (task 10 part A: world model, pathing, view, build mode; generators and system hooks = part B)
Unlimited floors above (`level` 1, 2, ...) and below (-1, -2, ...) ground. **Level 0 is the old world and is untouched** (every old call still means level 0).
- **Position** = `Vector3i(x, y, level)` (`LPos`: `make / tile / level / elev(level) = level * 3.0 m / tiles_of(route) / level_label / level_name`). `Folk.tile` + `Folk.level`, `WorldObject.tile` + `.level` (+ `.span`: extra levels a lift shaft serves), `Interaction.goto_level`, `Interaction.path3` (multi-floor route; `path` keeps its tiles). Folk, objects and saves default to level 0. **Anything that teleports a Folk should set `f.level = 0`** (Interaction.start also resets a stale level that does not exist at the tile).
- **Storage** (`World.levels`, `WorldLevels`): BUILDING records `{id, rect, min, max, roof, label, region}` + one sparse `LevelLayer` per level number != 0 (`floors: tile -> type` (no entry = void), `walls`, `mounts`, `blocked`, `holes` (stairwell openings), `occ`, `occ_floor`, `gen`). Buildings never overlap, so layers are global per level and cost only what is built (20 floors of 16x12 = 74 KB of save). Ground stays in `World.floors / walls / _blocked`. Templates opt in with a `levels` block (`LotLevels`; the office venue is 3 storeys + a basement), objects take `"level": n`. Save VERSION 4 (`world.levels` block, `level` / `span` on objects and folk); older saves are refused as before.
- **Level-aware World API** (all default to level 0): `is_walkable(t, level)`, `get_floor`, `edge_open`, `set_edge(e, type, level)`, `place_object / can_place / buy_place(def, tile, rot, [hid], level)`, `object_at(t, level)`, `set_wall_line(..., level)`, `paint_floor_rect(..., level)` (type `"none"` removes an upper floor). Rooms: `room_id / room_info / room_tiles / room_score / room_cleanliness / is_outdoor(tile, level)` (one room partition per level and building; a tile is outdoor only if nothing floors it over; the top level counts as outdoor only with roof `none`), `levels.covered(tile, level)`, `WorldRoomsLevels.can_see(world, a3, b3)` (line of sight: walls block, glass / doors / fences do not, floors block between levels except through a stairwell hole).
- **Routing** (`World.router`, `LevelRouter`): `World.find_route(from3, to3, stair_mult = 1.0) -> Array[Vector3i]` (start excluded, goal included), `route_length(from3, to3, stair_mult)` (cost in tile units: steps + portal cost; -1 = unreachable; cached), `has_route`. Level 0 to level 0 is just `WorldNav`. Otherwise a lazy A* over the walkable ends of the active portals of the one or two buildings involved (tile A* inside a level: `LevelPaths`; between ground points: `WorldNav`); unreachable levels fail BEFORE any tile search. `WorldIface.path_length(from, to, from_level, to_level)` (autonomy distance counts vertical travel), `WorldIface.find_route / route_cost / book_route / stair_mult / level_valid`.
- **Portals** (`World.portals`, `LevelPortals`; object defs with a `portal` block in objects.json: `stairs`, `stairs_down`, `ladder`, `ladder_down`, `fire_escape` (exterior), `elevator`; `pillar` = tag `support`): stairs 2x1 (walk on at f0 - dir on level L, off at f1 + dir on level L+dz; the opening above is a hole), ladder 1x1, lift = one object with `span` serving level .. top (default: up to the building's top; extended when a floor is added). A portal is active when its object is not broken / `out_of_order` and both ends are walkable on existing levels. Cost: stairs = steps + 4 per level x `LevelPortals.stair_mult(folk)` (elders x1.5, toddlers x1.7, children x1.05, divided by `Health.speed_mult`), lift = 4 + 2 + levels + queue. `LevelElevators`: capacity (def, 4); `book_route` books the rides at `Interaction.start`; folk beyond the capacity wait `CYCLE_MIN` per full car (extra minutes are added to `travel_total`); out of order = not in the graph. Toggle with `World.set_object_state(id, "out_of_order", true)`.
- **Build mode** (`World.lbuild`, `LevelBuild`): `ensure_building(tile)`, `add_level(bid, above)` (needs a stair / ladder going up on the top level or a lift to it; for basements a `*_down` stair / ladder on the lowest level; the new level starts as the footprint below with an outer wall; price `level_price(level)` = 700 + 300 per level above the first, 900 + 350 per basement, + 2 per floor tile, + 5 per wall), `why_not_add`, `set_roof(bid, flat|gable|hip|none)`, `paint_floor_rect / set_wall_line(level)`, `removal_blocked`. Structure rules: a floor above level 0 needs a floor below (levels above the first) and a wall edge or pillar of the level below within 4 tiles; walls, pillars and floors that a floor above rests on cannot be removed. Everything is undoable (`lv_*` ops in `WorldBuild._undo`).
- **View** (`LevelView`, child of LotView; `LevelMesher`, `LevelProps`; UI `FloorSelector`, `LevelBuildBar`): the active building = the selected Folk's, else the one under the camera, else (build mode) the home lot's; the viewed level follows the selected Folk's body (`follow`, toggle in the selector) or is stepped with the buttons / Page Up / Page Down (`sim_level_up / down`); levels above are not drawn, the viewed one uses the wall mode (cut-away = camera-side walls low), levels below are shells with their stairs, a basement view hides the ground inside the building, the roof shows on the top level in walls-up mode, building shells are as tall as the tower (`scale.y = storeys`), Folk of the building on other floors are hidden (dots in the selector), `LotView._plane_y` is the pick plane, `build_level()` the build tools' level, rain and snow stop at the roofs (a `GPUParticlesCollisionBox3D` over each building + `COLLISION_HIDE_ON_CONTACT`). FolkView walks stairs along `Interaction.path3` (y from `World.walk_y(tile, level)`, lift rides are vertical).
- **Part B must know**: other systems still think in `tile` only; use `f.level` / `o.level` wherever floors matter (fire spreading upward, falls, crime entry through level-0 doors, `CrimePlace`, hospital wards). `objects_in_radius` and `WorldIface.objects_near` return objects of ALL levels of the lot. Generators (`HouseGenerator`, venues) place level-0 content only; a template becomes multi-floor with a `levels` block (see the office in data/lot_templates.json, and `tests/level_kit.gd` for towers built by code). LotPicker keeps a lot's own multi-floor template instead of a generated single-storey venue.
- Tests: `tests/level_{route,walk,build,save,office,view,perf}_test.gd` (kit `level_kit.gd`); windowed harness `tests/level_shot.gd` (tower, each floor, stairs, basement, build mode, `perf`).
