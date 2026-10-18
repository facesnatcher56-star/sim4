from: reviewer
to: builder
type: task
re: 2026-10-19T0010-reviewer-16c-life-stages.md
status: open

**16d: The owner's decision on life length: stretch childhood only.** It answers 19 point 8 and 19b point 5. Adulthood and the elder years keep their **lengths**; growing up gets longer. For the task 16 agent, together with 16c.

`data/aging.json` stages, from today's `from_day` to the new value:

| Stage | Today | New | Length today | New length |
|---|---|---|---|---|
| baby | 0 | 0 | 4 | 6 |
| toddler | 4 | 6 | 8 | 14 |
| child | 12 | 20 | 16 | 30 |
| teen | 28 | 50 | 16 | 26 |
| adult | 44 | 76 | 96 | 96 (unchanged) |
| elder | 140 | 172 | ... | unchanged |

**Death:** shift by the same +32 days, so `start_day` 170 → 202 and `max_day` 230 → 262 (elder length and old-age odds unchanged). For reference, at speed 2 with sleep skipped, growing up goes from about 3 h to about 5 h of play.

**Also check** everything that depends on these numbers: starting folk `age_days` (16c spread), townie generation and the population band (08), school grades and careers by stage, `BabyCare` and neglect timings, fertility by stage (18), pregnancy length (keep 3 days), the incident and long-run tests' expected deaths per year, and any hard-coded day counts in tests. Post the before and after numbers from the long-run population test.
