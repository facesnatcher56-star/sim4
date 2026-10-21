from: reviewer
to: builder
type: task
re: 2026-10-23T1800-reviewer-jimmy-jam-run.md
status: open

**PRIORITY (owner): fix the broken and wrong items from the Jimmy Jam run now, ahead of the remaining solo stages.** Then I'll rerun the same scenario. The owner's testing rule holds (it just has to run).

1. **Crime career stuck at petty thief.** A correction to my finding: my probe picked scams whenever the bigger jobs were locked, and **Burglar needs stealth 2** (`crimelife.json` ranks). Scams don't train stealth, so a con artist can never rise however much cred they have (Jimmy had about 50 or more). Fix the design:
   - ranks accept the skill that matches how you work (stealth OR charisma, with a con-artist branch: grifter, then confidence man, then fixer);
   - or scams train some stealth.

   Also check that cred isn't wiped by arrests (`snitch_cred` −30 applies only to snitching).
2. **Unpaid fines and restitution just vanish.** Jimmy owed thousands while broke. Give them a real path (34 logic):
   - they become court debt;
   - a payment plan is taken from income;
   - missed payments mean more community service or days in jail;
   - debt blocks renting (already in solo) and goes on the credit score;
   - restitution unpaid goes to the victim as a civil claim.
3. **Magic events still visible** (43, these first):
   - **"Your home found N coins tucked inside an old coat":** remove it. It fired 9 times in 15 days.
   - **Small claims "over a damaged fence":** only with a real fence and a real damage event between the two lots. Jimmy filed 5 while homeless.
   - **"A long-lost sibling at the door":** only someone who already exists in the family tree.
   - **Identity theft** with no culprit.
   - **The inheritance-surprise death.**
4. **Remove the warnings to the player** (owner rule):
   - the heart-attack lead text ("looks pale and keeps holding their chest… some hours to act");
   - "feels queasy, that food may have been spoiled" before food poisoning;
   - "flu is getting worse, medicine could help" as a prediction;
   - the murder ladder toasts and prompt;
   - storyteller signs aimed at the player.

   Symptoms can show once the illness actually exists, as a state, not a countdown.
5. **Broke and homeless NPCs don't help themselves.** Jimmy (on NPC autonomy) collapsed from hunger 43 times in 125 homeless days. NPC autonomy (townies, and housemates in solo) must use the cheapest food it can afford, the night shelter, day labour and odd jobs, and accept job offers when broke. A broke person should be poor, not starving every 3 days. Check the autonomy weights and gates for homeless or broke folk.
6. **Pronouns:**
   - "bruised themselves", "Get them something to eat", "They was known in the underworld" (legacy) for folk with a known sex;
   - route every toast, chronicle and legacy template through `Sexes.fill`, and fix the "They was" grammar.
7. **Next after these** (already on the board): crimes need a physical way in, security against determination, and the rest of 43.

Post a short note when they're in, and I'll rerun Jimmy Jam (same setup: young adult criminal, Chaotic storyteller and Surprises).
