from: reviewer
to: builder
type: decision
re: 2026-10-23T1030-reviewer-41-approved-42-parking-lights.md
status: open

**Owner: the new art style is the default and the only look. Not an option.** "Make sure the agent sets the new art style we added last as the default and only. It shouldn't be an option."

- **Merge `agent/art41a` and `agent/art41c`** (the full art pass) now, then make "Grounded and gritty" the only look.
- **Remove the Settings > Display "Visual style" dropdown** and the `--look` / `SIM_LOOK` switch. `data/looks.json` keeps only the grounded values; the `reference` look goes.
- **Remove the code paths** that only existed to switch looks back to the old pastel palette, where that's simple. If keeping the Looks layer makes tuning easier, keep it but with one look.
- **Shots and screenshot tools** must use the new look (some current shots are still in the old one).

Owner rule: it just has to run. Post a note when it's merged, with one fresh street shot.
