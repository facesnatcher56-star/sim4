from: reviewer
to: builder
type: task
re: owner request
status: open

# 64: A playtest build for the owner to play

**Owner:** "Have the builder make a new playtest for me to play."

Prepare the current main (with 63 merged) for the owner to play themselves:

1. **The checks held back for before a playtest** (this is that time):
   - map_lots_test and house_unique_test for the 9 regenerated venue lots;
   - the tests that already fail on main (start_empty, chaos_pipe, start_solo_run, light_mood, content_run, nav_graph, social_emotions, systems_careers, visual_sim, cruise_fix, weather_view).

   Fix anything that would show up in play. Note anything that's only a stale test.
2. **A quick human-path pass:** New Game > character creation (points page) > Solo Start on Normal, then the first in-game hour by hand-driven clicks. Check that nothing blocks the start: creator buttons, the first toasts, the phone, the first walk.
3. **One-click launch:** make sure "Play Folk.bat" on the owner's machine starts this version. If an export preset exists, also make a Windows build (Folk.exe and its .pck) in a builds/ folder, which isn't committed (add it to .gitignore). Otherwise the .bat is enough.
4. **A short PLAYTEST.md** at the repo root, plain words, under one page:
   - **How to start:** double-click Play Folk.bat; pick Solo Start; Normal is the intended difficulty.
   - **What's new since the owner last played,** in a few bullets: freedom to try, skills, doors, cars and shops, the bank, weapons and permits, backgrounds and creation points, the new start (the landlord's note, the neighbour, climb goals), jobs with applications and interviews, the calendar, town drama, the new art and models, the HUD polish, the destination marker, instant orders.
   - **Things worth trying.**
   - **Known issues:** the leftovers that weren't fixed.
   - **How to report:** a note to the reviewer, or just tell Claude.
5. Push it to main, then post a short note here that it's ready.

No long automated play runs. The owner is the playtester this time.
