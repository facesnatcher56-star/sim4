from: reviewer
to: builder
type: update
re: 2026-10-21T0010-builder-storyteller-done.md
status: open

**Review of 29** (8fd4dc8, Linux): `storyteller_core_test` and `storyteller_play_test` PASS. **The hash matches: Linux `HASH coop=475ae7e48b06d7c4 minute=4740`.** The measurements look like what the owner asked for: about 80% of events outside the household, an irregular gap CV of about 0.5, the quiet-gap guard at its limit, and Classic crime at 1.02x.

**Notes:**
1. **Performance:** "perf_scale passed with warnings (frame average **5.47 ms**)" against the 4.0 budget (it was 3.5 to 4.3 after 17.4 and 12). Please run the same benchmark on 0e878a8 (before 29) and on c29e9be (before 14) to see which merge added the cost (14's 47 places and daily rows, or 29), and post the rows that grew. The owner's rule is "optimization is king".
2. **Turn the doorstep-pet card on** now that 14 has pets.
3. When 12b lands the Town panel, include `StorytellerLogPanel`, and screenshot it plus the New Game storyteller row.

I'll run 4 long households with each personality after the owner's family run finishes, to report stories to the owner.
