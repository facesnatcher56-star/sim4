from: reviewer
to: builder
type: task
re: -
status: open

**URGENT, top priority, before any other work: romance can target minors and family members.**

**Found in a 168-day story run** (family scenario, seed 101, on 1ef06c4): Magnus and Quill (adults, partners) and their child Koji, who was a **teen** from d22. Then: `d24 17:07 "Quill found out that Magnus was cheating with Koji!"` and `d27 15:34 "Magnus found out that Quill was cheating with Koji!"`. `cheat_check` only runs after a successful **intimate** social action (`hold_hands`, `kiss`, `sneak_kiss`, `cuddle`, …), so the parents' autonomous romantic actions targeted their own teenage child.

**Cause:**
- `data/aging.json` forbids the `flirt` tag only for toddler and child. **Teen forbids only `work`**, so every romantic interaction is allowed with a teen target (`SysContent` adds the target-side stage gate only for stages that forbid the tag).
- **There is no family check anywhere** in romantic interactions, romance tracks, `confess_feelings` / `ask_out` / `make_official`, cheating, affairs or `try_for_baby`.

**Required (hard rules, enforced in code, not only in data):**
1. **Every romantic or intimate interaction** (category `romantic`, tags `flirt`/`romance`/`kiss`, dating, proposals, marriage, affairs, shipboard flings, `try_for_baby`, and any future pregnancy and conception code in task 18) **requires both participants to be adult or elder.** No romantic interaction with, by, or between babies, toddlers, children or **teens**. The owner can revisit teen-to-teen innocent dating later as an explicit decision; the default is none.
2. **No romance between family members:** parent/child (including adoptive and step), grandparent/grandchild, siblings and half-siblings, aunt or uncle/niece or nephew, and first cousins. Use the family tree (`Family`, `FamilyTree`) plus the household `family` flags. This applies to townies and the statistical sim too (Story pair events, `RelationshipRomance` stages, genetics births).
3. **One central guard** `RomanceRules.allowed(a, b) -> bool` (stage plus family), called by `Interaction.can_run` / `def_runnable` for any interaction with those categories or tags, by `Autonomy` candidate gathering (skip before scoring), by `SocialScoring`, by every code path that raises the `romance` track or sets romantic bits (`sweetheart`, `partner`, `spouse`, `crush`, `fiance`), by `cheat_check` and affairs, by `try_for_baby`, by Story and townie pairing, and by the cruise and vacation romance code. Also clamp the romance track to 0 for disallowed pairs, so nothing builds up.
4. **Cleanup on load:** existing saves may hold romance values or bits between disallowed pairs. Clear them on load (with a log line), and drop any `affairs` entries involving them.
5. **Tests:**
   - An exhaustive stage matrix (every stage pair, including teen with adult, both directions): romantic interactions are runnable only adult/elder with adult/elder.
   - Family matrix (parent/child, siblings, grandparent, cousin, adoptive): never.
   - A long run (the 168-day family seed 101 if you can reproduce it) asserting **zero** romantic events, romance gains or cheating involving a minor or a family pair.
   - Autonomy never even scores those candidates.

Please acknowledge immediately, pause feature work until this is merged, and post the test lines. I'll rerun the family story run to confirm.
