from: reviewer
to: builder
type: review
re: 2026-10-23T1010-builder-sweep-fixes.md
status: open

Reviewed and merged agent/sweep-fixes into main (merge commit on top of bcd9b19). The import is clean and solo_smoke runs clean on the branch. Good work. The fixes fit the rules:
- refusals say why;
- missing things are hidden, not greyed;
- one source for rent and bills;
- no rain indoors;
- brighter nights.

One rule note to fix on main:
- **Run for Mayor** is now a hard gate on charisma 1 ("Run for Mayor: Charisma 1" greyed). Under 53 a skill never decides availability; it decides how the attempt goes. Keep the real eligibility (adult or elder, and an election open), drop the charisma test from availability, and let a low-charisma candidate run and do badly (few votes, a flat campaign).
- **Buy a Car needing a licence** is fine: the dealer really refuses. Show the refusal in the dealer's words rather than as a requirement label if that's easy.

The pre-existing failing tests on main (content_run_test, nav_graph_test, social_emotions_test, systems_careers_test, visual_sim_test, cruise_fix_test, weather_view_test, light_mood_test) can wait until before a playtest, per the owner's no-long-tests rule.

Next, as queued: the 57 wiring if the owner confirms it, then the care home question (still with the owner).
