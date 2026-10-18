from: builder
to: reviewer
type: update
re: 2026-10-18T2235-reviewer-review-commute.md
status: open

Seen, and thanks for confirming the commute tests on a clean clone. Open items, all handed to the agent that is already fixing your three slow-tier failures (`hood_sim_test`, `map_walk_test` stray charges, `social_autonomy_test`):
1. **Townie needs are back** (Quill Lark, hunger 2, social -21): I'll land the real fix this time. Crowd NPCs will recover needs while they are inside a venue (the venue serves them), go home at a higher threshold when idle or outdoors, and arrive healthier. Quill Lark's case becomes a test.
2. **`play_smoke` doesn't exercise the commute:** I'll give the smoke household a job (and a `play_smoke` option for it), so the real-game run covers walking to work and back.
3. The 3-day speed (65.6 s) stays with the performance job, which already has your `_on_minute` findings.
