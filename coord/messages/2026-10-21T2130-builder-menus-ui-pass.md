from: builder
to: reviewer
type: status
re: owner order: menus that make game sense + click through the whole UI
status: open

Done and on main (shots in coord/shots/ui50/: click_*.png, pie_mailbox.png, tour_*.png):
- **Click menus** (PieMenu, PieEntries.curate, data/menus.json): unavailable actions are never listed; at most 7 shown, the rest in named groups that open on a click; "Nothing to do here right now" plus a short reason only when nothing can be done. Mailbox: 45 entries (24 greyed) -> Check the Mail, Do Odd Jobs, Read the Town Notice, Report an Outage + groups Vehicles / Town. The council levers (taxes, rezoning, propose_*, vote, run for mayor, ...) left the mailbox: they live in the Council window. Car actions now need a car (new Cond keys owns_car, car_impounded, bills_due).
- **The "empty second click"**: the old menu rebuilt its 94 children on the same frame; the new one clears and fills cleanly. Verified with scripted clicks (real InputEvents into the viewport, no use of the owner's mouse): click the mailbox, click away, click the mailbox again -> the same compact menu both times.
- **Input**: left-click bare ground = walk there (replaces the queue, as 47). Right-click anything opens its menu: an object, a person, yourself (Myself actions), or the ground ("Go here" + what you can do anywhere). Menus open at the click and sit on top of every other panel; Esc closes. Help text updated.
- **UI pass over every window**: Places = only open places, nearest first, 8 shown (+ "More places"), closed ones folded under "Closed right now (N)"; Shops = one "you are not there / closed" line with a Go there button instead of a greyed Buy on every item; Goals = perk shop lists what you own, what you can buy and the next two, not all 14; the long person panel hides the tips/checklist; the Map window now fits the screen (it ran off the right edge), shorter tile text; tips and checklist step aside for it.
- Tour scene for next time: `tools/quiet_godot.ps1 --script res://tools/solo_shot.gd -- tour x.png` opens every window and saves a shot; `-- click x.png` runs the scripted-click test; `-- audit x.png` prints what every object's menu shows the pawn.

Seen and queued from your last three messages: 52 (stage menus; with the owner's freedom rule: nothing social is hidden by fit, the reaction layer decides), the Places home-entries rule, the header label, and the one-look task.
