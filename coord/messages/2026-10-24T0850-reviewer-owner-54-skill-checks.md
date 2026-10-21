from: reviewer
to: builder
type: task
re: 2026-10-24T0830-reviewer-owner-53-freedom-everywhere.md
status: open

# 54: Skill checks behind every attempt, and a broken-down skill set (owner)

**Owner:** "Doing this [53] means a lot more skill checks, because that's what would happen in the background. Your skills decide whether you succeed, how fast, and how catastrophic a failure is. We want all of that in the game. Before, you tied charisma to scamming, and that's correct. But there's also manipulation, which is separate from charisma; charisma obviously helps manipulation. So we want independent skills too, broken down."

Builds together with 53: every attempt that 53 opens up resolves through this.

## Where it stands (reviewer read)
- **Skills used now:** charisma (66 interactions), handiness, logic, cooking, writing, gardening, guitar, piano, fitness, painting, fishing. Stealth exists only on the crime side.
- **Crime jobs weight a few skills.** A scam rides on charisma, pickpocketing on stealth plus charisma, robbery on stealth plus charisma plus fitness. The ranks have skills_alt. That's a good base, but too few skills carry too much.

## 1. Break the skills down (independent, with "helped by")
Each skill levels on its own. A helper skill adds a smaller share, so charisma helps manipulation without replacing it. Suggested set (adjust names and splits, but keep them independent):

| Skill | Covers | Helped by |
|---|---|---|
| Charisma | Liking, persuasion, first impressions, flirting, making friends | — |
| **Manipulation** (new) | Lying, conning and scams, guilt trips, talking your way out, blackmail pressure | charisma, logic |
| **Intimidation** (new) | Threats, staring down, collecting debts, making a witness back off | fitness, fighting, reputation |
| **Perception** (new) | Noticing things: a lie, a pickpocket, a tail, a cop, an open window, someone home | logic |
| Stealth | Moving unseen and unheard, hiding, slipping past staff | fitness |
| **Sleight of hand** (new) | Pickpocketing, palming goods, swapping items, card tricks | stealth |
| **Lockpicking / security** (new) | Locks, alarms, safes, car doors | handiness, logic |
| **Mechanics** (new) | Hotwiring, car repair, tampering | handiness |
| **Fighting** (new) | Brawls, defending, disarming | fitness |
| **Driving** (new) | Normal driving, getaways, chases, accident avoidance | perception |
| Fitness | Running, climbing fences, chases, carrying, taking a hit | — |
| **First aid** (new) | Treating injuries, overdoses, self-care after a fight | logic |
| Handiness, logic, cooking and the creative skills | As now | — |

- **NPCs carry the same skills,** seeded by age, job, traits, background and crew life. A detective or guard has high perception, a bouncer fighting and intimidation, a con artist manipulation.
- **Skills grow by doing,** with failures too (smaller XP), plus books, classes and the phone where that makes sense.

## 2. One check for every attempt
`SkillCheck.attempt(actor, act, target_or_object, context) -> {grade, minutes, effects}`, used by every 53 attempt and every social reaction.

**Inputs:**
- the primary skill plus helpers × weights from data;
- tools carried (lockpick, crowbar, slim jim, weapon, phone);
- conditions: dark or lit, noise, crowd size, weather, the pawn's mood, drunk or high, injured, tired, hungry;
- traits.

**Opposed checks** when someone resists or watches:
- pickpocketing (sleight of hand) vs the target's perception;
- a lie (manipulation) vs perception and logic;
- a threat (intimidation) vs the target's fitness, fighting and bravery traits;
- sneaking (stealth) vs the perception of each person who could notice (the 53 "who can notice" step);
- a getaway (driving) vs the patrol's driving.

**Graded result, not pass or fail:**
- clean success;
- success but slow;
- partial (got some, left a trace);
- fail quietly (try again or leave);
- fail loudly (noise, noticed);
- **catastrophic:** injury, a broken tool left as evidence, an alarm, caught in the act, a car crash, a fire from bad wiring, an overdose.

How far the roll misses decides how bad it is. A low skill makes bad failures likelier, and a high skill makes even failures soft.

**Speed:** minutes scale with skill. An expert picks a lock in 1 minute, a novice in 10 (and a 10-minute job at a front door has more chances to be seen).

**Hidden, as always:** no odds, no difficulty, no "you might fail" text. The player learns their level from the Skills tab and from what happens.

## 3. Rewire what exists
- **Crime jobs** (crimelife.json, crimeunder.json):
  - scams to manipulation first, charisma as a helper;
  - pickpocketing to sleight of hand plus stealth;
  - burglary to stealth plus lockpicking;
  - robbery to intimidation plus fitness;
  - car theft to mechanics plus lockpicking;
  - fencing to charisma plus manipulation.
  - Rank skills and skills_alt are updated to match.
- **Social:**
  - persuade, ask for help, talk your way out of trouble → charisma;
  - lie, flatter, guilt-trip, gaslight → manipulation;
  - threaten → intimidation.
  - SocialReaction from 52 uses these in its odds.
- **Justice:** police questioning (manipulation vs the officer's perception), court testimony, plea talks, spotting the pawn (perception).
- **Work:** job performance reads the skills for that job (a guard uses perception, a mechanic mechanics, a salesperson charisma plus manipulation).
- **Hazards:** first aid on an injured person or an overdose; fitness and driving for car hits and escapes (49).

## Order
Build in slices that each run:
1. The SkillCheck core plus the new skills (with UI labels in Skills).
2. Hook it into the 53 door and car slice.
3. The crime job rewire.
4. Social and justice.
5. Work and hazards.

Data first (a skills block with weights and helpers in data), so tuning is by file. No test suites.
