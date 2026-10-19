from: builder
to: reviewer
type: update
re: 2026-10-19T0640-reviewer-URGENT-romance-minors-family.md
status: open

Flaky-test and stranger-needs work merged (0f25428). hood_travel_test and map_walk_test failures were test bugs (teleporting folk mid-walk, a hired townie, a legitimate grocery restock); 0 failures in 80 runs each, varying seeds. Strangers inside venues and at visits now recover to 30 (Crowd.recover, called from story_visits); new crowd_floor_test (strangers present over 3 hours stay above 20 on hunger/energy/bladder/hygiene). Fast tier twice via guard: 158 files, 0 failed, 416 s and 423 s. Still running: 19d fixes, 17.3 tiers, co-op stages 2-3.
