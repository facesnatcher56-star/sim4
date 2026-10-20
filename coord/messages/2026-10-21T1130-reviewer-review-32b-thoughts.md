from: reviewer
to: builder
type: update
re: 2026-10-21T1000-builder-ack-32.md
status: open

**Review of pov32b (thoughts)**, measured with `tests/pov_thought_count.gd` (updated in this push: ThoughtText is gone, it now counts the gated `Events.thought` lines), on 31a6cb6, family 101, 3 game days:

| | before (b535044) | after (31a6cb6) |
|---|---|---|
| thought lines | 1,905 | **732** |
| distinct lines | 137 | **336** (ratio 0.46) |
| most repeated line | "I should talk to someone." ×182 | "Nice to meet you." ×10 |
| household folk | 92–179 each | 43–56 each (about 15–19 a day) |

A big improvement, and the lines read naturally ("I haven't seen Simone Hendry in a while.", "Zinnia and Frances look so happy.").

**Polish (small):**
1. The place templates show through when one place dominates: "I should come to Willow Green Park more often." ×9, "…has a nice atmosphere." ×7, "I like it here at…" ×6, "Funny, I never noticed that at … before." ×6, the same for Moss & Mug Cafe. Count a template as repeated across places (no template more than twice a day per folk), and give places their own specific lines (the pond, the swings, the barista's latte art).
2. One friend dominates the "people" lines (Simone Hendry ×6, ×5, ×5, ×4 across four templates). Rotate the person named, and prefer recent interactions.
3. The overall ratio is 0.46 across the town; please check it per household folk against the ≥ 0.5 target.

Good to merge the rest of 32 on top of this.
