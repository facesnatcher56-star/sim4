# How to add an incident (rare events)

Everything lives in data. You normally add **one file** `data/incidents/NN_<your task>.json` and never edit someone else's file.
Overview of the system: `ARCHITECTURE.md`, section "Incidents (rare events)".

## File shape

```json
{
 "config":    { },                                   // optional overrides (year_days, hospital numbers ...)
 "handlers":  { "my_handler": {"script": "res://scripts/systems/my_events.gd", "method": "on_incident"} },
 "content":   { "buffs": {}, "interactions": {}, "objects": {}, "object_interactions": {} },   // ContentMerge format, installed for you
 "incidents": { "my_incident": { ...definition... } }
}
```
Death causes go in `data/death_causes/NN_<task>.json` (`{"causes": {"fire": {...}}}`, see `data/death_causes.json`).

## An incident definition

| key | meaning |
|---|---|
| `label` | player-facing name (debug panel, history) |
| `scope` | `folk` (each Folk and each far townie), `lot` (each household lot and each townie lot), `town` (one town roll, then damage rolled PER LOT), `townie` (townies only) |
| `check` | `hour` or `day`: how often the dice are rolled |
| `base_rate_per_year` | events per subject per game year (28 days). folk = per person, lot = per household, town = per town |
| `conditions` | Cond / SysCond list that must hold (see keys below) |
| `risk_mults` | `[{"when": [conds], "mult": 1.5, "label": "..."}]` multipliers, all matching entries multiply |
| `prevent` | same shape; `"block": true` instead of `mult` makes it impossible. This is the player's counterplay |
| `lot_hit`, `per_lot` | town scope only: `lot_hit` = base chance a given lot is hit once the town event happens; risk / prevent entries with `"per_lot": true` change that chance, the others change how often the town event itself happens |
| `warning` | `{lead_min, thought, text, kind, averted, doctor_can_defuse}`. With `lead_min > 0` the player gets the thought bubble and toast now and the outcome happens that many minutes later unless `defuse` conditions hold, a prevent entry blocks it, or `Incidents.call_doctor(folk_id)` is used (needs `doctor_can_defuse`) |
| `defuse` | conditions that cancel a warned incident when it comes due |
| `outcomes` | `[{"weight": 3, "when": [conds], "effects": [...], "text": "...", "kind": "bad"}]` weighted pick among the entries whose `when` holds |
| `statistical` | `{"outcomes": [{weight, when, effects, summary}]}` the far-away version, one line `summary` per outcome. If missing the normal outcomes are reused (handlers skipped) |
| `notify_policy` | `household` (only the player's own people / lots toast) / `known` (default: also people the household has met) / `town` (always) / `quiet` (chronicle only) |
| `surprise` | `false` = ignore the Surprises setting (default true) |
| `severity`, `public` | 1..5 and bool, copied into the chronicle entry |

Text tokens: `{name}` (the Folk, townie or "Your home"), `{house}` ("The Ashby house"), `{amount}`. Use they / them. No ids, no jargon.

### Condition keys
Every Cond / SysCond key (`has_trait`, `lacks_buff`, `skill_at_least`, `stat_below`, `age_stage_is`, `coins_at_least`, `time_between` ...) plus
`has_object` / `lacks_object` (def id or list), `weather_is` ([ids]), `season_is` ([ids]), `hour_between` ([h1, h2]),
`any_member` / `all_members` (for lot scope: a list of conditions applied to the lot's residents), `not`, `any`.
The same keys work for far townies: traits, career-based skills (a cook has cooking = level + 1), `age_stage_is`, `coins_at_least`, buffs
listed in the Story record. A check that a townie record cannot answer is false.

### Effects (inside an outcome's `effects`)
`kill "cause"` (goes through `Aging.kill`), `injure {severity 1-3, reason}`, `sick {severity, reason}`, `hospital {severity, reason}`,
`coins_range [lo, hi]` (household coins, fills `{amount}`), `handler "name"` (+ `"args": {}`), `thought "text"`, `chance 0..1`,
and any Loot key (`add_buff`, `remove_buff`, `stat_add`, `skill_xp`, `coins_add` ...).
Severity 2+ admits the person to the hospital (`Hospital.admit`).

### Handlers
For behaviour data cannot express (fire spread, a burglar walking in). Declare it in your file's `handlers` section (script path + static method)
or call `Incidents.register_handler("name", callable)`. Signature: `func(ctx: Dictionary, args: Dictionary) -> Dictionary`.
`ctx`: `incident`, `subject` (IncidentSubject: `kind`, `folk`, `lot_key`, `display_name()`, `members()` ...), `folk`, `household_id`, `lot_key`,
`statistical` (true = far version: do it with dice and records only, no real objects), `forced`, `amount`.
Return `{"text": "...", "kind": "bad"}` to override the outcome text, or `{}`.

## Worked example 1: a data-only incident (kitchen grease fire, no handler)

```json
{
 "incidents": {
  "grease_flare": {
   "label": "Grease flare", "scope": "folk", "check": "hour", "base_rate_per_year": 0.3, "notify_policy": "household",
   "conditions": [{"has_buff": "meal_ready"}, {"skill_below": ["cooking", 4]}],
   "risk_mults": [{"label": "Clumsy cook", "when": [{"has_trait": "clumsy"}], "mult": 2.0}],
   "prevent": [{"label": "Fire extinguisher at hand", "when": [{"has_object": "fire_extinguisher"}], "mult": 0.3}],
   "warning": {"lead_min": 3, "thought": "Is something burning?", "text": "{name} smells something burning in the kitchen.", "kind": "warn",
               "averted": "{name} caught it just in time."},
   "defuse": [{"has_buff": "focused_flow"}],
   "outcomes": [
    {"weight": 8, "effects": [{"stat_add": ["hygiene", -10]}], "text": "{name} singed the dinner and the apron.", "kind": "warn"},
    {"weight": 2, "effects": [{"injure": {"severity": 1, "reason": "a burn"}}], "text": "{name} burned a hand putting the pan out.", "kind": "bad"}
   ],
   "statistical": {"outcomes": [
    {"weight": 9, "effects": [], "summary": "{name} burned the dinner."},
    {"weight": 1, "effects": [{"hospital": {"severity": 2, "reason": "a burn"}}], "summary": "{name} was taken to hospital with a burn."}
   ]}
  }
 }
}
```
Force it from the F9 panel or `Incidents.force("grease_flare", {"folk_id": id, "outcome": 1})`.

## Worked example 2: an incident with a handler and a town roll

```json
{
 "handlers": {"storm_damage": {"script": "res://scripts/systems/storm_events.gd", "method": "on_storm"}},
 "incidents": {
  "windstorm": {
   "label": "Windstorm", "scope": "town", "check": "hour", "base_rate_per_year": 0.4, "lot_hit": 0.6, "notify_policy": "town",
   "conditions": [{"weather_is": ["windy", "thunderstorm"]}],
   "prevent": [{"label": "Shutters", "when": [{"has_object": "shutters"}], "mult": 0.2, "per_lot": true}],
   "outcomes": [{"weight": 1, "effects": [{"handler": "storm_damage", "args": {"power": 2}}], "text": "{house} lost some roof tiles in the storm.", "kind": "warn"}],
   "statistical": {"outcomes": [{"weight": 1, "effects": [], "summary": "{house} lost some roof tiles in the storm."}]}
  }
 }
}
```
```gdscript
# scripts/systems/storm_events.gd
class_name StormEvents
static func on_storm(ctx: Dictionary, args: Dictionary) -> Dictionary:
    if bool(ctx["statistical"]):
        return {}                       # far lot: the summary line is enough
    # real lot: remove / damage objects of ctx["household_id"], use args["power"]
    return {}
```
A town incident calls the handler once per lot that was hit (home lot FULL, the others `statistical`).

## Death causes
```json
{"causes": {"fire": {"label": "Fire", "text": "{name} could not escape the fire.", "legacy_text": "Their life ended in a house fire.",
  "grief": {"strength": 1.8, "days": 6}, "child_text": "I'm so scared. Where did they go?", "memory": {"value": -0.9, "text": "the night of the fire"},
  "grave_style": "urn", "unexpected": true, "severity": 5}}}
```
Kill with `Aging.kill(folk_or_townie_id, "fire")`. Grief strength <= 1 = normal grieving, <= 1.6 heavy, above = shattered; friends grieve 60% as long.

## Checklist
1. `Godot --headless --path . --script res://tests/run_one.gd -- incidents_schema_test` (validates every file).
2. Force each outcome in a test (`Incidents.force(id, {..., "outcome": i})`), check the effect, the toast text and the counters.
3. Add a long-run check if your rate matters (`tests/incidents_longrun_test.gd` is the pattern: `Incidents.measured_rate(id)`).
4. Every incident needs counterplay (`prevent` / `warning` / `defuse`) unless it is an act of nature.
