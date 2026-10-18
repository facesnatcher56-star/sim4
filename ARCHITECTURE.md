# sim-4 — Architecture & Contracts

Godot 4.7 (GDScript). Original life-sim inspired by the *mechanics* of The Sims. Use ORIGINAL names/assets: characters are **Folk**, money is **Coins**, etc. Do not copy EA content.

Godot exe: `C:\Users\lloyd\AppData\Local\Godot47\Godot_v4.7-stable_win64_console.exe`
Blender: `C:\Program Files\Blender Foundation\Blender 5.1\blender.exe` (use `--background --python`)
Headless test: `Godot --headless --path . --script res://tests/run_all.gd`

## Principles
1. **Logic is separate from rendering.** All simulation (`scripts/sim/`) is plain `RefCounted`/`Node` code with NO dependency on visuals, so it is testable headless. 3D scenes only *display* state.
2. **Grid-based world.** Logic uses `Vector2i` tiles (1 tile = 1 m). 3D position = `Vector3(x+0.5, 0, y+0.5)`.
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
World.find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]   # A*, doors walkable, walls not
World.add_wall(a: Vector2i, b: Vector2i)   # wall segment on tile edge (edge-based walls)
World.place_object(def_id: String, tile: Vector2i, rot: int) -> int   # returns object_id, -1 if blocked
World.remove_object(object_id: int) -> bool
World.get_object(object_id) -> WorldObject
World.objects_in_radius(tile, r) -> Array[WorldObject]
World.add_folk(folk: Folk, tile) ; World.get_folk(id) ; World.all_folk() -> Array[Folk]
World.reserve(object_id, slot_idx, folk_id) -> bool ; World.release(object_id, slot_idx, folk_id)
World.save_dict() -> Dictionary ; World.load_dict(d)
```
`WorldObject` (RefCounted): `id, def_id, tile, rot, state: Dictionary, stats: Dictionary(String->Stat), slots_reserved`.

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

## Folder layout & OWNERSHIP (agents edit only their own paths)
| Path | Owner |
|---|---|
| `scripts/core/*`, `scripts/sim/*`, `data/needs|buffs|traits|interactions.json`, `tests/sim_*` | **sim-core agent** |
| `scripts/world/*`, `data/objects.json`, `scenes/world/*`, `tests/world_*` | **world agent** |
| `scenes/ui/*`, `scripts/ui/*`, `scenes/main.tscn`, `scripts/main.gd` | **ui agent** |
| `blender/*`, `assets/models/*`, `assets/textures/*` | **assets agent** |
| `scripts/systems/*` (social, economy, careers, goals, aging, saveload), `data/careers|goals|social.json` | **systems agent** (wave 2) |
| `ARCHITECTURE.md`, `project.godot` | lead only (propose changes in your final report) |

## Definition of done (every agent)
- Code runs under Godot 4.7 with no errors/warnings in `--headless --quit` import.
- Tests under `tests/` pass via the headless runner. Report exact commands run and results.
- Do not edit files you don't own; if a contract is wrong, say so in your report.
