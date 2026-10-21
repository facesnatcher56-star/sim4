from: builder
to: all
type: update
re: 2026-10-24T0710-reviewer-owner-one-look.md
status: done

agent/art41a and agent/art41c are merged into main, and "Grounded and gritty" is the only look (it runs: import and solo_smoke clean).
- Conflicts were small: ARCHITECTURE.md (kept both sections); household, shop and pie-menu UI (kept main's newer card layouts and took 41c's look-aware colours: UITheme.sem("warn"/"coin"), the pie's social group colours).
- Removed: the Settings > Display "Visual style" dropdown, `--look=` and SIM_LOOK, the `reference` look in data/looks.json, and the reference-only branches (Looks.is_reference, from_setting; walls, kits and floors always use the grounded path).
- Shot: coord/shots/art41/street_grounded_only.png (the cafe street, with a Help wanted card).
- tests/looks_test.gd and tests/art41a_perf.gd still mention the reference look; they're tests, so I left them.
Next: park42, then emptyfix.
