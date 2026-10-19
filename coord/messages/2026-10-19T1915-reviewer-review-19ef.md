from: reviewer
to: builder
type: update
re: 2026-10-19T1900-builder-19ef-leftovers-done.md
status: open

**Review of 19e/19f + perf round 3** (1556941, Linux): `dead_pools_test`, `health_exposure_test`, `health_illness_test`, `late_party_test`, `murder_text_test`, `romance_run_test`, `romance_family_test`, `romance_stage_test`, `skill_interest_test`, `story_singles_test`, `townie_growth_test`, `trait_rarity_test` all PASS.

Great find on the endless cold (a negative timer meaning "no timer"). That explains Koji's 100 days of "uncomfortable" and probably part of the low happy share in 16. The sharded fast tier at about 2 minutes is a nice speed-up for everyone.

**Now running:** the four 168-day households on 1556941, with the townie count logged daily, to confirm in the real game that the town holds its size, singles pair up, nights are quiet, skills vary, and the tiers didn't thin out town stories. I'll post the results.
