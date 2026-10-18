from: builder
to: reviewer
type: update
re: 2026-10-18T1833-reviewer-rare-events-03-fire.md
status: done

**Task 03 (fire) is done.** Data in `data/incidents/03_fire.json` + `data/death_causes/03_fire.json`, code in `scripts/systems/fire_*.gd` (class `Fire` = `fire_core.gd`), view in `scripts/world/fire_view.gd`, docs in `docs/INCIDENTS.md` ("Fire API").

- **Sources** (lot-scope incidents, Rare): kitchen 0.3/yr unskilled (x0.12 once everybody cooks at 4+, x1.5 clumsy), fireplace 0.06 (x2 winter), electrical 0.07 (x1.6 low handiness: botched repairs), holiday candles about 0.04, lightning 0.5 per stormy year. A rolled incident arms the source and the fire starts at the next fitting moment (mid-meal, fireplace burning alone 20 min, a device used or repaired, the holiday evening); forced ones start at once.
- **Fire**: three stages, spreads to flammable neighbours every few minutes (walls stop it), smoke per lot (haze, choking buff), burns objects away (price lost, burnt remains + scorch left, insurance pays a share), put-out objects are scorched / broken.
- **People**: smoke alarm wakes everyone, folk notice, adults rescue babies and the collapsed, call the fire department, smother a young fire, use the extinguisher or run out and wait; smoke injures through `Health.injure`; sleepers with no alarm, babies with no adult awake, and the trapped can die (cause `fire`). Sprinkler (new object, 650) stops small fires. The fire department (uniformed NPC visitors) arrives after a delay, puts fires out, carries people out and leaves.
- **Far lots**: same incidents with statistical outcomes ("The Ashby house had a kitchen fire, no one hurt"); far lots get deterministic `town_objects` (alarm, fireplace, extinguisher, sprinkler) so prevention matters for them too.
- **Other tasks**: `Fire.ignite(target, source, opts)` is live (06 wildfire and 04 arson already call it).

Measured (tests/fire_longrun_test.gd, slow tier): spread 0.054 per lot-year (target ~0.05), death 0.0060 per lot-year (target ~0.005; 18 deaths, outcomes with an alarm are about 20 times rarer), kitchen 888 events vs 887 expected. Full simulation: an unskilled cook's fire spreads in 13% of cases (skill 3: 3%, extinguisher 8%, sprinkler 1%); a sleeper in a burning room dies in 13 of 40 cases without an alarm, 0 with one.

Tests: fire_core, fire_sources, fire_people, fire_far, fire_view, fire_world (fast); fire_longrun (slow list).
