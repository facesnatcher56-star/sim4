# Life areas (task 14): education, health, food and nightlife, culture and leisure

Everything here is OPTIONAL for the player and RUNS WITHOUT THEM: townies study, places change staff and close for a day, the job board turns over,
school events happen. The player joins in through one window ("Town" in the top bar, tabs Places / Study / Jobs) or through the in-world actions
that already exist (homework at a desk, the counsellor).

## What a place is (and what it is not)

The map has 16 lot slots and all 16 are in use (15 lots + the Town Green), and changing the map would touch every test that counts lots, the nav graph
and the other agents' work. So a **place is a named, staffed, timed service point INSIDE an existing lot** ("a wing of the building"), not a new
lot with its own 3D rooms. Each place has a host `lot`, opening hours, a staff roster, prices and services. To use a service the person walks to
the host lot (`Go there` runs the normal travel command), the place must be open and staffed, and the visit takes its minutes as a real
interaction (`place_visit`). A new building or floor for a place is a later visual task; the data (`lot`) is the only thing that would change.

`Venues.is_open_type` asks `Places.extra_open`, so a lot stays open while a place inside it is (the school lot is open on weekday evenings for the
college and the night classes; at night and at weekends it is closed as before).

## Files

| Area | Systems (`scripts/systems/`) | UI (`scripts/ui/`) | Data |
|---|---|---|---|
| Engine | `life_defs` (loads `data/life/*.json`), `places` (hours, status, host lot, stage rules), `place_staff` (rosters, turnover, closures), `place_use` (why_not / price / use / finish), `place_effects` (needs, buffs, skill xp, pass, event, text), `place_handlers` (code behind special services), `place_member` (passes), `life_note` (toast + chronicle policy), `life_content` (the `place_visit` interaction) | `life_hub` (+ `life_hub_places`, `life_hub_study`, `life_hub_jobs`) | `data/life/10_education.json` (and one file per later area), `data/content_life.json` |
| Door | `life_tick` (reset, new game, daily order, event routing, save), `life_command` (`use`, `go`, `college_drop`, `preschool_leave`, `job_apply`) | | `systems.life` save block (also in `data/share_schema.json`) |
| Health | `health_life` (meters, labels, score, age shift), `health_life_day` (daily pass, strain), `health_cond` (conditions), `counselling`, `health_risk` (incident multipliers), `health_services` (the handlers) | `life_hub_health` | `data/life/20_health.json`, `data/incidents/14_health.json` |
| Education | `edu_state`, `edu_school` (homework, report cards, events, preschool, graduation), `edu_college` (majors, lectures, exams, degrees), `edu_gate` (degree gates + wage bonus), `edu_courses` (night classes, library courses, certificates), `edu_jobs` (skills job board), `edu_townies` (statistical studies), `edu_services` (the handlers) | | |

Every player action goes through `Commands.run({action: "life", args: {action, args}})` (`LifeCommand`), so a co-op host or a replay sees it. All
randomness comes from the module's own seeded stream (`PlaceStaff.rng`, `EduState.rng`); nothing reads the OS clock.

## Education

* **Preschool** (toddlers, `preschool` place, weekday mornings): enrol once, a small fee each school morning, a little social and fun, `early` points; the
  child starts school with a head start (up to +6 grade). Unpaid fees end it.
* **School** (existing attendance and grade): after a school day the teacher sets **homework** (80 percent of days). `do_homework` or the Homework Club hands it in
  (+1 grade, logic xp); not handed in by the next school day costs 2 grade and a note. **Report cards** every 14 days: a letter per subject (Maths, Writing, Art,
  Sport, Science = the overall grade nudged by 4 per skill level above 2), the average, a teacher's comment and the teacher's real name. Honour roll and "needs help" go
  to the town chronicle. **School events** (science fair, sports day, school play, parents' evening) once a year on the first school day on or after their calendar day.
  **Graduation**: a teen who grows up gets a diploma with the final letter.
* **College** (`college` place, weekday evenings 17:00 to 21:30): seven majors (business, medicine, law, science, computing, teaching, arts). One lecture a day, 32 coins,
  a skill grows with each; an exam every 4 lectures (38 + 6 x best skill level + rest + luck; pass 55; a fail loses 2 credits); 12 credits give the degree.
* **Degrees unlock better careers**: the top rung of doctor, scientist, teacher, coder, painter, writer needs the matching degree, lawyer from rung 4, judge from rung 3
  (`Careers.qualify` asks `EduGate.extra_missing`). A degree in the career's field adds 8 percent to wages (business: every career) and lets a new hire start one rung higher.
* **Night classes** (adults, weekday evenings) and **library courses** (teens and adults, daytime): 4 lessons each, a skill grows, a certificate at the end that the job board counts.
* **Skills job board**: every week each career has 0 to 3 openings (fewer in a recession), shown best fit first with what is missing; applying takes an opening and hires.
* **Townies** (statistical, one line each a day): adults enrol (1.5 percent a day), earn credits and graduate; the chronicle gets the line. One child townie wins at each school event.

## Health

* **Places inside the hospital lot**: the Family Clinic (check-up 35 coins, treatment 45, flu shot 22; Mon-Fri 8-18, Sat 9-13; the doctor is a named staff member), the dentist
  (clean 25, fix a sore tooth 55; Mon-Fri 9-17) and the Mind and Mood Centre (counselling 40). Health insurance pays its share of the clinic and the counsellor (`insurable`).
  At the market: the Pharmacy Counter (prescription refills). At the gym: passes (a week or four weeks; they waive the lot's entry fee through `Venues.entry_total`) and classes
  (yoga, spinning, boxing, personal trainer) that raise fitness.
* **Meters** (`HealthLife`, residents AND townies): fitness (exercise, weights, classes; falls 0.4 a day, never below 15), diet (meals and snacks; drifts to the middle), teeth (brushing, the
  dentist; wear 1.1 a day, 0.7 with clean habits; below 35 a toothache buff) and work strain. The health score (45 percent fitness, 45 percent diet, 10 percent teeth) scales colds
  and flu (x1.35 down to x0.7 for fitness, x1.2 to x0.85 for diet) and heart trouble (x2 to x0.5, x1.6 to x0.7) through the incident tags `illness` / `cardiac`
  (`data/incidents/14_health.json`, hook `IncidentRisk.effective_rate` + the sampling bound), and moves the old-age death window by up to 14 game days either way (`HealthLife.age_shift`,
  hooks in `Aging._check_deaths` and the townie death roll): a fit person lives about 10 percent longer than an unfit one.
* **Long-term conditions** (rare, managed with medicine): asthma, diabetes, high blood pressure, arthritis (elders). About 0.07 new cases per adult per game year at average habits
  (poor fitness and diet roughly double diabetes and blood pressure). A case starts hidden; the household is told about the symptoms after 4 days; a check-up (or the first flare)
  diagnoses it; two weeks of medicine from the pharmacy counter make flares ten times rarer (1.8 a year unmanaged, 0.16 managed for asthma). Unmanaged conditions shorten life a little
  (x1.18 old-age risk), high blood pressure raises heart trouble. Townies buy their own medicine; their serious flares are a hospital stay.
* **Counselling and therapy** (`Counselling`): a session cuts grief by half, burnout / shock / trauma buffs (burnt out, shaken, afraid at home, worried sick ... the list is
  `config.counselling.other`) by 60 percent, work strain by 35, and gives the `in_therapy` buff. The old home action "Talk to a Counsellor" (task 18) now also works for those buffs.
* **Burnout**: every shift adds 2 strain (4.5 when worn out), days off ease 6 (3 without a job), a holiday glow 10 more; at 85 the person is burnt out (the existing `burnt_out` buff)
  and the strain resets to 40. Ordinary workers: 0.1 a game year; always-tired workers: 0.85.
* The "Health" tab of the Town window shows all of it in plain words.

## Food and nightlife

Data: `data/life/30_food.json`. Eight places: **The Copper Spoon Restaurant** (cafe lot, 11:00 to 22:00, waiters and a chef; starters, mains, desserts, a kids' menu and a tasting dinner;
**one special per course per day**, 20 percent cheaper and a little more fun, picked from the date so a replay agrees), **Zip Burger** (fast food: filling, cheap, bad for the diet meter),
**The Gilded Barrel** (bar, 17:00 to 02:00, adults only, a quiz night on Wednesdays), **Neon Hollow Nightclub** (Thursday to Sunday 22:00 to 04:00, adults only: dance floor, VIP booth, cocktails),
**Flour and Crumb Bakery** (loaves and pastries go to the home pantry), **Frosty's Ice Cream Cart** (closed in winter), **The Roaming Kitchen Food Truck** (Friday to Sunday; the cuisine changes
every week) and **Willow Green Farmers' Market** (Saturday and Sunday: produce for the pantry, honey, flowers, and it buys the household's crafts and garden produce at full price).
* Dishes are services: `needs` (hunger, fun ...), `buffs` (well fed, tipsy), `meters.diet` (fast food and snacks lower it, salads and fish raise it). Age rules are data: `adult_only` on the
  bar and the club (every service), `min_stage` on mains, `stages` on the kids' menu; teens and children are refused in plain words.
* **Drinks** (`FoodServices`): each strong drink counts for the evening (a night lasts until 06:00); the fourth gives a hangover, the barkeeper refuses at the fifth.
* The club and the bar are open after midnight (hours past 24 in `schedule`); the cafe lot stays open for them (`Places.extra_open`, `Venues.minutes_to_close` looks for the real closing time).
* Gambling is adult-only too: `BankGamble.play_cards` and the lottery tickets (`ShopBuy.why_not`) refuse children and teens.
* Each place posts its own small news items now and then (`PlaceNews`, about 1 a day across the whole town): "The Copper Spoon has Fish with Greens as today's special".

## Culture and leisure

Data: `data/life/40_culture.json`. **Starlight Cinema** (office lot, 13:00 to 01:00; a family film, a new release and a late show with ratings: a child sees only the family film, a teen not the late show),
**Larkfield Hall Theatre** and **Concerts** (school lot, Friday to Sunday; plays and live music, and you can take a part or book a set), **Hollow Oak Museum** and **Oak Street Gallery** (library lot),
**Ironleaf Bowling Alley**, **Arcade** and **Swimming Pool** (gym lot; a gym pass halves the pool), **Willow Green Sports Field** (pick-up games and a local league), **Lake Shore** and **Southwoods Campsite**
(park lot; closed in winter, swimming in summer only), **Hollow Oak Community Hall** with a book club (Tuesday), chess club (Thursday) and garden club (Saturday morning).
* **Programmes** (`Programme`): every title rotates weekly per slot ("Family Film: The Little Lighthouse"), counted from day 1.
* **Performing** (`LeisureServices`): skill-gated (guitar 3, piano 3, singing 4, acting 2); pay = base + per level x skill, success 55 percent + 7 per level above the minimum; a flop pays 40 percent and
  embarrasses. **Fame** (`LifeFame`) grows with sets, gallery sales and wins and fades 1.5 percent a day ("unknown" .. "a local star").
* **Gallery**: exhibit up to three paintings (from the crafts the household made) at 1.5 times the market stall price. **Records**: bowling and arcade scores, a personal best and a town record in the chronicle.
* **League** (`LeagueState`): four teams (Fernwood Foxes, Ironleaf Rovers, Larkfield Lions, Greenbarrow Giants) with townies on the rosters; a round each Saturday (resolved Sunday), a three-round
  season, a champion announced; a resident joins a team and plays on Saturdays to strengthen it (the measured title share of a team with a weekly player is 0.32 against 0.25 of a fair team).
* **Clubs** (`ClubState`): five townie members each; a resident joins for 5 coins, goes on the club's day: skill xp, company and friendship with some members; the club's weekly line is news.

## Tier / cadence / active set / caps

| System | Tier | Cadence | Active set | Caps |
|---|---|---|---|---|
| PlaceStaff | town | daily | ~8 places x a handful of names | rosters = the data; 1 closure line per place per day |
| PlaceUse / PlaceMember | event | on a command, on the visit's end; passes expire daily | the person acting | pending 1 per person |
| EduSchool | household | daily + school events | school-age residents (ACTIVE) | reports 8 per child |
| EduCollege / EduCourses | event | on a visit | the student | one lecture a day |
| EduTownies | town (statistical) | daily | alive adult townies (~12) | 2 degrees each |
| EduJobs | town | weekly refresh, board on demand | one dice per career | 3 openings per career |
| HealthLifeDay / HealthCond | residents ACTIVE, townies STATISTICAL | daily | all residents + alive townies (~24), a few lines each | 4 conditions, 1 flare roll per condition per day |
| HealthRisk | event | inside the incident dice | tagged incidents only (`illness`, `cardiac`) | one empty-array test otherwise |
| Counselling | event | on a session | the person | |
| PlaceNews | town | daily | places with a `news` list | about 1 chronicle line a day in total |
| LeagueState | town (statistical) | weekly (Sunday) | 4 teams, 12 townies, residents who joined | 8 results kept |
| ClubState | town | weekly lines; residents on their visit | 3 clubs x 5 members | |
| LifeFame / records | event + daily fade | | people with fame | fame 0..100 |

Nothing polls per minute. The one clock entry is `day/LifeTick.on_day` (SimRegistry).

## Notify policy

`LifeNote.say` toasts only when somebody of a player household is involved; everything else is a chronicle line (`place_news`, `graduation`, `school_event`, `honour_roll`,
`certificate`). Plain words, no ids.

## Not done in this slice (see the end of the task report)

See the status list at the bottom of this file, updated as areas land.

## Status

| Spec item | State |
|---|---|
| Health: family doctor and clinic, pharmacy counter, dentist, therapy and counsellor (grief, burnout, trauma), gym, long-term conditions, diet and fitness affecting health and lifespan | done (places inside the hospital, market and gym lots); hospital floors from task 10 |
| Food and nightlife: restaurant with menu and waiters, fast food, bar, nightclub, bakery, ice cream, food trucks, farmers market | done as places inside the cafe, market and park lots |
| Culture and leisure: cinema, theatre, concert hall, museum, gallery, bowling, arcade, pool, sports field with a league, lake, campsite, community centre with clubs | done as places inside the office, school, library, gym and park lots (no beach: the map has only the Town Green pond) |
| Education: preschool, school grades / homework / report cards / teachers / events, college, degrees, night classes, library courses, skills job market | done (places inside existing lots, no new 3D lots) |
