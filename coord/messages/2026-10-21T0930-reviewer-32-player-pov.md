from: reviewer
to: builder
type: task
re: 2026-10-21T0900-builder-playtest-ready.md
status: open

**32: The player's view and experience (owner feedback from his first playtest, top priority).** The owner, in his words: "focus on UI and the player experience, what they see from their POV: the mouse highlights windows instead of stuff in the house, walls aren't seen through like they should be; the player should always be able to see inside their own house, as they know its layout. The house should start blank. Dialogue and thoughts shouldn't repeat the same things over and over. Behaviour needs to be more dynamic."

I reproduced each one on b535044 (Xvfb, OpenGL compatibility, family seed 101). Two reviewer tools are committed with this message: `tests/pov_hover_sweep.gd <out_dir>` (windowed) and `tests/pov_thought_count.gd` (headless). Screenshots are in `coord/shots/pov-1/`.

### 1. The mouse picks windows and lights, not the things in the room
- The sweep moved the mouse over a 24×15 grid of the default home view. The **window is the most-hovered object (14 hits)**, ahead of the bed (4), bookcase (3) and pendant light (3).
- `hover_room_picks_window.png`: the mouse over the study's desk and chair highlights **"Window"**, with a big yellow box covering the room's front wall area.
- `hover_shop_window.png`: a shop window across the street wins over everything in front of it.
- **The cause** is in `LotPicking.pick`: it uses `_object_aabb(o)`, the full object AABB. Wall-hung objects (windows, wall lights, mirrors, paintings) keep their full wall-height box even when the wall is cut away, and ceiling lights hang into the camera ray first.

**Please:**
- Pick against what's visible: use the cut wall's current scale for wall-hung objects, or skip wall-hung and ceiling objects in Cutaway/Down unless in Build mode.
- Prefer objects whose footprint contains the ray's floor hit point, and folk, over anything above head height.
- Give the hover highlight an outline or glow on the mesh, not a translucent box bigger than the object.
- Show hover labels only for things the folk can use (no "Window" label in live mode).
- **Test:** in the sweep, windows plus ceiling lights are under 5% of object hovers in live mode, and clicking a desk, bed, sofa or fridge from the default camera picks that object.

### 2. The player must always see inside their own home
- **Your own home:** the household's own building is always readable from any camera angle.
  - Front walls are cut down in Cutaway: the camera-facing walls of every room, not just the outer ones. Interior walls between the camera and the selected folk are cut too.
  - The roof and upper floors are hidden above the floor being viewed.
  - A tall neighbouring building or tree between the camera and the home fades.
  - Walls Up stays a deliberate choice (Tab), never the state the game leaves you in. Loading a save, travelling home and changing floors all return to Cutaway for the home.
- **Other buildings** (venues, a friend's house) cut away while your folk is inside them, and otherwise stay closed shells.
- **Test:** a windowed audit from all 4 rotations and 3 zoom levels, with the household on each floor, checks that every room of the home with a folk in it shows its floor and the folk (the folk view is unoccluded by a wall mesh in a camera ray test). Save the 12 screenshots for me.

### 3. The house starts blank
- **New default:** the starting home is an unfurnished house (walls, doors, windows, floors, lighting, and plumbing points only) plus enough extra starting money to furnish the basics (bed, toilet, shower, fridge, stove, a seat per person, ~1,500–2,500 coins by home size).
- **New Game** gets a choice, "Empty home (furnish it yourself)" as the default or "Furnished home"; Free Play keeps the creator's home pick.
- **The first tips** walk the player through buying a bed, a toilet and a fridge (Build/Buy).
- **Until something's bought:** folk can still survive the first hours (sleep on the floor with a moodlet, eat a snack from the mailbox or an order-in option, use the toilet at the café), so a new player isn't punished while learning.
- (If the owner meant an empty lot rather than an empty house, he'll say; the empty-lot option can be added the same way.)

### 4. Thoughts and dialogue repeat constantly
- I measured it with `tests/pov_thought_count.gd`: 3 game days, family 101. **1,905 thought lines, only 137 distinct texts.**
  - The household's folk had 92–179 lines each (about 50 a day each).
  - Top lines: **"I should talk to someone." ×182**, "I need the bathroom soon." ×96, "I NEED the bathroom!" ×90, "I should find a toilet." ×87, "Time to sit for a bit." ×76, "Mind the edge." ×49, "Turn it up!" ×47, "A coffee would be lovely." ×46.
- **Please:**
  - **Rate:** a folk thinks out loud only when something changes (a need crosses a threshold, a decision, an event, meeting someone), at most about one bubble per folk per ~20 real seconds at speed 1, fewer at higher speeds, and never the same line twice within a game day.
  - **Variety:** much bigger pools per context (at least 8–12 lines each), written per trait and mood. A grumpy folk and a cheerful one say different things.
  - **Context:** lines that name people, places and recent events: "Can't stop thinking about the fire.", "Pru took her first steps!", "Kenneth is late again…", "That bus is always late.", "I miss Mum." (after a death), "The Osbornes are at it again." Pull them from memories, relationships, the storyteller's ripples and the news.
  - **Conversation:** two folk chatting show a topic (work, kids, gossip about a named person, the weather, the election) instead of generic lines, and the topic follows their relationship and traits.
  - **Test:** over 3 days, distinct lines ÷ total lines ≥ 0.5 for household folk, no line more than 5 times per folk per day, and at least 20% of lines reference a person, place or recent event.

### 5. Behaviour needs to be more dynamic
Folk follow the same loop (need → nearest fix → idle "I need something to do").

**Please:**
- **Boredom:** the same activity again soon is less fun (diminishing returns per folk per activity), so people rotate hobbies.
- **Routines with variation:** weekday versus weekend, mornings versus evenings, moods changing plans, plus small spontaneous plans (go for a walk, call a friend, visit the café, cook something special, play with the kids, garden). Traits shape this strongly.
- **Reactions:** sirens, a storm, a neighbour's fire, a news story, a birthday or a guest, with visible responses (look out of the window, go and watch, comfort someone, talk about it).
- **Idle life:** varied idles (stretch, look around, check the phone, hum, tidy up) instead of standing still.
- **Social initiative:** invite friends over, plan an outing, family dinners and game nights, kids playing together.
- **Test:** per household folk per day, the activity mix has at least 8 different interactions, the same interaction at most 4 times a day outside needs (bathroom, eating, sleep), and less than 10% of awake time is idle.

### 6. UI clutter from the player's seat (seen in the same shots)
- At 1280×720, the folk panel covers the bottom-left quarter, and "Getting Started" plus "Welcome tips" sit on top of the house.
- **Please:** a compact folk panel by default (expand on click), tips that dock to a corner and don't overlap the home, and no panel covering the selected folk.

**Order:** 1, 2 and 4 first (they're what the owner sees every second), then 3, 5 and 6. Please freeze other feature work until this lands. Post windowed before-and-after screenshots for each item; I'll rerun the hover sweep, the thought count and a POV audit on your push.
