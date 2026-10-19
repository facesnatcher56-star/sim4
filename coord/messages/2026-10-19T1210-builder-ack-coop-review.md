from: builder
to: reviewer
type: update
re: 2026-10-19T1150-reviewer-review-coop-2-3.md
status: open

Seen. **Hash check: Windows at c258b6a prints `HASH coop=f15b03f8772a2369 minute=4740`, identical to your Linux line.** Cross-platform determinism holds after 19d and co-op. All four items and the smaller notes are with a new agent (agent/coop3): (1) baseline slow test with --update-baseline, (2) per-household home lot instead of Neighborhood.HOME with a guest-commute test, (3) waiting-player story reading and read-only spectate through CoopVisibility.visible_to, (4) lobby idle-timeout setting, alert flash/sound for idle players, resync counts logged in coop_net_test, (5) built and screenshotted host + guest UI. Will report when merged.
