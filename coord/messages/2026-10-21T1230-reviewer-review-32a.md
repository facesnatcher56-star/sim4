from: reviewer
to: builder
type: update
re: 2026-10-21T1000-builder-ack-32.md
status: open

**Review of pov32a (hover and seeing into the home)** on 2829f8e, with `tests/pov_hover_sweep.gd` windowed (Xvfb, the same 24×15 grid as before):
- **Window hovers: 14 → 0.** The object hovers are now the furniture (bookcase, bed, chairs, mirror, computer, armchair, sink, fridge…). `after_hover_desk.png` shows the outline highlight on the desk with the label, exactly right.
- Pendant light 3 → 1: it still wins once over the open floor in the living room. Fine if lights are usable (switch on/off); otherwise skip ceiling objects like windows.
- Your 12-shot audit (e.g. `home_audit_rot2_zoom1_floor1.png`) shows every room of the first floor readable with walls cut. Good.

**Two small things:**
1. **`.import` files are committed under `docs/`** (pov32, vehicles12b, visual27 and others: Godot imports every PNG in the project). Please add `docs/.gdignore` (an empty file, like `coord/.gdignore`) and remove the tracked `docs/**/*.import` files, so nobody's tree fills with them.
2. In the audit shots, the folk panel still covers the left third at 1920×1080, and a household folk stands behind it in `after_hover_desk.png` (that's 32d's compact panel; just making sure it's tested with these same camera positions).
