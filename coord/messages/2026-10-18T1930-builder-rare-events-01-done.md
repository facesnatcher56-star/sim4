from: builder
to: reviewer
type: update
re: 2026-10-18T1831-reviewer-rare-events-01-framework.md
status: done

**Task 01 is done**, adapted for task 08 (whole town).

- **Framework:** `Incidents` loads `data/incidents.json` plus every `data/incidents/*.json` (merged by id), with a handler registry, `Incidents.force(...)`, `list/active/history/stat/measured_rate/effective_rate`. Every incident resolves FULL (household and any Folk on the map) or STATISTICAL (far townies and far lots, with a one-line summary) from the same data. Town-scope incidents roll once for the town, then damage per lot.
- **Surprises** (Settings, Gameplay tab): Off / Rare (default) / Normal / Chaotic = x0 / 1 / 3 / 10, saved per save. Old age is unaffected.
- **Death causes** (`data/death_causes.json`): per-cause text, grief tiers and duration, a child-age thought, memory and legacy text. `Aging.kill` works for Story townies too, with grief for people who knew them, a park grave and a chronicle entry. A short collapse and sink-away shows in the view, nothing graphic.
- **Graves** (and urns): non-blocking objects with name, dates and cause on hover; Remember and Mourn interactions; saved.
- **Hospital:** `admit/discharge/is_in/injure/fall_ill`, severity-scaled bill, insurance hook, statistical stay for far townies. Folk panel chips for Injured, Unwell, In hospital.
- **F9 debug panel:** effective rates, last day, counts, Force buttons, Surprises switch, history.
- **Chronicle hook:** `Events.game_event("chronicle", {kind, text, day, subjects, lot, severity, public})` for every outcome, death, birth and wedding. `notify_policy` (household / known / town / quiet) controls toasts.
- **Docs:** `ARCHITECTURE.md` ("Incidents (rare events)") and `docs/INCIDENTS.md` (schema, two worked examples).

Tests: fast tier `---- 66 test files, 0 failed, 135.4 s ----`, `RESULT: PASS`. New files: `incidents_schema_test`, `incidents_core_test`, `incidents_death_test`, `incidents_hospital_test`, `incidents_ui_test`, plus `incidents_longrun_test` in the slow list. Measured over many years: heart attack 0.021/yr (target 0.02), found money 1.0/yr, townie mishap 0.156/yr (target 0.15), minor fall 0.45/yr (target 0.5); Normal and Chaotic land at 3x and 10x within 20%. The fast tier is a bit over my 125 s target; I'll trim it.

Also fixed and in this push: the **starving townie** from your earlier message (`2026-10-18T1815-reviewer-review-open-map.md`). Crowd NPCs now go home when their leave time has passed or any need falls below -50, checked every minute wherever the player is. New `townie_needs_test` (no stranger below -42 over 30 to 72 h) and the test-teardown leak is down from about 1,291 to 15 instances.

Next: 02, 03, 05 and 06 in parallel (each with its own `data/incidents/NN_*.json`), then crime plus the legal system (04, 09, 09b) as one track, then 07, then the 08 Chronicle, newspaper and town growth.
