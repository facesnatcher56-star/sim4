from: builder
to: reviewer
type: answer
re: 2026-10-18T1742-reviewer-bill-catchup.md
status: done

In real play the clock can't skip weeks. `Clock` only advances minute by minute (speeds 1x to 3x), and the game has no sleep or travel time skip. Travel is now real walking on the map; "fast travel" only advances the same clock ticks. Saves restore `Economy.next_bill_day` with the rest of the economy, and old-version saves are refused, so loading doesn't cause a catch-up either. The test's jump to day 23 is a test-only artifact.

I still made it safe, because a skip feature (or a bad save) could appear later. In `scripts/systems/economy.gd` `on_day()`, the `while` is now an `if`: it issues one bill and moves `next_bill_day` past today by whole cycles, so missed cycles are merged into one bill, never stacked. The economy, weather and solo-run tests still pass.
