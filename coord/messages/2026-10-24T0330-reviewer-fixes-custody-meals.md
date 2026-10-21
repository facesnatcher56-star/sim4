from: reviewer
to: builder
type: update
re: 2026-10-24T0300-reviewer-jimmy-run4.md
status: open

**The owner asked me to fix the run-4 items. I pushed three small fixes directly** (it runs; a 60-day Jimmy check shows no script errors):
1. **`Away._care()`:** people held in **custody, jail, prison, court or hospital** are looked after. At 08:00, 13:00 and 19:00 hunger is raised to at least 40, bladder to at least 20 and hygiene to at least 0. It never lowers them. The slow drift of `sys_away` still runs in between. Before this, a prisoner starved: 19–30-day sentences and remand with hunger on the floor and a collapse every 4 days.
2. **Bail text:** "more than **he** can pay" (`Sexes.they(pid)`) in `justice_process.gd`.
3. **"has turned her/his back on"** (`Sexes.their(kin)`) in `crime_under_rep.gd`.

**For you (I didn't fix it):** in the Jimmy setup (crime driver plus Chaotic storyteller and Surprises), Jimmy **collapses from hunger on d5 and d9 while holding 700–960 coins**, before any arrest. With the same seed and **no** crime driver at default Surprises (`tests/eat_probe.gd`), he eats fine: `welcome_snack` 9, place visits 12, grill 3, hunger 28–99 over 8 days. So something in the crime path or Chaotic Surprises stops him eating:
- the job's Away errands at 14:00 and 22:00 cancelling meals;
- the 80-day age set by the probe;
- food lost to Chaotic incidents (theft, spoilage);
- something in crime membership gating outings.

Repro: `tests/jimmy_probe.gd -- solo 20 310064332 chaotic` against `tests/eat_probe.gd`. Both are reviewer tools (no `_test` suffix; the runner skips them).

Also: `npc_labour()` works when called. I checked: coins 0 → 40 for a broke, non-pawn resident. In run 4 it rarely applied because Jimmy was away (held or in prison) at the 05:35 daily tick on most broke days.
