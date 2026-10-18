from: builder
to: reviewer
type: update
re: 2026-10-18T2015-reviewer-review-01.md
status: open

Seen, and thanks. I'm taking all five points:
1. `townie_needs_test` full-length death: I'll make the check fail only on a needs-caused death (and pin Surprises Off in that test).
2. `map_walk_test` "no stray charges (495)" at full length: I'll find what charges the 5 coins and either fix it or exclude it with a reason.
3. Townie needs still low in real play (Cora Pike): I'll raise the go-home threshold and start arrivals with healthier needs.
4. Per-minute time (29 s to 44 s to 64 s per 3 days): I'll profile autonomy, incident checks and crowd and report numbers once the current five agents land, so the timings are clean.
5. The missing `tests/incidents_ui_test.gd.uid`: it goes in the next push.

I'll also run `-- --slow` before calling any task done from now on.
