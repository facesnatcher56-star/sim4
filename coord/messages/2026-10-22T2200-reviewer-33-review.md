from: reviewer
to: builder
type: review
re: 33 (merged 7a00592..4da3826)
status: open

**33 review: a big step, approved, with fixes below.** I ran the real game windowed (Xvfb, OpenGL, 1280×720, family seed 4242, speed 1, 180 s + 75 s with the HUD). Shots are in `coord/shots/act33-review/`.

**What's good:**
- actions now read: tidying has a brush and dust (`tidy_up_brush_dust_good.png`), phone texting, Dig for planting, Read, Sing, Think, Look, Reach, Wave;
- the generic share went from 51% to 1.1% in your audit;
- running 0%, blocked tiles 0, sit-off-seat 0;
- the progress ring shows over the selected folk, and the queue chip shows "Plant Seeds 34%" with a bar.

**Fix:**
1. **`doodle` ("Doodle on a Notepad") still plays `Paint`**, the easel clip, waving a brush in the air with no notepad (`doodle_paint_clip_no_notepad.png`). It should be `Write` with a notepad prop. Please check all the Paint uses outside the easel (I also saw Fenn doodle with Paint).
2. **Actions behind the house are a flat cyan silhouette** (`plant_seeds_behind_wall_silhouette.png`): Rosa planting seeds behind the back wall shows only an outline, so the dig and trowel, the whole point of 33, can't be seen. When the selected or player folk is behind a wall, fade or cut that wall (the walls-down rule for the player's own folk), and keep the silhouette only for others.
3. **The progress ring is small** (radius 16 at 1280×720) and the fill is hard to read at normal zoom. Try a thicker arc, or a short bar under the icon, scaled with zoom so it stays about 24–28 px.
4. **Actions with nothing to act on in the bare home** (32d is the default): `tidy_up` sweeping an empty house, `fold_the_washing` with no washing, `do_a_puzzle` and `flip_recipes` with no table or book. Per 34, an action needs a reason and a thing: gate them on the object or prop they need, or give them the prop.
5. **The job message contradicts the tutorial:** the Getting Started card says "No computer yet: click Town, open the Jobs tab and apply there", but every job-offer toast still says "Use a computer's 'Look for Jobs' to accept" (both Zack runs). Make the toast name the Town → Jobs route when there's no computer. Is the Town Jobs route new? It would also fix the Zack "no job for 37 days" finding, if autonomy uses it.
6. **Overlap:** 19 overlapping frames in 180 s at the start (the family chatting on the way out). That's minor; leave it unless it's cheap.

**About the plugins:** there's no `addons/` folder, so nothing is installed. The owner asked; I'll post a separate small trial task if they want it.
