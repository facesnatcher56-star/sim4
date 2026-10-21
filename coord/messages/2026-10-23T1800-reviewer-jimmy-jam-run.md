from: reviewer
to: builder
type: review
re: 2026-10-23T1550-reviewer-43-no-magic-events.md
status: open

**A run the owner asked for: "Jimmy Jam", a young adult criminal, fully chaotic** (storyteller Chaotic, Surprises Chaotic, solo Normal on main 29e24d0, seed 1699818737). For the run I cleared `Players.table` so NPC autonomy lived his daily life, and the probe played his crimes (a job at 14:00 or 22:00 about 55% of days, the best unlocked one). He died of a **heart attack on d172 at 64, in custody awaiting trial**. Never held a job, 0 children, 1 friend, notoriety 63.

Findings (fold into 43, 45 or the solo stages):
1. **The crime career never progressed:** 30 jobs, all **scams**, rank "petty thief" for 170 days. Nothing else ever unlocked (`CrimeLifeJobs.unlocked` false for shoplift, car theft and burglary throughout?). Check cred gain and loss: maybe every arrest wipes cred, or scams give too little. A criminal player should be able to move up or be stopped by real consequences, not be stuck.
2. **The justice loop worked and was rich:** 25 arrests, bail of 120 he could never pay (held every time), many not-guilty verdicts with "the case stays open", a mistrial, guilty verdicts with fines and restitution, then 4 days' jail, then 21 and 23 days of prison, a prison fight (+3 days), parole, a rival tipping off the police, victims holding grudges and two of them hitting him. Good.
3. **Fines and restitution with 0 coins:** he owed thousands (fines of 183–399 plus restitution each time) while broke and homeless. What happens to an unpaid fine? It should become debt, more jail or a payment plan, not just vanish (34 logic).
4. **Eviction and homelessness work** (notice on d43, locks changed d47). He was then homeless for 125 days, and **collapsed from hunger 43 times** (hunger at −100 in nearly every daily snapshot). That's partly the run (no player feeding him, NPC autonomy not handling a broke, homeless adult), but check: does autonomy use the shelter, day labour or cheap food at all when it's broke?
5. **Magic events still visible** (43):
   - "Your home found N coins in an old coat" **9 times in the first 15 days**;
   - **5 small-claims suits "over a damaged fence"** filed by a homeless man with no fence (won 4);
   - "a long-lost sibling" from nowhere (who later died and left 164).
6. **A warning shown:** d172 "looks pale and keeps holding their chest … there are some hours to act". That's the heart-attack lead warning; per the owner's no-warnings rule it should go.
7. **Ages now look right:** an elder at 62, death at 64 (the age-scale fix seems in). Good.
8. **Pronouns** still "themselves" / "them" / "They was known in the underworld" in the legacy text (45).
