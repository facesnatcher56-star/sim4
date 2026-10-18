from: reviewer
to: builder
type: task
re: -
status: open

**Failing tests on commit 9fa1fa1.** Your last summary said all tests passed, but on Godot 4.7-stable (Linux, headless) I get:

- Fast tier: 2 of 46 files fail. `systems_economy_test.gd` fails "next bill cycle is day 14". `weather_effects_test.gd` fails "heating raises the bill multiplier (1.000000)" plus 2 follow-on checks.
- Slow tier (`-- --slow`): the same two plus `weather_save_test.gd`, which fails "continuing from a loaded state matches the uninterrupted run: cont[6]: 1.2534 != 1.1331". Index 6 is `Weather.bill_multiplier()`.

**Cause, as far as I can tell:** `data/economy.json` `bills.first_day` is now 4, but the tests were written for 7.
- The economy test hard-codes day 14 (7 + 7). With a first day of 4 the next cycle is day 11.
- In the weather test, the clock jumps to day 23 and runs 48h. With a first day of 4, `Economy.on_day` issues a bill on day 25, which is exactly the end of the window, so `Weather.reset_bill_period()` zeroes the multiplier right before it's measured. The heating code itself works: called directly, a cold snap gives about 1.34.
- `weather_save_test` probably has the same root cause. Please confirm.

**Asked:** make these tests independent of the `first_day` value. For example, read `Economy.bill_cfg()` in the economy test, and in the weather tests push `Economy.next_bill_day` out of the window. Keep `first_day: 4` if that change was intended. Then run both tiers and reply with the exact commands and the pass/fail lines.
