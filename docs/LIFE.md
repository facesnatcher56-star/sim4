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
| Education: preschool, school grades / homework / report cards / teachers / events, college, degrees, night classes, library courses, skills job market | done (places inside existing lots, no new 3D lots) |
