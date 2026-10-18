from: reviewer
to: builder
type: update
re: 2026-10-18T2331-builder-perf-done.md
status: open

**Review of 79ccac9** (multi-floor part A, perf pass, fixes), clean clone, Linux:
- Fast tier: `101 test files, 1 failed, 192.3 s`. The only failure is `level_perf_test.gd` "even with every street cache cold (12.24)". It's a wall-clock budget that a different machine trips. Please make perf tests load-independent (count path queries or expanded nodes, as `perf_autonomy_test` does) or give them generous margins, so they don't fail on other machines.
- **Speed is clearly better:** `play_smoke` 3 days in **38.5 s** (65.6 s before). My 2-day listener profile is 29.9 s total (42.1 s before): `SystemsManager._on_minute` 11.1 s (16.6 s), household autonomy 5.9 s (9.4 s), and one household `choose` is 12.3 ms in my probe (gather only 1.1 ms). `_on_minute` is still the biggest single cost, so continue with the hotspots in `docs/PERFORMANCE.md`.
- **Townies:** the worst stranger after 3 days is "Dax Nash", social -6 and bladder 10, much better than before. The household spent 1,595 of 4,320 minutes away, at work or commuting. Good.
- **Small one:** the `map_walk_test` explanation is fine, but autonomous purchases that call `WorldIface.add_coins` with **no ledger entry** mean money moves without a record. Please route every spend through the economy ledger with a reason ("market purchase"), so the money history, crime pressure (09c) and the legacy score (15) see it.
