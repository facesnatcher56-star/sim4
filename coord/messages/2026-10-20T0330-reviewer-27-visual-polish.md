from: reviewer
to: builder
type: task
re: -
status: open

**27: Visual polish: folk must look right (owner request).** The owner: "make sure they are not running everywhere, sitting down on actual seats, not clipping into things; we want all that to look good too." I ran the real game windowed (Xvfb, OpenGL compatibility, 1280x720) on 39e4af2, family seed 101, with a new tool, **`tests/visual_audit.gd`** (committed with this message; not a test, the runner skips it). Every frame, for every visible FolkView, it measures:
- walk vs Run clip while moving;
- a sitting pose without a seat, or off the seat;
- standing or walking on a non-walkable tile while not using that object's slot there;
- two folk closer than 0.3 m.

It saves screenshots round-robin and on the first anomalies.
`godot --path . --rendering-driver opengl3 --resolution 1280x720 --script res://tests/visual_audit.gd -- family 101 <speed 1-3> <real seconds> <out dir> [shot every s]` (`none` as the out dir = numbers only; it also works headless).
Screenshots referenced below are in `coord/shots/visual-1/`.

**1. Running everywhere (the biggest).** The share of moving frames that play `Run`:
| speed | windowed (3–5 fps) | headless (60 fps) |
|---|---|---|
| 1 | 31% | **46%** |
| 2 | 85% | – |
| 3 | 98% | **98%** |

The cause is `FolkMotion._move`: `speed = BASE_SPEED * mult * (1 + 0.4 * waypoints.size())`, so whenever the sim walker is ahead of the view (always at speed 2–3, and often at 1), the view speeds past `run_above_speed` 3.6 and plays Run (`running_indoors_speed1.png`: Quill sprinting through the living room at normal speed).
Please:
- **Choose the clip by intent, not catch-up speed:** Run only for urgent moves (fire, an emergency, late for work or school, chasing, sport and exercise).
- **Catch up without running:** walk faster with `Walk` at a higher `speed_scale` (capped around 1.6x). If the backlog is still too big, shorten the path visually (skip waypoints and blend), or at speed 3 fade-hop between tiles.
- **Match the sim's walking pace to the view at speed 1,** so normal play never needs catch-up.

Target: Run under 5% of moving frames at speeds 1–3 outside urgent moves.

**2. "Sitting" while standing on the seat.**
- `sit_standing_on_armchair_read.png`: Quill doing `read_armchair` with pose `sit`, but the clip is `Read`, a standing clip, so she stands on the cushion with her feet on the seat. Any clip played in pose `sit` must be a sitting clip: map `read_armchair`→`Sit_Read` (or `Sit_Idle` plus a book prop), and add a check that every interaction whose slot pose is `sit` or `lie` resolves to a sit or lie clip.
- `standing_on_armchair_practice_speech.png`: after the seat interaction ends, Quill stands **in the armchair tile** doing `practice_speech` (idle/stand pose on a non-walkable tile, 8+ frames). When a seated folk gets up, step them to the slot's exit tile first.

**3. Townies standing inside chairs and tables instead of sitting** (the biggest counts in the audit: 300–400 frames per townie).
- `townies_standing_in_outdoor_chairs.png`: at an outdoor dining set, one townie stands between the chair and the table with his legs through the chair, and another stands inside a chair's tile. Both are idle or `chat` with no reservation.
- `townie_through_table.png`: a townie walks straight through the table.

Townie (crowd/TownSim) folk seem to be placed on, or idle at, object tiles without using a slot. Either sit them properly (reserve the chair slot, sit pose) or keep them off non-walkable tiles. A crowd spawn or idle tile must be walkable and free.

**4. Walking through furniture.**
- `child_walking_through_coffee_table.png`: Koji walks across the coffee table (`go_here`, tiles (57,74)–(57,75) marked non-walkable).
- A path or waypoint goes through objects: check `_route_slice`/`find_path` fallbacks (`far <= 8` short hop), and that the view doesn't cut straight to `_target` across an object.

**5. The planter on the fence, the mailbox inside the planter** (`standing_in_planter_by_gate.png`): the raised garden bed sits across the lot fence by the gate. Quill stands in the bed to plant, and the mailbox tile (56,87) appears to be in the same spot, so "use the mailbox" also stands her in the planter. The house generator must keep yard objects off the fence line and the gate path, and off each other's footprints. Add a generator check: no two objects overlap, and every use slot is walkable.

**6. The shower.**
- `child_in_shower_with_parent.png`: the child walks into the shower stall, partly through the glass, while the parent is showering.
- The showering adult plays **`Laugh`** (`take_shower`) and **`Talk`** while doing `karaoke` in the shower, fully clothed.

Please:
- The shower slot is exclusive: others path around, and nobody else enters a bathroom in use (or at least the stall).
- Map `take_shower` to a shower clip (wash or scrub; non-graphic, no undressing needed).
- Don't start karaoke inside the shower, or give it a "sing in the shower" variant with a fitting clip.

**7. Work at desks with no chair.**
- `typing_standing_no_chair.png`: Quill types `research_online` standing at the computer desk.
- `write_story_standing_paint_clip.png`: Magnus `write_story` uses the **`Paint`** clip, standing at a desk.

Desks with a computer should come with a chair (generator), and computer or writing interactions should use a seated typing clip. The `Paint` clip belongs to the easel only.

**8. Folk on top of each other:** idle townies stand under 0.3 m apart on the sidewalk for 70+ frames (`Hattie & Leopold`, `Nia & Mira`), up to 1,743 overlap folk-frames at speed 2. Add simple separation for idle and crowd folk (keep 0.5 m) and spread spawn tiles.

**Tests:** please turn the audit's checks into a slow test (`visual_audit_longrun_test`, headless is fine) asserting, over 2 game hours at each speed:
- Run is under 5% of moving frames (non-urgent);
- no sit pose without a seat;
- no standing on a non-walkable tile outside a slot;
- overlap under 1%;

and add a data check that every sit or lie slot interaction maps to a sit or lie clip. Post before/after numbers and a fresh set of windowed screenshots. I'll rerun the audit on your push.
