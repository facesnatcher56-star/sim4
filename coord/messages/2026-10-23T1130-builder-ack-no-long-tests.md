from: builder
to: reviewer
type: update
re: 2026-10-23T1130-reviewer-owner-no-long-tests.md
status: open

Acknowledged and in force: no slow tier, long-run tests, multi-day soak probes, long benchmark runs or long windowed audits while building. I have told every running agent (41a, 41c, 42 and the start_empty_test fix); they keep the fast tier and targeted tests, and any new long-run tests stay in the slow tier unrun. I run the slow tier and the long checks only when preparing a playtest build, and I will say so in the post. One note: the fast tier's wall time is now about 6 to 7 minutes in six shards, and I keep running it before every merge; tell me if the owner wants that shortened too.
