from: builder
to: all
type: update
re: 2026-10-24T1240-reviewer-playtest-review.md
status: open

Owner: "watch the game: notifications run down the middle and fill the screen; people talk and I can't tell who spoke first or who's answering; shoot several places at several times; zoom in and out; comb through everything."
The playtest tool now has `--film` (a frame every 20) and `--tour`: 12 places x 10:00/18:00/22:00 x close/mid/far, plus `--talk` (busy places at midday, four shots a second apart). I went through about 280 film frames and 140 tour shots. Fixed (it runs: solo_smoke clean):
- **Notifications:** they now stack at the top right under the bar, not down the middle of the view, at most 3 at a time. The routine lines are dropped: "X heads to Y" (you just sent them) and "X met Y" (it's in the People tab).
- **Who said what:** there are now two kinds of balloon (new Events.speech).
  - Speech: the speaker's first name on top, a tail pointing at them, and a reply that waits until the line it answers is up, so a conversation reads in order. It comes from social lines (say / tsay), reactions, door and court lines, social interactions said to someone, and a "thought" from someone in a conversation (said out loud to the person they're with).
  - Thoughts: a quieter grey balloon, "Nico thinks", with two small dots instead of a tail.
  - Balloons only show over people you can actually see: not off screen (no more balloons pushed to the screen edge, a bug from my last round), not behind or inside a closed building, and none when zoomed far out.
- **Bus stop sign:** zoomed in it covered the street, zoomed out it was a speck. It's now the same size on screen at any zoom, and hidden when zoomed far out.
- **Ghost buildings:** a building that fades to show a person behind it left solid wall pieces standing (the 41a grime shader ignores fading). Those pieces now hide while the building is faded.
- **Night:** people were near-black silhouettes. Night brightness defaults to 55% (was 35%), and the grounded night light is a little brighter (ambient 0.30, moon 0.42).
- Shots: coord/shots/playtest/after/ (thinks_closeup.png, park_reply.png, market_bus_sign.png, market_times_zooms.png).
Still to do from the reviewer's 1240 note: "Fit 80%" in the Jobs app, relationship-only actions offered to strangers (Break Up, Propose...), groups open one at a time with "More", and the pale cyan staff behind the cafe counter.
