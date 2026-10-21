from: reviewer
to: builder
type: review
re: owner run, Madrina Pierce (seed 439603864, normal settings, NPC autonomy played her)
status: open

The owner asked for a full life run. Madrina Pierce lived from a young adult to 84 (day 241, old age):
- teacher, laid off on day 115, then a paralegal, retired on day 169;
- Vik moved in on day 16; they married on day 182; Vik died on day 224;
- a break-in on day 104 (Ember Flynn arrested, then cleared), a fraud against Vik, a wildfire that set the home alight on day 181;
- 29,600 coins at the end, no children.

The whole life ran with no script errors.

Findings, most important first:

1. **The end-of-life summary (44) misses most of the life and gives wrong causes.** It has 13 entries, and the first is day 104.
   - **Missing:** meeting Vik, Vik moving in, every job and promotion, the layoff, retiring, the engagement, Vik's death and becoming a widow, the cold spell that nearly froze them on day 26, the court case.
   - **Wrong "Because" links:**
     - "Your home lost power... Because: Vik Young was cheated out of money."
     - "Snowed in. Because: Vik Young was cheated out of money."
     - "Married. Because: the fire at your home was put out."
     - "Power cut. Because: got married."

     LifeLedger._find_causes looks like it links the last entry about the same people and time, not the real cause. A cause should only be linked when one system actually caused the other: the break-in led to the arrest, the wildfire led to the house fire, the layoff led to the job change, the debt led to the eviction. Weather, power cuts and marriages shouldn't take causes they don't have.
   - **"The people in your life"** shows only a power-cut line for Vik. It should show who mattered: Vik (best friend, then partner, then husband, then widowed), close friends, enemies or grudges, and the people involved in her cases.
   - **"What you set in motion"** was empty because autonomy made every choice. In real play it fills from choices, so that's expected here, but autonomy-made big moves (taking a job, marrying) could still count as "your" moves for the summary.
2. **Elder alone at the end, which ties to the Jimmy hunger fix.**
   - After Vik died, Madrina lived alone for 17 days with 29,000 coins. She collapsed from hunger 3 times (days 216, 219, 229), with hygiene around −90 and bladder around −95 for days, "cannot manage alone and needs looking after".
   - For her last 2 weeks she kept ending up at the police station (met three people there; the desk officer picked her up).
   - Check two things:
     - An elder NPC with money should get food, wash and use the toilet. Something in elder autonomy or the place planner stops them looking after themselves.
     - For the player in the same state, there should be real options: home help (a carer who visits, paid), a care home, family or friends checking in.
3. **Vik moved in on day 16 as a best friend only** (a story_singles move-in). You've already made story_singles skip the player's character. This run had autonomy playing her, so it happened. No action needed beyond confirming the pawn skip covers "move in".
4. **The probe teardown aborts** (exit 134) after the run finishes, the same as the Jimmy runs. Harmless, just noting it.
