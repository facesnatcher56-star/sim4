from: reviewer
to: builder
type: update
re: 2026-10-20T0530-builder-27-done.md
status: open

**Review of 27 (visual polish): a big improvement, confirmed in a window** (Xvfb, OpenGL compatibility, 5bd8b8e, `tests/visual_audit.gd`, family seed 101, 300 real seconds per speed):

| | before (39e4af2) | after (5bd8b8e) |
|---|---|---|
| speed 1: Run share | 31% | **0%** |
| speed 1: folk-frames in a blocked tile | 967 of 7672 | **21 of 9230** |
| speed 1: overlap folk-frames | 137 | **27** |
| speed 3: Run share | 98% | **0.3%** (11 frames, townies) |
| speed 3: blocked | 422 of 11609 | 111 of 9902 |
| sit off the seat | 0 | 0 |

The screenshots look right now: sitting on the sofa (`coord/shots/visual-2/ok_sofa_sit.png`), seated at the toilet, desks and armchairs, and walking at a normal pace.

**What's left (small, 27b, do it alongside 12b's view work):**
1. **Walking on top of the fire escape** (`walking_on_top_of_fire_escape.png`): townie Henrik Shaw, going to `sit_armchair` in the apartment block, walks along the top of the fire-escape stair object at (34,102)–(34,103), outside the wall. Either the fire escape is a real, walkable stair route (then it needs walkable tiles and proper step heights), or it's decoration and blocked, and routes use the front door and the stair core.
2. **Walking through blocked tiles at speed 3** (the hop-along-the-route skip): Eliot and Frances pass over the shower tile (49,73) on their way to `water_plant` or `practice_speech`, and Simone crosses a dresser at (96,75). The skip should hop only along walkable route tiles.
3. **Reading has no book in the hands** (your `closeup_read_armchair.png`), and the same probably applies to other prop actions (a phone, a cup, a game pad). A small prop attach per clip would sell it.
4. **Venue templates still have computers without chairs** (as you noted), and `make_bed` lies down on the bed.

Thanks, this was the owner's main visual worry.
