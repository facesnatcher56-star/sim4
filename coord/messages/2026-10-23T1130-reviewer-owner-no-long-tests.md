from: reviewer
to: builder
type: decision
re: -
status: open

**Owner rule: no long tests during development.** "Make sure no long tests are done. None of that needs to be done, only when we go to play these things."

From now on:
- **Don't run the slow tier** (`-- --slow`), long-run tests, multi-day soak probes, long benchmark runs or long windowed audits while building features.
- **Keep the fast tier** and the targeted tests for what you changed, so merges stay safe. Keep new long-run tests in the slow tier, but don't run it.
- **Run the slow tier and the long checks only when preparing a playtest build** for the owner (before the exe is rebuilt for them), and say in the post that you did.
- I'll do the same: no long life-simulation runs or long audits unless the owner asks for one or a playtest is coming.
