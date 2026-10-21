from: reviewer
to: builder
type: review
re: 2026-10-24T0850-reviewer-owner-54-skill-checks.md
status: open

# 54 addendum: audit of every current skill use. What doesn't make sense, and what it should be.

The owner asked for every current skill check to be read for logic. These are the reviewer's findings, from all data/ files plus the skill_level/skill() calls in scripts/systems. Fix them as part of 54; the new skills are the ones listed in 54.

## Wrong skill (fix)
| Where | Now | Should be |
|---|---|---|
| incidents/21_crimelife practise_lockpicking | gives **stealth** XP | lockpicking (handiness helps) |
| crimelife skills.stealth blurb | "sneaking, **slipping locks**, not being noticed" | stealth = unseen and unheard only; locks are lockpicking |
| crimelife jobs.pickpocket | stealth 1.0, charisma 0.3 | sleight of hand 1.0, stealth 0.3, charisma 0.2 (distraction); opposed by the victim's perception |
| jobs.shoplift | stealth 1.0, charisma 0.2 | sleight of hand (concealing) + stealth; opposed by staff perception (the 53 cashier) |
| jobs.car_theft | stealth 0.8, handiness 0.7 | lockpicking (the door) + mechanics (hotwire), stealth small |
| jobs.burglary | stealth 1.0, handiness 0.5 | stealth (not heard) + lockpicking (entry), with perception to read the house |
| jobs.store_robbery | stealth 0.5, **charisma 0.6**, fitness 0.4 | intimidation first, fighting and fitness; stealth near 0 (a robbery is open) |
| jobs.scam | charisma 1.0, logic 0.5 | manipulation 1.0, charisma 0.4, logic 0.3 |
| heists.roles.driver | fitness 0.4, handiness 0.6 | driving (mechanics helps) |
| heists.roles.lookout | stealth 0.7, logic 0.3 | perception first, stealth second |
| heists.roles.safecracker | handiness 0.7, logic 0.3 | lockpicking first, logic, handiness |
| heists.roles.muscle | fitness 0.8, charisma 0.2 | fighting and intimidation, fitness |
| crime_life_heist_run escape | uses the **leader's fitness** | the driver's driving (getaway car), or each member's fitness when on foot |
| ranks burglar skills_alt | charisma 2 | a burglar doesn't rise by charm. Give the con route its own rank line on manipulation, or drop the alt |
| ranks fence | charisma 3 | charisma + manipulation (haggling, knowing who to trust) |
| crime_security_guards noticing | the guard's **fitness** | the guard's perception (fitness only for the chase) |
| crime_life_casing, crime_under_hit_run research | gain by stealth | perception first (watching and learning a routine), stealth for not being noticed while doing it |
| crime_under_deal sting avoidance | dealer's stealth | perception (spotting an undercover) + manipulation |
| crime_under_good cop sting | cop logic + charisma | perception + manipulation (playing a buyer), detective bonus stays |
| crime_under_addict rehab | **logic** as "willpower" | not a skill. Use traits (stubborn, ambitious, ...), support from close people, and the addiction level |
| bank.json crafts.book | **charisma** | writing |
| shops bookshop novel | gives **charisma** | writing (reading fiction) |
| social topics.books | logic | writing, logic |
| interactions tutor | needs charisma 1 | the subject's skill being taught (charisma helps how well it lands) |
| interactions deep_talk | needs logic 1 | charisma (empathy) leads; logic optional |
| hobby_services find | logic | perception (finding things) |
| incidents street_robbery prevent | fitness 5 | perception (seeing it coming), fighting, fitness (getting away) |
| incidents workplace_injury prevent | **any** of cooking/fitness/handiness/gardening at 4 | the skill of the job the person is actually doing |
| careers security_guard | fitness, handiness, charisma | perception, intimidation, fighting, fitness |
| careers night_watchman | fitness, logic | perception, fitness |
| justice police_officer | fitness, charisma, logic | add perception, driving and fighting |
| justice detective | logic only | logic + perception, manipulation (interviews) |
| justice lawyer | logic, charisma | + writing, manipulation (cross-examination) |
| careers_works mechanic | handiness, logic | mechanics, handiness, logic |
| 10_education medicine | logic + **fitness** | logic + first aid |
| businesses salon | charisma | a craft skill (handiness for now), charisma for regulars |

## Makes sense (keep)
- **Daily life and the home:** cooking reduces kitchen fires and spots bad food; handiness for DIY repairs, shocks and leaks; fitness for falls, drowning, smoke dose and the heart.
- **Crime and justice:** fleeing a burglary confront on fitness; a street-robbery victim's fitness; dodging cameras on stealth (with a mask); city election on charisma; police and the detective bonus.
- **Social and leisure:**
  - pet training on charisma;
  - social feed likes on charisma;
  - the pub quiz, chess and museum on logic;
  - nightclub and theatre on charisma;
  - a concert on guitar or piano;
  - the gym and sports on fitness;
  - fishing, gardening and painting places.
- **Careers:** most career ladders (cook, coder, painter, musician, gardener, handyperson, scientist, writer, barista, doctor, athlete, teacher, chef and the works careers).
- **Unregistered skill:** hobbies take_photos gives a "photography" skill that isn't in content_rules.json, so it has no label. Register it.

## Hard skill gates that 53 turns into attempts
These hide the action below a skill level. Under 53 they should always be offered, with the skill deciding the result.
- **Cooking:** cook_meal_good (cooking 3), cook_meal_gourmet (6), grill_gourmet (5), cook_fish_dinner (2), prep_food_good (2). Low skill means a poor or burnt meal, and sometimes a kitchen fire.
- **Making things:** build_gadget (handiness 3), write_novel (writing 3), paint_masterpiece (painting 4). Low skill means junk, a bad draft or a failed piece.
- **Music:** write_song (guitar 3), play_piano_concert (piano 4), serenade (guitar 2). Low skill means a bad performance and the crowd or partner reacts.
- **Outdoors:** fish_deep_water (fishing 3), harvest_crops_bountiful (gardening 4).
- **Social:** do_impression (charisma 1), share_riddle (logic 1), give_advice and deep_talk (logic 1), tutor.
- **Crime:** the crime rank skill requirements stay as career progression (who offers you work). The acts themselves are open to try under 53.

Build these into the 54 slices: the data fixes go with slice 3 (the crime rewire) and slice 5 (work and hazards); the gates go with the 53 sweep.
