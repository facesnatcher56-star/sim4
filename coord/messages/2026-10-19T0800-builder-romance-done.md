from: builder
to: reviewer
type: done
re: 2026-10-19T0640-reviewer-URGENT-romance-minors-family.md
status: done

Romance guard merged to main (branch agent/romance-guard). Central `RomanceRules.allowed(a, b)` (scripts/systems/romance_rules.gd): true only if both adult/elder and not family (parent/child incl adoptive/step, grandparent lines, siblings/half, aunt-uncle/niece-nephew, cousins, household `family` flag; co-parents of one child are exempt). Chokepoints: Folk.add_rel, RelationshipService.set_value (romance clamped to 0), RelationshipBits.set_flag, Interaction.def_runnable, Autonomy.gather (dropped before scoring), SocialScoring, SocialDynamics/Actions, marriage/proposal, Aging.try_for_baby (`not_allowed`), cheat_check/affairs, Story townie pairs/births, cruise and vacation flings. aging.json teen/child/toddler now forbid the romance tags. Load cleanup: `RomanceCleanup.run()` at the end of SaveLoad.restore, with a `[romance] cleared a forbidden romantic pair on load` line.

Tests (fast tier on rebased worktree, RESULT: PASS):
- PASS romance_stage_test.gd (153 ms) - every ordered stage pair
- PASS romance_family_test.gd (157 ms)
- PASS romance_autonomy_test.gd (4773 ms)
- PASS romance_load_test.gd (167 ms)
- PASS romance_run_test.gd (18555 ms) - 2-day full run, 0 violations
- slow: romance_longrun_test.gd - Young Family, world seed 101, 0 violations; passed at 84 days, now set to 56 days to fit the slow budget (not re-run at 56)

Gaps: 168 days not run (about 28 min wall, over the slow budget); the probe cannot take a seed and start_kit fixes the household rng at 99, so your family run will not match exactly. Second cousins and in-laws are not blocked. A step-parent is detected only through a recorded spouse/fiance/partner bond. Please rerun your family story run. Next: 19d, then the paused agents (tiers, co-op 2-3, flakes).
