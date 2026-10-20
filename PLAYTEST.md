# Folk playtest

Thank you for playing. Start the game with `Folk.exe` (or the Folk shortcut on the Desktop). Nothing needs installing. If the game ever looks wrong or crashes, see "Reporting a bug" at the bottom.

## Starting a game

1. Title screen: **New Game**, **Continue** (your latest save), **Load Game...**, **Co-op**, **Settings**, **Quit**.
2. **New Game** shows the scenario cards:
   - **Solo Start**: one Folk in a small flat. Find work, make a friend, pay the bills.
   - **Couple**: two partners moving in together.
   - **Young Family**: two parents and a child on a tight budget.
   - **Roommates**: three unrelated Folk in a big house.
   - **Free Play**: design your own household of 1 to 6 Folk, any age, any home. This opens the household creator (names, looks, traits, clothes, home).
3. Pick a difficulty (relaxed / normal / hard).
4. **Storyteller** row: Calm, Classic, Chaotic or Custom. This decides how often unexpected things happen (accidents, visitors, trouble, windfalls). Calm = few surprises, Chaotic = lots. Custom gives four sliders. "Surprises" in Settings > Gameplay is a separate switch (off / rare / normal / chaotic).
5. Start. The first time, short welcome tips appear (you can show them again from the help window).

## Controls

| What | Keys / mouse |
|---|---|
| Move the camera | W A S D, or hold the middle mouse button and drag |
| Rotate the view | Q / E |
| Zoom | Mouse wheel |
| Wall view (cut-away / walls up / down) | Tab |
| Change floor | Page Up / Page Down |
| Pause / resume | Space |
| Speed | 1 normal, 2 fast, 3 fastest |
| Select a Folk | Click them (or use the Folk buttons bottom-left to switch between your household) |
| Give an order | Click an object: a menu of things your Folk can do with it. Right-click the ground = "Go here" |
| Cancel a queued task | Click its chip in the queue bar |
| Click someone from another household | Opens the social menu (chat, flirt, etc.) |
| Build / Buy mode | B (or the Build/Buy button) |
| Rotate the item you are placing | R |
| Undo a build action | Ctrl+Z |
| Leave a build tool / close a window / open the pause menu | Esc |
| Neighbourhood map and travel | M |
| Case board (crime cases) | F10 |
| Help (all controls) | F1 or ? |

Top bar buttons: **Map**, **Money** (shops, your business, homes, bank), **Town** (school, college, clinic, food, fun, the job board, the phone), **Council** (mayor, taxes and budget, elections, building projects, outages, bus times), **Build/Buy**, **Save/Load**, **?**, **Menu** (pause menu and Settings). All keys can be changed in Settings > Controls. The game autosaves; the interval is in Settings.

## Things worth trying

- **Jobs**: open **Town** > Jobs tab (the Town window has tabs: Places, Study, Health, Pets, Phone, News, Jobs). Try the **factory** and other careers; watch the commute, the shift and promotions.
- **Stay-at-home parent**: have a parent with a small child skip work and look after the child at home.
- **A baby**: a couple can try for a baby; pregnancy, birth, toddler care, growing up.
- **School**: children and teens go to school; college is under **Town**.
- **Cafe and nightlife**: take your Folk out in the evening (use the Map to travel).
- **Pets**: adopt one (Town > Pets tab) and see how it settles in.
- **The phone**: under **Town** > Phone tab: calls, messages, media.
- **The criminal path**: the underworld and crime; the police and courts react. Open the **case board with F10** to follow a case.
- **Running for mayor**: **Council** shows the next election; a Folk can stand for it, and the mayor can change taxes and budget.
- **A vacation or a cruise**: from the Map / vacation window, send a Folk or a family away.
- **Co-op on two PCs**: title screen **Co-op**. One player **hosts** a saved game and shares the code, the other types it under **Join a game**. Both PCs must run the same build. 2 to 4 players.
- Build and decorate: **B**, buy furniture, place walls and floors, add a second floor.

## Known issues

From the latest notes, as plain as possible:

- Big building roofs may still hide a street at some zoom levels; they fade out when they are in front of the selected Folk. Zoom in or press Tab if you cannot see someone.
- Co-op was only tested between test programs on one machine, not yet between two real PCs. Expect rough edges (firewall prompts, the join code).
- Long play (many in-game weeks, big families, several generations) has been tested with scripted runs, not by a person. Odd story moments are possible: people who do not seem to care enough about each other, a very quiet day, an odd crime or death. Please report anything that feels silly.
- The developer-only incident panel (F9) is switched off in this build.
- The game exits with no extra window or sound; the log file is written next to the exe.

## Reporting a bug

Please send:
1. A screenshot (press the Windows key + Shift + S, or Print Screen).
2. One or two lines: **what I did** and **what happened** (and what you expected).
3. The log file: `folk.log` in the same folder as `Folk.exe` (the log from the run before it is `folk.old.log`). Do not restart the game more than once before sending it, or the first log is moved to `folk.old.log` and then overwritten the next time.
4. If you can, your save: `%APPDATA%\Godot\app_userdata\sim-4\saves` (paste that into the Explorer address bar). Copy the slot file that shows the problem.
