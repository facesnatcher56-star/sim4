# Crime and justice: end-to-end map

Written by the reviewer from a read-only pass over the code at main 2bdcb53. Paths are under the repo root. Numbers come mostly from `data/justice.json`, which overrides the fallback defaults in the code. A game year is 28 days.

## Global multipliers

Two multipliers scale nearly every crime roll:

- **Difficulty:** `Incidents.surprise_mult()`.
- **Storyteller** (`data/storyteller.json`):
  - `crime_mult` is 0.85 on calm, 1.0 on classic and 1.5 on chaotic. It applies to burglary, guest theft, street robbery, assault, vandalism, trespassing, public disturbance and identity theft.
  - `hard_mult` ranges 0.8–1.5 and is capped at 1.5. It applies to murder, the serial killer and child abuse.

On top of these:

- **Crime wave:** a cycle of 8–16 days. Burglary, robbery and vandalism are ×1.4; guest theft ×1.3.
- **District mix:** downtown crime ×1.8; suburb burglary ×1.6.

### Town crime rate (`crime_rate.gd`)

A score from 0 to 100. Base 8.

- **Raised by:**
  - crimes in the last 28 days, weighted: murder 8, serial killing 10, robbery 4, burglary 3, petty crime 0.2–0.3, gang violence 2;
  - share of poor residents ×20;
  - share of jobless residents ×25.
- **Lowered by:**
  - 6 per police officer (max 20);
  - 1.5 per street lamp (max 12);
  - 12 for an active neighbourhood watch;
  - well-funded police and parks budgets.

`crime_mult = 0.6 + rate/60`, clamped to 0.6–1.8. It scales the desperate-crime rolls and makes burglars give up in a safe town.

### Police strength (`police.gd`)

`0.55 + 0.12 per officer + 0.2 per detective + 0.4 during a serial-killer hunt`, clamped to 0.3–1.6.

`justice_careers.gd` keeps one townie officer, detective, lawyer and judge employed once there are at least 7 adult townies, so strength usually sits around 0.87.

`patrol_factor = curfew / (1 + 0.15 per officer)` and gates street crime.

## 1. Crimes: what triggers them, what happens

### Burglary (`crime_burglary.gd`, `04_crime.json`)

**Trigger.** 1.0 per lot per year, checked hourly, only between 23:00 and 05:00.

- Home holds 1,500+ coins: ×1.4.
- Burglar alarm owned: ×0.3.
- Lamp owned: ×0.85.

**What stops it.**

- A lit lamp: 35%.
- Someone awake at home: 97%.
- An alarm object: 50%.
- Locks, cameras, lights and a dog (`crime_security.gd`).
- In a safe town (`crime_mult` below 1), an extra (1 − mult) chance the burglar gives up.

**Who the burglar is.** Picked from a sample of 48 townies, weighted:

- poor ×3, modest ×1.5, comfortable ×0.4;
- jobless ×2, has a record ×2;
- honest ×0.05, dishonest ×2;
- on the criminal path ×3;
- all of that multiplied by (0.4 + 3 × pressure risk).

**On the player's lot** it plays as a timed scene:

1. The burglar comes in through a ground-floor door or window.
2. At 4 minutes they take the most valuable electronics or art object (80%), or otherwise 15% of the household's coins (20–300).
3. They leave at 6 minutes.

Each sleeper wakes with 30% chance. Anyone awake gets the "Intruder in the house!" buff and a toast with two options:

- **Confront:** the burglar flees with chance 0.45 + 0.06 × fitness (hot-headed +0.1, shy or clumsy −0.12). If they don't flee, someone is hurt (60% of the time it's the resident), and 1% of the time someone dies.
- **Call the police.**

**On townie lots** it's statistical: 30% silent abort, otherwise 15% of the owner's coins are taken; witnessed 20% of the time.

### Guest theft

- 3.0 per year, checked hourly while a townie visitor is on the lot.
- The thief is most likely a poor visitor with low reputation (honest ×0.05).
- Takes 15–80 coins, or the cheapest valuable object (50%).
- The case stays hidden and has no witnesses.

### Street robbery (`crime_street.gd`)

**Trigger.** 0.65 per year, from 22:00 to 04:00. Victims are teens or older, carrying 20+ coins.

- Elders ×1.4; fitness 5+ ×0.6.
- A player folk must be off any lot and alone.
- Far townies roll only 20% of the time.
- A `patrol_factor` roll follows.

**The player chooses:**

- **Hand over.**
- **Run:** escapes with chance 0.35 + 0.07 × fitness. A failed run hurts 40% of the time.
- **Fight:** wins with chance 0.25 + 0.08 × fitness. A loss means injury 1–2 and a 0.4% chance of death, charged as manslaughter.

The robber takes 50% of the victim's coins (minimum 20). Victims report it 85% of the time.

### Petty crime (`crime_petty.gd`, `09_justice.json`)

Rates per lot per year:

- vandalism 0.1 (cleanup costs 20–60);
- trespassing 0.07;
- public disturbance 0.4, between 21:00 and 03:00.

Shoplifting comes from desperation and from kleptomaniacs (2% per day). Offenders lean teen, reckless, vengeful, hot-headed or dishonest.

Chance of being caught, × police strength (×1.5 if seen):

- vandalism 0.3;
- trespassing 0.35;
- disturbance 0.45;
- shoplifting 0.4.

If caught, it's settled on the spot with no trial.

### Desperate crime (`crime_pressure.gd`)

**Pressure** builds from:

- being broke (under 50 coins: +0.3);
- debt, late bills, repossession;
- being jobless;
- a record with no job (+0.15);
- children (+0.05 each).

**Conscience** starts at 0.5 and moves with traits (honest +0.4, dishonest −0.35), reputation and close ties.

**Risk** = pressure × (1 − conscience) × 2. Once risk reaches 0.15, the daily chance is risk² × 0.02 × multipliers.

What they do, by weight: shoplifting 0.4, theft 0.15, burglary 0.2, robbery 0.1 × risk, or fraud.

Help lowers pressure, each for 14 days:

- a loan −0.25;
- charity;
- family −0.3;
- a job −0.3.

Player folk skip this roll; they may get a "shady work" offer instead.

### Assault and domestic violence (`crime_assault.gd`, `crime_domestic.gd`)

**Only grows out of** a screaming argument (level 4+) with tension 70+.

**Chance** = 0.012 × (tension/50) × temper ÷ (1 + 0.05 × officers).

- Temper: hot-headed ×2, drunk ×2, capped at ×3.
- An anger course: ×0.25.

**What happens.** Usually a shove. A hit 12% of the time, +50% for each earlier incident between the pair, capped at 45%.

- Friendship −25, trust −20 (halved for a shove).
- Aggressor's reputation −5.
- An injury that needs hospital.
- Cooldown 7 days after a shove, 21 after a hit.
- Never involves children (by design).

**Reporting.** Domestic cases are reported 60% of the time, others 50%.

**Afterwards.**

- A player victim chooses: call the police, make them leave (divorce or move-out), leave with the kids, or stay.
- A townie victim leaves 40% of the time after a hit, 10% after a shove.
- Far townies roll feuds statistically: 0.004 per day × anger.

### Murder (`crime_murder.gd`)

Never random. It builds as **rage** per ordered pair of people.

**Anger** = tension × 0.5 + grudge × 0.45 + hatred × 0.4 + greed 0.15 (a poor relative of someone rich).

**Rage** grows by (drive − 0.7) × 8 per day while drive (anger × traits) is above 0.7, and decays ×0.88 per day otherwise.

1. **At rage 45:** warning gossip ("glaring at"), and the player gets a "Step in" prompt that cuts rage ×0.35.
2. **At rage 80, after 10+ days:** the daily chance is 0.004 × opportunity × `hard_mult`. Opportunity: alone 1.0, others around 0.25, apart 0.1, far away 0.5.
3. **If a player is involved:** a 180-minute warning, between 22:00 and 05:00. It's called off if rage has dropped below 70.

**Witness chance:** public place 45%, at home with others 25%, alone 4%.

A townie victim "vanishes" (the death is hidden). A folk victim dies on the spot. An apology cuts rage ×0.7.

### Serial killer (`crime_serial.gd`)

- 0.001 per town per year. The killer is a far townie, with loners weighted up.
- Targets the isolated, weighted by isolation². Player folk ×0.3. Police officers and detectives are never targeted.
- A kill every 4–12 days.
- Witness chance and trace evidence are both ×0.4.

### Fraud (`crime_fraud.gd`)

- **Embezzlement:** office jobs only, risk 0.1+. 0.004 per day × (0.2 + 4 × risk), ×3 if dishonest. Takes 80–400.
- **Scams:** dishonest people only, 0.002 per day. Takes 40–150. Elders and the rich are targeted.
- **Insurance arson:** risk 0.5+, risk³ × 0.003 per day. Sets a real fire; payout 300–900. Detected 60% × police strength; otherwise it's recorded as an ordinary house fire.

### Blackmail (`crime_blackmail.gd`)

Anyone who knows a secret rolls 0.01 per day × inclination (dishonest ×3, honest ×0.1). The demand is 40–160 coins every 7 days.

The victim can:

- **Pay.**
- **Refuse:** the secret comes out. Reputation −8 × severity × 2, trust −10, and gossip spreads.
- **Go to the police:** the secret still leaks 35% of the time.
- **Confront:** wins at 0.4 + charisma difference × 0.4.

### Revenge (`crime_revenge.gd`)

**Starts when** a real culprit is acquitted, or gets a light sentence (a fine, service, probation, or 3 days' jail or less).

Each relative of the victim, and the victim, starts a revenge chain with chance 0.08 × traits (vengeful ×4) × (1 + 0.4 × severity).

**Escalation.** The chain's level rises 1 per day (2 if vengeful):

- level 4: gossip;
- level 6: vandalism;
- level 11: a fight;
- level 16: a vengeful avenger adds 25 rage toward murder.

**Ends** through forgiveness (0.004 per day, 0.08 if forgiving), an apology (works 60% of the time), or a later conviction.

Vigilantes: 0.002 per day, attacking a free person with a severity 3+ conviction.

### Child abuse (`crime_child_abuse.gd`, `child_services.gd`)

A separate path. A carer's risk minus their support builds a hidden score.

- **At 0.55:** warning moods, and a player prompt (take a break, or ask for help).
- **At 0.9:** 0.03 per day × score × `hard_mult` for an event-only incident, which opens a hidden case.

**Discovery:**

- a teacher notices at 0.3 per day and reports 85% of the time;
- a doctor reports 95% of the time;
- relatives may report;
- the child may tell.

Child services visit the next day and may remove the child.

### Identity theft (`chaos_money.gd`)

0.03 per year. A money drain with no culprit and no case. Reporting it returns 85% of the money. Outside the justice system.

### Player crime life (tasks 21 and 23)

- **Criminal path jobs:** pickpocket, shoplift, car theft, burglary, shop robbery, and heists on the jeweller, bank or museum. Joining is a hidden career, with ranks earned through cred.
- **Odds** depend on skill, gear, casing the job, security, the hour, patrols and heat.
- **Outcomes:** fail, fail but seen, clean, seen, caught.
- **The underworld:** hired gun, dealer (fictional substances), racketeer (loans, protection, dens, laundering), gangs, bribery and corruption.
- Townies run the same dice, statistically.

## 2. How criminals are caught

### Reporting (`case_discovery.gd`)

- A witnessed crime is reported at once.
- **Hidden thefts** are noticed while someone is home and awake: 0.5 per hour for objects, 0.12 per hour for coins. Townies notice at 0.15 per hour.
- Camera footage can expose a hidden case.
- **A hidden killing** builds a "missing" score:
  - +0.07 per hour;
  - +0.8 per close relative;
  - +1.0 during work hours, +1.5 during school hours;
  - +0.05 per friend.

  At 12, a missing-person report is filed.
- **A body can be found** at 0.006 per hour on the street, 0.0015 on a town lot, 0.0008 at home; ×2.5 after 48 hours.
- After a missing-person report, the search finds the body at 0.3 × (0.5 + strength) per day, or after 8 days regardless.

### At the scene (`police.gd`)

- The police arrive in 12–30 minutes (or the city dispatch time). A monitored alarm is faster.
- A burglar still on the scene is caught with chance 0.5 × strength, and the loot is recovered.

### Investigation (`case_investigation.gd`, `case_evidence.gd`)

**Progress** grows each day by strength × 0.09–0.17.

- Cold cases ×0.15.
- While the body is unfound ×0.25.
- A detective's `work_case_file` adds +0.4.

**Tips** come in at 0.05 × (1 + strength) per day (×0.08 on serial cases). Each is worth 0.1–0.25, capped at 0.6. A tip can reopen a cold case.

**Hard evidence** (only the culprit has it):

- trace × progress;
- witness clarity × 0.7;
- tips;
- footage × 0.7;
- recovered loot 0.5.

**Soft evidence**, capped at 0.52:

- motive × 0.3;
- no alibi 0.12 (alibis come from the hourly whereabouts log: at work 0.9, away 0.8);
- a record 0.08;
- bad reputation 0.06;
- gossip 0.06.

**Arrest** happens when the top suspect's score plus noise (0–0.05) reaches 0.62. After 30 days the case goes cold and stays on file.

### Serial killer cases

- 3 or more isolated victims within 45 days triggers a hunt: strength +0.4, fear in the town for 30 days, a headline.
- Daily catch chance = mistakes (0.15–0.4 added per kill) × 0.12 × (2 during a hunt, 0.12 otherwise).
- A forced arrest at the fifth victim.

### Finding: wrongful arrest can't happen

An innocent suspect's score tops out at 0.52 + 0.05 = 0.57, below the 0.62 arrest line. The acquittal, exoneration and "wrong person" logic all exist but almost never fire. The storyteller's `wrong_arrest` card only shows text.

## 3. After arrest

Files: `justice_process.gd`, `justice_trial.gd`, `courthouse.gd`, `justice_guideline.gd`, `justice_sentence.gd`.

### Arrest

- A player is held for 6 hours.
- Hot-headed suspects add a resisting-arrest charge 4% of the time.
- A domestic case brings a 10-day protective order at once.

### Charges

The main charge, plus probation violation (if on probation), plus breach of any order.

**Petty charges have no trial.** The outcome is:

- community service (1–3 days) 30–40% of the time, otherwise a fine: vandalism 20–60, trespassing 15–45, disturbance 10–40, shoplifting 15–50;
- reputation −1 to −3;
- a record entry.

### Bail

- Granted at severity 3 or below.
- Refused when on probation with severity 3+, and for repeat domestic offenders.
- Amounts: theft 40, burglary 120, robbery 250, murder 2,000.
- If the suspect can't pay, they're held until trial.

### Lawyers

| Lawyer | Skill | Cost |
|---|---|---|
| Public defender | 0.3 | free |
| Private | 0.6 | 150 |
| Star | 0.85 | 500 |

Townies hire one if they hold twice the fee (or the fee itself at severity 4+).

### Trial

Held 3–5 days after charging, at 09:00, lasting 3 hours.

**Plea.** A guilty defendant takes it with chance clamp((evidence − 0.4) × 1.5, 0, 0.8); an innocent one 3%. The player decides for themselves. Snitching means an automatic plea.

**Verdict.**

```
z = 9 × (evidence + testimony + jury − 0.58 − [0.04 if a judge reviewed] − defence)
P(guilty) = logistic(z)
```

- **Evidence** = hard + 0.5 × soft.
- **Defence** = lawyer × 0.55 + charisma × 0.08 + reputation/100 × 0.1 − 0.04 per record (up to 3).
- **Testimony:** each witness ±0.1–0.12; each friend −0.04. Player testimony ±0.14, or ×1.4 if it's a lie.
- **Jury:** six random adults' feelings about the accused × 0.25.

If |z| < 0.35, there's a 40% chance of a hung jury, with a retrial 5–8 days later.

A lie on the stand is caught 30% of the time: a 150-coin fine, reputation −10, and a perjury record.

**Not guilty:**

- If they really did it: the case goes back to cold (progress −0.3), and the revenge roll fires. There's no second trial.
- If they're innocent: reputation +4, and the case reopens.

### Sentencing

**Score** = 0.3 ± 0.04, then:

- **Aggravating:**
  - each record 0.07 (up to 4);
  - a repeat of the same charge 0.12;
  - injury 0.12;
  - a child victim 0.25, an elder victim 0.15;
  - domestic 0.08;
  - on probation 0.1;
  - several victims 0.75.
- **Mitigating:**
  - first offence 0.1;
  - a plea 0.12;
  - provocation 0.12;
  - remorse 0.05;
  - reputation 0.05;
  - the lawyer up to 0.1.

**Below the charge's `custody_at`:** a fine, plus community service at 0.4+ and probation at 0.6+.

**Above it:** jail, then prison above `prison_at`. Lengths are interpolated, and over 10 days counts as prison.

Examples:

- **Burglary:** fine 100–250, jail 2–6 days, prison 12–25 days (`custody_at` 0.4).
- **Robbery:** prison 12–25 days.
- **Murder:** always prison, 70–160 days; life at score 0.92+.

**Extras:**

- restitution equal to the loot;
- mandatory anger or parenting courses;
- a protective order of 28 days (+28 per prior offence, max 112);
- custody of 4+ days loses the job;
- reputation −4 × severity.

### Prison (`prison.gd`)

- **Fights:** 3% per day (×3 if hot-headed). Each adds 3 days and costs 25 behaviour.
- **Parole:** after half the sentence with behaviour 65+, 12% per day.
- **Visits:** townies visit 12%; the player visits from the case board (+3 friendship).
- **On release:**
  - reputation −6;
  - a "Fresh Start" buff;
  - no fights for 14 days;
  - inmates met inside become underworld contacts.

### Appeals (`justice_appeal.gd`)

- **New evidence:** 1.2% per day if innocent, leading to exoneration, 300 compensation, reputation +12 and the record wiped. 0.08% per day if guilty; for a real culprit an appeal cuts the sentence 25% of the time.
- **Pardon:** 0.2% per day at behaviour 90+.

### Records (`justice_records.gd`)

**Expunged** after a clean spell: petty 56 days, theft or assault 112, domestic 168. Felonies are never expunged.

**Job bans:**

- police, detective, lawyer and judge, for most violent, property and fraud charges;
- teacher and doctor, for child harm, murder and arson;
- guard, after theft, robbery or fraud.

A record also adds pressure (record with no job +0.15) and doubles the odds of being picked as a burglar.

## 4. What the player can do

**Respond:**

- confront an intruder, or call the police (needs a phone, computer or nightstand);
- react to a robbery, a dangerous grudge, the murder countdown, domestic trouble or blackmail;
- in court: bail, lawyer, plea, and testimony (for, against, or a lie either way).

**Prevent:**

- start a neighbourhood watch at the mailbox (−12 crime rate for 28 days; townies start one themselves at 5% per day when the rate is 55+);
- take an anger course;
- review camera footage;
- buy locks, an alarm, monitoring, cameras, a safe or a guard.

**Work in justice:** as a detective, officer, lawyer or judge, through `work_case_file` (+0.4 investigation, +0.05 lawyer skill, or a judge's review).

**Commit crimes:**

- pickpocketing (automatically joins the criminal path);
- the Blackmail social action (dishonest, grudge-holding or bored folk only);
- crime-life and underworld commands.

**Visit prisoners** from the case board (F10).

**The player can't:**

- **Press charges or sue anyone.** Small claims only arise from an incident (0.1 per year): the household head sues a random townie for 40–140 over "a damaged fence". Other civil cases happen on their own:
  - an injury lawsuit: 8% after a severity 2+ accident, for 250, ×3 if it was fatal;
  - divorce settlements;
  - inheritance fights: 10%.

  Base win chance is 0.55, adjusted for charisma, reputation, record and wealth.
- **Appeal.** `JusticeAppeal.file` exists (fee 200), but no interaction or UI calls it.

## 5. Ripples into other systems

- **Mood:**
  - an intruder alert;
  - "Uneasy at night" (10 days after a murder; and for residents while the crime rate is 55+);
  - blackmailed, shaken, troubled conscience, violated, afraid at home.
- **Relationships:**
  - friendship and trust losses, history entries;
  - divorce, break-ups and move-outs;
  - protective orders block visits; prison visits keep bonds going;
  - family finding out about a criminal life: friendship −18, and they may disown, cover up or join.
- **Reputation:** drops on conviction, on release, and when a secret comes out.
- **Money:**
  - losses, bail, lawyer fees, restitution;
  - fines (a player who can't pay gets a bill due in 3 days);
  - property values fall up to 20% while the crime rate is above 50;
  - security earns insurance discounts.
- **News:** every case is logged; seasonal "crime rises/falls" lines; serial-killer pattern and arrest headlines; jailings and releases.
- **Elsewhere:**
  - gossip feeds suspicion;
  - deaths go through `Aging.kill` (grief and graves);
  - child services can remove a child.

## 6. Missing or partial

- **Charges with `stub: true` have no crime that produces them:**
  - driving: DUI, reckless driving, hit-and-run, vehicular manslaughter;
  - against people: threats, harassment, kidnapping, elder abuse, custodial interference;
  - other: public intoxication, forgery, animal cruelty, contempt, false report, insurance fraud (insurance arson is charged as arson).

  `attempted_murder` and `extortion` are used, by the underworld.
- `CrimeUnderRep.refused_service` (shops refusing known thieves) is never called.
- The crimeunder `rep.wave` settings are never read.
- The storyteller arcs `rising_criminal`, `missing_person` and `admirer` produce text and small effects only, with no real cases.
- The police station and courthouse are off-map, with no buildings.
- Identity theft is never a case.
- Wrongful arrest is effectively impossible (see section 2).
