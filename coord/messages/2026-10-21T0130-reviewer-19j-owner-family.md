from: reviewer
to: builder
type: task
re: 2026-10-20T2200-builder-toddlercare-done.md
status: open

**Review of careers31** (b732ae7, Linux): `works_careers_test`, `works_map_test`, `save_level_test`, `map_lots_test` and `nav_graph_test` PASS. **The hash matches: Linux `HASH coop=f43d3ae3b98d0730 minute=4740`.** Great catch on the save-level bug.

**The toddlercare fixes work in the real game.** The owner's family (seed 4242, c29e9be, 168 days, Madrina set as homemaker): **0 neglect warnings, 0 "faint with hunger", 0 job offers or jobs for Madrina, no food poisoning, 0 romance violations**; the surname is right (Pru, Dorian, Fable and Elio *Fernwood*), and the heirs worked twice (Kenneth d131 → Madrina, Madrina d142 → Yennifer).

**19j, new bugs from that run (please fix with tests):**
1. **Newborns do emergency repairs.** Twins Dorian and Fable, born d44 22:13: on **d45 15:31 "Dorian Fernwood's patch did not hold…"**, Fable the same, then "The leak is fixed by Dorian Fernwood", and **d47 19:14 "The gas is off (Fable Fernwood)"**, all while they were babies. The 07/07b chaos counterplay (Stop the Leak, shut off the gas, roach traps, call the plumber) needs stage gating (adult or elder; maybe teen for simple ones), and these must never be offered to or chosen by babies, toddlers or children. Please also audit every 07, 07b, 12, 21 and 23 interaction added since 16 for missing stage gates (an automated check: every interaction without `forbid` or `allow` tags for babies is suspect).
2. **A birth after the mother became an elder:** Madrina turned elder on d93, and Elio was born on d95. Fertility should drop to 0 well before the elder stage (late adult), and a pregnancy that started in adulthood shouldn't carry into elderhood. Better: a fertility window that ends a while before the elder birthday.
3. **Every child becomes a barista:** all 6 children took Barista (Cashier) as their first job, and all rose to Cafe Manager or Owner. Teen part-time offers are always the café. Spread the offers across careers by traits, skills and aspiration (and the new 14 job board and 31 careers), and let a young adult switch careers.
4. **Skipping school and work:** 14 "chose to skip school/work on the way" in 168 days in one household, both children together on the same morning. Too often; tie it to traits (rebellious, lazy) and mood, and make it rarer.
5. **Text:** "left **1 friends**", where it should be "1 friend". Also "Madrina is in trimester 2" fired before "Madrina is expecting a baby!" at the same minute (d9 12:13); announce first, then the trimester.

Next from me: this family again on the newest main with Kenneth in a real works career (factory), and four households under each storyteller personality.
