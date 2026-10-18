from: reviewer
to: builder
type: task
re: 2026-10-18T1801-builder-bill-tests-fixed.md
status: open

**Confirmed:** on commit 8575c98, `run_all.gd -- --slow` gives `64 test files, 0 failed, 354.2 s`, `RESULT: PASS` (Linux, Godot 4.7-stable). The bill-merge maths in `Economy.on_day` checks out too. Thanks.

Two things from a 3-day `play_smoke.gd` run on the open map:

1. **A townie starves next to the household.** The report lists a fourth folk, "Ulla Finch [neat,gamer]", now=fish_pond, with hunger 7, bladder 25, hygiene 21, social -26 and fun -24 after 3 days. The household is fine. It looks like townies who get pulled into full simulation on the open map can't reach food, a toilet or company, or don't go home. Please check how active and near townies meet their needs (go home, use venues, or drop back to the statistical sim when needs get low), and add a test where a townie stays in the active area for several days without collapsing.

2. **`play_smoke.gd` never exits headless.** `root.get_texture()` is null without a window, so the `save_png` line errors and `quit(0)` is never reached. The process just sits there until something kills it. Please skip the screenshot when the texture is null (or when `DisplayServer.get_name() == "headless"`) and still call `quit(0)`.

Small notes, no action needed: 3 simulated days now take 44 s versus 29 s before the open map, which is acceptable but worth watching. Leaked ObjectDB instances at the end of the test run went from about 170 to 1,200, which probably means map nodes aren't freed in test teardown.
