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
| `chronicle_min_severity` | outcomes below this severity (1..5) are not written to the town chronicle, only to the history and the toast per `notify_policy` (everyday mishaps; default 0 = always) |

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

## Health API (task 02: needs deaths, illness, injury)
All in `scripts/systems/health*.gd`, data in `data/incidents/02_needs_health.json` (`config.health`, buffs, interactions, the illness incidents) and
`data/death_causes/02_needs_health.json`. Hooks are called from `Incidents.on_minute/on_hour/on_day` (state ticks) and `SystemsManager` (events).

**Other tasks call these** (static, safe on any Folk or folk id):

| call | what it does |
|---|---|
| `Health.injure(folk_or_id, severity 1..3, cause)` | the injury entry point (the `injure` incident effect and `Hospital.injure` go through it). Adds the `injured` buff for the severity's duration, records `inj`, severity 2+ is admitted to hospital |
| `Health.is_injured(f)` / `Health.injury_severity(f)` | 0 = healthy |
| `Health.speed_mult(f)` | walking speed factor (injured 0.8 / 0.6 / 0.45, flu, hypothermia, faint ... ). `Interaction.start` divides the walk time by it, never below 0.3 |
| `Health.blocks_activity(f, tags)` / `Health.work_block(f, career_id)` | `""` or a reason. Injured / flu folk do not get interactions tagged `exercise`, `fitness`, `dance` (test patch added by `HealthContent`); flu and food poisoning skip work, an injury skips physical careers (all work when severity 2+) |
| `Health.fall_ill(f, kind, severity, cause)` | kind `cold`, `flu`, `food_poisoning`, `exposure`, `generic`. `Hospital.fall_ill` = generic. Sets the illness buff, the `sick` marker and a record; severity 2+ admits |
| `Health.is_ill(f)` / `Health.illness_of(f)` | `{kind, severity, since}` |
| `Health.is_collapsed(f)` / `Health.collapse(f, kind)` / `Health.rescue(f, helper)` | the Collapsed state (kinds hunger, exhaustion, cold, heat): buff `collapsed`, lying on the floor, a housemate helps after about 20 min (`help_collapsed`), or a doctor, or the hospital |
| `Health.heal(f)` / `Health.on_doctor(f)` | cure; `Incidents.call_doctor` calls `on_doctor` (revives the collapsed, cuts illness 75 percent and injury 50 percent, adds `medicated`) and returns `treated: [...]` |
| `Health.stage_of(f)` | `{hunger, energy, cold, heat}` 0 fine .. 3 collapsed |
| `Health.register_neglect_hook(callable)` | **task 07**: `callable(folk, {kind, minutes, needs, day, time})` runs once when a toddler, child or elder has had hunger / hygiene / energy under -60 for 8 hours (buff `neglected`, game event `neglect_noticed`). A collapsed toddler or child is taken to hospital after 6 hours with no help (game event `neglect_emergency`) |

**Rules to remember**
- Starvation (hunger at the floor 12 h warning, 2 days collapse, from 3 days a small chance per hour of death), exhaustion (collapse after 2 days at the bottom, only elders can die after 5 days), hypothermia and heatstroke (shivering / overheating, then sick, then collapsed, then a small death chance) are **deterministic consequences of neglect**: they use `Health.rng`, not incident dice, and are **not** scaled by the Surprises setting (so Surprises Off still lets long neglect kill). Illness (catching, getting worse, food poisoning) and the scuffle injury are ordinary incidents and **are** scaled. Children and babies never die of these; thresholds are shorter for toddlers, children and elders (`config.health.stage_mult`).
- Colds and flu spread: every hour a contagious person marks housemates (and anyone they talked to in the last 90 minutes) with a hidden `exposed_cold` / `exposed_flu` buff, which multiplies the catch rate of `catch_cold` / `catch_flu`. Recovery gives a few days of immunity.
- Eating from a fridge with spoiled food rolls food poisoning (warned 25 minutes ahead; medicine or a doctor defuses it). Tossing the food (existing chore) removes the risk.
- Counterplay interactions (all in the 02 file): `take_medicine` and `treat_injury` (sink), `put_on_coat` (dresser / wardrobe), `drink_water` (sink), `help_collapsed`, plus ordinary rest and the doctor call.
- Save: `Health.to_dict/from_dict` inside the incidents block.

## Natural disasters (task 06)
`data/incidents/06_disasters.json` + `scripts/systems/disaster_*.gd` + `scripts/world/disaster_view.gd`. Town-scope incidents (`power_outage`, `utility_cutoff` (lot scope, overdue bills), `blizzard`, `tornado`, `flood`, `earthquake`, `wildfire`, `hailstorm`, `meteor_strike`) with ONE handler `disaster_hit` (`args.kind`, `args.power` 1..3).
- **Condition key `disaster`** (`DisasterConds`): `{rain_days_at_least, dry_days_at_least, overdue_bills, insured, damaged, outage}`. Any later task can use it in its own incident file.
- **State** (`DisasterState`, saved inside `Incidents.to_dict()["disasters"]`): running town events (siren / blizzard / outage / flood / smoke), per-lot damage records (`home:<hid>` real, `town:<n>` statistical), insurance level per household, rain / dry streaks, pending neighbour visits and disaster deaths. `DisasterState.begin(kind, minutes, power, headline)` starts a town event once per roll.
- **Numbers** are data: `config.disasters.damage[kind]` (arrays indexed by power), `config.disasters.insurance`, `.texts`. Base rates are per game year of QUALIFYING weather; `tests/disaster_longrun_test.gd` checks the real yearly frequency.
- **Counterplay**: shutters (tornado / hail) and sandbags (flood) lower the power by one; the `storm_shelter` and any bathroom fixture protect people who `take_cover` (autonomous during the siren); `generator` keeps the power on; insurance (mailbox > Home insurance) pays back a share of damage, hospital bills and doctor visits (`Incidents.insurance_fn`) for a weekly premium (`DisasterInsurance.bill_extra` in `Economy.compute_bill`).
- **Aftermath**: `clear_debris`, `call_repairers` (mailbox, pays the quote), `scrub_mould`, neighbours visiting with gifts, shared grief after deaths (`DisasterAftermath`). Wildfire hands over to `Fire.ignite(target, "wildfire", opts)` for lots it reaches.
- **Shared-file hooks** (one line each): `Incidents.reset/to_dict/from_dict`, `SystemsManager` minute / hour / day / game-event, `Economy.compute_bill`, `NeighborhoodTravel.can_travel` (blizzard closes the roads), `IncidentCond` (`disaster` key), `IncidentDefs.TOP_KEYS` (`lot_hit`), `LotView._ready` (`DisasterView`).

## Fire API (task 03)
`data/incidents/03_fire.json` (config.fire, five incidents, buffs, objects `sprinkler` / `ash_pile`, interactions) + `data/death_causes/03_fire.json` (`fire`) + `scripts/systems/fire_*.gd` (class `Fire` in `fire_core.gd`) + `scripts/world/fire_view.gd`. Everything is numbers in `config.fire`.

**Other tasks call these** (all static on `Fire`):

| call | what it does |
|---|---|
| `Fire.ignite(target, source = "unknown", opts = {}) -> bool` | `target`: an object, an object id or a `Vector2i` tile. Starts a fire there (false when it already burns, or nothing flammable is there; `arson`, `wildfire` and `lightning` always catch). `opts`: `culprit` (folk id), `force` (burn anything), `stage` 1..3, `quiet` (no "Fire!" toast). `source` picks the words of the summary: `cooking fireplace electrical repair candle lightning arson wildfire` (anything else = "fire") |
| `Fire.extinguish(target, by = "") -> bool` / `Fire.extinguish_lot(lot, by) -> int` | put a fire out (the object survives, scorched, and is `broken` if it burned a while) |
| `Fire.is_burning(target)`, `Fire.active()`, `Fire.fires_in(lot)`, `Fire.lots_burning()`, `Fire.smoke_of(lot)` (0..1) | queries. `lot` is the neighbourhood lot id (`Neighborhood.HOME` = `"home"`) |
| `Fire.call_brigade(lot, caller_id = -1)` | the fire department comes after a delay |
| `Fire.stats` | counters: ignited, blazes, spread_blazes, spread_events, destroyed, loss, deaths, hurt, by_folk, by_sprinkler, by_brigade, rescued, armed, averted |
| `Fire.hover_text(object)` | the extra tooltip lines (fire risk / protection) `LotPicking` adds under an object's name |

Game events: `fire_started {lot, tile, source, object}`, `fire_alarm`, `fire_brigade_called`, `fire_brigade_arrived`, `fire_ended`, `fire_out {lot, source, loss, spread, dead}`; chronicle kind `fire` (one entry per blaze, with the losses). Insurance (`Incidents.insurance_fn`) pays back part of the value lost.

**Sources** (incidents, lot scope, rates per household per game year, Rare): `kitchen_fire` 0.3 (x0.6 when everybody cooks at level 2+, x0.2 more at level 4+, x1.5 with a clumsy cook), `fireplace_fire` 0.06 (x2 in winter), `electrical_fire` 0.07 (x1.6 with low handiness: botched repairs), `candle_fire` 0.14 per holiday-year = about 0.04 (holidays only), `lightning_fire` 0.5 per stormy year (thunderstorms only). A rolled incident ARMS a source (`FireEvents`): the kitchen fire starts a few minutes into the next meal, the fireplace one when it burns unattended for 20 minutes, the electrical one when a device is used or repaired, the candle one on the holiday evening, lightning at once; an armed source that finds no moment in 4-6 days fizzles (counted as `averted`). `Incidents.force(id, {lot = "home:1"})` ignites at once.

**What a fire does**: stage 1 small, 2 growing, 3 raging by age (`stage_age`). Every ~4 minutes it may spread to flammable neighbours (walls stop it, tags / ids in `flam_tags` / `flam_ids`, carpet and wood floors), smoke builds per lot, the object burns away after ~9-23 minutes (price lost, `ash_pile` + scorch mark left). Putting it out early leaves the object scorched, broken if it burned a while.

**What people do** (`FireFolk`, each minute): a working smoke alarm wakes everybody; folk in the room notice within a minute, others within 3. Aware adults rescue babies and toddlers, phone the fire department, smother a young fire next to them (chance rises with cooking / handiness), fetch the extinguisher (`use_extinguisher`, 92 / 65 / 22 percent by stage), or run out (`flee_fire`, then `watch_fire` in the street until it is over). Children only run. Smoke hurts anyone in a burning room (`fire_smoke` buff, injured after 9 minutes of exposure); sleepers without an alarm, babies with no adult awake and anyone trapped can die (`Aging.kill(id, "fire")`) after 28 minutes. Sprinklers put small fires out by themselves and slow spread. The fire department (uniformed NPC visitors, ids from 7000) arrives 9-14 minutes after the call (a neighbour calls after 10 minutes if nobody does), puts fires out, carries stuck people out, tidies up and leaves.

**Far lots and townies**: the same five incidents use their `statistical.outcomes` ("The Ashby house had a kitchen fire, no one hurt", hospital, death). `FireTown` gives every townie lot a deterministic `town_objects` list (stove, fireplace, smoke alarm, extinguisher, sprinkler) so the `has_object` conditions and the outcome weights depend on it, keeps the hidden `holiday_today` marker on townie records for candle fires, and a burnt-out lot loses things and recovers after 10 days. Targets: spread ~0.05, death ~0.005 per household-year (tests/fire_longrun_test.gd measures them).

**Prevention shown to the player**: tooltip lines on stove / grill ("Low cooking skill: fire risk", "No working smoke alarm in the house"), fireplace ("Fire risk if left burning alone"), smoke alarm (battery), extinguisher (charge), sprinkler, broken electronics. Chores: `douse_fireplace` (Put Out the Fire), `test_smoke_alarm` / `replace_alarm_batteries` (already existed), `inspect_extinguisher`, `sweep_ash`; commands for the player: `use_extinguisher` ("Fight the Fire") and `call_firefighters` while a fire burns.

**Shared-file hooks** (one line each): `SystemsManager` (`Fire.reset`, `Fire.on_minute`, `Fire.on_day`, interaction-started and game-event routing), `SaveLoad` (`systems.fire`), `LotView._ready` (`FireView.ensure_on`), `LotPicking` (hover tooltip lines), `tests/run_all.gd` (SLOW list).

## Household chaos (task 07)
`data/incidents/07_chaos.json` (config.chaos, buffs, interactions) + `scripts/systems/chaos_*.gd` (`ChaosState` saved in `Incidents.to_dict()["chaos"]`, `ChaosEvents` handler `chaos_trouble`, `ChaosClock` hooks, `ChaosConds` = condition key `chaos`: `plumbing`, `appliance`, `messy_at_least`, `pests_below/at_least`, `pest_free`, `leaking`).
- Lot incidents per household-year (Rare): `burst_pipe` 0.18 (warned 60 min ahead; `check_pipes` at a sink defuses; x2.5 in snow), `toilet_overflow` 0.35, `appliance_breakdown` 0.9, `roach_infestation` 1.2 per MESSY household-year (dirty surfaces, spoiled food, full bin; far lots: 25 percent messy per week). Handiness 4+ in the house x0.6.
- Water damage and mould reuse `DisasterState.lot("home:<hid>")` (cost, flood, mould), so Call the Repairers and Scrub Mould work. Counterplay: Stop the Leak (DIY, chance 30 percent + 10 percent per handiness level), Call a Plumber / Handyperson / Exterminator at the mailbox (paid through Economy, they arrive after 30-120 min), Set Roach Traps at the bin, cleaning. Roaches grow 0.1/day while messy, die back 0.06/day when clean; 0.5 spoils fridge food, 0.85 can make people ill. An exterminator gives 14 days of protection.
- Only homes with a teen, adult or elder, and (for pipes / appliances) the matching objects, ever roll; far lots resolve statistically (one line, small coin cost, no toast).
