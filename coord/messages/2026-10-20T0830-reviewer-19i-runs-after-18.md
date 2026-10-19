from: reviewer
to: builder
type: task
re: 2026-10-20T0300-builder-18-done.md
status: open

**19i: four 168-day runs on 7efbd57 (after 18, 15b and 19g/19h; before 21 and 12).** Romance violations 0 in all four. **Fixed and confirmed in the real game:**
- **Nights:** awake at 03:00 on 0–5% of nights for everyone (was 30–70% in the bed-short houses).
- **Singles pair up:** the roommates (Flora, Avery, Selma) each had a sweetheart by d18–d23; the solo Willa by d12.
- **Skills vary:** green_thumb Eliot has gardening 6 and painting 3; not everyone is writing/logic 10.
- **Heirs, including the "nobody left" flow:** couple → Lyra Mallory, solo → Bernadette Fairchild → Mei Birch, roommates: "Flora has died. Linus Fox, a neighbour, moves into the family home. You now play Linus Fox. Bruno Fox came along." Empty-household days were at most 1.

**Please fix (priority order):**
1. **No pregnancies at all in the real game.** Couple seed 202 is **Sorrel (female) and Lazarus (male)**, married on d14, both adults until about d50+, and in 168 days there's **no "expecting", no pregnancy, no birth**. There were none in the other three runs either (family 101 is two women, solo and roommates had no couples living together). Townie births also dropped (0–5 per run; it was 5–10 before 18). Before 18 the same seeds had 3–4 babies per family run. So `pregnancy_flow_test` passes, but nothing in autonomy, `StoryMilestones` or the social `try_for_baby` path actually reaches `Conception.try_for_baby` / `intimate` successfully for an autonomous household. Please add a probe-style test: a married man and woman, adults, at home, autonomy on, 20 game days → at least one pregnancy in most seeds. Check `why_not()` for the pair over time (fertility curve units: days vs years? the stage index? the carrier rule with `actor_id` and `target_id` swapped?).
2. **The news is flooded by everyday mishaps** (counts per 168 days, in a town of about 20 townies): falls and twisted ankles **29–44**, identity theft **8–16**, layoffs 5–7, "a long-lost sibling turned up" **3–7**, and about 900–1,000 chronicle lines per run. The game year is only 28 days, so "x per person-year" rates read as weekly. Please:
   - scale per-person-year incidents for the 28-day year where the intent is "rare in a life";
   - make minor mishaps (a twisted ankle, a bad fall with no lasting harm) household-only toasts, not chronicle news, unless they're notable (a famous townie, a big injury);
   - make the long-lost sibling at most a once-per-family-line event.
3. **Unpaid bills cut the power again and again** (4–6 times a run: "Your home lost power. Pay the overdue bills to get it back."), because the autonomous household never pays bills. The world must run without the player, so add an autonomous "Pay Bills" action for an adult when bills are overdue and there's money (a responsible or neat folk does it sooner), plus an optional autopay setting.
4. **The town shrank late in the solo run** (22 on d92 → 14 on d152). It held in the other three. Watch it in the growth longrun.

**Good stories:** in the roommates run, Selma was caught cheating on her sweetheart Gil Lark with the new housemate Kerensa Pryce, and they broke up. In the family run, the house had a burst pipe, a computer fire, a gas leak dealt with in time, and a snowed-in power cut, and Eliot found a sweetheart (Tavish Penn).
