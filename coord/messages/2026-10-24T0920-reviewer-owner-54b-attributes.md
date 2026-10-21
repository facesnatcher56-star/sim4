from: reviewer
to: builder
type: task
re: 2026-10-24T0850-reviewer-owner-54-skill-checks.md
status: withdrawn

# 54b: Attributes that govern skills, Elder Scrolls style (owner)

**Owner:** "Do we have specific skills governed by a more general one? Like the Elder Scrolls: one attribute governs the skills beneath it and adds to them where that makes sense."

We don't. Skills are flat today, and 54 only adds skill-to-skill "helped by" links. This adds a layer above the skills. Build it in 54 slice 1, so SkillCheck reads it from the start and 55 can use it in creation.

## The attributes (7) and what they govern
Each skill has one main attribute (full bonus) and at most one second attribute (half bonus).

| Attribute | Governs (main) | Also helps (half) |
|---|---|---|
| **Strength** | fighting, fitness | intimidation, handiness (heavy work) |
| **Agility** | stealth, sleight of hand, lockpicking, driving | fighting, guitar, piano, mechanics |
| **Intellect** | logic, first aid, mechanics, writing | handiness, cooking, manipulation |
| **Presence** | charisma, manipulation, intimidation | performing (acting and singing), teaching |
| **Awareness** | perception, fishing | driving, stealth, first aid |
| **Willpower** | (no skills of its own) | resisting addiction, staying calm in fires, fights and police questioning, resisting threats and manipulation, stress and mood recovery |
| **Creativity** | painting, guitar, piano, cooking | writing, gardening, handiness (making things) |

**Willpower** is what the rehab check should use (the 54 audit flagged logic-as-willpower). It also becomes the defence in opposed checks: a threat against willpower, a con against awareness plus willpower.

## How they work
- **Scale:** attributes run 1–10, with 5 as average. Townies get rolled values shaped by their age, job and traits.
- **In SkillCheck:** skill level plus the main attribute's bonus, plus half the second attribute's, plus everything else from 54. This replaces most of the 54 skill-to-skill "helped by" links. Keep a link only where one skill really feeds another (stealth into sleight of hand, handiness into lockpicking).
- **On learning:** a higher governing attribute means faster XP for its skills (a sharp mind learns logic faster).
- **How attributes grow:** slowly, from using the skills under them (Oblivion style), plus direct training where real (the gym for strength and agility, puzzles, chess and reading for intellect, meditation for willpower).
- **What changes them for real:**
  - **Age:** strength and agility peak in the young-adult years and decline as an elder; intellect and willpower hold.
  - **Injuries and flaws:** a bad back lowers strength; poor eyesight lowers awareness until the pawn wears glasses.
  - **Temporary states:** drunk or high lowers agility and awareness and raises nerve; exhaustion and hunger lower everything a little.
- **Visibility:** the player sees attributes in the Skills tab, grouped with their skills, as plain levels. Never odds.

## Creation (55)
- Every character starts at 5 in all seven attributes.
- Backgrounds nudge them: a street kid gets +1 agility and awareness, a dropout +1 intellect.
- Points can raise an attribute (expensive, max 7 at creation).
- Flaws can lower one below 5 for points.
- Perks such as Strong or Keen eye become +attribute instead of +skill.

All of it goes in data (data/attributes.json: the governing map, bonuses, growth, age curve) so tuning is by file. No test suites.
