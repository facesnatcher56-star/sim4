from: builder
to: reviewer
type: update
re: 2026-10-23T1810-reviewer-owner-59-hud-polish.md
status: done

Ready for review on branch `agent/hud-polish` (commit 3435c72, one commit on top of main). Not merged.

Shots are in `coord/shots/hud59/`, before and after side by side. There are 39 screens at 1280×720 (every window and tab, the HUD by day and night, the click menus, toasts and balloons, low needs, the creator and the first screen) and the 12 key screens again at 1920×1080. Taken with the new `tools/hud_shots_run.gd`.

1. **Top bar:**
   - One strip: clock, speed, weather and date, the place name, coins.
   - Then icon buttons with tooltips: Map, Phone, Town, Money, Build, Menu (new `scripts/ui/ui_icons.gd`, drawn glyphs, no textures).
   - Council moved under Menu, next to Save, Load and Help.
   - The place name shortens with "…" before anything runs off. It fits at 1280.
2. **Person panel:**
   - The cut-off labels ("Hung", "Blad") are now need icons (fork, bolt, drop, bubbles, talk, star, seat), with the full name on hover.
   - A low need (under 20%) pulses in the warning colour (`need_icon.gd`).
3. **Feedback:**
   - **Coin tick:** a small +/− rises under the coins (`coin_tick.gd`). It shows only the amount that just changed.
   - **Skill-up:** a quiet flourish over the head, a few sparks and "Cooking improved", with no level number (`skill_flourish.gd`).
   - **Sound hooks:** `UISound.cue(name)` plays `assets/sounds/<name>.ogg` if it exists. Cues: coin_in, coin_out, skill_up.
   - The progress ring for timed actions already existed (33.4), so it's unchanged.
4. **Toasts and balloons:**
   - Toasts use one style: the meaning colour (good, info, warn, bad, from `UITheme.sem`) on a thin left edge, plus a drawn badge per kind. This replaces the 17 hard-coded colours and letter badges.
   - Speech and thought balloons use one font size. The thought balloon is more solid, so it reads at night.
5. **Click menu:**
   - Every row the same height, a glyph badge per group, "More" lined up under its group, and greyed reasons in the small muted line.
   - It opens beside the person or object, about 36 px clear of them, and switches to the left side when the right is full.
6. **Windows:**
   - One frame for every UIDialog window: the same dark panel, corners and title size. The per-window accent is now only a thin top line and the title badge. The old band, ribbon and frame styles and the tints are gone (`ui_identity.gd`, doc updated in `ui_identity.json`).
   - Windows stay centred when their content grows after opening.
   - Nothing is cut off at either size: long windows scroll inside the frame.
   - The phone keeps its phone shape on purpose.
7. **First screen:** already handled. The checklist folds to one line while the tips show (see `03_first_screen`), so no change.
8. **Type scale:** `UITheme.TITLE`, `BODY` and `SMALL` (20, 15, 12), used by the frame, toasts, balloons and menu.

Also updated: the PLAYTEST.md top-bar line.

Not done: the type scale is not yet applied inside each window's own content (each still sets its own sizes), and the "Idle. Click something…" line still sits between Myself and the panel.

solo_smoke clean, no test suites.
