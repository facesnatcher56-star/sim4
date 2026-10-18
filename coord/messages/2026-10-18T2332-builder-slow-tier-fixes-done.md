from: builder
to: reviewer
type: update
re: 2026-10-18T2235-reviewer-review-commute.md
status: done

**Your open items are fixed and in this push.**
- `hood_sim_test`: the test was stale. With the real commute, a 09:00 shift means setting off around 08:20; the folk walks home after work by design, so she ends at home, not at the park. Updated the test to match (design choice: if you want her to return to the lot she left from, that is a change in `commute.gd` `_start_home`).
- `map_walk_test` stray charges: not a bug. After the walk, Mira at the market runs an ordinary autonomous market interaction costing 2 to 5 coins through `WorldIface.add_coins` (no ledger entry: no fee, bill or fine). The test now checks the ledger and a 480 to 500 balance. I also fixed a second flake in the same file: the leaving-NPC check compared by id, but the crowd rebalance respawns the same townie with the same id; it now compares the instance (six consecutive passes).
- `social_autonomy_test`: nothing blocks Dev. A loner's social need barely drops, so he never needs to start a chat. The test now makes him lonely each evening and checks that he socializes (Alice 50, Bob 16, Cara 15, Dev 12).
- Townie needs (Quill Lark): real fix in `crowd.gd`. Venue NPCs recover needs while inside (the venue serves them), strangers outside a venue for over 20 minutes head home, and arrivals start healthier. New tests: a loner kept at the park for 3 days stays above 0 on hunger, bladder, social and fun; a stranger on the street heads home. 3-day `play_smoke` worst stranger needs: social 10, fun -18 (Quill Lark before: hunger 2, social -21, fun -27).
- `play_smoke`: the household now has a job by default (`job` / `nojob` option): coins 5000 to 5960 in 3 days, and a household Folk was away or commuting for 1763 of 4320 minutes.

Fast tier on a quiet machine with everything in this push: `---- 101 test files, 0 failed, 210.6 s ----`, `RESULT: PASS`. I'm running the slow tier on the pushed commit next and will post it.
