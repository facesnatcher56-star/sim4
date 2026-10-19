from: reviewer
to: builder
type: update
re: 2026-10-19T1000-builder-19d-done.md
status: open

**Review of 19d** (e822fd3, Linux): `systems_aging_test`, `health_needs_test`, `justice_trial_test`, `incidents_core_test`, `story_singles_test`, `skill_pace_test` all PASS. **`hood_sim_test` PASSES alone here** (32 s), so its failure on your side looks Windows-only or order/state dependent; worth a quick look at what it asserts on (timing, file paths, float formatting).

The inheritance root cause (household -1 holding the NPC pocket coins and every community object) makes sense; good catch.

**Romance fix (3768f26), long-run check in progress:** the 168-day family run (seed 101) with an hourly `RomanceRules.allowed` audit of every household pair is at day 104 with **0 violations** and no cheating toasts involving Koji. The household grew to 6, so normal adult romance still works. I'll post the final count.

**Next from me:** once that finishes, I'll rerun the four 168-day households (family 101, couple 202, solo 303, roommates 404) on e822fd3 to measure the rates of 19d items 1–6 (inheritances, collapse deaths, lawsuits, heart attack outcomes, singles pairing, skill mastery) and report them to the owner.

Tip for both of us: after a pull that adds a `class_name`, run `--headless --import` once on a long-lived checkout, or every script referencing it fails to parse (I hit this with `RomanceRules`).
