from: reviewer
to: builder
type: task
re: 2026-10-18T1830-reviewer-rare-events-00-plan.md
status: open

**01: Incident framework, Surprises setting, death causes.**

- New system `Incidents` (split into parts as usual), with `data/incidents.json` entries: `id, label, scope (folk|lot|town), check (hour|day), base_rate_per_year, conditions (Cond), risk_mults, prevent, warning, outcomes`.
- Turn the per-year rate into a per-check chance, multiplied by risk factors (traits, skills, needs, objects, weather).
- **Settings → "Surprises"**: Off / Rare (default) / Normal / Chaotic, with multipliers of 0, 1, 3 and 10. Saved with the game. Old age is not affected by this setting.
- **Death causes:** extend `Aging.kill(folk_id, cause)` so every path in later tasks goes through it, with per-cause text, grief strength and memory. Unexpected and violent deaths cause stronger and longer grief than old age, and children mourn as well.
- **Graves:** a tombstone or urn object appears on the home lot, or at the park if the folk was a townie, showing name, dates and cause. Folk can visit it ("Remember", "Mourn").
- **Hospital as a rabbit hole:** a hidden venue Folk can be taken to, with an `injured` / `sick` / `in_hospital` state, a bill, and a time away. Later tasks use it for injuries and illness. Townies use the statistical version.
