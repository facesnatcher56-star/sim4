# Folk playtest

Thank you for playing. Start the game with `Folk.exe` (or the Folk shortcut on the Desktop). Nothing needs installing. If the game ever looks wrong or crashes, see "Reporting a bug" at the bottom.

## Starting a game

1. Title screen: **New Game**, **Continue**, **Load Game...**, **Co-op**, **Settings**, **Quit**.
2. **New Game** is the one-character game: you play ONE Folk. Choose a name, traits, look and a heritage (or leave it random), a difficulty (Easy 350 coins, Normal 200, Hard 100) and a storyteller.
3. You start broke in a rented, empty studio. **Nobody feeds you** and your Folk does nothing unless you tell them: no free food, cooking costs ingredients, rent and bills come every week. Find work (Phone > Jobs, or the mailbox for Odd Jobs), eat from your pocket (bakery, burger place, vending machine) and buy a bed (B).
4. **Myself** (next to your face) lists things you can do with no furniture: sleep on the floor, sleep rough, a day's labour at the Works.
5. Miss the rent and the landlord evicts you. You are then homeless: sleep rough, use the night shelter (a few nights a week, no food), take day labour. Money > Homes shows the ladder (bedsit, council flat, studio, better flat, house) and lets you move; your things go with you.
6. The Kiln Quarter (south-east) is the rough district: cheap rooms, more crime, slow police, crews that make offers to broke people. Settings > Gameplay > Gang violence turns the violence down or off.
7. At speed 3 the clock races ahead while you sleep, work or walk, and slows when something needs you.
8. When your Folk dies, a summary of the life (what happened, why, and what your choices set in motion) is shown, then the heir takes over.

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

Top bar: the clock, speed, weather, where you are and your coins (click them for bills), then icon buttons (hover for the name): **Map**, **Phone**, **Town** (places, study, health, pets, news), **Money** (shops, your business, homes, bank), **Build and buy**, and **Menu** (council, save, load, settings, share, help, quit). All keys can be changed in Settings > Controls. The game autosaves; the interval is in Settings.

## Things worth trying

- **Jobs**: open **Phone** > Jobs (the Town window has tabs: Places, Study, Health, Pets, Phone, News). Try the **factory** and other careers; watch the commute, the shift and promotions.
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

## What changed since your first run

- **The home starts empty by default.** New Game has a Home row: "Empty home (furnish it yourself)" or "Furnished home". An empty home comes with a moving-in allowance (about 1,500 to 2,500 coins). Press B and buy a bed, a toilet and a fridge first; the tips walk you through it. Until then your Folk sleep on the floor, take a free snack from the welcome basket and use a free restroom.
- **The mouse picks things in the room.** Windows, doors and lights no longer steal the highlight; the thing under the mouse gets an outline.
- **You can always see inside your own home.** Walls cut down automatically; other buildings open while your Folk is inside. Walls Up (Tab) is a choice, and it resets to cut-away when you change floor or load.
- **Thoughts repeat less and mention real people, places and events.**
- **Folk do more with their days:** weekend routines, spontaneous plans, reactions to sirens and storms, idle life, family dinners and game nights, outings to the town places on their own.
- **Compact Folk panel.** Click Details to expand it; the tips dock to the left.
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
