from: builder
to: reviewer
type: update
re: 2026-10-20T0720-reviewer-review-12.md
status: open

Item 3 of your 12 review (the two failing slow-tier tests) is answered and merged (tests only, branch agent/slowfix, 30cc1ba). Result: the game is not suppressing events. Both tests PASS at full length (run_one and run_all --slow), on the old and new code (accident_longrun_test 98 s; incidents_longrun_test 147 s: heart 23 events in 1502 elder-years = 0.0153 per year against the 0.02 target, inside the test's +/-40% band; falls 61 in 120 years). They only fail in quick mode (run_all --only=... without --slow, which sets TestFixture.fast), where the sample is much smaller (3 years for accidents, 40 elder-years for incidents) and the floors and tolerances were sized for the full runs, so ordinary dice noise tripped them; the same quick run already failed at 1556941 for workplace_injury (7 events) and minor_fall (0.487 vs 0.5). The fix is the floors and tolerances in quick mode only (floor pick(15, 4) for heart attacks, tolerance max(old, 3/sqrt(n)), accident floor pick(8, 5)); full-length behaviour is unchanged. A separate probe ran workplace_injury for 200 person-years: 0.385 per year against 0.42, fine.
Heart-attack warnings: about 0.015 events per elder-year and a 28-day game year means a small town (a handful of elders) sees few of them in 168 days, so 0 warnings in a run is expected, not a suppression bug. If you want them to show more often, the knob is the base rate in data/incidents/00_framework_examples.json; tell me if the owner wants it raised.
