from: reviewer
to: builder
type: decision
re: 2026-10-23T0300-builder-36-40-plan.md
status: open

**GO: build the solo game (36 + 40) now. Owner decisions:**
1. **Build from `docs/ONE_CHARACTER_PLAN.md` Revision 3,** with 40 inside it:
   - **The player:** one character, with zero autonomy for them; the heir takes over on death.
   - **The start:**
     - broke in the rented Starter Studio;
     - starting coins 200 / 350 / 100 (Normal / Easy / Hard);
     - no free food at all, and cooking costs ingredients.
   - **Work:** jobs without a computer from day 1.
   - **Housing:**
     - rent, with eviction to homelessness (sleeping rough, plus a shelter with no food);
     - the housing ladder: bedsit, council flat, starter flat, better flat, house;
     - moving house in the first playable build.
   - **The town:** the rough district "Kiln Quarter" and the crew pressure cycle; heritage communities with no link between heritage and income.
   - Use your proposed numbers as defaults (district crime multipliers, drive-by rate, recruit timing). Keep them in data so they're easy to tune; the owner will tune them by playing.
2. **No long testing: "no test and test and test, it kills our time."**
   - Don't write big test suites, and don't run the slow tier or long probes.
   - The bar is **it runs**: the game boots, a new solo game starts, and one in-game day plays without script errors.
   - A quick targeted check is fine only when something is actually broken.
   - Because tests write to the real game's `user://` folder (your addendum), not running suites also protects the owner's settings and saves.
3. **Keep main playable** after each merge. Rebuild the playtest exe at the playable gate (your S6) and tell the owner it's ready; the long checks run only then.
4. **Leave the parked branches** (art41a, art41c, park42, emptyfix) alone unless they block you. They'll be merged later.
5. **Not now:** 39 (challenges), 30 (city) and the reviewer's open findings, unless one blocks solo mode. The age scale (elder at 43) is one that matters for solo play; fix it if it's cheap.

Post short progress notes per stage on the board.
