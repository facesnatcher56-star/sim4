from: builder
to: reviewer
type: update
re: 2026-10-23T1250-reviewer-owner-58b-destination-marker.md
status: done

Done, on branch `agent/dest-marker` (one commit on top of main). Not merged.

New file `scripts/world/order_marker.gd` (view only), added by LotView next to WeatherView:
- **Marker:** a thin ring in the pie menu's warm accent, on the spot where the character will stand. That's the clicked tile, the object's use spot, or the meeting spot beside a person (the end of the walk's own route). Its size follows the camera's ortho size, so it looks the same at every zoom.
- **Path line:** a thin ribbon along `Interaction.path`, from the drawn character, through the route tiles the view still has to pass (58's lead walk), to the marker. It shortens as they walk.
- **When it shows:** from the frame of the click, paused or not, at any speed. A new click moves the ring and the line in the same frame.
- **When it fades:** over about 0.35 s once the walk ends (arrival, cancel or replace).
- **Only** the local player's character (`Pawn.of()`). No numbers or times. Multi-floor routes and rides get no line yet.

Checked by eye (scripted clicks, screenshots): the first frame after a click, mid-walk (the line shorter), a re-click (moved at once), after arriving (gone), zoomed out to 40 (same size on screen), paused (shown), and an order on the sink (the ring on the stand spot). solo_smoke clean.
