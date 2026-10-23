from: builder
to: reviewer
type: update
re: -
status: open

Owner asked for a full playthrough, then fixes. Ready for review on branch `agent/sweep-fixes` (commit e52da90, one commit on top of main 2e2f7ae; not merged to main yet).

New tool: `tools/sweep.gd` (+ `sweep_run.gd`) presses every window, the Myself menu, every object kind and every person action through the real pie menu, with a close-up shot halfway through each. `tools/sweep_watch.ps1` runs it, kills and resumes a frozen run, and stops on script-error floods. Usage: `powershell -File tools/sweep_watch.ps1 -Out <dir>`.

Fixes:
- **Rain indoors:** single-storey buildings now stop rain/snow (`scripts/world/rain_roofs.gd`), and it thins out when the camera looks into a room.
- **Orders that never started:** a refused order now says why (`scripts/ui/order_refusal.gd`). Doors and ceiling lamps (objects with no slots) can be used. Cafe orders are greyed when they cannot be served and are no longer billed when nothing is served.
- **Rent and bills:** one source (`scripts/systems/upkeep.gd`); the money window, the Homes tab and the holiday planner now agree.
- **Menus:** things that don't exist are hidden (car actions with no car, Vote with no election, crime acts on your own door, Apologize with no row). Reachable things are greyed with the reason (Buy a Car: needs a driving licence; Run for Mayor: Charisma 1).
- **Guitar** is held in front, and the stand is empty while it's played (rule in `tools/gen_object_visuals.py`).
- **Refused hugs and kisses** stop at the refusal instead of playing out.
- **Text:** staff names no longer carry their job (the name tag still shows it). Lines about the other person stay thoughts. Balloons show only the spoken words; reactions use first names. Thoughts fit the hour and weather (`data/thought_voice.json` "fits").
- **Homes:** private homes no longer announce "closes in 20 minutes". Host a Gathering needs someone to invite and waking hours.
- **Night** is brighter: a higher light floor, and the Night brightness default is now 65%.

Checks: solo_smoke clean. The social, weather, thought, crowd, travel and city tests touched pass. These tests already fail on main and are not fixed here: content_run_test (talk_interests), nav_graph_test, social_emotions_test, systems_careers_test, visual_sim_test, cruise_fix_test, weather_view_test, and light_mood_test (two old checks; its 35% default check is updated to 65%).
