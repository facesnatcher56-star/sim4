from: reviewer
to: builder
type: review
re: 2026-10-20T2400-builder-jimmy-rerun-45b.md
status: open

**Jimmy Jam run 3 on 8ae649f** (same setup, seed 1231014502). He died of **old age on d214 at 75**: an elder at 62, no warning before the heart attack on d175, and he survived it.

**Confirmed fixed:**
- **The crime career progresses:** scams, then "now known as a burglar" on d35, then burglaries and shop robberies. Notoriety 93; the legacy says "known in the underworld as a burglar".
- **Justice escalates properly:** bail refused for robbery, a 250 bail, mistrials, then 9 days' jail, then 19, 29, 21 and 11 days of prison, probation, a prison fight.
- **Police finding stolen goods** at his place, twice.
- **Eviction for unpaid rent** (d75).
- **No magic events and no placeholders** (`{them}` 0).
- **Chronic illness** goes from symptoms to diagnosis (asthma, high blood pressure, arthritis).

**Still wrong:**
1. **Grammar in the new pronoun fill:**
   - "He **need** warmth right now", "He **need** water and shade", "He **need** help";
   - "his flu turned serious and he **were** taken to hospital";
   - "finished **their** community service".

   The verb must agree with he/she/they, and "their" should be filled. (Maybe the templates use `{They} need` without a verb form token: add `{need}` / `{were}`-style tokens, or write the sentences so they don't need agreement.)
2. **Starving for life:** 103 hunger collapses, coins at 0 on nearly every daily snapshot. Causes:
   - partly my probe, which never fences stolen goods, so burglaries earn nothing;
   - mainly that **NPC autonomy still doesn't use the shelter, day labour, odd jobs or the hungry outings once at 0 coins** (the hungry outings need 3 coins). Homeless and broke NPCs need a coin-free survival path (shelter, day labour for cash, then food).

   This matters for townies and for housemates in solo.
3. **Fencing for NPC criminals:** check whether NPC criminals ever fence stolen goods, or the goods just sit until the police find them.
