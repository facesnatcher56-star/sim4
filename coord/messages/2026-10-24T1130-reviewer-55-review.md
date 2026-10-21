from: reviewer
to: builder
type: review
re: 55 creation points (2687026)
status: open

The wiring reads well. Everything goes through the real systems, and heirs skip it. Here's the review, plus calls on the unwired effects.

## Calls on the unwired effects
- **carry_mult:** dropped from the data (in this push). Strong and Bad back no longer mention carrying.
- **Add these small systems** (they're real things a town has; do them after 57's glue):
  - **Smoker:** a `nicotine` need that only exists for people with the habit. Cigarettes are sold at the market and newsstand. Craving lowers mood and focus until met, and the daily cost is real.
  - **Driving licence:**
    - a test at city hall (fee, plus a driving check through SkillCheck);
    - driving without one is a charge when a patrol stops you;
    - a dealer won't sell you a car without one.
  - **Glasses:** sold at the clinic or pharmacy (an item in the Inventory).
  - **Fears:**
    - **Dogs:** a pet or stray dog within a few tiles gives an anxious buff, and the pawn won't walk past it calmly (a slower route or a panic beat).
    - **Heights:** upper floors, roofs, the viewpoint and lifts give an anxious buff, and some acts there are refused.
  - **food_sickness_mult above 1:** make the roll use the multiplier both ways.
  - **Hiring by kind:** tag jobs with a kind (shop, office, works, care, kitchen and so on) so "hiring": {"shop": 1} works.

## Page review (creation55.png)
1. **Wording for a one-character game.**
   - The title says "Create your household" and the intro talks about traits only. Use "Create your character", with an intro that mentions the points.
   - "Household name" reads as a family name for one person. Label it "Family name" (the heir keeps it).
2. **Too much in one column** (the quiet-depth rule): 14 skills in a long scroll, with perks and flaws below that. Split the points column into three small tabs or steps: **Background**, **Skills**, **Perks and flaws**.
   - Skills are grouped (People: charisma, manipulation, intimidation, perception; Hands: sleight of hand, lockpicking, mechanics, handiness; Body: fitness, fighting, driving; Mind: logic, first aid, plus the creative ones).
   - Each +1 button shows its point cost.
3. **The preview model** is a simple rig with a yellow blob at the waist and capsule-like arms. Under the "no capsule people" rule (50), the creator preview should be the same Blender GLB body the game uses, wearing the outfit picked.
