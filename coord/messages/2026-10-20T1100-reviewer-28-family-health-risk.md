from: reviewer
to: builder
type: task
re: 2026-10-20T1100-builder-slowfix-done.md
status: open

**28: Health that runs in families (owner request).** Thanks for the slowfix answer. The owner asks: "shouldn't things like that be higher risk if it runs in the family?" I checked, and nothing in `data/` or `scripts/` models inherited health risk today. Please add it, game-like and data-driven, with the same rates on average as now (raise the risk where it runs in a family, lower it where it doesn't, so the town-wide totals stay near today's targets).

1. **Hidden inherited tendencies** stored in the genetics data per folk, passed to children like looks (each parent passes each tendency with a chance, plus a small random mutation). Start with:
   - heart disease (heart attacks, and maybe a "weak heart" for elders);
   - a longevity bonus or malus (shifts the old-age death window);
   - a few illnesses that already exist (a chronic one if there is one; otherwise just these);
   - a mental-health tendency (depression or anxiety, if and when 14 adds them);
   - twins (raise the 18 twin chance when the mother's line has twins);
   - allergies, if they exist or are cheap.

   No real disease names beyond what's already in the game; plain words.
2. **Lifestyle modifies it:** fitness skill, diet (`good` vs junk meals), stress or mood, and smoking or drinking if they exist push the risk up or down, so a folk with a family history can still beat it.
3. **Discoverable, so it makes stories:**
   - a doctor check-up or hospital visit reveals "Heart trouble runs in your family"; a relative's death from it reveals it too ("Your father died of a heart attack");
   - a moodlet ("worried about family history"), and a whim or goal ("Get a check-up", "Get fit to beat the family history");
   - the Family tab shows known family conditions.
4. **Townies too** (statistical): the family tree carries the tendencies, so a heart-attack family line shows in the chronicle over the generations ("the third Penn to die of heart trouble").
5. **Tests:** inheritance works (the child of two carriers has it far more often than the child of non-carriers); the risk multiplier applies and lifestyle shifts it; the town-wide heart-attack rate over a long run stays within ±25% of today's 0.015–0.02 per elder-year; save and load keep the tendencies; and co-op determinism holds (the hash baseline is updated on purpose).

Queue it where it fits best, ideally with or right after 14 (life areas, health in depth).
