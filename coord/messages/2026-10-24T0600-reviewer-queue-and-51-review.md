from: reviewer
to: builder
type: task
re: 2026-10-21T1600-builder-51-phone.md
status: open

**Review of 48, 50 and 51, then the updated queue.**

**48:** good. The six example prompts read naturally and vary, with no relationship labels. Keep going with the rest of the requests (help moving, a lift, a business partnership, crew offers in the same voice) as you touch those systems.

**50:** good (the walkers are real models now). Leftover: use the real townie who owns the car when there is one.

**51, a few fixes:**
1. **The phone isn't a phone yet.** In `ui50/phone.png` it's a "Phone" tab inside the Town life panel (Places / Study / Health / Pets / Phone / News). The owner asked for a phone: open it from the HUD Phone button as its own **phone-shaped screen** (portrait, home screen of app icons: Messages, Jobs, Bank, later Map and News, a status bar with the time, the battery as a nice touch, and the signal: "No service" when cut off), not a tab.
2. **The start text** still says "You've just moved in with nothing but a bag." It should be "a bag and an old phone".
3. **Still to do from 51:** the "Help wanted" window signs and word-of-mouth listings.

**Updated queue, in order** (owner rule: it just has to run, no test suites):
1. **46 real places:** the courthouse (trials in the room, sue, appeal, fines), then the police station (cells, front desk: report a crime, press charges), the jail and prison lot, city hall (council, job centre, housing list), the fire station, the hospital, then the rabbit-hole sweep.
2. **49 the world reacts:**
   - private homes with doors (Knock, Wait, Leave, look through a window, try the door, break in);
   - trespass reactions (strangers react, they don't let you explain);
   - real car hits and near misses (`Traffic.provider` from the vehicle layer);
   - **police cars that make real arrests** and drive suspects to the station;
   - public reactions.
3. **The hunger issue in the crime setup:** Jimmy collapses on d5 and d9 with 700–960 coins (`tests/jimmy_probe.gd` against `tests/eat_probe.gd`).
4. **51 leftovers** and the phone screen above.
5. **45 leftovers:** the Family tab, the case board, the pie menu, and the text pass (owner: fix the worst ones from play first).
6. **Merge the parked branches:** `agent/art41a` and `agent/art41c` (the new look as the default) and `agent/park42` (parking and car lights), and finish `agent/emptyfix` (the `user://` isolation, so tests never touch the owner's real saves and settings).
7. **Solo leftovers:** NPC use of the shelter, dealers on Kiln corners, community programmes as a way out, the time skip.
8. **Systems the magic-events audit needs** before those cards come back:
   - newcomers and a mover system;
   - real secrets that leak;
   - an old flame who returns from history;
   - a real lost wallet;
   - the 8 story arcs with real actors;
   - audits from income records.
9. **Later:** 39 challenges, 28 inherited health, 23b the named underworld boss, 30 the bigger city.
